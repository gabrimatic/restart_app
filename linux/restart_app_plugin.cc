#include "include/restart_app/restart_app_plugin.h"
#include "restart_app_argv.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <errno.h>
#include <limits.h>
#include <string.h>
#include <unistd.h>

// Stored at registration time so we can pass them to execv on restart.
static char **g_argv = nullptr;
// A process can host more than one Flutter engine or plugin registration.
static gint g_restart_pending = 0;

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

static const gchar *response_error_message(const GError *error);

// Scheduled via g_timeout_add so the method channel response has time to reach
// Dart before the process is replaced.
static gboolean do_restart(gpointer user_data) {
  (void)user_data;

  char exe_path[PATH_MAX];
  if (!resolve_exe_path(exe_path, sizeof(exe_path))) {
    g_warning("restart_app: failed to resolve executable path: %s",
              strerror(errno));
    g_atomic_int_set(&g_restart_pending, 0);
    return G_SOURCE_REMOVE;
  }

  // Verify the resolved path is executable before replacing the process.
  if (access(exe_path, X_OK) != 0) {
    g_warning("restart_app: executable not accessible: %s: %s", exe_path,
              strerror(errno));
    g_atomic_int_set(&g_restart_pending, 0);
    return G_SOURCE_REMOVE;
  }

  if (g_argv != nullptr) {
    execv(exe_path, g_argv);
  } else {
    char *fallback_argv[] = {exe_path, nullptr};
    execv(exe_path, fallback_argv);
  }

  // execv only returns on failure. The Dart side already received "ok", so
  // there is no channel to report through. Keep the current process alive so
  // a transient launch failure does not turn a recoverable restart into data
  // loss. The caller can inspect this warning and retry explicitly.
  g_warning("restart_app: execv failed; keeping current process alive: %s",
            strerror(errno));
  g_atomic_int_set(&g_restart_pending, 0);
  return G_SOURCE_REMOVE;
}

static void respond_restart_capability(FlMethodCall *method_call) {
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "fullProcessRestart",
                           fl_value_new_bool(TRUE));
  fl_value_set_string_take(result, "flutterEngineRestart",
                           fl_value_new_bool(FALSE));
  fl_value_set_string_take(result, "notificationFallback",
                           fl_value_new_bool(FALSE));
  fl_value_set_string_take(result, "engineRestartConfigured",
                           fl_value_new_bool(FALSE));
  fl_value_set_string_take(result, "platformDefaultMode",
                           fl_value_new_string("process"));
  fl_value_set_string_take(result, "reason", fl_value_new_null());

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("restart_app: failed to send response: %s",
              response_error_message(error));
  }
}

static const gchar *lookup_string_arg(FlValue *args, const gchar *name,
                                      const gchar *fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }

  FlValue *value = fl_value_lookup_string(args, name);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return fallback;
  }

  return fl_value_get_string(value);
}

static gboolean lookup_bool_arg(FlValue *args, const gchar *name,
                                gboolean fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }

  FlValue *value = fl_value_lookup_string(args, name);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }

  return fl_value_get_bool(value);
}

static const gchar *response_error_message(const GError *error) {
  return error == nullptr ? "unknown channel error" : error->message;
}

static FlMethodResponse *restart_success_response(gboolean structured_result) {
  if (!structured_result) {
    return FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_string("ok")));
  }

  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "success", fl_value_new_bool(TRUE));
  fl_value_set_string_take(result, "mode", fl_value_new_string("process"));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data) {
  const gchar *method = fl_method_call_get_name(method_call);

  if (strcmp(method, "restartCapability") == 0) {
    respond_restart_capability(method_call);
  } else if (strcmp(method, "restartApp") == 0) {
    FlValue *args = fl_method_call_get_args(method_call);
    const gchar *mode = lookup_string_arg(args, "mode", "platformDefault");
    gboolean structured_result =
        lookup_bool_arg(args, "structuredResult", FALSE);

    if (strcmp(mode, "platformDefault") != 0 && strcmp(mode, "process") != 0) {
      g_autoptr(FlMethodResponse) err_response =
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "UNSUPPORTED_RESTART_MODE",
              "Requested restart mode is not supported on Linux", nullptr));
      g_autoptr(GError) err = nullptr;
      fl_method_call_respond(method_call, err_response, &err);
      return;
    }

    if (!g_atomic_int_compare_and_exchange(&g_restart_pending, 0, 1)) {
      g_autoptr(FlMethodResponse) response =
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "RESTART_ALREADY_IN_PROGRESS",
              "An application restart is already in progress", nullptr));
      g_autoptr(GError) error = nullptr;
      fl_method_call_respond(method_call, response, &error);
      return;
    }

    // Validate that the executable is resolvable and accessible before
    // responding with success. Later failures can only be logged natively.
    char exe_path[PATH_MAX];
    if (!resolve_exe_path(exe_path, sizeof(exe_path))) {
      g_atomic_int_set(&g_restart_pending, 0);
      g_autoptr(FlMethodResponse) err_response =
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "RESTART_FAILED", "Could not resolve executable path", nullptr));
      g_autoptr(GError) err = nullptr;
      fl_method_call_respond(method_call, err_response, &err);
      return;
    }
    if (access(exe_path, X_OK) != 0) {
      g_atomic_int_set(&g_restart_pending, 0);
      g_autoptr(FlMethodResponse) err_response =
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "RESTART_FAILED", "Executable not accessible", nullptr));
      g_autoptr(GError) err = nullptr;
      fl_method_call_respond(method_call, err_response, &err);
      return;
    }

    // Respond before the restart so the Dart side receives the result.
    g_autoptr(FlMethodResponse) response =
        restart_success_response(structured_result);
    g_autoptr(GError) error = nullptr;
    if (!fl_method_call_respond(method_call, response, &error)) {
      g_atomic_int_set(&g_restart_pending, 0);
      g_warning("restart_app: failed to send response: %s",
                response_error_message(error));
      return;
    }

    // Allow the channel response to drain before execv replaces the process.
    if (g_timeout_add(100, do_restart, nullptr) == 0) {
      g_atomic_int_set(&g_restart_pending, 0);
      g_warning("restart_app: failed to schedule deferred restart");
    }
  } else {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    g_autoptr(GError) error = nullptr;
    if (!fl_method_call_respond(method_call, response, &error)) {
      g_warning("restart_app: failed to send response: %s",
                response_error_message(error));
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
  if (!restart_app_replace_argv(&g_argv, argc, argv)) {
    g_warning("restart_app: failed to copy command-line arguments");
  }
}
