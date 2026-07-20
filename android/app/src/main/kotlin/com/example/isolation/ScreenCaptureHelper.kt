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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val windowMetrics = windowManager.currentWindowMetrics
            val bounds = windowMetrics.bounds
            screenWidth = bounds.width()
            screenHeight = bounds.height()
            density = context.resources.configuration.densityDpi
        } else {
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
        }

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
            val planes = image.planes
            if (planes.isEmpty()) {
                image.close()
                return null
            }
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
            image.close()
            return (a shl 24) or (r shl 16) or (g shl 8) or b
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
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
