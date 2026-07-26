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
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import java.util.concurrent.atomic.AtomicBoolean

interface MacroExecutorListener {
    fun onMacroStatus(message: String)

    /** 宏内部 print(...) 输出，与框架生命周期状态分离 */
    fun onMacroPrint(message: String) {}
}

class MacroExecutor(
    private val service: AccessibilityService,
    private val assetsDir: String? = null
) {

    companion object {
        private const val TAG = "MacroExecutor"
        private var activeExecutor: MacroExecutor? = null
        private val listeners = mutableListOf<MacroExecutorListener>()
        private var clickCount = 0
        private var lastClickTime = 0L
        private const val MULTI_CLICK_THRESHOLD_MS = 600
        private const val MULTI_CLICK_COUNT = 3

        fun addListener(listener: MacroExecutorListener) {
            synchronized(listeners) {
                if (!listeners.contains(listener)) listeners.add(listener)
            }
        }

        fun removeListener(listener: MacroExecutorListener) {
            synchronized(listeners) {
                listeners.remove(listener)
            }
        }

        @Deprecated("请使用 addListener/removeListener", ReplaceWith("addListener(listener)"))
        fun setListener(listener: MacroExecutorListener?) {
            synchronized(listeners) {
                listeners.clear()
                if (listener != null) listeners.add(listener)
            }
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
    @Volatile
    private var stopRequested = false
    @Volatile
    internal var running = false
    @Volatile
    private var debugMode = false

    /**
     * 图片匹配默认特征点采样数目，从宏设置读取。
     */
    private var defaultFeaturePointCount = 8

    /**
     * 图片匹配默认特征点命中比例阈值，从宏设置读取。
     */
    private var defaultFeaturePointThreshold = 0.80

    /**
     * find 块命中的坐标栈。click() 无参时取栈顶点击。
     * 支持 find 嵌套：内层 find 命中会压栈，块结束自动弹栈。
     */
    private val foundCoordinates = ArrayDeque<Pair<Int, Int>>()

    /**
     * 变量表，用于 var / assign 步骤及表达式求值。
     */
    private val variables = mutableMapOf<String, Variable>()

    fun execute(settings: Map<String, Any>, steps: List<Map<String, Any>>) {
        if (running) return
        running = true
        stopRequested = false
        debugMode = settings["debugMode"] as? Boolean ?: false
        defaultFeaturePointCount =
            (settings["featurePointCount"] as? Number)?.toInt()?.coerceIn(1, 32) ?: 8
        defaultFeaturePointThreshold =
            (settings["featurePointThreshold"] as? Number)?.toDouble()?.coerceIn(0.0, 1.0) ?: 0.80
        activeExecutor = this

        val infiniteLoop = (settings["loopCount"] as? Number)?.toInt()?.let { it <= 0 } ?: false

        Thread {
            try {
                postStatus("开始执行")
                if (infiniteLoop) {
                    while (!stopRequested) {
                        executeSteps(steps)
                    }
                    postStatus("宏已停止")
                } else {
                    executeSteps(steps)
                    postStatus(if (stopRequested) "任务已停止" else "任务完成")
                }
            } catch (t: Throwable) {
                postStatus("任务异常: ${t.message}")
            } finally {
                running = false
                activeExecutor = null
                debugMode = false
                defaultFeaturePointCount = 8
                defaultFeaturePointThreshold = 0.80
                variables.clear()
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
    private fun executeSteps(steps: List<Map<String, Any>>) {
        for ((index, step) in steps.withIndex()) {
            if (stopRequested) break
            executeStep(step, index + 1)
        }
    }

    /** 执行单个步骤 */
    private fun executeStep(step: Map<String, Any>, stepNumber: Int) {
        val type = step["type"] as? String ?: return
        if (debugMode) {
            postStatus("执行第 $stepNumber 步: $type")
        }

        val delay = (step["delay"] as? Number)?.toLong() ?: 0L
        if (delay > 0) Thread.sleep(delay)
        if (stopRequested) return

        when (type) {
            // 新指令
            "click" -> executeClickStep(step)
            "roll" -> executeRollStep(step)
            "print" -> {
                val messageExpr = step["message"]
                val msg = when (messageExpr) {
                    is String -> messageExpr
                    is Map<*, *> -> {
                        val result = ExpressionEvaluator.evaluate(
                            messageExpr as Map<String, Any>,
                            variables
                        )
                        (result as? Variable.Number)?.value?.toInt()?.toString()
                            ?: result?.toString() ?: ""
                    }
                    else -> ""
                }
                if (msg.isNotEmpty()) postPrint(msg)
            }
            "wait" -> {
                val durationExpr = step["duration"]
                val duration = when (durationExpr) {
                    is Number -> durationExpr.toLong()
                    is Map<*, *> -> {
                        val result = ExpressionEvaluator.evaluate(
                            durationExpr as Map<String, Any>,
                            variables
                        )
                        (result as? Variable.Number)?.value?.toLong() ?: 0L
                    }
                    else -> 0L
                }
                if (duration > 0) Thread.sleep(duration)
            }
            "for" -> executeForStep(step)
            "find" -> executeFindStep(step)
            "if" -> executeIfStep(step)
            "var" -> executeVarStep(step)
            "assign" -> executeAssignStep(step)

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

    // ---------- 新指令实现 ----------

    private fun executeClickStep(step: Map<String, Any>) {
        val x = evaluateCoordinate(step["x"])
        val y = evaluateCoordinate(step["y"])
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
        val duration = evaluateNumber(step["duration"])?.toLong() ?: 400L

        // 命名参数：从指定起点按相对偏移滑动（支持负值反向滑动）
        val fromX = evaluateNumber(step["fromX"])
        val fromY = evaluateNumber(step["fromY"])
        val relDx = evaluateNumber(step["dx"])
        val relDy = evaluateNumber(step["dy"])
        if (fromX != null && fromY != null && relDx != null && relDy != null) {
            dispatchSwipe(
                fromX.toFloat(), fromY.toFloat(),
                (fromX.toFloat() + relDx.toFloat()), (fromY.toFloat() + relDy.toFloat()),
                duration
            )
            return
        }

        val start = step["start"]
        val end = step["end"]
        if (start is Map<*, *> && end is Map<*, *>) {
            val startMap = start as? Map<String, Any>
            val endMap = end as? Map<String, Any>
            val sx = startMap?.let { evaluateCoordinate(it["x"]) }
            val sy = startMap?.let { evaluateCoordinate(it["y"]) }
            val ex = endMap?.let { evaluateCoordinate(it["x"]) }
            val ey = endMap?.let { evaluateCoordinate(it["y"]) }
            if (sx != null && sy != null && ex != null && ey != null) {
                dispatchSwipe(sx.toFloat(), sy.toFloat(), ex.toFloat(), ey.toFloat(), duration)
                return
            }
        }

        val dx = evaluateNumber(step["dx"])?.toInt() ?: 0
        val dy = evaluateNumber(step["dy"])?.toInt() ?: 0
        val (cx, cy) = screenCenter()
        dispatchSwipe(cx.toFloat(), cy.toFloat(), (cx + dx).toFloat(), (cy + dy).toFloat(), duration)
    }

    private fun executeVarStep(step: Map<String, Any>) {
        val name = step["name"] as? String ?: return
        val varType = step["varType"] as? String ?: return

        when (varType) {
            "int", "double" -> {
                val value = step["value"] as? Map<String, Any> ?: return
                val result = ExpressionEvaluator.evaluate(value, variables) ?: return
                if (result is Variable.Number) {
                    variables[name] = result
                }
            }
            "point" -> {
                val value = step["value"] as? Map<String, Any> ?: return
                val x = evaluateCoordinate(value["x"]) ?: return
                val y = evaluateCoordinate(value["y"]) ?: return
                variables[name] = Variable.Point(x, y)
            }
            "color" -> {
                val value = step["value"] as? Map<String, Any> ?: return
                val result = ExpressionEvaluator.evaluate(value, variables) ?: return
                if (result is Variable.Number) {
                    variables[name] = Variable.Color(result.value.toInt())
                }
            }
        }
    }

    private fun executeAssignStep(step: Map<String, Any>) {
        val name = step["name"] as? String ?: return
        val value = step["value"] as? Map<String, Any> ?: return
        val result = ExpressionEvaluator.evaluate(value, variables) ?: return
        variables[name] = result
    }

    private fun evaluateCoordinate(value: Any?): Int? {
        return evaluateNumber(value)?.toInt()
    }

    private fun evaluateNumber(value: Any?): Number? {
        return when (value) {
            is Number -> value
            is Map<*, *> -> {
                val expr = value as? Map<String, Any>
                val result = ExpressionEvaluator.evaluate(expr, variables)
                if (result is Variable.Number) result.value else null
            }
            else -> null
        }
    }

    private fun executeForStep(step: Map<String, Any>) {
        val condition = step["condition"] as? Map<String, Any>
        if (condition != null) {
            val init = step["init"] as? Map<String, Any>
            val update = step["update"] as? Map<String, Any>
            val children = (step["children"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: return

            init?.let { executeVarStep(it) }
            while (!stopRequested && ExpressionEvaluator.toBoolean(
                    ExpressionEvaluator.evaluate(condition, variables)
                )) {
                executeSteps(children)
                update?.let { executeAssignStep(it) }
            }
            return
        }

        val count = (step["count"] as? Number)?.toInt() ?: 1
        val children = (step["children"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: return
        for (i in 1..count) {
            if (stopRequested) break
            if (debugMode) {
                postStatus("循环 $i/$count")
            }
            executeSteps(children)
        }
    }

    private fun ensureScreenCapturePermission(): Boolean {
        if (ScreenCaptureHelper.isGranted(service)) return true
        postStatus("find: 需要屏幕录制权限，请在弹窗中点击开始")
        val granted = ScreenCapturePermissionRequester.request(service)
        if (!granted) {
            postStatus("find: 未获得屏幕录制权限（Android 14+ 需悬浮球前台服务保持运行）")
        }
        return granted
    }

    private fun executeFindStep(step: Map<String, Any>) {
        val imageName = step["image"] as? String
        val colorValue = step["color"]
        val location = step["location"] as? Map<String, Any>
        val target = step["target"] as? Map<String, Any>
        val needsScreenCapture = imageName != null || colorValue != null || location != null
        if (needsScreenCapture && !ensureScreenCapturePermission()) return

        val children = (step["children"] as? List<*>)?.mapNotNull { it as? Map<String, Any> }
        val loop = step["loop"] as? Boolean ?: false
        val assignTo = step["assignTo"] as? String
        val hasFindTarget = imageName != null || colorValue != null || location != null || target != null

        if (assignTo != null) {
            val coord = findStepCoordinate(step)
            assignFindResult(step, coord)
            return
        }

        val childrenNonNull = children ?: return

        if (loop && hasFindTarget) {
            // loop 与查找目标一起使用时：循环查找直到命中，执行一次块内指令
            while (!stopRequested) {
                val coord = findStepCoordinate(step)
                if (coord != null) {
                    foundCoordinates.addFirst(coord)
                    try {
                        executeSteps(childrenNonNull)
                    } finally {
                        foundCoordinates.removeFirstOrNull()
                    }
                    break
                }
                Thread.sleep(300)
            }
        } else if (loop) {
            // loop 单独使用：无限循环执行块内指令，直到手动停止
            while (!stopRequested) {
                executeSteps(childrenNonNull)
                Thread.sleep(50)
            }
        } else {
            val coord = findStepCoordinate(step) ?: return
            foundCoordinates.addFirst(coord)
            try {
                executeSteps(childrenNonNull)
            } finally {
                foundCoordinates.removeFirstOrNull()
            }
        }
    }

    /**
     * 将 find 结果按类型写入变量：
     * - image / text / node 返回 point（中心坐标）
     * - location 无 color 参数时返回 color（该点色号）
     * - location 带 color 或 color 查找返回 bool（1/0）
     */
    private fun assignFindResult(step: Map<String, Any>, coord: Pair<Int, Int>?) {
        val name = step["assignTo"] as? String ?: return
        val location = step["location"] as? Map<String, Any>
        val hasColor = step["color"] != null

        val value: Variable = when {
            location != null -> {
                if (hasColor) {
                    Variable.Number(if (coord != null) 1.0 else 0.0)
                } else {
                    val (x, y) = coord ?: return
                    val captured = ScreenCaptureHelper.captureColor(service, x, y) ?: return
                    Variable.Color(captured)
                }
            }
            hasColor -> Variable.Number(if (coord != null) 1.0 else 0.0)
            else -> {
                val (x, y) = coord ?: return
                Variable.Point(x, y)
            }
        }
        variables[name] = value
    }

    /**
     * 执行一次 find 查找，返回命中坐标；未命中返回 null 并输出状态。
     * 支持图片、颜色和节点三种查找方式。
     */
    private fun findStepCoordinate(step: Map<String, Any>): Pair<Int, Int>? {
        val imageName = step["image"] as? String
        if (imageName != null) {
            val region = step["region"] as? List<*>
            val options = mutableMapOf<String, Any>(
                "featureCount" to (step["featureCount"] as? Number ?: defaultFeaturePointCount),
                "colorTolerance" to (step["colorTolerance"] as? Number ?: 20),
                "featurePointThreshold" to (step["featurePointThreshold"] as? Number ?: defaultFeaturePointThreshold)
            )

            val point = ImageFinder.find(service, assetsDir, imageName, 0.80, region, options)
            return if (point != null) {
                postStatus("find: 图片命中 (${point.x}, ${point.y})")
                Pair(point.x, point.y)
            } else {
                postStatus("find: 未找到图片")
                null
            }
        }

        // 颜色查找：find(color=0xFF0000, tolerance=20) { ... }
        val colorValue = step["color"]
        if (colorValue != null && step["location"] == null) {
            val targetColor = ColorParser.parseColor(colorValue)
            val tolerance = (step["tolerance"] as? Number)?.toInt() ?: 20
            val point = ScreenCaptureHelper.findColor(service, targetColor, tolerance)
            return if (point != null) {
                postStatus("find: 颜色命中 (${point.x}, ${point.y})")
                Pair(point.x, point.y)
            } else {
                postStatus("find: 未找到颜色")
                null
            }
        }

        // 位置/点色号查找：find(location=(x, y)) 或 find(location=(x, y), color=0xFF0000)
        val location = step["location"] as? Map<String, Any>
        if (location != null) {
            if (!ScreenCaptureHelper.isGranted(service)) {
                postStatus("find: 缺少屏幕录制权限")
                return null
            }
            val x = evaluateCoordinate(location["x"]) ?: return null
            val y = evaluateCoordinate(location["y"]) ?: return null
            if (colorValue != null) {
                val targetColor = ColorParser.parseColor(colorValue)
                val tolerance = (step["tolerance"] as? Number)?.toInt() ?: 20
                val captured = ScreenCaptureHelper.captureColor(service, x, y)
                if (captured != null && colorMatches(captured, targetColor, tolerance)) {
                    postStatus("find: 位置颜色命中 ($x, $y)")
                    return Pair(x, y)
                }
                postStatus("find: 位置颜色不匹配 ($x, $y)")
                return null
            }
            postStatus("find: 位置读取 ($x, $y)")
            return Pair(x, y)
        }

        // 节点查找：find(text="签到") { click() }
        val target = step["target"] as? Map<String, Any>
        if (target == null) {
            postStatus("find: 缺少 color 或 target 参数")
            return null
        }
        val root = service.rootInActiveWindow ?: run {
            postStatus("find: 当前无窗口")
            return null
        }
        val node = findMatchingNode(root, target)
        return if (node != null) {
            val rect = Rect()
            node.getBoundsInScreen(rect)
            val cx = (rect.left + rect.right) / 2
            val cy = (rect.top + rect.bottom) / 2
            postStatus("find: 节点命中 ($cx, $cy)")
            Pair(cx, cy)
        } else {
            postStatus("find: 节点未命中")
            null
        }
    }

    private fun colorMatches(captured: Int, target: Int, tolerance: Int): Boolean {
        val cr = (captured shr 16) and 0xFF
        val cg = (captured shr 8) and 0xFF
        val cb = captured and 0xFF
        val tr = (target shr 16) and 0xFF
        val tg = (target shr 8) and 0xFF
        val tb = target and 0xFF
        return kotlin.math.abs(cr - tr) <= tolerance &&
                kotlin.math.abs(cg - tg) <= tolerance &&
                kotlin.math.abs(cb - tb) <= tolerance
    }

    private fun executeIfStep(step: Map<String, Any>) {
        val expression = step["expression"] as? Map<String, Any>
        val condition = step["condition"] as? Map<String, Any>
        val then = (step["then"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: emptyList()
        val elseBranch = (step["else"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: emptyList()

        if (expression != null) {
            val result = ExpressionEvaluator.toBoolean(
                ExpressionEvaluator.evaluate(expression, variables)
            )
            executeSteps(if (result) then else elseBranch)
            return
        }

        // 条件命中时把坐标压栈，then 块内可用 click() 直接点击
        val matchedCoord = evaluateConditionWithCoord(condition)
        if (matchedCoord != null) {
            foundCoordinates.addFirst(matchedCoord)
            try {
                executeSteps(then)
            } finally {
                foundCoordinates.removeFirstOrNull()
            }
        } else {
            executeSteps(elseBranch)
        }
    }

    /**
     * 评估 if 条件。条件只支持 find(...) 形式：
     * - find(color=0xFF0000)  颜色查找
     * - find(text="签到")      节点查找
     * - find(image="xxx.jpg") 图片查找
     * 命中返回坐标，未命中返回 null。
     */
    private fun evaluateConditionWithCoord(condition: Map<String, Any>?): Pair<Int, Int>? {
        if (condition == null) return null
        val type = condition["type"] as? String ?: return null
        if (type != "find") return null

        // 图片条件
        val imageName = condition["image"] as? String
        if (imageName != null) {
            val region = condition["region"] as? List<*>
            val options = mapOf<String, Any>(
                "featureCount" to (condition["featureCount"] as? Number ?: defaultFeaturePointCount),
                "colorTolerance" to (condition["colorTolerance"] as? Number ?: 20),
                "featurePointThreshold" to (condition["featurePointThreshold"] as? Number ?: defaultFeaturePointThreshold)
            )
            if (!ScreenCaptureHelper.isGranted(service)) return null
            val point = ImageFinder.find(service, assetsDir, imageName, 0.80, region, options)
            return point?.let { Pair(it.x, it.y) }
        }

        // 颜色条件（不含 location）
        val colorValue = condition["color"]
        val location = condition["location"] as? Map<String, Any>
        if (colorValue != null && location == null) {
            val targetColor = ColorParser.parseColor(colorValue)
            val tolerance = (condition["tolerance"] as? Number)?.toInt() ?: 20
            if (!ScreenCaptureHelper.isGranted(service)) return null
            val point = ScreenCaptureHelper.findColor(service, targetColor, tolerance)
            return point?.let { Pair(it.x, it.y) }
        }

        // 位置/点色号条件
        if (location != null) {
            if (!ScreenCaptureHelper.isGranted(service)) return null
            val x = evaluateCoordinate(location["x"]) ?: return null
            val y = evaluateCoordinate(location["y"]) ?: return null
            if (colorValue != null) {
                val targetColor = ColorParser.parseColor(colorValue)
                val tolerance = (condition["tolerance"] as? Number)?.toInt() ?: 20
                val captured = ScreenCaptureHelper.captureColor(service, x, y)
                if (captured != null && colorMatches(captured, targetColor, tolerance)) {
                    return Pair(x, y)
                }
                return null
            }
            return Pair(x, y)
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
        InputAccessibilityService.showClickAnimation(x.toFloat(), y.toFloat())
        // 加入极短位移，避免某些系统把单点手势优化掉
        val path = Path().apply {
            moveTo(x.toFloat(), y.toFloat())
            lineTo(x.toFloat() + 0.5f, y.toFloat() + 0.5f)
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 80))
            .build()
        val result = AtomicBoolean(false)
        val latch = java.util.concurrent.CountDownLatch(1)
        mainHandler.post {
            try {
                val ok = service.dispatchGesture(gesture, null, null)
                result.set(ok)
                if (!ok) Log.w(TAG, "dispatchClick($x, $y) 被系统拒绝")
            } catch (e: Exception) {
                Log.e(TAG, "dispatchClick($x, $y) 异常", e)
            } finally {
                latch.countDown()
            }
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
        InputAccessibilityService.showSwipeAnimation(startX, startY, endX, endY)
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
            try {
                val ok = service.dispatchGesture(gesture, null, null)
                result.set(ok)
                if (!ok) Log.w(TAG, "dispatchSwipe($startX, $startY -> $endX, $endY) 被系统拒绝")
            } catch (e: Exception) {
                Log.e(TAG, "dispatchSwipe 异常", e)
            } finally {
                latch.countDown()
            }
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

    private fun postStatus(message: String) {
        mainHandler.post {
            val snapshot: List<MacroExecutorListener>
            synchronized(listeners) {
                snapshot = listeners.toList()
            }
            snapshot.forEach { it.onMacroStatus(message) }
        }
    }

    private fun postPrint(message: String) {
        mainHandler.post {
            val snapshot: List<MacroExecutorListener>
            synchronized(listeners) {
                snapshot = listeners.toList()
            }
            snapshot.forEach { it.onMacroPrint(message) }
        }
    }
}
