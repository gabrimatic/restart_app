package gabrimatic.info.restart

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Looper
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ActivityController
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.lang.reflect.Proxy
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [21, 34], manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
class RestartPluginTest {
    private val activities = mutableListOf<ActivityController<RecordingActivity>>()

    @After
    fun finishPendingActivityRestart() {
        // Drain any accepted activity-only request, then deliver the replacement
        // lifecycle through the same public API the host uses. No test exits the JVM.
        dispatchRestart()
        RestartPlugin().onAttachedToActivity(binding(activity()))
        activities.forEach { it.destroy() }
    }

    @Test
    fun missingActivityDoesNotBlockTheNextRequest() {
        val plugin = RestartPlugin()
        assertError("RESTART_FAILED", restart(plugin))
        val host = activity()
        addLauncher(host)
        plugin.onAttachedToActivity(binding(host))
        assertAccepted(restart(plugin))
        dispatchRestart()
        assertEquals(1, host.launches.size)
    }

    @Test
    fun missingLauncherDoesNotBlockTheNextRequest() {
        val host = activity()
        val plugin = attachedPlugin(host)
        assertError("RESTART_FAILED", restart(plugin))
        addLauncher(host)
        assertAccepted(restart(plugin))
        dispatchRestart()
        assertEquals(1, host.launches.size)
    }

    @Test
    fun packageManagerFailureDoesNotBlockTheNextRequest() {
        val host = activity()
        addLauncher(host)
        val plugin = attachedPlugin(host)
        host.failPackageLookup = true
        assertError("RESTART_FAILED", restart(plugin))
        host.failPackageLookup = false
        assertAccepted(restart(plugin))
        dispatchRestart()
        assertEquals(1, host.launches.size)
    }

    @Test
    fun deferredLaunchFailureAllowsAnotherRequest() {
        val host = activity()
        addLauncher(host)
        val plugin = attachedPlugin(host)
        host.failLaunch = true
        assertAccepted(restart(plugin))
        dispatchRestart()
        assertEquals(1, host.launchAttempts)
        assertEquals(0, host.launches.size)

        host.failLaunch = false
        assertAccepted(restart(plugin))
        dispatchRestart()
        assertEquals(2, host.launchAttempts)
        assertEquals(1, host.launches.size)
    }

    @Test
    fun concurrentPluginInstancesCannotQueueMoreThanOneLaunch() {
        val host = activity()
        addLauncher(host)
        assertAccepted(restart(attachedPlugin(host)))
        repeat(8) {
            assertError("RESTART_ALREADY_IN_PROGRESS", restart(attachedPlugin(activity())))
        }
        dispatchRestart()
        assertEquals(1, host.launches.size)
        assertEquals(1, activities.sumOf { it.get().launchAttempts })
    }

    @Test
    fun configurationReattachmentBeforeDispatchDoesNotReleaseGuard() {
        val original = activity()
        addLauncher(original)
        val plugin = attachedPlugin(original)
        assertAccepted(restart(plugin))

        plugin.onDetachedFromActivityForConfigChanges()
        val recreated = activity()
        plugin.onReattachedToActivityForConfigChanges(binding(recreated))
        assertError("RESTART_ALREADY_IN_PROGRESS", restart(plugin))
        dispatchRestart()
        assertEquals(1, original.launches.size)
        assertEquals(0, recreated.launches.size)

        val replacement = activity()
        plugin.onDetachedFromActivity()
        plugin.onAttachedToActivity(binding(replacement))
        assertAccepted(restart(plugin))
        dispatchRestart()
        assertEquals(1, replacement.launches.size)
    }

    @Test
    fun sameActivityReattachmentAfterDispatchDoesNotReleaseGuard() {
        val host = activity()
        addLauncher(host)
        val plugin = attachedPlugin(host)
        assertAccepted(restart(plugin))
        dispatchRestart()

        plugin.onDetachedFromActivityForConfigChanges()
        plugin.onReattachedToActivityForConfigChanges(binding(host))
        assertError("RESTART_ALREADY_IN_PROGRESS", restart(plugin))
        assertError("RESTART_ALREADY_IN_PROGRESS", restart(attachedPlugin(host)))
        assertEquals(1, host.launches.size)
    }

    @Test
    fun twoSuccessiveReplacementActivitiesCanRestartAgain() {
        val first = activity()
        addLauncher(first)
        val plugin = attachedPlugin(first)
        assertAccepted(restart(plugin))
        dispatchRestart()
        assertEquals(1, first.launches.size)

        // A cached engine attaches the same plugin to the replacement activity.
        val second = activity()
        plugin.onDetachedFromActivity()
        plugin.onAttachedToActivity(binding(second))
        assertAccepted(restart(plugin))
        dispatchRestart()
        assertEquals(1, second.launches.size)

        // A newly created engine uses a different plugin instance.
        val third = activity()
        val newPlugin = attachedPlugin(third)
        assertAccepted(restart(newPlugin))
        dispatchRestart()
        assertEquals(1, third.launches.size)
    }

    @Test
    fun leanbackOnlyLauncherStillRestarts() {
        val host = activity()
        addLauncher(host, Intent.CATEGORY_LEANBACK_LAUNCHER)
        assertAccepted(restart(attachedPlugin(host)))
        dispatchRestart()
        assertEquals(1, host.launches.size)
        assertEquals(
            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK,
            host.launches.single().flags and
                (Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK),
        )
    }

    private fun activity(): RecordingActivity {
        val controller = Robolectric.buildActivity(RecordingActivity::class.java).create()
        activities.add(controller)
        return controller.get()
    }

    private fun addLauncher(
        host: Activity,
        category: String = Intent.CATEGORY_LAUNCHER,
    ) {
        val manager = shadowOf(host.packageManager)
        val component = ComponentName(host.packageName, RecordingActivity::class.java.name)
        manager.addActivityIfNotPresent(component).exported = true
        manager.addIntentFilterForActivity(
            component,
            IntentFilter(Intent.ACTION_MAIN).apply { addCategory(category) },
        )
    }

    private fun attachedPlugin(host: Activity) =
        RestartPlugin().apply {
            onAttachedToActivity(binding(host))
        }

    private fun binding(host: Activity): ActivityPluginBinding =
        Proxy.newProxyInstance(
            ActivityPluginBinding::class.java.classLoader,
            arrayOf(ActivityPluginBinding::class.java),
        ) { _, method, _ ->
            check(method.name == "getActivity") { "Unexpected binding call: ${method.name}" }
            host
        } as ActivityPluginBinding

    private fun restart(plugin: RestartPlugin): CapturingResult =
        CapturingResult().also {
            plugin.onMethodCall(
                MethodCall("restartApp", mapOf("mode" to "platformDefault", "structuredResult" to true)),
                it,
            )
        }

    private fun dispatchRestart() {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(300))
    }

    private fun assertAccepted(result: CapturingResult) {
        assertEquals(1, result.responses)
        assertNull(result.errorCode)
        assertEquals(mapOf("success" to true, "mode" to "platformDefault"), result.value)
    }

    private fun assertError(
        code: String,
        result: CapturingResult,
    ) {
        assertEquals(1, result.responses)
        assertEquals(code, result.errorCode)
        assertNull(result.value)
    }

    private class CapturingResult : MethodChannel.Result {
        var responses = 0
        var value: Any? = null
        var errorCode: String? = null

        override fun success(result: Any?) {
            responses += 1
            value = result
        }

        override fun error(
            code: String,
            message: String?,
            details: Any?,
        ) {
            responses += 1
            errorCode = code
        }

        override fun notImplemented(): Unit = throw AssertionError("Restart must be implemented")
    }

    class RecordingActivity : Activity() {
        var failPackageLookup = false
        var failLaunch = false
        var launchAttempts = 0
        val launches = mutableListOf<Intent>()

        override fun getPackageManager(): PackageManager {
            if (failPackageLookup) throw SecurityException("Package lookup denied")
            return super.getPackageManager()
        }

        override fun startActivity(intent: Intent) {
            launchAttempts += 1
            if (failLaunch) throw SecurityException("Activity launch denied")
            launches.add(intent)
        }
    }
}
