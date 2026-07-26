package com.example.isolation

import android.graphics.Point
import android.util.Log
import org.opencv.core.Mat
import org.opencv.core.Rect
import org.opencv.imgproc.Imgproc

/**
 * 基于中心原点 + 相对特征点的图片匹配器。
 *
 * 算法思路：
 * 1. 以参考图片中心为“原点”，记录原点颜色。
 * 2. 在原点周围选取与原点颜色差异较大的点作为特征点，并记录它们相对原点的偏移和颜色。
 * 3. 在屏幕上搜索与原色匹配的位置，作为候选原点。
 * 4. 按相对偏移逐一校验特征点颜色，全部命中则认为找到目标，返回屏幕上的原点坐标（即目标中心）。
 *
 * 参数：
 * - featureCount：特征点采样数目，越多越稳定但越慢。
 * - colorTolerance：颜色容差。
 * - originSearchStep：原点搜索步长，越小越精确但越慢。
 */
object FeaturePointMatcher {

    private const val TAG = "FeaturePointMatcher"

    private const val DEFAULT_FEATURE_COUNT = 8
    private const val DEFAULT_COLOR_TOLERANCE = 20
    private const val DEFAULT_ORIGIN_SEARCH_STEP = 2
    private const val DEFAULT_MATCH_THRESHOLD = 0.80
    private const val MAX_TEMPLATE_SIZE = 1280

    data class Result(val x: Int, val y: Int)

    private data class IntColor(val r: Int, val g: Int, val b: Int)

    private data class Feature(
        val dx: Int,
        val dy: Int,
        val r: Int,
        val g: Int,
        val b: Int
    )

    fun match(
        template: Mat,
        frame: ScreenCaptureHelper.Frame,
        searchRect: Rect? = null,
        featureCount: Int = DEFAULT_FEATURE_COUNT,
        colorTolerance: Int = DEFAULT_COLOR_TOLERANCE,
        originSearchStep: Int = DEFAULT_ORIGIN_SEARCH_STEP,
        matchThreshold: Double = DEFAULT_MATCH_THRESHOLD
    ): Result? {
        if (template.empty() || frame.width <= 0 || frame.height <= 0) return null

        val resizedTemplate = resizeIfNeeded(template)
        val templateRgba = Mat()
        Imgproc.cvtColor(resizedTemplate, templateRgba, Imgproc.COLOR_BGR2RGBA)
        if (resizedTemplate != template) resizedTemplate.release()

        val w = templateRgba.width()
        val h = templateRgba.height()
        val originX = w / 2
        val originY = h / 2
        val originColor = readColor(templateRgba, originX, originY) ?: run {
            templateRgba.release()
            return null
        }

        val features = extractFeatures(
            templateRgba, originX, originY, originColor,
            featureCount.coerceIn(1, 32), colorTolerance
        )
        templateRgba.release()

        if (features.isEmpty()) {
            Log.w(TAG, "未提取到有效特征点")
            return null
        }

        val regionX = (searchRect?.x ?: 0).coerceIn(0, frame.width - 1)
        val regionY = (searchRect?.y ?: 0).coerceIn(0, frame.height - 1)
        val regionW = (searchRect?.width ?: (frame.width - regionX))
            .coerceIn(1, frame.width - regionX)
        val regionH = (searchRect?.height ?: (frame.height - regionY))
            .coerceIn(1, frame.height - regionY)

        val buf = frame.buffer
        val rowStride = frame.rowStride
        val pixelStride = frame.pixelStride
        val needed = kotlin.math.ceil(features.size * matchThreshold.coerceIn(0.0, 1.0)).toInt()
            .coerceIn(1, features.size)

        var bestX = -1
        var bestY = -1
        var bestMatched = 0

        var y = regionY
        while (y < regionY + regionH) {
            var x = regionX
            while (x < regionX + regionW) {
                if (!colorMatches(
                        buf, frame.width, frame.height,
                        rowStride, pixelStride, x, y,
                        originColor, colorTolerance
                    )
                ) {
                    x += originSearchStep
                    continue
                }

                val matched = countFeatureMatches(
                    buf, frame.width, frame.height,
                    rowStride, pixelStride, x, y,
                    features, colorTolerance
                )
                if (matched > bestMatched) {
                    bestMatched = matched
                    bestX = x
                    bestY = y
                    if (bestMatched >= needed) {
                        Log.d(TAG, "命中 origin=($bestX,$bestY), 命中特征点=$bestMatched/${features.size}, threshold=$matchThreshold")
                        return Result(bestX, bestY)
                    }
                }
                x += originSearchStep
            }
            y += originSearchStep
        }

        return if (bestMatched >= needed) {
            Log.d(TAG, "命中 origin=($bestX,$bestY), 命中特征点=$bestMatched/${features.size}, threshold=$matchThreshold")
            Result(bestX, bestY)
        } else {
            Log.d(TAG, "未达阈值 bestMatched=$bestMatched/${features.size}, threshold=$matchThreshold")
            null
        }
    }

    /**
     * 在模板周围选取颜色差异大、分布分散的特征点。
     */
    private fun extractFeatures(
        template: Mat,
        originX: Int,
        originY: Int,
        originColor: IntColor,
        featureCount: Int,
        tolerance: Int
    ): List<Feature> {
        val w = template.width()
        val h = template.height()

        // 在模板上均匀撒点，步长根据期望特征点数量估算
        val gridStep = maxOf(1, minOf(w, h) / (featureCount * 3))
        val candidates = mutableListOf<Triple<Int, Int, Int>>()

        var y = gridStep / 2
        while (y < h) {
            var x = gridStep / 2
            while (x < w) {
                if (x == originX && y == originY) {
                    x += gridStep
                    continue
                }
                val c = readColor(template, x, y) ?: run {
                    x += gridStep
                    continue
                }
                val diff = colorDiff(c, originColor)
                if (diff >= maxOf(tolerance, 8)) {
                    candidates.add(Triple(x, y, diff))
                }
                x += gridStep
            }
            y += gridStep
        }

        // 按颜色差异从大到小排序，优先选对比度强的点
        candidates.sortByDescending { it.third }

        val minOriginDist = maxOf(5.0, minOf(w, h) / 12.0)
        val minFeatureDist = maxOf(4.0, minOf(w, h) / (featureCount * 2.0).coerceAtLeast(2.0))

        val selected = mutableListOf<Feature>()
        for ((x, y, _) in candidates) {
            val dx = x - originX
            val dy = y - originY
            val distToOrigin = kotlin.math.hypot(dx.toDouble(), dy.toDouble())
            if (distToOrigin < minOriginDist) continue

            val tooClose = selected.any {
                kotlin.math.hypot((it.dx - dx).toDouble(), (it.dy - dy).toDouble()) < minFeatureDist
            }
            if (tooClose) continue

            val c = readColor(template, x, y) ?: continue
            selected.add(Feature(dx, dy, c.r, c.g, c.b))
            if (selected.size >= featureCount) break
        }

        return selected
    }

    private fun resizeIfNeeded(template: Mat): Mat {
        val maxDim = kotlin.math.max(template.width(), template.height())
        if (maxDim <= MAX_TEMPLATE_SIZE) return template
        val scale = MAX_TEMPLATE_SIZE.toDouble() / maxDim
        val resized = Mat()
        org.opencv.imgproc.Imgproc.resize(
            template, resized,
            org.opencv.core.Size(template.width() * scale, template.height() * scale)
        )
        return resized
    }

    private fun readColor(mat: Mat, x: Int, y: Int): IntColor? {
        if (x < 0 || y < 0 || x >= mat.width() || y >= mat.height()) return null
        val pixel = mat.get(y, x) ?: return null
        return IntColor(
            pixel[0].toInt(),
            pixel[1].toInt(),
            pixel[2].toInt()
        )
    }

    private fun readScreenColor(
        buf: ByteArray, rowStride: Int, pixelStride: Int,
        width: Int, height: Int, x: Int, y: Int
    ): IntColor? {
        if (x < 0 || y < 0 || x >= width || y >= height) return null
        val offset = y * rowStride + x * pixelStride
        if (offset + 2 >= buf.size) return null
        return IntColor(
            buf[offset].toInt() and 0xFF,
            buf[offset + 1].toInt() and 0xFF,
            buf[offset + 2].toInt() and 0xFF
        )
    }

    private fun colorMatches(
        buf: ByteArray, width: Int, height: Int,
        rowStride: Int, pixelStride: Int,
        x: Int, y: Int,
        color: IntColor, tolerance: Int
    ): Boolean {
        val c = readScreenColor(buf, rowStride, pixelStride, width, height, x, y) ?: return false
        return kotlin.math.abs(c.r - color.r) <= tolerance &&
                kotlin.math.abs(c.g - color.g) <= tolerance &&
                kotlin.math.abs(c.b - color.b) <= tolerance
    }

    private fun countFeatureMatches(
        buf: ByteArray, width: Int, height: Int,
        rowStride: Int, pixelStride: Int,
        originX: Int, originY: Int,
        features: List<Feature>, tolerance: Int
    ): Int {
        var matched = 0
        for (f in features) {
            val sx = originX + f.dx
            val sy = originY + f.dy
            val c = readScreenColor(buf, rowStride, pixelStride, width, height, sx, sy)
                ?: return 0
            if (kotlin.math.abs(c.r - f.r) <= tolerance &&
                kotlin.math.abs(c.g - f.g) <= tolerance &&
                kotlin.math.abs(c.b - f.b) <= tolerance
            ) {
                matched++
            }
        }
        return matched
    }

    private fun colorDiff(a: IntColor, b: IntColor): Int {
        return maxOf(
            kotlin.math.abs(a.r - b.r),
            kotlin.math.abs(a.g - b.g),
            kotlin.math.abs(a.b - b.b)
        )
    }
}
