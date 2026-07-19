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
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast

interface MacroExecutorListener {
    fun onMacroStatus(message: String)
}

class MacroExecutor(private val service: AccessibilityService) {

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

        fun notifyFloatingBallClick(context: Context) {
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
            }
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var stopRequested = false
    private var running = false

    fun execute(settings: Map<String, Any>, steps: List<Map<String, Any>>) {
        if (running) return
        running = true
        stopRequested = false
        activeExecutor = this

        val smartRecognition = settings["smartRecognition"] as? Boolean ?: false
        val loopCount = (settings["loopCount"] as? Number)?.toInt() ?: 1
        val effectiveLoopCount = if (loopCount <= 0) Int.MAX_VALUE else loopCount

        Thread {
            for (cycle in 1..effectiveLoopCount) {
                if (stopRequested) break

                if (effectiveLoopCount == Int.MAX_VALUE) {
                    postStatus("新循环开始 #${cycle}")
                } else if (effectiveLoopCount > 1) {
                    postStatus("开始第 ${cycle}/${effectiveLoopCount} 轮")
                } else {
                    postStatus("开始执行")
                }

                for ((index, step) in steps.withIndex()) {
                    if (stopRequested) break

                    val stepNumber = index + 1
                    postStatus("执行第 ${stepNumber} 步")

                    val delay = (step["delay"] as? Number)?.toLong() ?: 0L
                    if (delay > 0) Thread.sleep(delay)
                    if (stopRequested) break

                    if (smartRecognition) {
                        waitForColorMatch(step, stepNumber)
                        if (stopRequested) break
                    }

                    when (step["type"] as? String) {
                        "clickNode" -> executeClickNode(step)
                        "clickPoint" -> executeClickPoint(step)
                        "launchApp" -> executeLaunchApp(step)
                        "inputText" -> executeInputText(step)
                        "wait" -> {
                            val duration = (step["duration"] as? Number)?.toLong() ?: 0L
                            if (duration > 0) Thread.sleep(duration)
                        }
                        "back" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
                        "home" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
                        "recents" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_RECENTS)
                    }
                }

                if (stopRequested) break
            }

            postStatus(if (stopRequested) "任务已停止" else "任务完成")
            running = false
            activeExecutor = null
        }.start()
    }

    fun stop() {
        stopRequested = true
    }

    fun dispatchClickForCompanion(x: Int, y: Int): Boolean {
        return dispatchClick(x, y)
    }

    private fun waitForColorMatch(step: Map<String, Any>, stepNumber: Int) {
        val colorInfo = step["color"] as? Map<String, Any> ?: return
        val x = (colorInfo["x"] as? Number)?.toInt() ?: return
        val y = (colorInfo["y"] as? Number)?.toInt() ?: return
        val expectedColor = (colorInfo["color"] as? Number)?.toInt() ?: return

        if (!ScreenCaptureHelper.isGranted(service)) {
            postStatus("第 ${stepNumber} 步无屏幕权限，跳过识别")
            return
        }

        val tolerance = 20
        val maxWaitMs = 10000L
        val checkIntervalMs = 200L
        var waited = 0L

        while (!stopRequested && waited < maxWaitMs) {
            val actualColor = ScreenCaptureHelper.captureColor(service, x, y)
            if (actualColor != null && colorsMatch(expectedColor, actualColor, tolerance)) {
                return
            }
            postStatus("正在等待第 ${stepNumber} 步匹配")
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

    private fun executeClickNode(step: Map<String, Any>) {
        val target = step["target"] as? Map<String, Any> ?: return
        val boundsList = target["bounds"] as? List<*>
        val fallbackBounds = boundsList?.mapNotNull { it as? Int }

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

    private fun findMatchingNode(root: AccessibilityNodeInfo, target: Map<String, Any>): AccessibilityNodeInfo? {
        val resourceId = target["resourceId"] as? String
        val text = target["text"] as? String
        val contentDescription = target["contentDescription"] as? String
        val className = target["className"] as? String
        val boundsList = target["bounds"] as? List<*>
        val bounds = boundsList?.mapNotNull { it as? Int }?.takeIf { it.size == 4 }?.let {
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

    private fun executeClickPoint(step: Map<String, Any>) {
        val point = step["point"] as? Map<String, Any> ?: return
        val x = (point["x"] as? Number)?.toInt() ?: return
        val y = (point["y"] as? Number)?.toInt() ?: return
        dispatchClick(x, y)
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

    private fun dispatchClick(x: Int, y: Int): Boolean {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) return false
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        return service.dispatchGesture(gesture, null, null)
    }

    private fun postStatus(message: String) {
        mainHandler.post {
            listener?.onMacroStatus(message)
        }
    }
}
