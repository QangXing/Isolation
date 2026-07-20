package com.example.isolation

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Point
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.view.Display
import android.view.WindowManager

object ScreenCaptureHelper {
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var screenWidth: Int = 0
    private var screenHeight: Int = 0
    private var density: Int = 0

    fun isGranted(context: Context): Boolean {
        return mediaProjection != null
    }

    fun requestPermission(activity: Activity, requestCode: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return
        val manager = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val intent = manager.createScreenCaptureIntent()
        activity.startActivityForResult(intent, requestCode)
    }

    fun onActivityResult(context: Context, resultCode: Int, data: Intent?): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return false
        if (resultCode != Activity.RESULT_OK || data == null) return false
        val manager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = manager.getMediaProjection(resultCode, data)
        initImageReader(context)
        return true
    }

    private fun initImageReader(context: Context) {
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        @Suppress("DEPRECATION")
        val display: Display = windowManager.defaultDisplay
        @Suppress("DEPRECATION")
        val point = Point()
        @Suppress("DEPRECATION")
        display.getRealSize(point)
        screenWidth = point.x
        screenHeight = point.y
        @Suppress("DEPRECATION")
        val metrics = context.resources.displayMetrics
        density = metrics.densityDpi

        imageReader?.close()
        imageReader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 2)

        virtualDisplay?.release()
        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "isolation_screen_capture",
            screenWidth,
            screenHeight,
            density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface,
            null,
            null
        )
    }

    fun captureColor(context: Context, x: Int, y: Int): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return null
        if (mediaProjection == null || imageReader == null) {
            return null
        }
        try {
            val image = imageReader!!.acquireLatestImage() ?: return null
            try {
                val planes = image.planes
                if (planes.isEmpty()) return null
                val buffer = planes[0].buffer
                val pixelStride = planes[0].pixelStride
                val rowStride = planes[0].rowStride
                val clampedX = x.coerceIn(0, screenWidth - 1)
                val clampedY = y.coerceIn(0, screenHeight - 1)
                val offset = clampedY * rowStride + clampedX * pixelStride
                buffer.position(offset)
                val r = buffer.get().toInt() and 0xFF
                val g = buffer.get().toInt() and 0xFF
                val b = buffer.get().toInt() and 0xFF
                val a = if (pixelStride >= 4) buffer.get().toInt() and 0xFF else 0xFF
                return (a shl 24) or (r shl 16) or (g shl 8) or b
            } finally {
                image.close()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }

    /**
     * 在全屏范围内寻找第一个匹配目标颜色的像素坐标。
     *
     * @param targetColor 形如 0xAARRGGBB 或 0xRRGGBB 的颜色
     * @param tolerance   每个通道允许的偏差
     * @param step        扫描步长（像素），>1 可加速但会降低精度
     * @return 命中坐标；未命中或无屏幕权限时返回 null
     */
    fun findColor(
        context: Context,
        targetColor: Int,
        tolerance: Int = 20,
        step: Int = 4
    ): Point? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return null
        if (mediaProjection == null || imageReader == null) return null

        // 统一按 0xRRGGBB 解释（忽略 alpha 通道，屏幕像素 alpha 恒为 0xFF）
        val tr = (targetColor shr 16) and 0xFF
        val tg = (targetColor shr 8) and 0xFF
        val tb = targetColor and 0xFF

        try {
            val image = imageReader!!.acquireLatestImage() ?: return null
            try {
                val planes = image.planes
                if (planes.isEmpty()) return null
                val buffer = planes[0].buffer
                val pixelStride = planes[0].pixelStride
                val rowStride = planes[0].rowStride

                val h = screenHeight
                val w = screenWidth
                var y = 0
                while (y < h) {
                    val rowStart = y * rowStride
                    var x = 0
                    while (x < w) {
                        val offset = rowStart + x * pixelStride
                        if (offset + 2 < buffer.capacity()) {
                            buffer.position(offset)
                            val r = buffer.get().toInt() and 0xFF
                            val g = buffer.get().toInt() and 0xFF
                            val b = buffer.get().toInt() and 0xFF
                            if (kotlin.math.abs(r - tr) <= tolerance &&
                                kotlin.math.abs(g - tg) <= tolerance &&
                                kotlin.math.abs(b - tb) <= tolerance
                            ) {
                                return Point(x, y)
                            }
                        }
                        x += step
                    }
                    y += step
                }
            } finally {
                image.close()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return null
    }

    fun release() {
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        mediaProjection?.stop()
        mediaProjection = null
    }
}
