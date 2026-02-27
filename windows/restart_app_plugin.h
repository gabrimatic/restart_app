#ifndef FLUTTER_PLUGIN_RESTART_APP_PLUGIN_H_
#define FLUTTER_PLUGIN_RESTART_APP_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace restart_app {

class RestartAppPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);

  RestartAppPlugin();
  ~RestartAppPlugin() override;

  RestartAppPlugin(const RestartAppPlugin&) = delete;
  RestartAppPlugin& operator=(const RestartAppPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace restart_app

#endif  // FLUTTER_PLUGIN_RESTART_APP_PLUGIN_H_
