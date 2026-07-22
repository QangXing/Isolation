package com.example.isolation

import android.content.Context
import android.graphics.Point
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.Rect
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import java.io.File

/**
 * 基于 OpenCV 模板匹配的图片查找器。
 *
 * 在屏幕上搜索与模板图片最相似的区域，命中后返回目标中心点坐标。
 * 默认使用灰度 + TM_CCOEFF_NORMED 匹配，可通过 [region] 限定搜索范围以提升速度。
 */
object ImageFinder {

    private const val DEFAULT_THRESHOLD = 0.80

    /**
     * 在屏幕上查找模板图片。
     *
     * @param context 用于获取插件资源目录
     * @param assetsDir 插件资源目录绝对路径
     * @param imageName 模板图片文件名（如 "button_login.jpg"）
     * @param threshold 相似度阈值，0.0 ~ 1.0，默认 0.80
     * @param region 可选搜索区域 [left, top, right, bottom]，未指定则全屏
     * @return 命中区域中心坐标；未命中或无屏幕权限时返回 null
     */
    fun find(
        context: Context,
        assetsDir: String?,
        imageName: String,
        threshold: Double = DEFAULT_THRESHOLD,
        region: List<*>? = null
    ): Point? {
        if (!ScreenCaptureHelper.isGranted(context)) return null

        val templatePath = resolveTemplatePath(assetsDir, imageName) ?: return null
        val templateGray = loadTemplateGray(templatePath) ?: return null

        val frame = ScreenCaptureHelper.getLatestFrame() ?: return null
        var screenMat: Mat? = null
        var screenGray: Mat? = null
        var searchMat: Mat? = null
        var resultMat: Mat? = null

        try {
            screenMat = frameToMat(frame) ?: return null
            screenGray = Mat()
            Imgproc.cvtColor(screenMat, screenGray, Imgproc.COLOR_RGBA2GRAY)

            val searchRect = parseSearchRegion(region, frame.width, frame.height)
            searchMat = if (searchRect != null) {
                Mat(screenGray, searchRect)
            } else {
                screenGray
            }

            // 模板不能比搜索区域大
            if (templateGray.width() > searchMat.width() || templateGray.height() > searchMat.height()) {
                return null
            }

            resultMat = Mat()
            Imgproc.matchTemplate(searchMat, templateGray, resultMat, Imgproc.TM_CCOEFF_NORMED)
            val mmr = Core.minMaxLoc(resultMat)

            return if (mmr.maxVal >= threshold) {
                val matchX = mmr.maxLoc.x.toInt()
                val matchY = mmr.maxLoc.y.toInt()
                val offsetX = searchRect?.x ?: 0
                val offsetY = searchRect?.y ?: 0
                val centerX = offsetX + matchX + templateGray.width() / 2
                val centerY = offsetY + matchY + templateGray.height() / 2
                Point(centerX, centerY)
            } else {
                null
            }
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        } finally {
            resultMat?.release()
            searchMat?.takeIf { it !== screenGray }?.release()
            screenGray?.release()
            screenMat?.release()
            templateGray.release()
        }
    }

    private fun resolveTemplatePath(assetsDir: String?, imageName: String): String? {
        if (assetsDir.isNullOrEmpty()) return null
        val file = File(assetsDir, imageName)
        return if (file.exists()) file.absolutePath else null
    }

    private fun loadTemplateGray(path: String): Mat? {
        return try {
            val mat = Imgcodecs.imread(path, Imgcodecs.IMREAD_COLOR)
            if (mat.empty()) return null
            val gray = Mat()
            Imgproc.cvtColor(mat, gray, Imgproc.COLOR_BGR2GRAY)
            gray
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun frameToMat(frame: ScreenCaptureHelper.Frame): Mat? {
        val buf = frame.buffer
        val w = frame.width
        val h = frame.height
        val rowStride = frame.rowStride
        val pixelStride = frame.pixelStride
        if (w <= 0 || h <= 0 || pixelStride <= 0) return null

        return try {
            val mat = Mat(h, w, CvType.CV_8UC4)
            if (rowStride == w * pixelStride) {
                // 无 padding，直接写入
                mat.put(0, 0, buf)
            } else {
                // 逐行复制，跳过 row padding
                val rowBytes = ByteArray(w * 4)
                for (y in 0 until h) {
                    val srcStart = y * rowStride
                    for (x in 0 until w) {
                        val srcOffset = srcStart + x * pixelStride
                        val dstOffset = x * 4
                        rowBytes[dstOffset] = buf[srcOffset]
                        rowBytes[dstOffset + 1] = buf[srcOffset + 1]
                        rowBytes[dstOffset + 2] = buf[srcOffset + 2]
                        rowBytes[dstOffset + 3] = buf[srcOffset + 3]
                    }
                    mat.put(y, 0, rowBytes)
                }
            }
            mat
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun parseSearchRegion(region: List<*>?, screenW: Int, screenH: Int): Rect? {
        if (region == null || region.size < 4) return null
        val left = (region[0] as? Number)?.toInt() ?: return null
        val top = (region[1] as? Number)?.toInt() ?: return null
        val right = (region[2] as? Number)?.toInt() ?: return null
        val bottom = (region[3] as? Number)?.toInt() ?: return null
        val x = left.coerceIn(0, screenW - 1)
        val y = top.coerceIn(0, screenH - 1)
        val width = (right - x).coerceIn(1, screenW - x)
        val height = (bottom - y).coerceIn(1, screenH - y)
        return Rect(x, y, width, height)
    }
}
