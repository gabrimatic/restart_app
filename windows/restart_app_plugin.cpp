#include "restart_app_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>
#include <thread>
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
  if (method_call.method_name() != "restartApp") {
    result->NotImplemented();
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
  std::wstring cmd_line = GetCommandLineW();
  std::vector<wchar_t> cmd_buf(cmd_line.begin(), cmd_line.end());
  cmd_buf.push_back(L'\0');

  // Respond before any destructive action so the Dart side receives the result.
  result->Success(flutter::EncodableValue("ok"));

  // Launch the new instance and terminate on a detached thread so the platform
  // message loop can pump the response back to Dart before the process exits.
  std::thread([exe_path = std::move(exe_path),
               cmd_buf = std::move(cmd_buf)]() mutable {
    // Short delay to let the message loop drain the response to Dart.
    Sleep(150);

    STARTUPINFOW si = {};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi = {};

    BOOL ok = CreateProcessW(
        exe_path.c_str(), // Application path (handles spaces without quoting)
        cmd_buf.data(),   // Writable command line copy
        nullptr,          // Process security attributes
        nullptr,          // Thread security attributes
        FALSE,            // Do not inherit handles
        CREATE_NEW_PROCESS_GROUP, // Isolate child from parent's console
        nullptr,                  // Inherit environment
        nullptr,                  // Inherit working directory
        &si, &pi);

    if (ok) {
      CloseHandle(pi.hProcess);
      CloseHandle(pi.hThread);
      ExitProcess(0);
    } else {
      OutputDebugStringW(L"restart_app: CreateProcessW failed\n");
    }
  }).detach();
}

} // namespace restart_app
