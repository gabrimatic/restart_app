package gabrimatic.info.restart

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.lang.ref.WeakReference

/** Android implementation for the `restart` platform channel. */
class RestartPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null

    private class PendingRestart(
        activity: Activity,
        val forceKill: Boolean,
    ) {
        val originatingActivity = WeakReference(activity)
        var launchDispatched = false
    }

    private companion object {
        // Platform-channel handlers and ActivityAware callbacks run on the main looper.
        // This state is shared by every plugin instance, including other Flutter engines.
        var pendingRestart: PendingRestart? = null

        fun clearPendingRestart(request: PendingRestart) {
            if (pendingRestart === request) {
                pendingRestart = null
            }
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "restart")
        channel.setMethodCallHandler(this)
    }

    /**
     * Handles platform-channel calls from the Dart API.
     *
     * The result is sent before the restart is triggered so the Flutter engine has time to
     * deliver it across the platform channel. Without this delay, the task teardown can rip
     * down the engine mid-delivery, causing a FlutterJNI detached error.
     *
     * When forceKill is true, the longer delay lets the old engine deliver the response.
     * startActivity then requests the replacement launch and the current process exits
     * immediately, ensuring a cold restart with no stale native resources.
     */
    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        when (call.method) {
            "restartCapability" -> {
                result.success(
                    mapOf(
                        "fullProcessRestart" to true,
                        "flutterEngineRestart" to false,
                        "notificationFallback" to false,
                        "engineRestartConfigured" to false,
                        "platformDefaultMode" to "platformDefault",
                        "reason" to null,
                    ),
                )
            }

            "restartApp" -> {
                val mode = call.argument<String>("mode") ?: "platformDefault"
                val structuredResult = call.argument<Boolean>("structuredResult") ?: false
                if (mode != "platformDefault" && mode != "process") {
                    result.error(
                        "UNSUPPORTED_RESTART_MODE",
                        "Restart mode '$mode' is not supported on Android.",
                        null,
                    )
                    return
                }

                val forceKill = mode == "process" || (call.argument<Boolean>("forceKill") ?: false)
                val resolvedMode = if (forceKill) "process" else "platformDefault"
                if (pendingRestart != null) {
                    result.error(
                        "RESTART_ALREADY_IN_PROGRESS",
                        "A restart is already in progress.",
                        null,
                    )
                    return
                }
                val currentActivity = activity

                if (currentActivity == null) {
                    result.error("RESTART_FAILED", "No activity available", null)
                    return
                }

                val request = PendingRestart(currentActivity, forceKill)
                pendingRestart = request

                val intent =
                    try {
                        val pm = currentActivity.packageManager
                        val pkg = currentActivity.packageName
                        // Android TV and Fire TV may expose only a leanback launcher.
                        val launcher =
                            pm.getLaunchIntentForPackage(pkg)
                                ?: if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                    pm.getLeanbackLaunchIntentForPackage(pkg)
                                } else {
                                    null
                                }
                        launcher?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                    } catch (e: Exception) {
                        clearPendingRestart(request)
                        result.error("RESTART_FAILED", "Unable to find launch activity: ${e.message}", null)
                        return
                    }

                if (intent == null) {
                    clearPendingRestart(request)
                    result.error("RESTART_FAILED", "No launchable activity found", null)
                    return
                }

                // Delay the destructive operations so the platform channel result can be delivered
                // to the Dart side before the Flutter engine is torn down.
                val delay = if (forceKill) 300L else 100L
                val queued =
                    try {
                        Handler(Looper.getMainLooper()).postDelayed({
                            try {
                                // Keep the guard until a replacement activity attaches. Releasing
                                // here would let another engine restart during task teardown.
                                request.launchDispatched = true
                                // CLEAR_TASK already finishes the previous task's activities.
                                currentActivity.startActivity(intent)
                                if (forceKill) {
                                    Runtime.getRuntime().exit(0)
                                }
                            } catch (e: Exception) {
                                clearPendingRestart(request)
                                Log.e("RestartPlugin", "Restart failed: ${e.message}", e)
                            }
                        }, delay)
                    } catch (e: Exception) {
                        clearPendingRestart(request)
                        result.error("RESTART_FAILED", "Unable to schedule restart: ${e.message}", null)
                        return
                    }

                if (!queued) {
                    clearPendingRestart(request)
                    result.error("RESTART_FAILED", "Unable to schedule restart", null)
                    return
                }

                if (structuredResult) {
                    result.success(
                        mapOf(
                            "success" to true,
                            "mode" to resolvedMode,
                        ),
                    )
                } else {
                    result.success("ok")
                }
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        val pending = pendingRestart
        if (pending != null &&
            pending.launchDispatched &&
            !pending.forceKill &&
            pending.originatingActivity.get() !== binding.activity
        ) {
            clearPendingRestart(pending)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
