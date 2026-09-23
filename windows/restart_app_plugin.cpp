#include "restart_app_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <exception>
#include <memory>
#include <string>
#include <thread>
#include <variant>
#include <vector>

namespace restart_app {

namespace {

void close_process_handles(HANDLE process, HANDLE thread) {
  if (thread != nullptr) {
    CloseHandle(thread);
  }
  if (process != nullptr) {
    CloseHandle(process);
  }
}

void terminate_suspended_process(HANDLE process, HANDLE thread) {
  if (process != nullptr && !TerminateProcess(process, 1)) {
    OutputDebugStringW(L"restart_app: failed to terminate suspended child\n");
  }
  close_process_handles(process, thread);
}

} // namespace

void RestartAppPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "restart",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<RestartAppPlugin>();

  channel->SetMethodCallHandler(
      [plugin_ptr = plugin.get()](const auto &call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

RestartAppPlugin::RestartAppPlugin() {}

RestartAppPlugin::~RestartAppPlugin() {}

void RestartAppPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "restartCapability") {
    flutter::EncodableMap capability = {
        {flutter::EncodableValue("fullProcessRestart"),
         flutter::EncodableValue(true)},
        {flutter::EncodableValue("flutterEngineRestart"),
         flutter::EncodableValue(false)},
        {flutter::EncodableValue("notificationFallback"),
         flutter::EncodableValue(false)},
        {flutter::EncodableValue("engineRestartConfigured"),
         flutter::EncodableValue(false)},
        {flutter::EncodableValue("platformDefaultMode"),
         flutter::EncodableValue("process")},
        {flutter::EncodableValue("reason"), flutter::EncodableValue()},
    };
    result->Success(flutter::EncodableValue(capability));
    return;
  }

  if (method_call.method_name() != "restartApp") {
    result->NotImplemented();
    return;
  }

  const auto *arguments =
      std::get_if<flutter::EncodableMap>(method_call.arguments());
  std::string mode = "platformDefault";
  bool structured_result = false;

  if (arguments != nullptr) {
    auto mode_it = arguments->find(flutter::EncodableValue("mode"));
    if (mode_it != arguments->end()) {
      if (const auto *mode_value = std::get_if<std::string>(&mode_it->second)) {
        mode = *mode_value;
      }
    }

    auto structured_it =
        arguments->find(flutter::EncodableValue("structuredResult"));
    if (structured_it != arguments->end()) {
      if (const auto *structured_value =
              std::get_if<bool>(&structured_it->second)) {
        structured_result = *structured_value;
      }
    }
  }

  if (mode != "platformDefault" && mode != "process") {
    result->Error("UNSUPPORTED_RESTART_MODE",
                  "Restart mode '" + mode + "' is not supported on Windows.");
    return;
  }

  // Resolve the path to the current executable. Use a dynamically sized buffer
  // to handle paths longer than MAX_PATH, with a cap to prevent runaway loops.
  DWORD buf_size = MAX_PATH;
  std::wstring exe_path(buf_size, L'\0');
  while (true) {
    DWORD len = GetModuleFileNameW(nullptr, exe_path.data(), buf_size);
    if (len == 0) {
      result->Error("RESTART_FAILED", "Could not resolve executable path");
      return;
    }
    if (len < buf_size) {
      exe_path.resize(len);
      break;
    }
    if (buf_size >= 32768) {
      result->Error("RESTART_FAILED", "Executable path exceeds maximum length");
      return;
    }
    buf_size *= 2;
    exe_path.resize(buf_size);
  }

  // Build the command line for the child process. GetCommandLineW() includes
  // argv[0], but when lpApplicationName is set CreateProcessW still expects
  // argv[0] in lpCommandLine. We pass the full original command line as-is.
  // CreateProcessW may modify the buffer in place, so use a writable copy.
  const wchar_t *original_cmd_line = GetCommandLineW();
  if (original_cmd_line == nullptr) {
    result->Error("RESTART_FAILED",
                  "Could not resolve the process command line");
    return;
  }
  std::wstring cmd_line = original_cmd_line;
  std::vector<wchar_t> cmd_buf(cmd_line.begin(), cmd_line.end());
  cmd_buf.push_back(L'\0');

  // Create the new instance suspended so the launch outcome is known before
  // the response is sent, without two live app instances running side by side.
  // Hosts whose packaging or activation policy rejects CreateProcess surface
  // that failure before the current process is terminated.
  STARTUPINFOW si = {};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi = {};

  BOOL ok = CreateProcessW(
      exe_path.c_str(), // Application path (handles spaces without quoting)
      cmd_buf.data(),   // Writable command line copy
      nullptr,          // Process security attributes
      nullptr,          // Thread security attributes
      FALSE,            // Do not inherit handles
      CREATE_NEW_PROCESS_GROUP | CREATE_SUSPENDED, // Isolated, not yet running
      nullptr,                                     // Inherit environment
      nullptr,                                     // Inherit working directory
      &si, &pi);

  if (!ok) {
    const DWORD error = GetLastError();
    result->Error("RESTART_FAILED",
                  "Failed to launch a new application instance (error " +
                      std::to_string(error) + ")");
    return;
  }

  HANDLE response_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (response_event == nullptr) {
    const DWORD error = GetLastError();
    terminate_suspended_process(pi.hProcess, pi.hThread);
    result->Error("RESTART_FAILED",
                  "Could not schedule the application relaunch (event " +
                      std::to_string(error) + ")");
    return;
  }

  // Resume the child and terminate on a detached thread so the platform
  // message loop can pump the response back to Dart before the process exits.
  // Start this before sending success so a thread-creation failure can still
  // be returned as a normal platform error while the child is suspended. The
  // event keeps the thread from racing the channel response.
  try {
    std::thread([process = pi.hProcess, thread = pi.hThread, response_event]() {
      const DWORD response_status =
          WaitForSingleObject(response_event, INFINITE);
      CloseHandle(response_event);
      if (response_status != WAIT_OBJECT_0) {
        OutputDebugStringW(L"restart_app: response event was not signaled\n");
        terminate_suspended_process(process, thread);
        return;
      }

      // Short delay to let the message loop drain the response to Dart.
      Sleep(150);

      if (ResumeThread(thread) == static_cast<DWORD>(-1)) {
        // The child never ran; keep the current process alive rather than
        // exiting into nothing.
        OutputDebugStringW(L"restart_app: ResumeThread failed\n");
        terminate_suspended_process(process, thread);
        return;
      }

      close_process_handles(process, thread);
      ExitProcess(0);
    }).detach();
  } catch (const std::exception &error) {
    CloseHandle(response_event);
    terminate_suspended_process(pi.hProcess, pi.hThread);
    result->Error("RESTART_FAILED",
                  "Could not schedule the application relaunch: " +
                      std::string(error.what()));
    return;
  }

  // Respond before any destructive action so the Dart side receives the result.
  if (structured_result) {
    flutter::EncodableMap restart_result = {
        {flutter::EncodableValue("success"), flutter::EncodableValue(true)},
        {flutter::EncodableValue("mode"), flutter::EncodableValue("process")},
    };
    result->Success(flutter::EncodableValue(restart_result));
  } else {
    result->Success(flutter::EncodableValue("ok"));
  }

  if (!SetEvent(response_event)) {
    OutputDebugStringW(L"restart_app: failed to signal response event\n");
  }
}

} // namespace restart_app
