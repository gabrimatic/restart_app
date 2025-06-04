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
import kotlin.system.exitProcess

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
     * For any other method call, it sends a 'not implemented' result.
     */
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        if (call.method == "restartApp") {
            val args = call.arguments as? Map<String, Any> ?: mapOf()
            val delayBeforeRestart = (args["delayBeforeRestart"] as? Int) ?: 0
            val forceKill = (args["forceKill"] as? Boolean) ?: false
            
            restartApp(delayBeforeRestart, forceKill)
            result.success("ok")
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

    /**
     * Restarts the application.
     * 
     * @param delayBeforeRestart Delay in milliseconds before restarting
     * @param forceKill Whether to force kill the process (for better cleanup)
     */
    private fun restartApp(delayBeforeRestart: Int = 0, forceKill: Boolean = false) {
        val currentActivity = activity ?: return
        
        val restartAction = {
            try {
                val intent = currentActivity.packageManager.getLaunchIntentForPackage(currentActivity.packageName)
                intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                
                if (forceKill) {
                    // Use the older behavior that forces a complete process restart
                    // This helps with cleanup issues like Android Open Accessory connections
                    currentActivity.startActivity(intent)
                    currentActivity.finishAffinity()
                    
                    // Force exit the process after a small delay to ensure cleanup
                    Handler(Looper.getMainLooper()).postDelayed({
                        exitProcess(0)
                    }, 100)
                } else {
                    // Standard restart behavior
                    currentActivity.startActivity(intent)
                    currentActivity.finishAffinity()
                }
            } catch (e: Exception) {
                // Fallback to force kill if standard restart fails
                currentActivity.finishAffinity()
                exitProcess(0)
            }
        }
        
        if (delayBeforeRestart > 0) {
            Handler(Looper.getMainLooper()).postDelayed(restartAction, delayBeforeRestart.toLong())
        } else {
            restartAction()
        }
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