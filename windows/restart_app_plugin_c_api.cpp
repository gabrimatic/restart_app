#include "include/restart_app/restart_app_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "restart_app_plugin.h"

void RestartAppPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  restart_app::RestartAppPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
