package com.example.isolation

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.DisplayMetrics
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import java.util.concurrent.atomic.AtomicBoolean

interface MacroExecutorListener {
    fun onMacroStatus(message: String)
}

class MacroExecutor(
    private val service: AccessibilityService,
    private val assetsDir: String? = null
) {

    companion object {
        private var activeExecutor: MacroExecutor? = null
        private var listener: MacroExecutorListener? = null
        private var clickCount = 0
        private var lastClickTime = 0L
        private const val MULTI_CLICK_THRESHOLD_MS = 600
        private const val MULTI_CLICK_COUNT = 3

        fun setListener(listener: MacroExecutorListener?) {
            this.listener = listener
        }

        /** 当前是否有宏正在运行 */
        fun isRunning(): Boolean = activeExecutor?.running == true

        /** 强制停止当前运行中的宏（用于服务销毁等清理场景） */
        fun stopActive() {
            activeExecutor?.stop()
        }

        /**
         * 通知悬浮球被点击。仅在宏运行中调用，用于三连击强制停止。
         * @return true 表示触发了停止，false 表示仅累加计数
         */
        fun notifyFloatingBallClick(context: Context): Boolean {
            val now = SystemClock.elapsedRealtime()
            if (now - lastClickTime > MULTI_CLICK_THRESHOLD_MS) {
                clickCount = 0
            }
            clickCount++
            lastClickTime = now

            if (clickCount >= MULTI_CLICK_COUNT) {
                clickCount = 0
                activeExecutor?.stop()
                Toast.makeText(context, "已强制停止循环", Toast.LENGTH_SHORT).show()
                return true
            }
            return false
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var stopRequested = false
    @Volatile
    internal var running = false

    /**
     * find 块命中的坐标栈。click() 无参时取栈顶点击。
     * 支持 find 嵌套：内层 find 命中会压栈，块结束自动弹栈。
     */
    private val foundCoordinates = ArrayDeque<Pair<Int, Int>>()

    fun execute(settings: Map<String, Any>, steps: List<Map<String, Any>>) {
        if (running) return
        running = true
        stopRequested = false
        activeExecutor = this

        val smartRecognition = settings["smartRecognition"] as? Boolean ?: false
        val loopCount = (settings["loopCount"] as? Number)?.toInt() ?: 1
        val effectiveLoopCount = if (loopCount <= 0) Int.MAX_VALUE else loopCount

        Thread {
            try {
                for (cycle in 1..effectiveLoopCount) {
                    if (stopRequested) break
                    if (effectiveLoopCount == Int.MAX_VALUE) {
                        postStatus("新循环开始 #$cycle")
                    } else if (effectiveLoopCount > 1) {
                        postStatus("开始第 $cycle/$effectiveLoopCount 轮")
                    } else {
                        postStatus("开始执行")
                    }
                    executeSteps(steps, smartRecognition)
                    if (stopRequested) break
                }
                postStatus(if (stopRequested) "任务已停止" else "任务完成")
            } catch (t: Throwable) {
                postStatus("任务异常: ${t.message}")
            } finally {
                running = false
                activeExecutor = null
            }
        }.start()
    }

    fun stop() {
        stopRequested = true
    }

    fun dispatchClickForCompanion(x: Int, y: Int): Boolean {
        return dispatchClick(x, y)
    }

    /** 递归执行一组步骤 */
    private fun executeSteps(steps: List<Map<String, Any>>, smartRecognition: Boolean) {
        for ((index, step) in steps.withIndex()) {
            if (stopRequested) break
            executeStep(step, index + 1, smartRecognition)
        }
    }

    /** 执行单个步骤 */
    private fun executeStep(step: Map<String, Any>, stepNumber: Int, smartRecognition: Boolean) {
        val type = step["type"] as? String ?: return
        postStatus("执行第 $stepNumber 步: $type")

        val delay = (step["delay"] as? Number)?.toLong() ?: 0L
        if (delay > 0) Thread.sleep(delay)
        if (stopRequested) return

        if (smartRecognition && hasColorInfo(step)) {
            waitForColorMatch(step, stepNumber)
            if (stopRequested) return
        }

        when (type) {
            // 新指令
            "click" -> executeClickStep(step)
            "roll" -> executeRollStep(step)
            "print" -> {
                val msg = step["message"] as? String ?: ""
                if (msg.isNotEmpty()) postStatus(msg)
            }
            "wait" -> {
                val duration = (step["duration"] as? Number)?.toLong() ?: 0L
                if (duration > 0) Thread.sleep(duration)
            }
            "for" -> executeForStep(step, smartRecognition)
            "find" -> executeFindStep(step, smartRecognition)
            "if" -> executeIfStep(step, smartRecognition)

            // 系统键
            "back" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
            "home" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
            "recents" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_RECENTS)

            // 旧指令兼容
            "clickNode" -> executeClickNode(step)
            "clickPoint" -> executeClickPoint(step)
            "swipe" -> executeSwipe(step)
            "launchApp" -> executeLaunchApp(step)
            "inputText" -> executeInputText(step)
        }
    }

    private fun hasColorInfo(step: Map<String, Any>): Boolean = step["color"] != null

    // ---------- 新指令实现 ----------

    private fun executeClickStep(step: Map<String, Any>) {
        val x = (step["x"] as? Number)?.toInt()
        val y = (step["y"] as? Number)?.toInt()
        if (x != null && y != null) {
            dispatchClick(x, y)
            return
        }
        // 无坐标参数：在 find 块内点击最近命中的坐标
        val coord = foundCoordinates.firstOrNull()
        if (coord != null) {
            dispatchClick(coord.first, coord.second)
        } else {
            postStatus("click: 缺少坐标且不在 find 块内")
        }
    }

    private fun executeRollStep(step: Map<String, Any>) {
        val dx = (step["dx"] as? Number)?.toInt() ?: 0
        val dy = (step["dy"] as? Number)?.toInt() ?: 0
        val duration = (step["duration"] as? Number)?.toLong() ?: 400L
        val (cx, cy) = screenCenter()
        dispatchSwipe(cx.toFloat(), cy.toFloat(), (cx + dx).toFloat(), (cy + dy).toFloat(), duration)
    }

    private fun executeForStep(step: Map<String, Any>, smartRecognition: Boolean) {
        val count = (step["count"] as? Number)?.toInt() ?: 1
        val children = (step["children"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: return
        for (i in 1..count) {
            if (stopRequested) break
            postStatus("循环 $i/$count")
            executeSteps(children, smartRecognition)
        }
    }

    private fun executeFindStep(step: Map<String, Any>, smartRecognition: Boolean) {
        val children = (step["children"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: return

        // 0) 图片查找优先：find(image="xxx.jpg", threshold=0.8, region=[...]) { ... }
        val imageName = step["image"] as? String
        if (imageName != null) {
            val threshold = (step["threshold"] as? Number)?.toDouble() ?: 0.80
            val region = step["region"] as? List<*>
            if (!ScreenCaptureHelper.isGranted(service)) {
                postStatus("find: 无屏幕录制权限，跳过图片查找")
                return
            }
            val point = ImageFinder.find(service, assetsDir, imageName, threshold, region)
            if (point != null) {
                postStatus("find: 图片命中 (${point.x}, ${point.y})")
                foundCoordinates.addFirst(Pair(point.x, point.y))
                try {
                    executeSteps(children, smartRecognition)
                } finally {
                    foundCoordinates.removeFirstOrNull()
                }
            } else {
                postStatus("find: 未找到图片")
            }
            return
        }

        // 1) 颜色查找：find(color=0xFF0000, tolerance=20) { ... }
        val colorValue = step["color"]
        if (colorValue != null) {
            val targetColor = parseColor(colorValue)
            val tolerance = (step["tolerance"] as? Number)?.toInt() ?: 20
            if (!ScreenCaptureHelper.isGranted(service)) {
                postStatus("find: 无屏幕录制权限，跳过颜色查找")
                return
            }
            val point = ScreenCaptureHelper.findColor(service, targetColor, tolerance)
            if (point != null) {
                postStatus("find: 颜色命中 (${point.x}, ${point.y})")
                foundCoordinates.addFirst(Pair(point.x, point.y))
                try {
                    executeSteps(children, smartRecognition)
                } finally {
                    foundCoordinates.removeFirstOrNull()
                }
            } else {
                postStatus("find: 未找到颜色")
            }
            return
        }

        // 2) 节点查找：find(text="签到") { click() }
        val target = step["target"] as? Map<String, Any>
        if (target == null) {
            postStatus("find: 缺少 color 或 target 参数")
            return
        }
        val root = service.rootInActiveWindow ?: run {
            postStatus("find: 当前无窗口")
            return
        }
        val node = findMatchingNode(root, target)
        if (node != null) {
            val rect = Rect()
            node.getBoundsInScreen(rect)
            val cx = (rect.left + rect.right) / 2
            val cy = (rect.top + rect.bottom) / 2
            postStatus("find: 节点命中 ($cx, $cy)")
            foundCoordinates.addFirst(Pair(cx, cy))
            try {
                executeSteps(children, smartRecognition)
            } finally {
                foundCoordinates.removeFirstOrNull()
            }
        } else {
            postStatus("find: 节点未命中")
        }
    }

    /** 把 DSL 中的颜色字面量解析为 0xRRGGBB 整数。支持 0xFF0000 / #FF0000 / 16711680 */
    private fun parseColor(value: Any): Int {
        return when (value) {
            is Number -> value.toInt()
            is String -> {
                val s = value.removePrefix("#")
                if (s.startsWith("0x") || s.startsWith("0X")) {
                    s.substring(2).toInt(16)
                } else if (s.length == 6 || s.length == 8) {
                    s.toInt(16)
                } else {
                    s.toIntOrNull() ?: 0
                }
            }
            else -> 0
        }
    }

    private fun executeIfStep(step: Map<String, Any>, smartRecognition: Boolean) {
        val condition = step["condition"] as? Map<String, Any>
        val then = (step["then"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: emptyList()
        val elseBranch = (step["else"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: emptyList()

        // 条件命中时把坐标压栈，then 块内可用 click() 直接点击
        val matchedCoord = evaluateConditionWithCoord(condition)
        if (matchedCoord != null) {
            foundCoordinates.addFirst(matchedCoord)
            try {
                executeSteps(then, smartRecognition)
            } finally {
                foundCoordinates.removeFirstOrNull()
            }
        } else {
            executeSteps(elseBranch, smartRecognition)
        }
    }

    /**
     * 评估 if 条件。条件只支持 find(...) 形式：
     * - find(color=0xFF0000)  颜色查找
     * - find(text="签到")      节点查找
     * 命中返回坐标，未命中返回 null。
     */
    private fun evaluateConditionWithCoord(condition: Map<String, Any>?): Pair<Int, Int>? {
        if (condition == null) return null
        val type = condition["type"] as? String ?: return null
        if (type != "find") return null

        // 颜色条件
        val colorValue = condition["color"]
        if (colorValue != null) {
            val targetColor = parseColor(colorValue)
            val tolerance = (condition["tolerance"] as? Number)?.toInt() ?: 20
            if (!ScreenCaptureHelper.isGranted(service)) return null
            val point = ScreenCaptureHelper.findColor(service, targetColor, tolerance)
            return point?.let { Pair(it.x, it.y) }
        }

        // 节点条件
        val target = condition["target"] as? Map<String, Any> ?: return null
        val root = service.rootInActiveWindow ?: return null
        val node = findMatchingNode(root, target) ?: return null
        val rect = Rect()
        node.getBoundsInScreen(rect)
        return Pair((rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2)
    }

    // ---------- 旧指令实现（保留兼容） ----------

    private fun executeClickNode(step: Map<String, Any>) {
        val target = step["target"] as? Map<String, Any> ?: return
        val boundsList = target["bounds"] as? List<*>
        val fallbackBounds = boundsList?.mapNotNull { (it as? Number)?.toInt() }

        val root = service.rootInActiveWindow ?: return
        val node = findMatchingNode(root, target)

        if (node != null) {
            val clicked = node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            if (clicked) return
        }

        if (fallbackBounds != null && fallbackBounds.size == 4) {
            val centerX = (fallbackBounds[0] + fallbackBounds[2]) / 2
            val centerY = (fallbackBounds[1] + fallbackBounds[3]) / 2
            dispatchClick(centerX, centerY)
        }
    }

    private fun executeClickPoint(step: Map<String, Any>) {
        val point = step["point"] as? Map<String, Any> ?: return
        val x = (point["x"] as? Number)?.toInt() ?: return
        val y = (point["y"] as? Number)?.toInt() ?: return
        dispatchClick(x, y)
    }

    private fun executeSwipe(step: Map<String, Any>) {
        val start = step["start"] as? Map<String, Any> ?: return
        val end = step["end"] as? Map<String, Any> ?: return
        val duration = (step["duration"] as? Number)?.toLong() ?: 300L
        val sx = (start["x"] as? Number)?.toFloat() ?: return
        val sy = (start["y"] as? Number)?.toFloat() ?: return
        val ex = (end["x"] as? Number)?.toFloat() ?: return
        val ey = (end["y"] as? Number)?.toFloat() ?: return
        dispatchSwipe(sx, sy, ex, ey, duration)
    }

    private fun executeLaunchApp(step: Map<String, Any>) {
        val packageName = step["packageName"] as? String ?: return
        val intent = service.packageManager.getLaunchIntentForPackage(packageName) ?: return
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        service.startActivity(intent)
    }

    private fun executeInputText(step: Map<String, Any>) {
        val text = step["text"] as? String ?: return
        val root = service.rootInActiveWindow ?: return
        val node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (node != null) {
            val args = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            }
            node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        }
    }

    // ---------- 节点查找 ----------

    private fun findMatchingNode(root: AccessibilityNodeInfo, target: Map<String, Any>): AccessibilityNodeInfo? {
        val resourceId = target["resourceId"] as? String
        val text = target["text"] as? String
        val contentDescription = target["contentDescription"] as? String
        val className = target["className"] as? String
        val boundsList = target["bounds"] as? List<*>
        val bounds = boundsList?.mapNotNull { (it as? Number)?.toInt() }?.takeIf { it.size == 4 }?.let {
            Rect(it[0], it[1], it[2], it[3])
        }

        val allNodes = mutableListOf<AccessibilityNodeInfo>()
        collectNodes(root, allNodes)

        if (!resourceId.isNullOrEmpty()) {
            allNodes.firstOrNull { it.viewIdResourceName == resourceId }?.let { return it }
        }
        if (!text.isNullOrEmpty()) {
            allNodes.firstOrNull { it.text?.toString() == text || it.contentDescription?.toString() == text }
                ?.let { return it }
        }
        if (!contentDescription.isNullOrEmpty()) {
            allNodes.firstOrNull { it.contentDescription?.toString() == contentDescription }
                ?.let { return it }
        }
        if (!className.isNullOrEmpty() && bounds != null) {
            allNodes.firstOrNull {
                it.className?.toString() == className && nodeBoundsOverlap(it, bounds)
            }?.let { return it }
        }
        return null
    }

    private fun collectNodes(node: AccessibilityNodeInfo, out: MutableList<AccessibilityNodeInfo>) {
        out.add(node)
        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { collectNodes(it, out) }
        }
    }

    private fun nodeBoundsOverlap(node: AccessibilityNodeInfo, target: Rect): Boolean {
        val rect = Rect()
        node.getBoundsInScreen(rect)
        return Rect.intersects(rect, target)
    }

    // ---------- 手势派发 ----------

    private fun dispatchClick(x: Int, y: Int): Boolean {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) return false
        FloatingBallService.showClickAnimation(x.toFloat(), y.toFloat())
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        val result = AtomicBoolean(false)
        val latch = java.util.concurrent.CountDownLatch(1)
        mainHandler.post {
            result.set(service.dispatchGesture(gesture, null, null))
            latch.countDown()
        }
        try { latch.await() } catch (_: InterruptedException) { /* ignore */ }
        return result.get()
    }

    private fun dispatchSwipe(
        startX: Float, startY: Float,
        endX: Float, endY: Float,
        durationMs: Long
    ): Boolean {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) return false
        FloatingBallService.showSwipeAnimation(startX, startY, endX, endY)
        val path = Path().apply {
            moveTo(startX, startY)
            lineTo(endX, endY)
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        val result = AtomicBoolean(false)
        val latch = java.util.concurrent.CountDownLatch(1)
        mainHandler.post {
            result.set(service.dispatchGesture(gesture, null, null))
            latch.countDown()
        }
        try { latch.await() } catch (_: InterruptedException) { /* ignore */ }
        return result.get()
    }

    private fun screenCenter(): Pair<Int, Int> {
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        (service.getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager)
            .defaultDisplay.getRealMetrics(metrics)
        return Pair(metrics.widthPixels / 2, metrics.heightPixels / 2)
    }

    // ---------- 颜色识别 ----------

    private fun waitForColorMatch(step: Map<String, Any>, stepNumber: Int) {
        val colorInfo = step["color"] as? Map<String, Any> ?: return
        val x = (colorInfo["x"] as? Number)?.toInt() ?: return
        val y = (colorInfo["y"] as? Number)?.toInt() ?: return
        val expectedColor = (colorInfo["color"] as? Number)?.toInt() ?: return

        if (!ScreenCaptureHelper.isGranted(service)) {
            postStatus("第 $stepNumber 步无屏幕权限，跳过识别")
            return
        }

        val tolerance = (colorInfo["tolerance"] as? Number)?.toInt() ?: 30
        val maxWaitMs = 10000L
        val checkIntervalMs = 200L
        var waited = 0L

        while (!stopRequested && waited < maxWaitMs) {
            val actualColor = ScreenCaptureHelper.captureColor(service, x, y)
            if (actualColor != null && colorsMatch(expectedColor, actualColor, tolerance)) {
                return
            }
            postStatus("正在等待第 $stepNumber 步匹配")
            Thread.sleep(checkIntervalMs)
            waited += checkIntervalMs
        }
    }

    private fun colorsMatch(expected: Int, actual: Int, tolerance: Int): Boolean {
        val er = (expected shr 16) and 0xFF
        val eg = (expected shr 8) and 0xFF
        val eb = expected and 0xFF
        val ar = (actual shr 16) and 0xFF
        val ag = (actual shr 8) and 0xFF
        val ab = actual and 0xFF
        return kotlin.math.abs(er - ar) <= tolerance &&
                kotlin.math.abs(eg - ag) <= tolerance &&
                kotlin.math.abs(eb - ab) <= tolerance
    }

    private fun postStatus(message: String) {
        mainHandler.post {
            listener?.onMacroStatus(message)
        }
    }
}
