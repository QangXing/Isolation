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
                "startMacroRecording" -> {
                    val started = InputAccessibilityService.startRecording(this)
                    result.success(started)
                }
                "stopMacroRecording" -> {
                    val steps = InputAccessibilityService.stopRecording(this)
                    result.success(steps)
                }
                "executeMacro" -> {
                    val macroId = call.argument<String>("macroId") ?: ""
                    val loop = call.argument<Boolean>("loop") ?: false
                    val smartRecognition = call.argument<Boolean>("smartRecognition") ?: false
                    val steps = call.argument<List<Map<String, Any>>>("steps") ?: emptyList()
                    InputAccessibilityService.executeMacro(this, macroId, steps, loop, smartRecognition)
                    result.success(true)
                }
                "stopMacroExecution" -> {
                    val stopped = InputAccessibilityService.stopExecution(this)
                    result.success(stopped)
                }
                "isRecording" -> {
                    result.success(InputAccessibilityService.isRecording())
                }
                "isExecuting" -> {
                    result.success(InputAccessibilityService.isExecuting())
                }
                "setMacroConfig" -> {
                    val macroId = call.argument<String>("macroId") ?: ""
                    val loop = call.argument<Boolean>("loop") ?: false
                    val smartRecognition = call.argument<Boolean>("smartRecognition") ?: false
                    val steps = call.argument<List<Map<String, Any>>>("steps")
                    InputAccessibilityService.setMacroConfig(macroId, loop, smartRecognition, steps)
                    result.success(null)
                }
                "showFloatingBallToast" -> {
                    val message = call.argument<String>("message") ?: ""
                    FloatingBallService.showToast(this, message)
                    result.success(null)
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
