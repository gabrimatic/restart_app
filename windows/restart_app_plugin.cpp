#include "restart_app_plugin.h"
#include "restart_app_relaunch.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>
#include <vector>

namespace restart_app {

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

  if (!try_begin_restart()) {
    result->Error("RESTART_ALREADY_IN_PROGRESS",
                  "An application restart is already in progress.");
    return;
  }

  // Resolve the path to the current executable. Use a dynamically sized buffer
  // to handle paths longer than MAX_PATH, with a cap to prevent runaway loops.
  DWORD buf_size = MAX_PATH;
  std::wstring exe_path(buf_size, L'\0');
  while (true) {
    DWORD len = GetModuleFileNameW(nullptr, exe_path.data(), buf_size);
    if (len == 0) {
      cancel_restart();
      result->Error("RESTART_FAILED", "Could not resolve executable path");
      return;
    }
    if (len < buf_size) {
      exe_path.resize(len);
      break;
    }
    if (buf_size >= 32768) {
      cancel_restart();
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
    cancel_restart();
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
    cancel_restart();
    result->Error("RESTART_FAILED",
                  "Failed to launch a new application instance (error " +
                      std::to_string(error) + ")");
    return;
  }

  HANDLE response_event = nullptr;
  std::string scheduling_error;
  if (!schedule_restart(pi.hProcess, pi.hThread, &response_event,
                        &scheduling_error)) {
    result->Error("RESTART_FAILED", scheduling_error);
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

  signal_restart(response_event);
}

} // namespace restart_app
