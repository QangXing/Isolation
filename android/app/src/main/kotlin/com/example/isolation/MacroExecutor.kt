package com.example.isolation

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.media.MediaPlayer
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.DisplayMetrics
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

private data class StringValue(val value: String) : Variable() {
    override fun toString() = value
}

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

    /**
     * 循环栈，用于支持 breakLoop(name) / breakLoop() 终止指定或全部循环。
     */
    private val loopStack = ArrayDeque<LoopFrame>()

    private data class LoopFrame(val name: String?, var breakRequested: Boolean = false)

    private val floaterRegistry = FloaterRegistry()
    private var currentFloaterAssetsDir: String? = null
    private var lastFoundCoordinate: Pair<Int, Int>? = null
    private var lastFoundText: String? = null

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
        floaterRegistry.clear()
        currentFloaterAssetsDir = null
        lastFoundCoordinate = null
        lastFoundText = null

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
                loopStack.clear()
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

        var success = true
        when (type) {
            // 动作
            "click" -> success = executeClickStep(step)
            "swipe", "swipeRel" -> success = executeSwipeStep(step)
            "input" -> success = executeInputStep(step)
            "print" -> executePrintStep(step)
            "wait" -> executeWaitStep(step)

            // 系统键
            "back" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
            "home" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
            "recents" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_RECENTS)
            "launch" -> success = executeLaunchStep(step)

            // 查找与等待
            "findText", "findColor", "findImage" -> success = executeFindLikeStep(step)
            "waitForText", "waitForColor", "waitForImage" -> success = executeWaitForStep(step)
            "loop" -> executeLoopStep(step)
            "colorAt" -> executeColorAtStep(step)

            // 流程控制
            "for" -> executeForStep(step)
            "if" -> executeIfStep(step)
            "ifText", "ifColor", "ifImage", "ifColorAt" -> executeIfLikeStep(step)
            "breakLoop" -> executeBreakLoopStep(step)

            // 变量
            "let" -> executeLetStep(step)
            "var" -> executeVarStep(step)
            "assign" -> executeAssignStep(step)

            // 悬浮球
            "include" -> success = executeIncludeStep(step)
            "cornerRadius" -> executeCornerRadiusStep(step)
            "size" -> executeSizeStep(step)
            "image" -> executeImageStep(step)
            "audio" -> executeAudioStep(step)
            "floater" -> registerFloaterStep(step)
        }
        runFloaterHandlers(type, step, success)
    }

    // ---------- 新指令实现 ----------

    private fun executeClickStep(step: Map<String, Any>): Boolean {
        val x = evaluateCoordinate(step["x"])
        val y = evaluateCoordinate(step["y"])
        if (x != null && y != null) {
            return dispatchClick(x, y)
        }
        // 无坐标参数：在 find 块内点击最近命中的坐标
        val coord = foundCoordinates.firstOrNull()
        return if (coord != null) {
            dispatchClick(coord.first, coord.second)
        } else {
            postStatus("click: 缺少坐标且不在 find 块内")
            false
        }
    }

    private fun executeSwipeStep(step: Map<String, Any>): Boolean {
        val duration = evaluateNumber(step["duration"])?.toLong() ?: 400L

        // 命名参数：从指定起点按相对偏移滑动（支持负值反向滑动）
        val fromX = evaluateNumber(step["fromX"])
        val fromY = evaluateNumber(step["fromY"])
        val relDx = evaluateNumber(step["dx"])
        val relDy = evaluateNumber(step["dy"])
        if (fromX != null && fromY != null && relDx != null && relDy != null) {
            return dispatchSwipe(
                fromX.toFloat(), fromY.toFloat(),
                (fromX.toFloat() + relDx.toFloat()), (fromY.toFloat() + relDy.toFloat()),
                duration
            )
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
                return dispatchSwipe(sx.toFloat(), sy.toFloat(), ex.toFloat(), ey.toFloat(), duration)
            }
        }

        val dx = evaluateNumber(step["dx"])?.toInt() ?: 0
        val dy = evaluateNumber(step["dy"])?.toInt() ?: 0
        val (cx, cy) = screenCenter()
        return dispatchSwipe(cx.toFloat(), cy.toFloat(), (cx + dx).toFloat(), (cy + dy).toFloat(), duration)
    }

    private fun executeInputStep(step: Map<String, Any>): Boolean {
        val textExpr = step["text"]
        val text = when (textExpr) {
            is String -> textExpr
            is Map<*, *> -> {
                val result = ExpressionEvaluator.evaluate(
                    textExpr as Map<String, Any>, variables
                )
                (result as? Variable.Number)?.value?.toInt()?.toString()
                    ?: result?.toString() ?: ""
            }
            else -> ""
        }
        if (text.isEmpty()) return false
        val node = service.rootInActiveWindow?.findFocus(android.view.accessibility.AccessibilityNodeInfo.FOCUS_INPUT)
        return if (node != null) {
            val args = Bundle()
            args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            true
        } else {
            false
        }
    }

    private fun executePrintStep(step: Map<String, Any>) {
        val messageExpr = step["message"]
        val msg = when (messageExpr) {
            is String -> messageExpr
            is Map<*, *> -> {
                val result = ExpressionEvaluator.evaluate(
                    messageExpr as Map<String, Any>, variables
                )
                (result as? Variable.Number)?.value?.toInt()?.toString()
                    ?: result?.toString() ?: ""
            }
            else -> ""
        }
        if (msg.isNotEmpty()) postPrint(msg)
    }

    private fun executeWaitStep(step: Map<String, Any>) {
        val durationExpr = step["duration"]
        val duration = when (durationExpr) {
            is Number -> durationExpr.toLong()
            is Map<*, *> -> {
                val result = ExpressionEvaluator.evaluate(
                    durationExpr as Map<String, Any>, variables
                )
                (result as? Variable.Number)?.value?.toLong() ?: 0L
            }
            else -> 0L
        }
        if (duration > 0) Thread.sleep(duration)
    }

    private fun executeLaunchStep(step: Map<String, Any>): Boolean {
        val packageName = step["packageName"] as? String
        if (packageName.isNullOrEmpty()) return false
        val timeout = evaluateNumber(step["timeout"])?.toLong() ?: 0L
        val assignTo = step["assignTo"] as? String

        val intent = service.packageManager.getLaunchIntentForPackage(packageName)
        if (intent == null) {
            postStatus("launch: 无法启动 $packageName")
            if (assignTo != null) variables[assignTo] = Variable.Number(0.0)
            return false
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        service.startActivity(intent)

        if (timeout <= 0) {
            if (assignTo != null) variables[assignTo] = Variable.Number(1.0)
            return true
        }

        val start = SystemClock.elapsedRealtime()
        var success = false
        while (!stopRequested) {
            if (service.rootInActiveWindow?.packageName?.toString() == packageName) {
                success = true
                break
            }
            Thread.sleep(200)
            if (SystemClock.elapsedRealtime() - start >= timeout) {
                break
            }
        }
        if (assignTo != null) variables[assignTo] = Variable.Number(if (success) 1.0 else 0.0)
        return success
    }

    private fun executeLetStep(step: Map<String, Any>) {
        val name = step["name"] as? String ?: return
        val value = step["value"] as? Map<String, Any> ?: return
        val result = ExpressionEvaluator.evaluate(value, variables) ?: return
        variables[name] = result
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

    // ---------- 悬浮球新指令 ----------

    private fun executeCornerRadiusStep(step: Map<String, Any>) {
        val value = evaluateNumber(step["value"])?.toInt() ?: return
        FloatingBallService.applyCornerRadius(value)
    }

    private fun executeSizeStep(step: Map<String, Any>) {
        val value = evaluateNumber(step["value"])?.toInt() ?: return
        FloatingBallService.applySize(value)
    }

    private fun executeImageStep(step: Map<String, Any>) {
        val path = resolveAssetPath(step["path"] as? String) ?: return
        FloatingBallService.applyImage(path)
    }

    private fun executeAudioStep(step: Map<String, Any>) {
        val path = resolveAssetPath(step["path"] as? String) ?: return
        playAudio(path)
    }

    private fun executeIncludeStep(step: Map<String, Any>): Boolean {
        val displayName = step["displayName"] as? String ?: return false
        val pluginDir = findPluginDirectoryByName(displayName)
        if (pluginDir == null) {
            postStatus("include: 未找到 $displayName")
            return false
        }
        val steps = loadFloaterSteps(pluginDir)
        if (steps == null) {
            postStatus("include: 无法加载 $displayName 的 floater.json")
            return false
        }
        currentFloaterAssetsDir = File(pluginDir, "assets").absolutePath
        for (s in steps) {
            when (s["type"] as? String) {
                "cornerRadius" -> executeCornerRadiusStep(s)
                "size" -> executeSizeStep(s)
                "image" -> executeImageStep(s)
                "floater" -> registerFloaterStep(s)
            }
        }
        return true
    }

    private fun registerFloaterStep(step: Map<String, Any>) {
        val event = step["event"] as? String ?: return
        val children = (step["children"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: emptyList()
        val elseChildren = (step["else"] as? List<*>)?.mapNotNull { it as? Map<String, Any> }
        floaterRegistry.register(event, children, elseChildren)
    }

    private fun runFloaterHandlers(event: String, step: Map<String, Any>, success: Boolean) {
        setEventVariables(event, step, success)
        val handlers = floaterRegistry.get(event)
        for (handler in handlers) {
            val children = if (success) handler.children else handler.elseChildren
            if (children != null) {
                executeSteps(children)
            }
        }
    }

    private fun setEventVariables(event: String, step: Map<String, Any>, success: Boolean) {
        when (event) {
            "click" -> {
                val x = evaluateNumber(step["x"])?.toInt() ?: 0
                val y = evaluateNumber(step["y"])?.toInt() ?: 0
                variables["clickX"] = Variable.Number(x.toDouble())
                variables["clickY"] = Variable.Number(y.toDouble())
            }
            "swipe", "swipeRel" -> {
                val fromX = evaluateNumber(step["fromX"])?.toInt()
                val fromY = evaluateNumber(step["fromY"])?.toInt()
                val dx = evaluateNumber(step["dx"])?.toInt() ?: 0
                val dy = evaluateNumber(step["dy"])?.toInt() ?: 0
                val start = step["start"] as? Map<*, *>
                val end = step["end"] as? Map<*, *>
                val (sx, sy) = when {
                    fromX != null && fromY != null -> Pair(fromX, fromY)
                    start is Map<*, *> -> {
                        val sx_ = evaluateCoordinate(start["x"])
                        val sy_ = evaluateCoordinate(start["y"])
                        if (sx_ != null && sy_ != null) Pair(sx_, sy_) else screenCenter()
                    }
                    else -> screenCenter()
                }
                val (ex, ey) = when {
                    end is Map<*, *> -> {
                        val ex_ = evaluateCoordinate(end["x"])
                        val ey_ = evaluateCoordinate(end["y"])
                        if (ex_ != null && ey_ != null) Pair(ex_, ey_) else Pair(sx + dx, sy + dy)
                    }
                    else -> Pair(sx + dx, sy + dy)
                }
                variables["swipeFromX"] = Variable.Number(sx.toDouble())
                variables["swipeFromY"] = Variable.Number(sy.toDouble())
                variables["swipeToX"] = Variable.Number(ex.toDouble())
                variables["swipeToY"] = Variable.Number(ey.toDouble())
            }
            "findText", "waitForText" -> {
                val text = if (success) lastFoundText ?: step["text"] as? String ?: "" else ""
                variables["foundText"] = StringValue(text)
            }
            "findColor", "findImage", "waitForColor", "waitForImage" -> {
                val coord = if (success) lastFoundCoordinate else null
                variables["foundX"] = Variable.Number(coord?.first?.toDouble() ?: 0.0)
                variables["foundY"] = Variable.Number(coord?.second?.toDouble() ?: 0.0)
            }
            "input" -> {
                variables["inputText"] = StringValue(step["text"] as? String ?: "")
            }
            "launch" -> {
                variables["packageName"] = StringValue(step["packageName"] as? String ?: "")
            }
        }
    }

    private fun resolveAssetPath(path: String?): String? {
        if (path == null) return null
        if (File(path).isAbsolute) return path
        val assetsDir = currentFloaterAssetsDir ?: return path
        return File(assetsDir, path).absolutePath
    }

    private fun playAudio(path: String) {
        try {
            val player = MediaPlayer()
            player.setDataSource(path)
            player.prepare()
            player.start()
            player.setOnCompletionListener { it.release() }
        } catch (e: Exception) {
            Log.e(TAG, "audio: 播放失败 $path", e)
        }
    }

    private fun findPluginDirectoryByName(displayName: String): String? {
        val prefs = service.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("isolation_plugins", null) ?: return null
        return try {
            val array = JSONArray(raw)
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                if (obj.optString("name") == displayName && obj.optString("type") == "floaterPlugin") {
                    val id = obj.optString("id")
                    if (id.isNotEmpty()) return File(service.filesDir, "plugins/$id").absolutePath
                }
            }
            null
        } catch (e: Exception) {
            null
        }
    }

    private fun loadFloaterSteps(pluginDir: String): List<Map<String, Any>>? {
        val file = File(pluginDir, "floater.json")
        if (!file.exists()) return null
        return try {
            val text = file.readText()
            val array = JSONArray(text)
            val list = mutableListOf<Map<String, Any>>()
            for (i in 0 until array.length()) {
                list.add(jsonObjectToMap(array.getJSONObject(i)))
            }
            list
        } catch (e: Exception) {
            null
        }
    }

    private fun jsonObjectToMap(obj: JSONObject): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = obj.get(key)
            map[key] = when (value) {
                is JSONObject -> jsonObjectToMap(value)
                is JSONArray -> jsonArrayToList(value)
                else -> value
            }
        }
        return map
    }

    private fun jsonArrayToList(array: JSONArray): List<Any> {
        val list = mutableListOf<Any>()
        for (i in 0 until array.length()) {
            val value = array.get(i)
            list.add(when (value) {
                is JSONObject -> jsonObjectToMap(value)
                is JSONArray -> jsonArrayToList(value)
                else -> value
            })
        }
        return list
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
        postStatus("需要屏幕录制权限，请在弹窗中点击开始")
        val granted = ScreenCapturePermissionRequester.request(service)
        if (!granted) {
            postStatus("未获得屏幕录制权限（Android 14+ 需悬浮球前台服务保持运行）")
        }
        return granted
    }

    // ---------- 查找、等待、颜色、条件 ----------

    private fun executeFindLikeStep(step: Map<String, Any>): Boolean {
        val type = step["type"] as? String ?: return false
        val assignTo = step["assignTo"] as? String
        val coord = findTargetCoordinate(step)
        updateFoundContext(step, coord)
        if (assignTo != null) {
            if (coord != null) variables[assignTo] = Variable.Point(coord.first, coord.second)
            return coord != null
        }
        val children = (step["children"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: return false
        if (coord == null) {
            postStatus("$type: 未命中")
            return false
        }
        foundCoordinates.addFirst(coord)
        try {
            executeSteps(children)
        } finally {
            foundCoordinates.removeFirstOrNull()
        }
        return true
    }

    private fun executeWaitForStep(step: Map<String, Any>): Boolean {
        val type = step["type"] as? String ?: return false
        val children = (step["children"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: return false
        val timeout = evaluateNumber(step["timeout"])?.toLong() ?: 0L
        val start = SystemClock.elapsedRealtime()
        var found = false
        while (!stopRequested) {
            if (timeout > 0 && SystemClock.elapsedRealtime() - start >= timeout) {
                postStatus("$type: 等待超时")
                break
            }
            val coord = findTargetCoordinate(step)
            if (coord != null) {
                found = true
                updateFoundContext(step, coord)
                foundCoordinates.addFirst(coord)
                try {
                    executeSteps(children)
                } finally {
                    foundCoordinates.removeFirstOrNull()
                }
                break
            }
            postStatus("$type: 等待中...")
            Thread.sleep(300)
        }
        return found
    }

    private fun updateFoundContext(step: Map<String, Any>, coord: Pair<Int, Int>?) {
        if (coord != null) lastFoundCoordinate = coord
        val type = step["type"] as? String ?: return
        if (type.contains("Text", ignoreCase = true)) {
            lastFoundText = step["text"] as? String ?: ""
        }
    }

    private fun executeLoopStep(step: Map<String, Any>) {
        val name = step["name"] as? String
        val children = (step["children"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: return
        val frame = LoopFrame(name)
        loopStack.addLast(frame)
        try {
            while (!stopRequested && !frame.breakRequested) {
                executeSteps(children)
                Thread.sleep(50)
            }
        } finally {
            loopStack.removeLastOrNull()
        }
    }

    private fun executeBreakLoopStep(step: Map<String, Any>) {
        val name = step["name"] as? String
        if (name == null) {
            // 无参数：终止当前所有活跃循环
            for (frame in loopStack) {
                frame.breakRequested = true
            }
        } else {
            // 终止指定名称的循环以及嵌套在内的所有内层循环
            var found = false
            for (frame in loopStack) {
                if (frame.name == name) {
                    found = true
                }
                if (found) {
                    frame.breakRequested = true
                }
            }
        }
    }

    private fun executeColorAtStep(step: Map<String, Any>) {
        if (!ensureScreenCapturePermission()) return
        val x = evaluateCoordinate(step["x"]) ?: return
        val y = evaluateCoordinate(step["y"]) ?: return
        val color = ScreenCaptureHelper.captureColor(service, x, y) ?: return
        val assignTo = step["assignTo"] as? String
        if (assignTo != null) {
            variables[assignTo] = Variable.Color(color)
        }
    }

    private fun executeIfLikeStep(step: Map<String, Any>) {
        val type = step["type"] as? String ?: return
        val then = (step["then"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: emptyList()
        val elseBranch = (step["else"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: emptyList()
        val coord = when (type) {
            "ifText" -> findTextCoordinate(step)
            "ifColor" -> findColorCoordinate(step)
            "ifImage" -> findImageCoordinate(step)
            "ifColorAt" -> {
                val x = evaluateCoordinate(step["x"]) ?: return executeSteps(elseBranch)
                val y = evaluateCoordinate(step["y"]) ?: return executeSteps(elseBranch)
                if (evaluateColorAt(step)) Pair(x, y) else null
            }
            else -> null
        }
        if (coord != null) {
            foundCoordinates.addFirst(coord)
            try {
                executeSteps(then)
            } finally {
                foundCoordinates.removeFirstOrNull()
            }
        } else {
            executeSteps(elseBranch)
        }
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

        val condType = condition?.get("type") as? String
        val matchedCoord = when (condType) {
            "findText" -> findTextCoordinate(condition)
            "findColor" -> findColorCoordinate(condition)
            "findImage" -> findImageCoordinate(condition)
            "colorAt" -> {
                val x = evaluateCoordinate(condition["x"]) ?: return executeSteps(elseBranch)
                val y = evaluateCoordinate(condition["y"]) ?: return executeSteps(elseBranch)
                if (evaluateColorAt(condition)) Pair(x, y) else null
            }
            "launch" -> if (executeLaunchStep(condition)) Pair(0, 0) else null
            else -> null
        }
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

    // ---------- 查找辅助 ----------

    private fun findTargetCoordinate(step: Map<String, Any>): Pair<Int, Int>? {
        val type = step["type"] as? String ?: return null
        return when (type) {
            "findText", "waitForText", "ifText" -> findTextCoordinate(step)
            "findColor", "waitForColor", "ifColor" -> findColorCoordinate(step)
            "findImage", "waitForImage", "ifImage" -> findImageCoordinate(step)
            else -> null
        }
    }

    private fun findTextCoordinate(step: Map<String, Any>): Pair<Int, Int>? {
        val text = step["text"] as? String ?: return null
        val root = service.rootInActiveWindow ?: run {
            postStatus("findText: 当前无窗口")
            return null
        }
        val target = if (text.contains('/') || text.contains(':')) {
            mapOf("resourceId" to text)
        } else {
            mapOf("text" to text)
        }
        val node = findMatchingNode(root, target) ?: run {
            postStatus("findText: 未命中 \"$text\"")
            return null
        }
        val rect = Rect()
        node.getBoundsInScreen(rect)
        val cx = (rect.left + rect.right) / 2
        val cy = (rect.top + rect.bottom) / 2
        postStatus("findText: 命中 \"$text\" ($cx, $cy)")
        return Pair(cx, cy)
    }

    private fun findColorCoordinate(step: Map<String, Any>): Pair<Int, Int>? {
        if (!ensureScreenCapturePermission()) return null
        val colorValue = step["color"] ?: return null
        val targetColor = ColorParser.parseColor(colorValue)
        val tolerance = (step["tolerance"] as? Number)?.toInt() ?: 20
        val scanStep = (step["step"] as? Number)?.toInt() ?: 2
        val region = step["region"] as? List<*>
        val point = ScreenCaptureHelper.findColor(service, targetColor, tolerance, scanStep, region)
        return if (point != null) {
            postStatus("findColor: 命中 (${point.x}, ${point.y})")
            Pair(point.x, point.y)
        } else {
            postStatus("findColor: 未命中")
            null
        }
    }

    private fun findImageCoordinate(step: Map<String, Any>): Pair<Int, Int>? {
        if (!ensureScreenCapturePermission()) return null
        val imageName = step["image"] as? String ?: return null
        val region = step["region"] as? List<*>
        val options = mutableMapOf<String, Any>(
            "featureCount" to (step["featureCount"] as? Number ?: defaultFeaturePointCount),
            "colorTolerance" to (step["colorTolerance"] as? Number ?: 20),
            "featurePointThreshold" to (step["featurePointThreshold"] as? Number ?: defaultFeaturePointThreshold)
        )
        val point = ImageFinder.find(service, assetsDir, imageName, 0.80, region, options)
        return if (point != null) {
            postStatus("findImage: 命中 (${point.x}, ${point.y})")
            Pair(point.x, point.y)
        } else {
            postStatus("findImage: 未命中")
            null
        }
    }

    private fun evaluateColorAt(step: Map<String, Any>): Boolean {
        if (!ensureScreenCapturePermission()) return false
        val x = evaluateCoordinate(step["x"]) ?: return false
        val y = evaluateCoordinate(step["y"]) ?: return false
        val colorValue = step["color"] ?: return false
        val targetColor = ColorParser.parseColor(colorValue)
        val tolerance = (step["tolerance"] as? Number)?.toInt() ?: 20
        val captured = ScreenCaptureHelper.captureColor(service, x, y) ?: return false
        return colorMatches(captured, targetColor, tolerance)
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
