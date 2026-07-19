package com.example.isolation

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.example.isolation/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "startFloatingBall" -> {
                    val intent = Intent(this, FloatingBallService::class.java).apply {
                        action = FloatingBallService.ACTION_SHOW
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopFloatingBall" -> {
                    val intent = Intent(this, FloatingBallService::class.java).apply {
                        action = FloatingBallService.ACTION_HIDE
                    }
                    startService(intent)
                    result.success(true)
                }
                "updateFloatingBallMacro" -> {
                    val intent = Intent(this, FloatingBallService::class.java).apply {
                        action = FloatingBallService.ACTION_UPDATE_MACRO
                    }
                    startService(intent)
                    result.success(true)
                }
                "checkOverlayPermission" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "requestOverlayPermission" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                    startActivity(intent)
                    result.success(null)
                }
                "checkAccessibilityPermission" -> {
                    result.success(InputAccessibilityService.isEnabled(this))
                }
                "requestAccessibilityPermission" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    startActivity(intent)
                    result.success(null)
                }
                "executeAction" -> {
                    val type = call.argument<String>("type")
                    val params = call.argument<Map<String, Any>>("params")
                    executeAction(type, params)
                    result.success(null)
                }
                "startRecording" -> {
                    result.success(InputAccessibilityService.startRecording())
                }
                "stopRecording" -> {
                    Thread {
                        val steps = InputAccessibilityService.stopRecording()
                        runOnUiThread { result.success(steps) }
                    }.start()
                }
                "executeMacro" -> {
                    @Suppress("UNCHECKED_CAST")
                    val steps = call.argument<List<Map<String, Any>>>("steps") ?: emptyList()
                    val loop = call.argument<Boolean>("loop") ?: false
                    val smartRecognition = call.argument<Boolean>("smartRecognition") ?: false
                    result.success(InputAccessibilityService.executeMacro(steps, loop, smartRecognition))
                }
                "cancelMacro" -> {
                    InputAccessibilityService.cancelExecution()
                    result.success(true)
                }
                "isMacroExecuting" -> {
                    result.success(InputAccessibilityService.isExecuting())
                }
                "dispatchClick" -> {
                    val x = call.argument<Int>("x") ?: 0
                    val y = call.argument<Int>("y") ?: 0
                    result.success(InputAccessibilityService.dispatchClick(x, y))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun executeAction(type: String?, params: Map<String, Any>?) {
        when (type) {
            "open_url" -> {
                val url = params?.get("url") as? String ?: return
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            }
            "launch_app" -> {
                val packageName = params?.get("package") as? String ?: return
                val intent = packageManager.getLaunchIntentForPackage(packageName)
                if (intent != null) {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                } else {
                    Toast.makeText(this, "无法打开应用", Toast.LENGTH_SHORT).show()
                }
            }
            "show_toast" -> {
                val message = params?.get("message") as? String ?: "Hello"
                Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
            }
        }
    }
}
