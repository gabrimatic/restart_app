package gabrimatic.info.restart
import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.os.Process
import android.os.Handler
import android.os.Looper

/**
 * `RestartPlugin` class provides a method to restart a Flutter application in Android.
 *
 * It uses the Flutter platform channels to communicate with the Flutter code.
 * Specifically, it uses a `MethodChannel` named 'restart' for this communication.
 *
 * Enhanced to ensure a complete process restart to properly apply Shorebird updates.
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
            restartApp()
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
    * Completely restarts the application to ensure updates are properly applied.
    * 
    * The restart process follows these steps:
    * 1. Creates a new launch intent using makeRestartActivityTask() which properly clears the task stack
    * 2. Starts the new activity instance
    * 3. Waits a brief moment to ensure the new activity has time to initialize
    * 4. Terminates the current process completely using Process.killProcess()
    * 5. Uses Runtime.getRuntime().exit(0) as a backup termination method
    * 
    * This implementation specifically addresses issues with Shorebird CodePush and similar
    * hot update mechanisms that require a complete process restart to apply updates.
    * 
    * If the enhanced restart fails for any reason, we fall back to the original implementation
    * but still force process termination to ensure updates are applied.
    */
    private fun restartApp() {
        activity?.let { currentActivity ->
            try {
                // Create a proper restart intent
                val packageManager = currentActivity.packageManager
                val intent = packageManager.getLaunchIntentForPackage(currentActivity.packageName)
                val componentName = intent!!.component
                val restartIntent = Intent.makeRestartActivityTask(componentName)
                
                // Start the new instance
                currentActivity.startActivity(restartIntent)
                
                // Give the new activity time to start
                Handler(Looper.getMainLooper()).postDelayed({
                    // Kill the current process completely
                    Process.killProcess(Process.myPid())
                    // Force exit as a backup method
                    Runtime.getRuntime().exit(0)
                }, 100)
            } catch (e: Exception) {
                // Fallback to the previous implementation if anything fails
                val intent = currentActivity.packageManager.getLaunchIntentForPackage(currentActivity.packageName)
                intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                currentActivity.startActivity(intent)
                currentActivity.finishAffinity()
                
                // Additionally force process termination
                Handler(Looper.getMainLooper()).postDelayed({
                    Process.killProcess(Process.myPid())
                }, 100)
            }
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