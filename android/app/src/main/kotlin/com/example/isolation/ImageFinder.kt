package com.example.isolation

import android.content.Context
import android.graphics.Point
import android.util.Log
import org.opencv.core.Mat
import org.opencv.core.Rect
import org.opencv.imgcodecs.Imgcodecs
import java.io.File

/**
 * 图片查找入口。
 *
 * 现在只使用“中心原点 + 相对特征点”算法：
 * 以参考图中心为原点，在周围选取颜色差异明显的特征点并记录相对偏移，
 * 然后在屏幕上找原点颜色并校验各特征点颜色，返回目标中心坐标。
 */
object ImageFinder {

    private const val TAG = "ImageFinder"

    fun find(
        context: Context,
        assetsDir: String?,
        imageName: String,
        threshold: Double = 0.80,
        region: List<*>? = null,
        options: Map<String, Any>? = null
    ): Point? {
        if (!ScreenCaptureHelper.isGranted(context)) return null

        val templatePath = resolveTemplatePath(assetsDir, imageName) ?: return null
        val template = loadTemplate(templatePath) ?: return null

        val frame = ScreenCaptureHelper.getLatestFrame() ?: run {
            template.release()
            return null
        }

        return try {
            val searchRect = parseSearchRegion(region, frame.width, frame.height)
            val result = FeaturePointMatcher.match(
                template,
                frame,
                searchRect,
                featureCount = (options?.get("featureCount") as? Number)?.toInt() ?: 8,
                colorTolerance = (options?.get("colorTolerance") as? Number)?.toInt() ?: 20,
                originSearchStep = (options?.get("originSearchStep") as? Number)?.toInt() ?: 2,
                matchThreshold = (options?.get("featurePointThreshold") as? Number)?.toDouble() ?: 0.80
            )
            if (result != null) {
                Log.d(TAG, "find: 命中 (${result.x}, ${result.y})")
                Point(result.x, result.y)
            } else {
                Log.d(TAG, "find: 未命中")
                null
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        } finally {
            template.release()
        }
    }

    private fun resolveTemplatePath(assetsDir: String?, imageName: String): String? {
        if (assetsDir.isNullOrEmpty()) return null
        val file = File(assetsDir, imageName)
        return if (file.exists()) file.absolutePath else null
    }

    private fun loadTemplate(path: String): Mat? {
        return try {
            val mat = Imgcodecs.imread(path, Imgcodecs.IMREAD_COLOR)
            if (mat.empty()) null else mat
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
