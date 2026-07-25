package com.example.isolation

import android.util.Log
import org.opencv.core.Mat
import org.opencv.core.Rect
import org.opencv.imgproc.Imgproc

/**
 * 点采样图片匹配器。
 *
 * 在参考图上等间隔取点并记录颜色，然后在屏幕上以多个缩放比例滑动窗口比对。
 * 只要足够多的采样点颜色匹配（达到阈值），即认为命中，返回命中区域中心。
 * 相比传统模板匹配，对缩放、轻微形变更鲁棒。
 */
object SampledPointMatcher {

    private const val TAG = "SampledPointMatcher"

    private const val DEFAULT_GRID = 16
    private const val DEFAULT_COLOR_TOLERANCE = 20
    private const val DEFAULT_MIN_SCALE = 0.5
    private const val DEFAULT_MAX_SCALE = 2.0
    private const val DEFAULT_SCALE_STEP = 0.1
    private const val DEFAULT_THRESHOLD = 0.70
    private const val DEFAULT_POSITION_STEP = 4

    data class Result(
        val score: Double,
        val loc: org.opencv.core.Point,
        val scale: Double,
        val templateW: Int,
        val templateH: Int
    )

    fun match(
        template: Mat,
        screen: Mat,
        searchRect: Rect? = null,
        gridSize: Int = DEFAULT_GRID,
        colorTolerance: Int = DEFAULT_COLOR_TOLERANCE,
        minScale: Double = DEFAULT_MIN_SCALE,
        maxScale: Double = DEFAULT_MAX_SCALE,
        scaleStep: Double = DEFAULT_SCALE_STEP,
        matchThreshold: Double = DEFAULT_THRESHOLD,
        positionStep: Int = DEFAULT_POSITION_STEP
    ): Result? {
        if (template.empty() || screen.empty()) return null

        val templateRgba = Mat()
        Imgproc.cvtColor(template, templateRgba, Imgproc.COLOR_BGR2RGBA)

        val samples = extractSamples(templateRgba, gridSize)
        if (samples.isEmpty()) {
            templateRgba.release()
            Log.w(TAG, "未提取到有效采样点")
            return null
        }
        val sampleCount = samples.size

        val regionX = searchRect?.x ?: 0
        val regionY = searchRect?.y ?: 0
        val regionW = searchRect?.width ?: screen.width()
        val regionH = searchRect?.height ?: screen.height()

        var bestScore = matchThreshold
        var bestLoc = org.opencv.core.Point()
        var bestScale = 1.0
        var bestW = 0
        var bestH = 0

        try {
            var scale = minScale
            while (scale <= maxScale + 1e-6) {
                val patternW = (templateRgba.width() * scale).toInt()
                val patternH = (templateRgba.height() * scale).toInt()
                if (patternW > regionW || patternH > regionH) {
                    scale += scaleStep
                    continue
                }

                val stepX = maxOf(positionStep, patternW / 8)
                val stepY = maxOf(positionStep, patternH / 8)

                var x = regionX
                while (x + patternW <= regionX + regionW) {
                    var y = regionY
                    while (y + patternH <= regionY + regionH) {
                        val matched = countMatches(
                            screen, x, y, scale,
                            samples, colorTolerance, bestScore, sampleCount
                        )
                        val score = matched / sampleCount.toDouble()
                        if (score > bestScore) {
                            bestScore = score
                            bestLoc = org.opencv.core.Point(x.toDouble(), y.toDouble())
                            bestScale = scale
                            bestW = patternW
                            bestH = patternH
                        }
                        y += stepY
                    }
                    x += stepX
                }

                scale += scaleStep
            }
        } finally {
            templateRgba.release()
        }

        return if (bestScore >= matchThreshold) {
            Log.d(TAG, "命中 score=${"%.3f".format(bestScore)}, scale=${"%.2f".format(bestScale)}, loc=(${(bestLoc.x + bestW / 2).toInt()}, ${(bestLoc.y + bestH / 2).toInt()})")
            Result(bestScore, bestLoc, bestScale, bestW, bestH)
        } else null
    }

    private data class Sample(val x: Int, val y: Int, val r: Int, val g: Int, val b: Int)

    private fun extractSamples(template: Mat, gridSize: Int): List<Sample> {
        val w = template.width()
        val h = template.height()
        if (w <= 0 || h <= 0) return emptyList()

        val stepX = maxOf(1, w / gridSize)
        val stepY = maxOf(1, h / gridSize)

        val samples = mutableListOf<Sample>()
        var y = stepY / 2
        while (y < h) {
            var x = stepX / 2
            while (x < w) {
                val pixel = template.get(y, x) ?: continue
                val r = pixel[0].toInt()
                val g = pixel[1].toInt()
                val b = pixel[2].toInt()
                val a = pixel.getOrElse(3) { 255.0 }.toInt()
                if (a >= 128) {
                    samples.add(Sample(x, y, r, g, b))
                }
                x += stepX
            }
            y += stepY
        }
        return samples
    }

    private fun countMatches(
        screen: Mat,
        offsetX: Int,
        offsetY: Int,
        scale: Double,
        samples: List<Sample>,
        tolerance: Int,
        currentBestScore: Double,
        sampleCount: Int
    ): Int {
        var matched = 0
        val needed = (currentBestScore * sampleCount).toInt() + 1
        for (i in samples.indices) {
            val s = samples[i]
            val sx = (offsetX + s.x * scale).toInt()
            val sy = (offsetY + s.y * scale).toInt()
            if (sx < 0 || sy < 0 || sx >= screen.width() || sy >= screen.height()) continue

            val pixel = screen.get(sy, sx) ?: continue
            val sr = pixel[0].toInt()
            val sg = pixel[1].toInt()
            val sb = pixel[2].toInt()

            if (kotlin.math.abs(sr - s.r) <= tolerance &&
                kotlin.math.abs(sg - s.g) <= tolerance &&
                kotlin.math.abs(sb - s.b) <= tolerance
            ) {
                matched++
            }

            // 提前剪枝：即使剩下所有点都匹配也无法超过当前最佳
            val remaining = sampleCount - i - 1
            if (matched + remaining < needed) return matched
        }
        return matched
    }
}
