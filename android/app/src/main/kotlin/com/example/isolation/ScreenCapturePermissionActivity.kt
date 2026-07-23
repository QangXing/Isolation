package com.example.isolation

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle

/**
 * 专用于从服务/后台线程申请屏幕录制权限的透明 Activity。
 *
 * 从服务启动 [MainActivity] 会导致 Flutter 应用被拉到前台，权限结束后用户感知为“应用退出”。
 * 该 Activity 使用透明主题，仅用于承载系统屏幕录制授权对话框，授权完成后立即 finish，
 * 不影响原应用前台状态。
 */
class ScreenCapturePermissionActivity : Activity() {

    companion object {
        private const val REQUEST_CODE = 1002

        /**
         * 启动透明权限申请 Activity。
         *
         * @param context 建议使用 Application 或 Service 的 context
         */
        fun start(context: Context) {
            val intent = Intent(context, ScreenCapturePermissionActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            context.startActivity(intent)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            ScreenCapturePermissionRequester.onResult(false)
            finish()
            return
        }
        if (ScreenCaptureHelper.isGranted(this)) {
            ScreenCapturePermissionRequester.onResult(true)
            finish()
            return
        }
        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_CODE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE) {
            val granted = ScreenCaptureHelper.onActivityResult(this, resultCode, data)
            ScreenCapturePermissionRequester.onResult(granted)
            finish()
        }
    }
}
