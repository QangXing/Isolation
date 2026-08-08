package com.example.isolation

import android.graphics.Point
import android.util.Log
import android.util.LruCache
import org.opencv.core.Mat
import org.opencv.core.Rect
import org.opencv.imgproc.Imgproc

/**
 * 基于中心原点 + 相对特征点的图片匹配器。
 *
 * 算法思路：
 * 1. 以参考图中心为原点，记录原点颜色。
 * 2. 在图片上选择颜色最稀有、且位于明显色块分界线（梯度大）的点作为特征点；
 *    其中距离原点最远的特征点作为主参考点，其余为副参考点。
 * 3. 把原点、主参考点、副参考点的相对偏移与颜色缓存起来，避免每次搜索重复计算。
 * 4. 搜索时，先在屏幕上找主参考点颜色；对每个候选点，沿原点方向按距离搜索原点颜色，
 *    由此自动算出缩放比例，再用该比例校验副参考点颜色。达到阈值后返回原点坐标（目标中心）。
 */
object FeaturePointMatcher {

    private const val TAG = "FeaturePointMatcher"

    private const val DEFAULT_FEATURE_COUNT = 8
    private const val DEFAULT_COLOR_TOLERANCE = 20
    private const val DEFAULT_MATCH_THRESHOLD = 0.80
    private const val DEFAULT_SEARCH_STEP = 2
    private const val DEFAULT_SCALE_SEARCH_STEP_PX = 2
    private const val DEFAULT_MIN_SCALE = 0.5
    private const val DEFAULT_MAX_SCALE = 2.0
    private const val MAX_TEMPLATE_SIZE = 1280

    /**
     * 每个图片模板预计算出的特征数据缓存。
     * 键为模板路径/名称，LRU 保留最近使用的 20 张图。
     */
    private val featureCache = LruCache<String, TemplateFeatures>(20)

    data class Result(val x: Int, val y: Int)

    private data class IntColor(val r: Int, val g: Int, val b: Int)

    private data class FeaturePoint(
        val dx: Int,
        val dy: Int,
        val r: Int,
        val g: Int,
        val b: Int
    ) {
        val distance: Double by lazy { kotlin.math.hypot(dx.toDouble(), dy.toDouble()) }
    }

    private data class TemplateFeatures(
        val originColor: IntColor,
        val primary: FeaturePoint,
        val secondaries: List<FeaturePoint>,
        val unitX: Double,
        val unitY: Double,
        val primaryDistance: Double,
        val minScale: Double,
        val maxScale: Double
    )

    fun match(
        cacheKey: String,
        template: Mat,
        frame: ScreenCaptureHelper.Frame,
        searchRect: Rect? = null,
        featureCount: Int = DEFAULT_FEATURE_COUNT,
        colorTolerance: Int = DEFAULT_COLOR_TOLERANCE,
        searchStep: Int = DEFAULT_SEARCH_STEP,
        matchThreshold: Double = DEFAULT_MATCH_THRESHOLD,
        scaleSearchStepPx: Int = DEFAULT_SCALE_SEARCH_STEP_PX,
        minScale: Double = DEFAULT_MIN_SCALE,
        maxScale: Double = DEFAULT_MAX_SCALE
    ): Result? {
        if (template.empty() || frame.width <= 0 || frame.height <= 0) return null

        var cached = featureCache.get(cacheKey)
        if (cached == null) {
            cached = extractTemplateFeatures(
                template,
                featureCount.coerceIn(1, 32),
                colorTolerance,
                minScale.coerceIn(0.1, 5.0),
                maxScale.coerceIn(0.1, 5.0)
            ) ?: return null
            featureCache.put(cacheKey, cached)
        }

        val regionX = (searchRect?.x ?: 0).coerceIn(0, frame.width - 1)
        val regionY = (searchRect?.y ?: 0).coerceIn(0, frame.height - 1)
        val regionW = (searchRect?.width ?: (frame.width - regionX))
            .coerceIn(1, frame.width - regionX)
        val regionH = (searchRect?.height ?: (frame.height - regionY))
            .coerceIn(1, frame.height - regionY)

        val threshold = matchThreshold.coerceIn(0.0, 1.0)
        val totalPoints = 2 + cached.secondaries.size // 原点 + 主参考点 + 副参考点
        val needed = kotlin.math.ceil(totalPoints * threshold).toInt()
            .coerceIn(1, totalPoints)

        val buf = frame.buffer
        val rowStride = frame.rowStride
        val pixelStride = frame.pixelStride
        val step = searchStep.coerceAtLeast(1)

        // 第一步：在屏幕上搜索主参考点颜色
        var py = regionY
        while (py < regionY + regionH) {
            var px = regionX
            while (px < regionX + regionW) {
                if (colorMatches(
                        buf, frame.width, frame.height,
                        rowStride, pixelStride, px, py,
                        cached.primary, colorTolerance
                    )
                ) {
                    val result = searchOriginAlongLine(
                        buf, frame.width, frame.height,
                        rowStride, pixelStride,
                        px, py, regionX, regionY, regionW, regionH,
                        cached, colorTolerance, scaleSearchStepPx, needed
                    )
                    if (result != null) {
                        Log.d(TAG, "命中 origin=(${result.x},${result.y}), 主参考点=($px,$py)")
                        return result
                    }
                }
                px += step
            }
            py += step
        }

        Log.d(TAG, "未命中: 主参考点/原点未满足阈值")
        return null
    }

    /**
     * 对某个主参考点候选，沿模板中主参考点到原点的方向搜索原点颜色，
     * 找到后自动计算缩放比例并校验副参考点。
     */
    private fun searchOriginAlongLine(
        buf: ByteArray, width: Int, height: Int,
        rowStride: Int, pixelStride: Int,
        primaryX: Int, primaryY: Int,
        regionX: Int, regionY: Int, regionW: Int, regionH: Int,
        features: TemplateFeatures,
        colorTolerance: Int,
        scaleStepPx: Int,
        needed: Int
    ): Result? {
        val minD = features.primaryDistance * features.minScale
        val maxD = features.primaryDistance * features.maxScale
        var d = minD
        val step = scaleStepPx.coerceAtLeast(1)

        while (d <= maxD) {
            val ox = (primaryX + features.unitX * d).toInt()
            val oy = (primaryY + features.unitY * d).toInt()
            if (ox in regionX until regionX + regionW &&
                oy in regionY until regionY + regionH &&
                colorMatches(
                    buf, width, height, rowStride, pixelStride,
                    ox, oy, features.originColor, colorTolerance
                )
            ) {
                val scale = d / features.primaryDistance
                val matched = 2 + countSecondaryMatches(
                    buf, width, height, rowStride, pixelStride,
                    ox, oy, scale, features.secondaries, colorTolerance
                )
                if (matched >= needed) {
                    return Result(ox, oy)
                }
            }
            d += step
        }
        return null
    }

    /**
     * 提取并缓存模板特征数据：原点、主参考点、副参考点。
     */
    private fun extractTemplateFeatures(
        template: Mat,
        featureCount: Int,
        colorTolerance: Int,
        minScale: Double,
        maxScale: Double
    ): TemplateFeatures? {
        val resized = resizeIfNeeded(template)
        val rgba = Mat()
        Imgproc.cvtColor(resized, rgba, Imgproc.COLOR_BGR2RGBA)
        if (resized != template) resized.release()

        val w = rgba.width()
        val h = rgba.height()
        val originX = w / 2
        val originY = h / 2
        val originColor = readColor(rgba, originX, originY) ?: run {
            rgba.release()
            return null
        }

        // 1) 量化颜色直方图，用于评估颜色稀有度
        val binCounts = IntArray(4096) // 4 bits per channel
        val allColors = Array(w * h) { IntColor(0, 0, 0) }
        for (y in 0 until h) {
            for (x in 0 until w) {
                val c = readColor(rgba, x, y) ?: continue
                allColors[y * w + x] = c
                val bin = ((c.r shr 4) shl 8) or ((c.g shr 4) shl 4) or (c.b shr 4)
                binCounts[bin]++
            }
        }

        // 2) 收集候选点：梯度大、离原点有一定距离、颜色稀有
        val candidates = mutableListOf<Candidate>()
        val minOriginDist = maxOf(5.0, minOf(w, h) / 12.0)
        for (y in 0 until h) {
            for (x in 0 until w) {
                if (x == originX && y == originY) continue
                val c = allColors[y * w + x]
                val dx = x - originX
                val dy = y - originY
                val dist = kotlin.math.hypot(dx.toDouble(), dy.toDouble())
                if (dist < minOriginDist) continue

                val grad = gradient(rgba, allColors, w, h, x, y)
                if (grad <= maxOf(colorTolerance, 8)) continue

                val bin = ((c.r shr 4) shl 8) or ((c.g shr 4) shl 4) or (c.b shr 4)
                val rarity = 1.0 / (1 + binCounts[bin])
                val score = rarity * grad
                candidates.add(Candidate(x, y, dx, dy, c, score))
            }
        }

        // 3) 优先选稀有+边界明显的点，同时保证分布分散
        candidates.sortByDescending { it.score }

        val minFeatureDist = maxOf(4.0, minOf(w, h) / (featureCount * 2.0).coerceAtLeast(2.0))
        val selected = mutableListOf<FeaturePoint>()
        for (c in candidates) {
            val tooClose = selected.any {
                kotlin.math.hypot((it.dx - c.dx).toDouble(), (it.dy - c.dy).toDouble()) < minFeatureDist
            }
            if (tooClose) continue
            selected.add(FeaturePoint(c.dx, c.dy, c.color.r, c.color.g, c.color.b))
            if (selected.size >= featureCount) break
        }

        if (selected.isEmpty()) {
            rgba.release()
            Log.w(TAG, "未提取到有效特征点")
            return null
        }

        // 4) 距离原点最远的点作为主参考点
        val primary = selected.maxByOrNull { it.distance }!!
        val secondaries = selected.filter { it !== primary }

        val primaryDistance = primary.distance
        val unitX = -primary.dx / primaryDistance
        val unitY = -primary.dy / primaryDistance

        rgba.release()

        Log.d(TAG, "特征点: 主参考点(${primary.dx},${primary.dy}), 副参考点=${secondaries.size}")
        return TemplateFeatures(
            originColor, primary, secondaries,
            unitX, unitY, primaryDistance,
            minScale, maxScale
        )
    }

    private data class Candidate(
        val x: Int, val y: Int,
        val dx: Int, val dy: Int,
        val color: IntColor,
        val score: Double
    )

    /**
     * 计算 (x,y) 与右、下邻居的颜色最大差异，作为边界梯度。
     */
    private fun gradient(
        rgba: Mat,
        colors: Array<IntColor>,
        w: Int,
        h: Int,
        x: Int,
        y: Int
    ): Int {
        val c = colors[y * w + x]
        var maxDiff = 0
        if (x + 1 < w) {
            val right = colors[y * w + (x + 1)]
            maxDiff = maxOf(maxDiff, colorDiff(c, right))
        }
        if (y + 1 < h) {
            val bottom = colors[(y + 1) * w + x]
            maxDiff = maxOf(maxDiff, colorDiff(c, bottom))
        }
        return maxDiff
    }

    private fun resizeIfNeeded(template: Mat): Mat {
        val maxDim = kotlin.math.max(template.width(), template.height())
        if (maxDim <= MAX_TEMPLATE_SIZE) return template
        val scale = MAX_TEMPLATE_SIZE.toDouble() / maxDim
        val resized = Mat()
        Imgproc.resize(template, resized, org.opencv.core.Size(template.width() * scale, template.height() * scale))
        return resized
    }

    private fun readColor(mat: Mat, x: Int, y: Int): IntColor? {
        if (x < 0 || y < 0 || x >= mat.width() || y >= mat.height()) return null
        val pixel = mat.get(y, x) ?: return null
        return IntColor(pixel[0].toInt(), pixel[1].toInt(), pixel[2].toInt())
    }

    private fun readScreenColor(
        buf: ByteArray, width: Int, height: Int,
        rowStride: Int, pixelStride: Int,
        x: Int, y: Int
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

    private fun colorMatches(
        buf: ByteArray, width: Int, height: Int,
        rowStride: Int, pixelStride: Int,
        x: Int, y: Int,
        point: FeaturePoint, tolerance: Int
    ): Boolean {
        return colorMatches(
            buf, width, height, rowStride, pixelStride,
            x, y, IntColor(point.r, point.g, point.b), tolerance
        )
    }

    private fun countSecondaryMatches(
        buf: ByteArray, width: Int, height: Int,
        rowStride: Int, pixelStride: Int,
        originX: Int, originY: Int,
        scale: Double,
        secondaries: List<FeaturePoint>,
        tolerance: Int
    ): Int {
        var matched = 0
        for (f in secondaries) {
            val sx = (originX + f.dx * scale).toInt()
            val sy = (originY + f.dy * scale).toInt()
            if (colorMatches(
                    buf, width, height, rowStride, pixelStride,
                    sx, sy, f, tolerance
                )
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
