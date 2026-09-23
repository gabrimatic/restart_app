package com.example.restart_android_proof

import android.os.Bundle
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** Disposable QA host. Never shipped as part of the restart_app plugin. */
class MainActivity : FlutterActivity() {
    private val proofActivityId = UUID.randomUUID().toString()

    private fun record(event: String) {
        val value = JSONObject()
            .put("event", event)
            .put("time", System.currentTimeMillis())
            .put("activity", proofActivityId)
            .put("pid", Process.myPid())
            .put("orientation", resources.configuration.orientation)
        File(filesDir, "restart-proof-native.jsonl").appendText("$value\n")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "restart_proof_host")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "host" -> result.success(
                        mapOf(
                            "filesDirectory" to filesDir.absolutePath,
                            "activity" to proofActivityId,
                            "orientation" to resources.configuration.orientation,
                        ),
                    )
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        record("onCreate")
    }

    override fun onResume() {
        super.onResume()
        record("onResume")
    }

    override fun onPause() {
        record("onPause")
        super.onPause()
    }

    override fun onDestroy() {
        record("onDestroy")
        super.onDestroy()
    }
}
