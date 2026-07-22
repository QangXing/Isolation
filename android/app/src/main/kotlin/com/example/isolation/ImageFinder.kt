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

/**
 * 基于 OpenCV 模板匹配的图片查找器。
 *
 * 在屏幕上搜索与模板图片最相似的区域，命中后返回目标中心点坐标。
 * 默认使用灰度 + TM_CCOEFF_NORMED 匹配，可通过 [region] 限定搜索范围以提升速度。
 * 支持多尺度匹配与可选的颜色通道匹配，以提升不同渲染尺寸/颜色场景下的准确率。
 */
object ImageFinder {

    private const val DEFAULT_THRESHOLD = 0.80
    private const val TAG = "ImageFinder"

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
        return find(context, assetsDir, imageName, threshold, region, null)
    }

    /**
     * 在屏幕上查找模板图片（带高级选项）。
     *
     * 额外 [options] 说明：
     * - "useColor": Boolean，是否启用颜色通道匹配（默认 false）
     * - "useBlur": Boolean，是否在匹配前对图像做高斯模糊去噪（默认 true）
     * - "minScale": Number，多尺度最小缩放（默认 0.8）
     * - "maxScale": Number，多尺度最大缩放（默认 1.2）
     * - "scaleStep": Number，多尺度步长（默认 0.1）
     */
    fun find(
        context: Context,
        assetsDir: String?,
        imageName: String,
        threshold: Double,
        region: List<*>?,
        options: Map<String, Any>?
    ): Point? {
        if (!ScreenCaptureHelper.isGranted(context)) return null

        val templatePath = resolveTemplatePath(assetsDir, imageName) ?: return null
        val templateColor = loadTemplateColor(templatePath) ?: return null
        val templateGray = Mat()
        Imgproc.cvtColor(templateColor, templateGray, Imgproc.COLOR_BGR2GRAY)

        val frame = ScreenCaptureHelper.getLatestFrame() ?: run {
            templateColor.release()
            templateGray.release()
            return null
        }

        var screenMat: Mat? = null
        var screenGray: Mat? = null
        var searchRect: Rect? = null

        try {
            screenMat = frameToMat(frame) ?: return null
            screenGray = Mat()
            Imgproc.cvtColor(screenMat, screenGray, Imgproc.COLOR_RGBA2GRAY)
            searchRect = parseSearchRegion(region, frame.width, frame.height)

            val useColor = options?.get("useColor") as? Boolean ?: false
            val useBlur = options?.get("useBlur") as? Boolean ?: true
            val minScale = (options?.get("minScale") as? Number)?.toDouble() ?: 0.8
            val maxScale = (options?.get("maxScale") as? Number)?.toDouble() ?: 1.2
            val scaleStep = (options?.get("scaleStep") as? Number)?.toDouble() ?: 0.1

            val grayResult = matchMultiScale(
                templateGray, screenGray, searchRect,
                minScale, maxScale, scaleStep, useBlur
            )

            var bestResult = grayResult

            if (useColor && grayResult.score < threshold) {
                val colorResult = matchMultiScaleColor(
                    templateColor, screenMat, searchRect,
                    minScale, maxScale, scaleStep, useBlur
                )
                if (colorResult.score > bestResult.score) {
                    bestResult = colorResult
                }
            }

            Log.d(
                TAG,
                "best match score=${"%.3f".format(bestResult.score)}, " +
                    "scale=${"%.2f".format(bestResult.scale)}"
            )

            return if (bestResult.score >= threshold) {
                val offsetX = searchRect?.x ?: 0
                val offsetY = searchRect?.y ?: 0
                val centerX = offsetX + bestResult.loc.x.toInt() + bestResult.templateW / 2
                val centerY = offsetY + bestResult.loc.y.toInt() + bestResult.templateH / 2
                Point(centerX, centerY)
            } else {
                null
            }
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        } finally {
            screenGray?.release()
            screenMat?.release()
            templateGray.release()
            templateColor.release()
        }
    }

    private data class MatchResult(
        val score: Double,
        val loc: org.opencv.core.Point,
        val scale: Double,
        val templateW: Int,
        val templateH: Int
    )

    /**
     * 灰度多尺度模板匹配。
     *
     * 在 [minScale] ~ [maxScale] 范围内以 [scaleStep] 为步长缩放模板，
     * 使用 TM_CCOEFF_NORMED 与 [screen] 做匹配，返回最优结果。
     */
    private fun matchMultiScale(
        template: Mat,
        screen: Mat,
        searchRect: Rect?,
        minScale: Double,
        maxScale: Double,
        scaleStep: Double,
        useBlur: Boolean
    ): MatchResult {
        var bestScore = -1.0
        var bestLoc = org.opencv.core.Point()
        var bestScale = 1.0
        var bestW = 0
        var bestH = 0

        var scale = minScale
        while (scale <= maxScale + 1e-6) {
            val scaledTemplate = Mat()
            Imgproc.resize(template, scaledTemplate, Size(), scale, scale, Imgproc.INTER_LINEAR)

            val searchMat: Mat
            val releaseSearchMat: Boolean
            if (searchRect != null) {
                searchMat = Mat(screen, searchRect)
                releaseSearchMat = true
            } else {
                searchMat = screen
                releaseSearchMat = false
            }

            if (scaledTemplate.width() > searchMat.width() ||
                scaledTemplate.height() > searchMat.height()
            ) {
                scaledTemplate.release()
                if (releaseSearchMat) searchMat.release()
                scale += scaleStep
                continue
            }

            val processedTemplate = if (useBlur) {
                val blurred = Mat()
                Imgproc.GaussianBlur(scaledTemplate, blurred, Size(3.0, 3.0), 0.0)
                blurred
            } else {
                scaledTemplate
            }

            val processedSearch = if (useBlur) {
                val blurred = Mat()
                Imgproc.GaussianBlur(searchMat, blurred, Size(3.0, 3.0), 0.0)
                blurred
            } else {
                searchMat
            }

            val resultMat = Mat()
            Imgproc.matchTemplate(processedSearch, processedTemplate, resultMat, Imgproc.TM_CCOEFF_NORMED)
            val mmr = Core.minMaxLoc(resultMat)

            if (mmr.maxVal > bestScore) {
                bestScore = mmr.maxVal
                bestLoc = mmr.maxLoc
                bestScale = scale
                bestW = scaledTemplate.width()
                bestH = scaledTemplate.height()
            }

            resultMat.release()
            if (useBlur) {
                processedTemplate.release()
                processedSearch.release()
            }
            scaledTemplate.release()
            if (releaseSearchMat) searchMat.release()

            scale += scaleStep
        }

        return MatchResult(bestScore, bestLoc, bestScale, bestW, bestH)
    }

    /**
     * 颜色多尺度模板匹配。
     *
     * 将模板与屏幕转换到 BGR 空间，拆分三个通道后分别做 TM_CCOEFF_NORMED 匹配，
     * 取三个通道最大相关系数的平均值作为该尺度得分，从而保留颜色信息。
     */
    private fun matchMultiScaleColor(
        templateColor: Mat,
        screenRgba: Mat,
        searchRect: Rect?,
        minScale: Double,
        maxScale: Double,
        scaleStep: Double,
        useBlur: Boolean
    ): MatchResult {
        val screenBgr = Mat()
        Imgproc.cvtColor(screenRgba, screenBgr, Imgproc.COLOR_RGBA2BGR)

        val templateChannels = ArrayList<Mat>()
        val screenChannels = ArrayList<Mat>()
        Core.split(templateColor, templateChannels)
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
                    } else {
                        ch
                    }
                }

                val processedSearchChannels = searchMats.map { ch ->
                    if (useBlur) {
                        val blurred = Mat()
                        Imgproc.GaussianBlur(ch, blurred, Size(3.0, 3.0), 0.0)
                        blurred
                    } else {
                        ch
                    }
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

        return MatchResult(bestScore, bestLoc, bestScale, bestW, bestH)
    }

    private fun resolveTemplatePath(assetsDir: String?, imageName: String): String? {
        if (assetsDir.isNullOrEmpty()) return null
        val file = File(assetsDir, imageName)
        return if (file.exists()) file.absolutePath else null
    }

    private fun loadTemplateColor(path: String): Mat? {
        return try {
            val mat = Imgcodecs.imread(path, Imgcodecs.IMREAD_COLOR)
            if (mat.empty()) return null
            mat
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
