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

/** Android implementation for the `restart` platform channel. */
class RestartPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "restart")
        channel.setMethodCallHandler(this)
    }

    /**
     * Handles platform-channel calls from the Dart API.
     *
     * The result is sent before the restart is triggered so the Flutter engine has time to
     * deliver it across the platform channel. Without this delay, finishAffinity() can tear
     * down the engine mid-delivery, causing a FlutterJNI detached error.
     *
     * When forceKill is true, the process is terminated immediately after the new activity
     * launches, ensuring a clean cold restart with no stale native resources. A longer delay
     * gives the new activity time to initialize before the current process exits.
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
                val currentActivity = activity

                if (currentActivity == null) {
                    result.error("RESTART_FAILED", "No activity available", null)
                    return
                }

                val pm = currentActivity.packageManager
                val pkg = currentActivity.packageName

                // Try the standard launcher intent first, then fall back to the leanback
                // launcher used by Android TV and Fire TV devices (API 21+).
                var intent = pm.getLaunchIntentForPackage(pkg)
                if (intent == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    intent = pm.getLeanbackLaunchIntentForPackage(pkg)
                }

                if (intent == null) {
                    result.error("RESTART_FAILED", "No launchable activity found for $pkg", null)
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

                // Delay the destructive operations so the platform channel result can be delivered
                // to the Dart side before the Flutter engine is torn down.
                val delay = if (forceKill) 300L else 100L
                Handler(Looper.getMainLooper()).postDelayed({
                    try {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                        currentActivity.startActivity(intent)
                        if (forceKill) {
                            Runtime.getRuntime().exit(0)
                        } else {
                            currentActivity.finishAffinity()
                        }
                    } catch (e: Exception) {
                        Log.e("RestartPlugin", "Restart failed: ${e.message}", e)
                    }
                }, delay)
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
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
