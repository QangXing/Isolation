package com.example.isolation

import android.content.Context
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object ScreenCapturePermissionRequester {

    private val lock = Any()
    private var latch: CountDownLatch? = null
    private var result: Boolean = false

    /**
     * 阻塞式申请屏幕录制权限。调用方必须在后台线程调用。
     *
     * 内部使用透明的 [ScreenCapturePermissionActivity] 承载系统授权对话框，
     * 避免拉起 [MainActivity] 导致 Flutter 应用被强制带到前台。
     *
     * @param context 用于启动透明 Activity 的 Context（需为 Application/Service）
     * @param timeoutMs 等待超时，默认 30 秒
     * @return 是否获得权限
     */
    fun request(context: Context, timeoutMs: Long = 30000): Boolean {
        val newLatch: CountDownLatch
        synchronized(lock) {
            result = false
            newLatch = CountDownLatch(1)
            latch = newLatch
        }

        ScreenCapturePermissionActivity.start(context)

        val success = newLatch.await(timeoutMs, TimeUnit.MILLISECONDS)
        return success && synchronized(lock) { result }
    }

    /**
     * 由 [ScreenCapturePermissionActivity.onActivityResult] 调用。
     */
    fun onResult(granted: Boolean) {
        synchronized(lock) {
            result = granted
            latch?.countDown()
        }
    }
}
