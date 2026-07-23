package com.example.isolation

import org.opencv.calib3d.Calib3d
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.DMatch
import org.opencv.core.Mat
import org.opencv.core.MatOfDMatch
import org.opencv.core.MatOfKeyPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Rect
import org.opencv.core.Size
import org.opencv.features2d.AKAZE
import org.opencv.features2d.BFMatcher
import org.opencv.features2d.ORB
import org.opencv.imgproc.Imgproc

object FeatureMatcher {

    data class Result(
        val rect: Rect,           // 屏幕坐标系候选矩形
        val estimatedScale: Double // 估计缩放比例
    )

    fun match(
        template: Mat,
        screen: Mat,
        algorithm: String = "orb",
        minMatches: Int = 6,
        region: Rect? = null
    ): Result? {
        val screenRoi = if (region != null) Mat(screen, region) else screen
        val releaseRoi = region != null

        try {
            val (workingScreen, screenScale) = downsampleIfNeeded(screenRoi)
            val (workingTemplate, _) = downsampleIfNeeded(template)

            val detector = createDetector(algorithm)

            val templateKp = MatOfKeyPoint()
            val templateDesc = Mat()
            detector.detectAndCompute(workingTemplate, Mat(), templateKp, templateDesc)

            val screenKp = MatOfKeyPoint()
            val screenDesc = Mat()
            detector.detectAndCompute(workingScreen, Mat(), screenKp, screenDesc)

            if (templateKp.toArray().isEmpty() || screenKp.toArray().isEmpty()) {
                templateKp.release(); templateDesc.release()
                screenKp.release(); screenDesc.release()
                releaseWorking(workingScreen, screenRoi)
                releaseWorking(workingTemplate, template)
                return null
            }

            val goodMatches = matchDescriptors(templateDesc, screenDesc, algorithm)

            templateDesc.release(); screenDesc.release()

            if (goodMatches.size < minMatches) {
                templateKp.release(); screenKp.release()
                releaseWorking(workingScreen, screenRoi)
                releaseWorking(workingTemplate, template)
                return null
            }

            val srcPoints = MatOfPoint2f()
            val dstPoints = MatOfPoint2f()
            val templateArray = templateKp.toArray()
            val screenArray = screenKp.toArray()
            val srcList = mutableListOf<Point>()
            val dstList = mutableListOf<Point>()
            for (m in goodMatches) {
                srcList.add(templateArray[m.queryIdx].pt)
                dstList.add(screenArray[m.trainIdx].pt)
            }
            srcPoints.fromList(srcList)
            dstPoints.fromList(dstList)

            templateKp.release(); screenKp.release()

            val mask = Mat()
            val homography = Calib3d.findHomography(srcPoints, dstPoints, Calib3d.RANSAC, 3.0, mask)
            val inliers = if (!mask.empty()) Core.countNonZero(mask) else 0

            srcPoints.release(); dstPoints.release(); mask.release()

            if (inliers < minMatches) {
                homography.release()
                releaseWorking(workingScreen, screenRoi)
                releaseWorking(workingTemplate, template)
                return null
            }

            val corners = MatOfPoint2f().apply {
                fromArray(
                    Point(0.0, 0.0),
                    Point(workingTemplate.width().toDouble(), 0.0),
                    Point(workingTemplate.width().toDouble(), workingTemplate.height().toDouble()),
                    Point(0.0, workingTemplate.height().toDouble())
                )
            }
            val projected = MatOfPoint2f()
            Core.perspectiveTransform(corners, projected, homography)

            val pts = projected.toArray()
            val minX = pts.minOf { it.x }
            val maxX = pts.maxOf { it.x }
            val minY = pts.minOf { it.y }
            val maxY = pts.maxOf { it.y }

            corners.release(); projected.release(); homography.release()
            releaseWorking(workingScreen, screenRoi)
            releaseWorking(workingTemplate, template)

            val offsetX = region?.x ?: 0
            val offsetY = region?.y ?: 0
            val originalMinX = (minX / screenScale + offsetX).toInt()
            val originalMinY = (minY / screenScale + offsetY).toInt()
            val originalMaxX = (maxX / screenScale + offsetX).toInt()
            val originalMaxY = (maxY / screenScale + offsetY).toInt()

            val x = originalMinX.coerceIn(0, screen.width() - 1)
            val y = originalMinY.coerceIn(0, screen.height() - 1)
            val width = (originalMaxX - x).coerceIn(1, screen.width() - x)
            val height = (originalMaxY - y).coerceIn(1, screen.height() - y)

            val estimatedScale = ((maxX - minX) / workingTemplate.width() +
                    (maxY - minY) / workingTemplate.height()) / 2.0

            return Result(Rect(x, y, width, height), estimatedScale)
        } finally {
            if (releaseRoi) screenRoi.release()
        }
    }

    private fun downsampleIfNeeded(src: Mat, maxHeight: Int = 1080): Pair<Mat, Double> {
        if (src.height() <= maxHeight) return Pair(src, 1.0)
        val scale = maxHeight.toDouble() / src.height()
        val dst = Mat()
        Imgproc.resize(src, dst, Size(src.width() * scale, maxHeight.toDouble()))
        return Pair(dst, scale)
    }

    private fun releaseWorking(working: Mat, original: Mat) {
        if (working != original) working.release()
    }

    private fun createDetector(algorithm: String): org.opencv.features2d.Feature2D {
        return when (algorithm.lowercase()) {
            // AKAZE 通过阈值控制关键点数量，阈值越小点越少；这里保持默认，必要时再调
            "akaze" -> AKAZE.create()
            else -> ORB.create().apply { setMaxFeatures(500) }
        }
    }

    private fun matchDescriptors(templateDesc: Mat, screenDesc: Mat, algorithm: String): List<DMatch> {
        val normType = if (algorithm.lowercase() == "akaze") Core.NORM_L2 else Core.NORM_HAMMING
        val matcher = BFMatcher(normType, true)
        val matches = MatOfDMatch()
        matcher.match(templateDesc, screenDesc, matches)
        val result = matches.toList()
        matches.release()
        return result
    }
}
