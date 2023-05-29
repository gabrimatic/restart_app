package gabrimatic.info.restart

import android.content.Context
import android.content.Intent
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
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
class RestartPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel

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
     * Restarts the application.
     *
     * It starts a new activity with a restart task for the launch intent of the application, 
     * and then exits the running application.
     */
    private fun restartApp() {
        context.startActivity(
            Intent.makeRestartActivityTask(
                (context.packageManager.getLaunchIntentForPackage(
                    context.packageName
                ))!!.component
            )
        )
        Runtime.getRuntime().exit(0)
    }

}
