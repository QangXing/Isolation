package com.example.isolation

import org.opencv.core.Core
import org.opencv.core.Mat
import org.opencv.core.Rect
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc

object TemplateMatcher {

    data class Result(
        val score: Double,
        val loc: org.opencv.core.Point,
        val scale: Double,
        val templateW: Int,
        val templateH: Int
    )

    /**
     * 多尺度模板匹配。
     *
     * @param template BGR 格式模板图
     * @param screen   RGBA 格式屏幕图
     * @param searchRect 可选搜索区域（屏幕坐标）
     * @param minScale 最小缩放
     * @param maxScale 最大缩放
     * @param scaleStep 缩放步长
     * @param useBlur  是否高斯模糊去噪
     */
    fun match(
        template: Mat,
        screen: Mat,
        searchRect: Rect? = null,
        minScale: Double = 0.5,
        maxScale: Double = 2.0,
        scaleStep: Double = 0.05,
        useBlur: Boolean = true
    ): Result {
        val templateGray = Mat()
        Imgproc.cvtColor(template, templateGray, Imgproc.COLOR_BGR2GRAY)
        val screenGray = Mat()
        Imgproc.cvtColor(screen, screenGray, Imgproc.COLOR_RGBA2GRAY)

        val searchMat = if (searchRect != null) Mat(screenGray, searchRect) else screenGray
        val releaseSearchMat = searchRect != null

        try {
            var bestScore = -1.0
            var bestLoc = org.opencv.core.Point()
            var bestScale = 1.0
            var bestW = 0
            var bestH = 0

            var scale = minScale
            while (scale <= maxScale + 1e-6) {
                val scaledTemplate = Mat()
                Imgproc.resize(templateGray, scaledTemplate, Size(), scale, scale, Imgproc.INTER_LINEAR)

                if (scaledTemplate.width() > searchMat.width() ||
                    scaledTemplate.height() > searchMat.height()
                ) {
                    scaledTemplate.release()
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

                scale += scaleStep
            }

            return Result(bestScore, bestLoc, bestScale, bestW, bestH)
        } finally {
            templateGray.release()
            screenGray.release()
            if (releaseSearchMat) searchMat.release()
        }
    }
}
