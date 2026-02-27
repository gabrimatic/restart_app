#ifndef FLUTTER_PLUGIN_RESTART_APP_PLUGIN_H_
#define FLUTTER_PLUGIN_RESTART_APP_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

FLUTTER_PLUGIN_EXPORT void restart_app_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

// Call from main() before running the Flutter engine to preserve argv for
// restart. Without this, restarted processes lose their original arguments.
FLUTTER_PLUGIN_EXPORT void restart_app_plugin_store_argv(int argc, char** argv);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_RESTART_APP_PLUGIN_H_
