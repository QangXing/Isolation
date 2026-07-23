package com.example.isolation

import android.content.Context
import android.graphics.Point
import android.util.Log
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.Rect
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import java.io.File

object ImageFinder {

    private const val DEFAULT_THRESHOLD = 0.80
    private const val TAG = "ImageFinder"
    private const val MAX_TEMPLATE_SIZE = 320

    fun find(
        context: Context,
        assetsDir: String?,
        imageName: String,
        threshold: Double = DEFAULT_THRESHOLD,
        region: List<*>? = null,
        options: Map<String, Any>? = null
    ): Point? {
        if (!ScreenCaptureHelper.isGranted(context)) return null

        val templatePath = resolveTemplatePath(assetsDir, imageName) ?: return null
        val templateOriginal = loadTemplate(templatePath) ?: return null
        val template = resizeIfNeeded(templateOriginal)
        templateOriginal.release()

        val frame = ScreenCaptureHelper.getLatestFrame() ?: run {
            template.release()
            return null
        }

        var screenMat: Mat? = null
        try {
            screenMat = frameToMat(frame) ?: return null
            val searchRect = parseSearchRegion(region, screenMat.width(), screenMat.height())

            val feature = options?.get("feature") as? String ?: "orb"
            val minMatches = (options?.get("minMatches") as? Number)?.toInt() ?: 6
            val timeoutMs = (options?.get("timeoutMs") as? Number)?.toLong() ?: 5000L
            val startTime = System.currentTimeMillis()

            if (feature != "template") {
                val featureResult = FeatureMatcher.match(
                    template, screenMat, feature, minMatches, searchRect
                )
                if (featureResult != null && System.currentTimeMillis() - startTime < timeoutMs) {
                    val refinedRect = expandRect(featureResult.rect, 0.2, screenMat.width(), screenMat.height())
                    val centerScale = featureResult.estimatedScale
                    val templateResult = TemplateMatcher.match(
                        template, screenMat, refinedRect,
                        minScale = (centerScale * 0.9).coerceAtLeast(0.5),
                        maxScale = (centerScale * 1.1).coerceAtMost(2.0),
                        scaleStep = 0.02
                    )
                    Log.d(TAG, "feature refine score=${"%.3f".format(templateResult.score)}, scale=${"%.2f".format(templateResult.scale)}")
                    if (templateResult.score >= threshold) {
                        return centerPoint(templateResult, refinedRect)
                    }
                }
            }

            if (System.currentTimeMillis() - startTime < timeoutMs) {
                val useColor = options?.get("useColor") as? Boolean ?: false
                val useBlur = options?.get("useBlur") as? Boolean ?: true
                val minScale = (options?.get("minScale") as? Number)?.toDouble() ?: 0.5
                val maxScale = (options?.get("maxScale") as? Number)?.toDouble() ?: 2.0
                val scaleStep = (options?.get("scaleStep") as? Number)?.toDouble() ?: 0.05

                val templateResult = if (useColor) {
                    matchColorFallback(template, screenMat, searchRect, minScale, maxScale, scaleStep, useBlur)
                } else {
                    TemplateMatcher.match(template, screenMat, searchRect, minScale, maxScale, scaleStep, useBlur)
                }

                Log.d(TAG, "fallback score=${"%.3f".format(templateResult.score)}, scale=${"%.2f".format(templateResult.scale)}")
                return if (templateResult.score >= threshold) centerPoint(templateResult, searchRect) else null
            }

            Log.w(TAG, "find: 匹配超时")
            return null
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        } finally {
            screenMat?.release()
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

    private fun resizeIfNeeded(template: Mat): Mat {
        val max = kotlin.math.max(template.width(), template.height())
        if (max <= MAX_TEMPLATE_SIZE) return template
        val scale = MAX_TEMPLATE_SIZE.toDouble() / max
        val resized = Mat()
        Imgproc.resize(template, resized, Size(template.width() * scale, template.height() * scale))
        return resized
    }

    private fun expandRect(rect: Rect, ratio: Double, maxW: Int, maxH: Int): Rect {
        val dx = (rect.width * ratio).toInt()
        val dy = (rect.height * ratio).toInt()
        val x = (rect.x - dx).coerceIn(0, maxW - 1)
        val y = (rect.y - dy).coerceIn(0, maxH - 1)
        val width = (rect.width + dx * 2).coerceIn(1, maxW - x)
        val height = (rect.height + dy * 2).coerceIn(1, maxH - y)
        return Rect(x, y, width, height)
    }

    private fun centerPoint(result: TemplateMatcher.Result, searchRect: Rect?): Point {
        val offsetX = searchRect?.x ?: 0
        val offsetY = searchRect?.y ?: 0
        val centerX = offsetX + result.loc.x.toInt() + result.templateW / 2
        val centerY = offsetY + result.loc.y.toInt() + result.templateH / 2
        return Point(centerX, centerY)
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
                mat.put(0, 0, buf)
            } else {
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

    /** 颜色通道 fallback：保留原 ImageFinder 颜色匹配能力 */
    private fun matchColorFallback(
        template: Mat,
        screen: Mat,
        searchRect: Rect?,
        minScale: Double,
        maxScale: Double,
        scaleStep: Double,
        useBlur: Boolean
    ): TemplateMatcher.Result {
        val screenBgr = Mat()
        Imgproc.cvtColor(screen, screenBgr, Imgproc.COLOR_RGBA2BGR)

        val templateChannels = ArrayList<Mat>()
        val screenChannels = ArrayList<Mat>()
        Core.split(template, templateChannels)
        Core.split(screenBgr, screenChannels)

        var bestScore = -1.0
        var bestLoc = org.opencv.core.Point()
        var bestScale = 1.0
        var bestW = 0
        var bestH = 0

        try {
            var scale = minScale
            while (scale <= maxScale + 1e-6) {
                val scaledTemplateChannels = templateChannels.map { ch ->
                    val resized = Mat()
                    Imgproc.resize(ch, resized, Size(), scale, scale, Imgproc.INTER_LINEAR)
                    resized
                }

                val releaseSearchMats = searchRect != null
                val searchMats = screenChannels.map { ch ->
                    if (searchRect != null) Mat(ch, searchRect) else ch
                }

                if (scaledTemplateChannels[0].width() > searchMats[0].width() ||
                    scaledTemplateChannels[0].height() > searchMats[0].height()
                ) {
                    scaledTemplateChannels.forEach { it.release() }
                    if (releaseSearchMats) searchMats.forEach { it.release() }
                    scale += scaleStep
                    continue
                }

                val processedTemplateChannels = scaledTemplateChannels.map { ch ->
                    if (useBlur) {
                        val blurred = Mat()
                        Imgproc.GaussianBlur(ch, blurred, Size(3.0, 3.0), 0.0)
                        blurred
                    } else ch
                }

                val processedSearchChannels = searchMats.map { ch ->
                    if (useBlur) {
                        val blurred = Mat()
                        Imgproc.GaussianBlur(ch, blurred, Size(3.0, 3.0), 0.0)
                        blurred
                    } else ch
                }

                val resultMats = List(3) { Mat() }
                var sumScore = 0.0
                for (i in 0..2) {
                    Imgproc.matchTemplate(
                        processedSearchChannels[i],
                        processedTemplateChannels[i],
                        resultMats[i],
                        Imgproc.TM_CCOEFF_NORMED
                    )
                    val mmr = Core.minMaxLoc(resultMats[i])
                    sumScore += mmr.maxVal
                }
                val avgScore = sumScore / 3.0
                val referenceMmr = Core.minMaxLoc(resultMats[0])

                if (avgScore > bestScore) {
                    bestScore = avgScore
                    bestLoc = referenceMmr.maxLoc
                    bestScale = scale
                    bestW = scaledTemplateChannels[0].width()
                    bestH = scaledTemplateChannels[0].height()
                }

                resultMats.forEach { it.release() }
                if (useBlur) {
                    processedTemplateChannels.forEach { it.release() }
                    processedSearchChannels.forEach { it.release() }
                }
                scaledTemplateChannels.forEach { it.release() }
                if (releaseSearchMats) searchMats.forEach { it.release() }

                scale += scaleStep
            }
        } finally {
            screenBgr.release()
            templateChannels.forEach { it.release() }
            screenChannels.forEach { it.release() }
        }

        return TemplateMatcher.Result(bestScore, bestLoc, bestScale, bestW, bestH)
    }
}
