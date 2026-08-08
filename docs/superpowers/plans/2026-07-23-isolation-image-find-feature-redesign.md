# `find(image=...)` 图片查找重构实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把现有 `find(image=...)` 从单一 OpenCV 模板匹配升级为“特征点粗定位 + 模板精修”混合方案，并在宏执行中自动申请屏幕录制权限。

**Architecture:** 新增 `TemplateMatcher` 与 `FeatureMatcher` 两个独立匹配器，`ImageFinder` 作为编排器按 `feature` 参数选择策略、管理 fallback；新增 `ScreenCapturePermissionRequester` 在 `find(image=...)` / `find(color=...)` 执行前主动申请权限。

**Tech Stack:** Kotlin, OpenCV 4.12 (ORB/AKAZE/Calib3d), Flutter/Dart

---

## 文件结构

| 文件 | 责任 |
|------|------|
| `android/app/src/main/kotlin/com/example/isolation/TemplateMatcher.kt` | 多尺度灰度模板匹配，可被限定区域与缩放范围复用 |
| `android/app/src/main/kotlin/com/example/isolation/FeatureMatcher.kt` | ORB/AKAZE 特征点检测、匹配、RANSAC 几何校验 |
| `android/app/src/main/kotlin/com/example/isolation/ImageFinder.kt` | 加载模板、策略编排、fallback、资源释放 |
| `android/app/src/main/kotlin/com/example/isolation/ScreenCapturePermissionRequester.kt` | 宏执行中阻塞式申请屏幕录制权限 |
| `android/app/src/main/kotlin/com/example/isolation/MainActivity.kt` | 处理 `ACTION_REQUEST_SCREEN_CAPTURE` action 并通知 requester |
| `android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt` | `find` 前确保权限，解析并透传 `feature`/`minMatches` |
| `lib/services/macro_program_parser.dart` | 序列化新增 `feature`、`minMatches` 参数 |
| `lib/screens/instruction_manual_screen.dart` | 更新 `find(image=...)` 文档说明 |

---

## Task 1: 创建 `TemplateMatcher.kt`

**Files:**
- Create: `android/app/src/main/kotlin/com/example/isolation/TemplateMatcher.kt`

把现有 `ImageFinder.matchMultiScale` 的逻辑抽取为独立对象，输入统一为 OpenCV `Mat`（模板为 BGR、屏幕为 RGBA），内部转灰度后匹配。

- [ ] **Step 1: 创建文件**

```kotlin
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
```

- [ ] **Step 2: 编译检查**

Run: `cd /workspace/Isolation/android && ./gradlew :app:compileDebugKotlin`
Expected: 通过（此时 ImageFinder 还未引用它，不会触发连锁错误）

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/example/isolation/TemplateMatcher.kt
git commit -m "feat: 提取多尺度模板匹配为 TemplateMatcher"
```

---

## Task 2: 创建 `FeatureMatcher.kt`

**Files:**
- Create: `android/app/src/main/kotlin/com/example/isolation/FeatureMatcher.kt`

实现 ORB/AKAZE 特征点检测、BFMatcher 匹配、RANSAC 几何校验，返回候选矩形与估计缩放。

- [ ] **Step 1: 创建文件**

```kotlin
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
```

- [ ] **Step 2: 编译检查**

Run: `cd /workspace/Isolation/android && ./gradlew :app:compileDebugKotlin`
Expected: 通过

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/example/isolation/FeatureMatcher.kt
git commit -m "feat: 新增 ORB/AKAZE 特征点匹配 FeatureMatcher"
```

---

## Task 3: 重构 `ImageFinder.kt` 为编排器

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/isolation/ImageFinder.kt`

用 `TemplateMatcher` + `FeatureMatcher` 替换原有内联匹配逻辑，保留模板路径解析、Mat 加载、region 解析、中心点计算。

- [ ] **Step 1: 用新实现替换 `ImageFinder.kt` 全部内容**

```kotlin
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
```

- [ ] **Step 2: 编译检查**

Run: `cd /workspace/Isolation/android && ./gradlew :app:compileDebugKotlin`
Expected: 通过

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/example/isolation/ImageFinder.kt
git commit -m "refactor: ImageFinder 使用 FeatureMatcher + TemplateMatcher，支持 feature 策略与 fallback"
```

---

## Task 4: 创建 `ScreenCapturePermissionRequester.kt`

**Files:**
- Create: `android/app/src/main/kotlin/com/example/isolation/ScreenCapturePermissionRequester.kt`

提供阻塞式权限申请，等待 `MainActivity.onActivityResult` 回传结果。

- [ ] **Step 1: 创建文件**

```kotlin
package com.example.isolation

import android.content.Context
import android.content.Intent
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object ScreenCapturePermissionRequester {

    private val lock = Any()
    private var latch: CountDownLatch? = null
    private var result: Boolean = false

    /**
     * 阻塞式申请屏幕录制权限。调用方必须在后台线程调用。
     *
     * @param context 用于启动 MainActivity 的 Context（需为 Application/Service）
     * @param timeoutMs 等待超时，默认 30 秒
     * @return 是否获得权限
     */
    fun request(context: Context, timeoutMs: Long = 30000): Boolean {
        val newLatch: CountDownLatch
        synchronized(lock) {
            result = false
            newLatch = CountDownLatch(1)
            latch = newLatch
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            action = "ACTION_REQUEST_SCREEN_CAPTURE"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        context.startActivity(intent)

        val success = newLatch.await(timeoutMs, TimeUnit.MILLISECONDS)
        return success && synchronized(lock) { result }
    }

    /**
     * 由 MainActivity.onActivityResult 调用。
     */
    fun onResult(granted: Boolean) {
        synchronized(lock) {
            result = granted
            latch?.countDown()
        }
    }
}
```

- [ ] **Step 2: 编译检查**

Run: `cd /workspace/Isolation/android && ./gradlew :app:compileDebugKotlin`
Expected: 通过

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/example/isolation/ScreenCapturePermissionRequester.kt
git commit -m "feat: 新增宏执行中屏幕录制权限申请 ScreenCapturePermissionRequester"
```

---

## Task 5: 更新 `MainActivity.kt`

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/isolation/MainActivity.kt`

处理 `ACTION_REQUEST_SCREEN_CAPTURE` action，在 `onActivityResult` 中通知 `ScreenCapturePermissionRequester`。

- [ ] **Step 1: 在 `onCreate` 与 `onNewIntent` 中分发 intent**

```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    handleIntent(intent)
}

override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    handleIntent(intent)
}

private fun handleIntent(intent: Intent?) {
    if (intent?.action == "ACTION_REQUEST_SCREEN_CAPTURE") {
        ScreenCaptureHelper.requestPermission(this, REQUEST_SCREEN_CAPTURE)
    }
}
```

- [ ] **Step 2: 在 `onActivityResult` 中通知 requester**

将现有：

```kotlin
if (requestCode == REQUEST_SCREEN_CAPTURE) {
    val granted = ScreenCaptureHelper.onActivityResult(this, resultCode, data)
    pendingResult?.success(granted)
    pendingResult = null
}
```

替换为：

```kotlin
if (requestCode == REQUEST_SCREEN_CAPTURE) {
    val granted = ScreenCaptureHelper.onActivityResult(this, resultCode, data)
    ScreenCapturePermissionRequester.onResult(granted)
    pendingResult?.success(granted)
    pendingResult = null
}
```

- [ ] **Step 3: 编译检查**

Run: `cd /workspace/Isolation/android && ./gradlew :app:compileDebugKotlin`
Expected: 通过

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/com/example/isolation/MainActivity.kt
git commit -m "feat: MainActivity 支持宏执行中请求屏幕录制权限"
```

---

## Task 6: 更新 `MacroExecutor.kt`

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt`

在 `executeFindStep` 中确保屏幕录制权限，并把 `feature`/`minMatches` 透传给 `ImageFinder`。

- [ ] **Step 1: 添加 `ensureScreenCapturePermission()`**

在 `MacroExecutor` 类内添加：

```kotlin
private fun ensureScreenCapturePermission(): Boolean {
    if (ScreenCaptureHelper.isGranted(service)) return true
    postStatus("find: 需要屏幕录制权限")
    val granted = ScreenCapturePermissionRequester.request(service)
    if (!granted) postStatus("find: 未获得屏幕录制权限")
    return granted
}
```

- [ ] **Step 2: 在 `executeFindStep` 开头检查权限**

在 `executeFindStep` 方法开头（解析 children 之前）插入：

```kotlin
private fun executeFindStep(step: Map<String, Any>) {
    val imageName = step["image"] as? String
    val colorValue = step["color"]
    val needsScreenCapture = imageName != null || colorValue != null
    if (needsScreenCapture && !ensureScreenCapturePermission()) return

    val children = (step["children"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: return
    val loop = step["loop"] as? Boolean ?: false
    // ... 后续逻辑保持不变
}
```

- [ ] **Step 3: 把 `feature`/`minMatches` 透传给 ImageFinder**

找到 `executeFindStep` 中的 `imageName != null` 分支，把：

```kotlin
val point = ImageFinder.find(service, assetsDir, imageName, threshold, region)
```

替换为：

```kotlin
val options = mutableMapOf<String, Any>()
val feature = step["feature"] as? String
if (feature != null) options["feature"] = feature
val minMatches = step["minMatches"] as? Number
if (minMatches != null) options["minMatches"] = minMatches.toInt()

val point = ImageFinder.find(service, assetsDir, imageName, threshold, region, options)
```

- [ ] **Step 4: 编译检查**

Run: `cd /workspace/Isolation/android && ./gradlew :app:compileDebugKotlin`
Expected: 通过

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt
git commit -m "feat: MacroExecutor 执行 find 前确保屏幕权限并透传 feature/minMatches"
```

---

## Task 7: 更新 `macro_program_parser.dart`

**Files:**
- Modify: `lib/services/macro_program_parser.dart`

解析器已自动支持任意命名参数（`_parseArgs`），只需在序列化时输出 `feature` 与 `minMatches`。

- [ ] **Step 1: 修改 `_serializeFindArgs`**

在 `_serializeFindArgs` 中，region 解析之后、color 解析之前插入：

```dart
final feature = step['feature'];
if (feature != null) pairs.add('feature=${_quoteValue(feature)}');
final minMatches = step['minMatches'];
if (minMatches != null) pairs.add('minMatches=$minMatches');
```

最终 `_serializeFindArgs` 中参数顺序建议为：`loop` → `image` → `feature` → `minMatches` → `threshold` → `region` → `color` → `tolerance` → `target`。

- [ ] **Step 2: 验证序列化/反序列化对称**

在 `test/` 目录下找现有 parser 测试，若无则新增一个简单测试：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:isolation/services/macro_program_parser.dart';

void main() {
  test('find image with feature and minMatches round-trip', () {
    final steps = [
      {
        'type': 'find',
        'image': 'btn.jpg',
        'feature': 'akaze',
        'minMatches': 8,
        'threshold': 0.85,
        'children': <Map<String, dynamic>>[
          {'type': 'click'},
        ],
      },
    ];
    final code = MacroProgramParser.serialize(steps);
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.first['feature'], 'akaze');
    expect(parsed.first['minMatches'], 8);
    expect(parsed.first['image'], 'btn.jpg');
  });
}
```

- [ ] **Step 3: 运行测试**

Run: `cd /workspace/Isolation && flutter test test/macro_program_parser_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/services/macro_program_parser.dart test/macro_program_parser_test.dart
git commit -m "feat: 序列化 find 的 feature 与 minMatches 参数"
```

---

## Task 8: 更新使用说明文档

**Files:**
- Modify: `lib/screens/instruction_manual_screen.dart`

在 `find(image=...)` 相关说明处补充 `feature` 与 `minMatches` 说明，并说明执行中会自动申请屏幕录制权限。

- [ ] **Step 1: 找到图片查找说明文本并补充**

将类似：

```dart
Text('find(image="xxx.jpg", threshold=0.8) { ... }')
```

扩展为：

```dart
Text('find(image="xxx.jpg", feature="orb", minMatches=6, threshold=0.8) { ... }')
```

并在说明段落中增加：

```dart
Text('feature: orb（默认）/ akaze / template，template 仅使用传统模板匹配。')
Text('minMatches: 特征点匹配通过的最少内点数，默认 6。')
Text('执行图片/颜色查找时若未授权屏幕录制，会自动弹出授权。')
```

- [ ] **Step 2: Commit**

```bash
git add lib/screens/instruction_manual_screen.dart
git commit -m "docs: 更新 find(image=...) 的 feature/minMatches 与权限说明"
```

---

## Task 9: 集成测试与收尾

- [ ] **Step 1: Android 端编译**

Run: `cd /workspace/Isolation/android && ./gradlew :app:assembleDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 2: Dart 端分析**

Run: `cd /workspace/Isolation && flutter analyze`
Expected: 无 error

- [ ] **Step 3: 真机/模拟器验证**

验证场景：
1. 创建 `find(image="btn.jpg") { click() }`，运行宏，确认命中。
2. 手动撤销屏幕录制权限，再次运行宏，确认弹出授权对话框，授权后自动继续。
3. 使用 `find(image="btn.jpg", feature="template")` 确认纯模板匹配仍可用。
4. 纯色按钮场景确认 fallback 模板匹配命中。

- [ ] **Step 4: 提交集成测试说明并标记设计文档状态**

```bash
git add docs/superpowers/specs/2026-07-23-isolation-image-find-feature-redesign.md
git commit -m "docs: 标记 image-find 重构设计为已实现"
```

---

## Self-Review Checklist

1. **Spec coverage**
   - 特征点粗定位 + 模板精修：Task 2 + Task 3
   - feature / minMatches 参数：Task 3 + Task 7
   - fallback 到模板匹配：Task 3
   - 屏幕权限主动申请 + 自动恢复：Task 4 + Task 5 + Task 6
   - 性能控制（降采样、超时、关键点上限）：Task 2 + Task 3
   - DSL 序列化：Task 7

2. **Placeholder scan**
   - 无 TBD/TODO，所有步骤含完整代码或明确命令。

3. **类型一致性**
   - `ImageFinder.find` 的 `options` 为 `Map<String, Any>`，`MacroExecutor` 透传时使用 `Map<String, Any>`。
   - `TemplateMatcher.Result` 与 `FeatureMatcher.Result` 命名不冲突。
   - `ScreenCapturePermissionRequester.onResult` 与 `MainActivity.onActivityResult` 调用一致。

4. **已知风险**
   - OpenCV Android 4.12 的 `AKAZE`/`ORB`/`Calib3d` 是否完整包含需编译验证（Task 1/2 的 compileDebugKotlin 会暴露）。
   - 如果 `findHomography` 的 mask 类型导致 `countNonZero` 异常，需在 Task 2 编译时调整。
