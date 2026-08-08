package com.example.isolation

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log

/**
 * 专用于从服务/后台线程申请屏幕录制权限的透明 Activity。
 *
 * 从服务启动 [MainActivity] 会导致 Flutter 应用被拉到前台，权限结束后用户感知为“应用退出”。
 * 该 Activity 使用透明主题，仅用于承载系统屏幕录制授权对话框，授权完成后立即 finish，
 * 不影响原应用前台状态。
 */
class ScreenCapturePermissionActivity : Activity() {

    companion object {
        private const val TAG = "ScreenCapturePermAct"
        private const val REQUEST_CODE = 1002
        private const val KEY_REQUESTED = "requested"

        /**
         * 启动透明权限申请 Activity。
         *
         * @param context 建议使用 Application 或 Service 的 context
         */
        fun start(context: Context) {
            val intent = Intent(context, ScreenCapturePermissionActivity::class.java).apply {
                // 单任务避免重复创建；NEW_TASK 保证能从 Service 启动
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            context.startActivity(intent)
        }
    }

    private var requested = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requested = savedInstanceState?.getBoolean(KEY_REQUESTED, false) ?: false

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            notifyResult(false)
            return
        }

        if (ScreenCaptureHelper.isGranted(this)) {
            notifyResult(true)
            return
        }

        // Android 14+ 要求 MediaProjection/VirtualDisplay 必须在带有 mediaProjection 类型的前台服务中创建。
        // 透明 Activity 本身不是服务，所以先把 FloatingBallService 拉起来作为权限承载容器。
        ensureFloatingBallService()

        if (requested) {
            // 配置变化或系统回收后重建，已发起过请求，等待 onActivityResult
            Log.d(TAG, " recreated, waiting for result")
            return
        }

        try {
            val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            requested = true
            startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_CODE)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to request screen capture", e)
            notifyResult(false)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean(KEY_REQUESTED, requested)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CODE) return
        Log.d(TAG, "onActivityResult resultCode=$resultCode")

        // 服务启动是异步的，等它 ready 后再初始化屏幕录制。
        val handler = Handler(Looper.getMainLooper())
        val startTime = SystemClock.elapsedRealtime()
        val timeoutMs = 5000L
        val checkRunnable = object : Runnable {
            override fun run() {
                val service = FloatingBallService.getInstance()
                if (service != null) {
                    val granted = try {
                        Log.d(TAG, "Delegating screen capture init to FloatingBallService")
                        service.initScreenCapture(resultCode, data)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to handle screen capture result", e)
                        false
                    }
                    notifyResult(granted)
                    return
                }
                if (SystemClock.elapsedRealtime() - startTime > timeoutMs) {
                    Log.w(TAG, "FloatingBallService not ready, init from activity context")
                    val granted = try {
                        ScreenCaptureHelper.onActivityResult(this@ScreenCapturePermissionActivity, resultCode, data)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to init screen capture from activity", e)
                        false
                    }
                    notifyResult(granted)
                    return
                }
                handler.postDelayed(this, 100)
            }
        }
        handler.post(checkRunnable)
    }

    private fun notifyResult(granted: Boolean) {
        ScreenCapturePermissionRequester.onResult(granted)
        finish()
    }

    /**
     * 拉起 FloatingBallService 作为屏幕录制权限的承载容器。
     * Android 14+ 不允许在普通 Activity 上下文中创建 VirtualDisplay。
     */
    private fun ensureFloatingBallService() {
        if (FloatingBallService.getInstance() != null) return
        val intent = Intent(this, FloatingBallService::class.java).apply {
            action = FloatingBallService.ACTION_PREPARE
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start FloatingBallService", e)
        }
    }
}
