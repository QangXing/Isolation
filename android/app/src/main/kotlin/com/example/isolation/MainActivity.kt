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
import org.opencv.android.OpenCVLoader

class MainActivity : FlutterActivity() {

    init {
        // 静态初始化 OpenCV，避免运行时动态加载失败
        if (!OpenCVLoader.initLocal()) {
            android.util.Log.e("OpenCV", "OpenCV 静态初始化失败")
        } else {
            android.util.Log.d("OpenCV", "OpenCV 静态初始化成功")
        }
    }

    private val CHANNEL = "com.example.isolation"
    private var pendingResult: MethodChannel.Result? = null

    companion object {
        const val REQUEST_OVERLAY = 1001
        const val REQUEST_SCREEN_CAPTURE = 1002
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == "ACTION_REQUEST_SCREEN_CAPTURE") {
            ScreenCaptureHelper.requestPermission(this, REQUEST_SCREEN_CAPTURE)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkOverlayPermission" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "requestOverlayPermission" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                    startActivityForResult(intent, REQUEST_OVERLAY)
                    result.success(true)
                }
                "setFloatingBallIcon" -> {
                    val imagePath = call.argument<String>("imagePath")
                    val saved = FloatingBallService.setCustomIcon(this, imagePath)
                    result.success(saved)
                }
                "getFloatingBallIcon" -> {
                    result.success(FloatingBallService.getCustomIcon(this))
                }
                "checkAccessibilityPermission" -> {
                    result.success(InputAccessibilityService.isEnabled(this))
                }
                "requestAccessibilityPermission" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                }
                "startFloatingBall" -> {
                    if (!Settings.canDrawOverlays(this)) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val serviceIntent = Intent(this, FloatingBallService::class.java).apply {
                        action = FloatingBallService.ACTION_SHOW
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    result.success(true)
                }
                "stopFloatingBall" -> {
                    val serviceIntent = Intent(this, FloatingBallService::class.java).apply {
                        action = FloatingBallService.ACTION_HIDE
                    }
                    startService(serviceIntent)
                    result.success(true)
                }
                "executeAction" -> {
                    val type = call.argument<String>("type")
                    @Suppress("UNCHECKED_CAST")
                    val params = call.argument<Map<String, Any>>("params")
                    executeAction(type, params)
                    result.success(null)
                }
                "startRecording" -> {
                    val captureColors = call.argument<Boolean>("captureColors") ?: false
                    val started = InputAccessibilityService.startRecording(this, captureColors)
                    result.success(started)
                }
                "stopRecording" -> {
                    val steps = InputAccessibilityService.stopRecording(this)
                    result.success(steps)
                }
                "executeMacro" -> {
                    @Suppress("UNCHECKED_CAST")
                    val settings = (call.argument<Map<String, Any>>("settings") ?: emptyMap()).toMap()
                    @Suppress("UNCHECKED_CAST")
                    val rawSteps = call.argument<List<Map<String, Any>>>("steps")
                    val steps = rawSteps?.map { it.toMap() }
                    val assetsDir = call.argument<String>("assetsDir")
                    if (steps != null) {
                        InputAccessibilityService.executeMacro(this, settings, steps, assetsDir)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "dispatchClick" -> {
                    val x = call.argument<Int>("x") ?: 0
                    val y = call.argument<Int>("y") ?: 0
                    val dispatched = InputAccessibilityService.dispatchClick(this, x, y)
                    result.success(dispatched)
                }
                "checkScreenCapturePermission" -> {
                    result.success(ScreenCaptureHelper.isGranted(this))
                }
                "requestScreenCapturePermission" -> {
                    pendingResult = result
                    ScreenCaptureHelper.requestPermission(this, REQUEST_SCREEN_CAPTURE)
                }
                "captureScreenColor" -> {
                    val x = call.argument<Int>("x") ?: 0
                    val y = call.argument<Int>("y") ?: 0
                    val color = ScreenCaptureHelper.captureColor(this, x, y)
                    result.success(color)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_SCREEN_CAPTURE) {
            val granted = ScreenCaptureHelper.onActivityResult(this, resultCode, data)
            ScreenCapturePermissionRequester.onResult(granted)
            pendingResult?.success(granted)
            pendingResult = null
        }
    }

    private fun executeAction(type: String?, params: Map<String, Any>?) {
        when (type) {
            "open_url" -> {
                val url = params?.get("url") as? String ?: return
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
            }
            "launch_app" -> {
                val packageName = params?.get("packageName") as? String ?: return
                val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(intent)
            }
            "show_toast" -> {
                val message = params?.get("message") as? String ?: return
                Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
            }
        }
    }
}
