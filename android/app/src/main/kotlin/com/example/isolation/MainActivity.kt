package com.example.isolation

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
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

    // === 悬浮球相关的权限检查/请求（新版本 Android 兼容） ===
    /** Android 13 (API 33) 通知权限：前台服务的通知需要运行时授权。 */
    private fun hasPostNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    /** 悬浮球启动前：确保通知权限已授权（未授权则先请求，再启动服务） */
    private fun ensureNotificationPermissionThenStart(result: MethodChannel.Result) {
        val startBall = {
            val serviceIntent = Intent(this, FloatingBallService::class.java).apply {
                action = FloatingBallService.ACTION_SHOW
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
                result.success(true)
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "启动悬浮球服务失败", e)
                result.success(false)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !hasPostNotificationPermission()) {
            try {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                // 无论用户同意与否，都继续启动悬浮球（无通知权限时前台服务的通知可能不显示，但悬浮球本身仍可用）
                startBall()
            } catch (e: Exception) {
                android.util.Log.w("MainActivity", "请求通知权限失败，直接启动悬浮球", e)
                startBall()
            }
        } else {
            startBall()
        }
    }

    // 使用新的 ActivityResult API 替代已弃用的 startActivityForResult + onActivityResult
    private val overlayPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { /* 权限结果由系统在 Settings.canDrawOverlays 中保存，Dart 侧会再次调用 checkOverlayPermission */ }

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* 结果不需要回调 Dart，只用于影响前台服务通知显示 */ }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkOverlayPermission" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "checkNotificationPermission" -> {
                    result.success(hasPostNotificationPermission())
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        !hasPostNotificationPermission()
                    ) {
                        try {
                            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                        } catch (e: Exception) {
                            android.util.Log.w("MainActivity", "请求通知权限失败", e)
                        }
                    }
                    result.success(true)
                }
                "requestOverlayPermission" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                    try {
                        overlayPermissionLauncher.launch(intent)
                    } catch (e: Exception) {
                        // 某些 Android 10+ 系统修改了 overlay 设置页面的返回行为，兜底直接启动
                        startActivity(intent)
                    }
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
                    // 新版本兼容：启动前检查/请求通知权限，确保前台服务通知正常显示
                    ensureNotificationPermissionThenStart(result)
                }
                "stopFloatingBall" -> {
                    val serviceIntent = Intent(this, FloatingBallService::class.java).apply {
                        action = FloatingBallService.ACTION_HIDE
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            // Android 8+ 禁止后台 startService；即使是停止动作，也用 startForegroundService 确保送达，
                            // FloatingBallService onStartCommand 收到 ACTION_HIDE 后会自己 stopForeground + stopSelf
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                    } catch (e: Exception) {
                        // 服务可能已经被系统杀死，忽略异常
                        android.util.Log.w("MainActivity", "停止悬浮球服务失败（可能已停止）", e)
                    }
                    result.success(true)
                }
                "isFloatingBallRunning" -> {
                    result.success(FloatingBallService.getInstance() != null)
                }
                "checkManageExternalStorage" -> {
                    result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            Environment.isExternalStorageManager()
                        } else {
                            true
                        }
                    )
                }
                "requestManageExternalStorage" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                    startActivity(intent)
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
            // Android 14+ 要求 VirtualDisplay 在带有 mediaProjection 前台服务类型的 Service 中创建。
            val granted = try {
                val service = FloatingBallService.getInstance()
                if (service != null) {
                    service.initScreenCapture(resultCode, data)
                } else {
                    ScreenCaptureHelper.onActivityResult(this, resultCode, data)
                }
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "屏幕录制初始化失败", e)
                false
            }
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
