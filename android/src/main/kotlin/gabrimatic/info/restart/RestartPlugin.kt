package gabrimatic.info.restart

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * `RestartPlugin` class provides a method to restart a Flutter application in Android.
 *
 * It uses the Flutter platform channels to communicate with the Flutter code.
 * Specifically, it uses a `MethodChannel` named 'restart' for this communication.
 *
 * The main functionality is provided by the `onMethodCall` method.
 */
class RestartPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null

    /**
     * Called when the plugin is attached to the Flutter engine.
     *
     * It initializes the `context` with the application context and
     * sets this plugin instance as the handler for method calls from Flutter.
     */
    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "restart")
        channel.setMethodCallHandler(this)
    }

    /**
     * Handles method calls from the Flutter code.
     *
     * If the method call is 'restartApp', it restarts the app and sends a successful result.
     * The result is sent before the restart is triggered so the Flutter engine has time to
     * deliver it across the platform channel. Without this delay, finishAffinity() can tear
     * down the engine mid-delivery, causing a FlutterJNI detached error.
     *
     * When forceKill is true, the process is terminated immediately after the new activity
     * launches, ensuring a clean cold restart with no stale native resources. A longer delay
     * gives the new activity time to initialize before the current process exits.
     *
     * For any other method call, it sends a 'not implemented' result.
     */
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        if (call.method == "restartApp") {
            val forceKill = call.argument<Boolean>("forceKill") ?: false
            val currentActivity = activity
            val intent = currentActivity?.packageManager?.getLaunchIntentForPackage(currentActivity.packageName)

            if (currentActivity == null || intent == null) {
                result.error("RESTART_FAILED", "Could not restart the application", null)
                return
            }

            result.success("ok")

            // Delay the destructive operations so the platform channel result can be delivered
            // to the Dart side before the Flutter engine is torn down.
            val delay = if (forceKill) 300L else 100L
            Handler(Looper.getMainLooper()).postDelayed({
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                currentActivity.startActivity(intent)
                if (forceKill) {
                    Runtime.getRuntime().exit(0)
                } else {
                    currentActivity.finishAffinity()
                }
            }, delay)
        } else {
            result.notImplemented()
        }
    }

    /**
     * Called when the plugin is detached from the Flutter engine.
     *
     * It removes the handler for method calls from Flutter.
     */
    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
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
