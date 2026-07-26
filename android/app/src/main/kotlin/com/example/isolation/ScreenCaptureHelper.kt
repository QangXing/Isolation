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
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Display
import android.view.WindowManager

object ScreenCaptureHelper {
    private const val TAG = "ScreenCaptureHelper"
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var screenWidth: Int = 0
    private var screenHeight: Int = 0
    private var density: Int = 0

    // 持续缓存最新一帧屏幕数据，避免每次读取都调用 acquireLatestImage，
    // 同时让录制时读取的颜色更接近点击发生前的状态。
    private var latestBuffer: ByteArray? = null
    private var latestRowStride: Int = 0
    private var latestPixelStride: Int = 0
    private var latestWidth: Int = 0
    private var latestHeight: Int = 0
    private val bufferLock = Any()

    /**
     * 最新一帧屏幕像素的包装，便于图像匹配类直接使用。
     */
    data class Frame(
        val buffer: ByteArray,
        val width: Int,
        val height: Int,
        val rowStride: Int,
        val pixelStride: Int
    )

    private var handlerThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null

    fun isGranted(context: Context): Boolean {
        return mediaProjection != null && virtualDisplay != null
    }

    fun requestPermission(activity: Activity, requestCode: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return
        val manager = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val intent = manager.createScreenCaptureIntent()
        activity.startActivityForResult(intent, requestCode)
    }

    fun onActivityResult(context: Context, resultCode: Int, data: Intent?, beforeVirtualDisplay: (() -> Unit)? = null): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return false
        if (resultCode != Activity.RESULT_OK || data == null) return false
        val manager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        // Android 14+ 禁止复用旧 projection 实例，先释放旧的再获取新的
        release()
        mediaProjection = manager.getMediaProjection(resultCode, data)
        mediaProjection?.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                clearCaptureResources()
                mediaProjection = null
            }
        }, null)
        // 给调用方机会在创建 VirtualDisplay 前升级前台服务类型（mediaProjection）
        beforeVirtualDisplay?.invoke()
        return try {
            initImageReader(context)
            true
        } catch (e: Exception) {
            Log.e(TAG, "initImageReader failed, clearing media projection", e)
            release()
            false
        }
    }

    private fun startBackgroundThread() {
        stopBackgroundThread()
        handlerThread = HandlerThread("ScreenCapture").apply { start() }
        backgroundHandler = Handler(handlerThread!!.looper)
    }

    private fun stopBackgroundThread() {
        backgroundHandler = null
        handlerThread?.quitSafely()
        handlerThread = null
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

        startBackgroundThread()

        imageReader?.close()
        imageReader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 3)

        // 在后台线程持续缓存最新帧，captureColor/findColor 优先读取缓存。
        imageReader?.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val planes = image.planes
                if (planes.isEmpty()) return@setOnImageAvailableListener
                val buffer = planes[0].buffer
                val pixelStride = planes[0].pixelStride
                val rowStride = planes[0].rowStride
                val capacity = buffer.capacity()
                val bytes = ByteArray(capacity)
                buffer.get(bytes)
                synchronized(bufferLock) {
                    latestBuffer = bytes
                    latestPixelStride = pixelStride
                    latestRowStride = rowStride
                    latestWidth = screenWidth
                    latestHeight = screenHeight
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                image.close()
            }
        }, backgroundHandler)

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

    /**
     * 获取最新一帧屏幕像素数据。返回 null 表示尚未缓存或权限未授予。
     */
    fun getLatestFrame(): Frame? {
        synchronized(bufferLock) {
            val buf = latestBuffer ?: return null
            if (latestWidth <= 0 || latestHeight <= 0 || latestPixelStride <= 0) return null
            return Frame(buf, latestWidth, latestHeight, latestRowStride, latestPixelStride)
        }
    }

    fun captureColor(context: Context, x: Int, y: Int): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return null
        if (mediaProjection == null || imageReader == null) {
            return null
        }

        // 优先从持续缓存读取，更快且更接近“当前”时刻
        val snapshot = synchronized(bufferLock) {
            val buf = latestBuffer
            if (buf != null && latestPixelStride > 0 && latestRowStride > 0) {
                CaptureSnapshot(buf, latestPixelStride, latestRowStride, latestWidth, latestHeight)
            } else null
        }

        if (snapshot != null) {
            try {
                val clampedX = x.coerceIn(0, snapshot.width - 1)
                val clampedY = y.coerceIn(0, snapshot.height - 1)
                val offset = clampedY * snapshot.rowStride + clampedX * snapshot.pixelStride
                if (offset + 2 < snapshot.buf.size) {
                    val r = snapshot.buf[offset].toInt() and 0xFF
                    val g = snapshot.buf[offset + 1].toInt() and 0xFF
                    val b = snapshot.buf[offset + 2].toInt() and 0xFF
                    val a = if (snapshot.pixelStride >= 4) snapshot.buf[offset + 3].toInt() and 0xFF else 0xFF
                    return (a shl 24) or (r shl 16) or (g shl 8) or b
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // fallback：直接从 ImageReader 取最新帧
        return captureColorFromImageReader(x, y)
    }

    private fun captureColorFromImageReader(x: Int, y: Int): Int? {
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

    private data class CaptureSnapshot(
        val buf: ByteArray,
        val pixelStride: Int,
        val rowStride: Int,
        val width: Int,
        val height: Int
    )

    /**
     * 在全屏或指定区域内寻找第一个匹配目标颜色的像素坐标。
     *
     * @param targetColor 形如 0xAARRGGBB 或 0xRRGGBB 的颜色
     * @param tolerance   每个通道允许的偏差
     * @param step        扫描步长（像素），越小越精确，默认 2
     * @param region      限定查找区域 [left, top, right, bottom]
     * @return 命中坐标；未命中或无屏幕权限时返回 null
     */
    fun findColor(
        context: Context,
        targetColor: Int,
        tolerance: Int = 20,
        step: Int = 2,
        region: List<*>? = null
    ): Point? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return null
        if (mediaProjection == null || imageReader == null) return null

        // 统一按 0xRRGGBB 解释（忽略 alpha 通道，屏幕像素 alpha 恒为 0xFF）
        val tr = (targetColor shr 16) and 0xFF
        val tg = (targetColor shr 8) and 0xFF
        val tb = targetColor and 0xFF
        val scanStep = step.coerceAtLeast(1)

        // 优先从缓存读取：先把引用和元数据拷出来，避免长时间持有锁阻塞 ImageReader 回调
        val snapshot = synchronized(bufferLock) {
            val buf = latestBuffer
            if (buf != null && latestPixelStride > 0 && latestRowStride > 0 && latestWidth > 0 && latestHeight > 0) {
                CaptureSnapshot(buf, latestPixelStride, latestRowStride, latestWidth, latestHeight)
            } else null
        }

        if (snapshot != null) {
            try {
                val (startX, startY, endX, endY) = parseRegion(region, snapshot.width, snapshot.height)
                var y = startY
                while (y < endY) {
                    val rowStart = y * snapshot.rowStride
                    var x = startX
                    while (x < endX) {
                        val offset = rowStart + x * snapshot.pixelStride
                        if (offset + 2 < snapshot.buf.size) {
                            val r = snapshot.buf[offset].toInt() and 0xFF
                            val g = snapshot.buf[offset + 1].toInt() and 0xFF
                            val b = snapshot.buf[offset + 2].toInt() and 0xFF
                            if (kotlin.math.abs(r - tr) <= tolerance &&
                                kotlin.math.abs(g - tg) <= tolerance &&
                                kotlin.math.abs(b - tb) <= tolerance
                            ) {
                                return Point(x, y)
                            }
                        }
                        x += scanStep
                    }
                    y += scanStep
                }
                return null
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // fallback：直接从 ImageReader 取最新帧
        return findColorFromImageReader(targetColor, tolerance, scanStep, region)
    }

    private fun findColorFromImageReader(
        targetColor: Int,
        tolerance: Int,
        step: Int,
        region: List<*>?
    ): Point? {
        try {
            val image = imageReader!!.acquireLatestImage() ?: return null
            try {
                val planes = image.planes
                if (planes.isEmpty()) return null
                val buffer = planes[0].buffer
                val pixelStride = planes[0].pixelStride
                val rowStride = planes[0].rowStride

                val tr = (targetColor shr 16) and 0xFF
                val tg = (targetColor shr 8) and 0xFF
                val tb = targetColor and 0xFF

                val (startX, startY, endX, endY) = parseRegion(region, screenWidth, screenHeight)
                var y = startY
                while (y < endY) {
                    val rowStart = y * rowStride
                    var x = startX
                    while (x < endX) {
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

    private fun parseRegion(region: List<*>?, width: Int, height: Int): IntArray {
        if (region == null || region.size < 4) {
            return intArrayOf(0, 0, width, height)
        }
        val left = (region[0] as? Number)?.toInt() ?: 0
        val top = (region[1] as? Number)?.toInt() ?: 0
        val right = (region[2] as? Number)?.toInt() ?: width
        val bottom = (region[3] as? Number)?.toInt() ?: height
        val x = left.coerceIn(0, width - 1)
        val y = top.coerceIn(0, height - 1)
        val x2 = right.coerceIn(x + 1, width)
        val y2 = bottom.coerceIn(y + 1, height)
        return intArrayOf(x, y, x2, y2)
    }

    private fun clearCaptureResources() {
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        stopBackgroundThread()
        synchronized(bufferLock) {
            latestBuffer = null
        }
    }

    fun release() {
        clearCaptureResources()
        mediaProjection?.stop()
        mediaProjection = null
    }
}
