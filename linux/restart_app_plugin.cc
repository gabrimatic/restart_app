#include "include/restart_app/restart_app_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <errno.h>
#include <limits.h>
#include <string.h>
#include <unistd.h>

// Stored at registration time so we can pass them to execv on restart.
static char **g_argv = nullptr;

// Resolves the path to the current executable. Returns TRUE on success and
// writes a null-terminated path into |buf| of size |buf_size|.
static gboolean resolve_exe_path(char *buf, size_t buf_size) {
  ssize_t len = readlink("/proc/self/exe", buf, buf_size - 1);
  if (len <= 0 || (size_t)len >= buf_size - 1) {
    return FALSE;
  }
  buf[len] = '\0';

  // When the binary is replaced on disk while running, the kernel appends
  // " (deleted)" to the symlink target. Strip it so execv finds the new binary.
  const char *suffix = " (deleted)";
  size_t suffix_len = strlen(suffix);
  if ((size_t)len > suffix_len && strcmp(buf + len - suffix_len, suffix) == 0) {
    buf[len - suffix_len] = '\0';
  }

  return TRUE;
}

// Scheduled via g_timeout_add so the method channel response has time to reach
// Dart before the process is replaced.
static gboolean do_restart(gpointer user_data) {
  char exe_path[PATH_MAX];
  if (!resolve_exe_path(exe_path, sizeof(exe_path))) {
    g_warning("restart_app: failed to resolve executable path: %s",
              strerror(errno));
    return G_SOURCE_REMOVE;
  }

  // Verify the resolved path is executable before replacing the process.
  if (access(exe_path, X_OK) != 0) {
    g_warning("restart_app: executable not accessible: %s: %s", exe_path,
              strerror(errno));
    return G_SOURCE_REMOVE;
  }

  if (g_argv != nullptr) {
    execv(exe_path, g_argv);
  } else {
    char *fallback_argv[] = {exe_path, nullptr};
    execv(exe_path, fallback_argv);
  }

  // execv only returns on failure. The Dart side already received "ok", so
  // there is no channel to report through. Terminate to avoid leaving a
  // half-dead process that Dart believes has restarted.
  g_warning("restart_app: execv failed: %s", strerror(errno));
  _exit(1);
}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data) {
  const gchar *method = fl_method_call_get_name(method_call);

  if (strcmp(method, "restartApp") == 0) {
    // Validate that the executable is resolvable and accessible before
    // responding with success. Once "ok" is sent, failures are silent.
    char exe_path[PATH_MAX];
    if (!resolve_exe_path(exe_path, sizeof(exe_path))) {
      g_autoptr(FlMethodResponse) err_response =
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "RESTART_FAILED", "Could not resolve executable path", nullptr));
      g_autoptr(GError) err = nullptr;
      fl_method_call_respond(method_call, err_response, &err);
      return;
    }
    if (access(exe_path, X_OK) != 0) {
      g_autoptr(FlMethodResponse) err_response =
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "RESTART_FAILED", "Executable not accessible", nullptr));
      g_autoptr(GError) err = nullptr;
      fl_method_call_respond(method_call, err_response, &err);
      return;
    }

    // Respond before the restart so the Dart side receives the result.
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_string("ok")));
    g_autoptr(GError) error = nullptr;
    if (!fl_method_call_respond(method_call, response, &error)) {
      g_warning("restart_app: failed to send response: %s", error->message);
    }

    // 100ms delay to let the response reach Dart before execv replaces the
    // process. Matches the delay used on Android, macOS, and Windows.
    g_timeout_add(100, do_restart, nullptr);
  } else {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    g_autoptr(GError) error = nullptr;
    if (!fl_method_call_respond(method_call, response, &error)) {
      g_warning("restart_app: failed to send response: %s", error->message);
    }
  }
}

void restart_app_plugin_register_with_registrar(FlPluginRegistrar *registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "restart", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, nullptr,
                                            nullptr);
}

void restart_app_plugin_store_argv(int argc, char **argv) {
  (void)argc;
  g_argv = g_strdupv(argv);
}
