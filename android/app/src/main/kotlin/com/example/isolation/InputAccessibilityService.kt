package com.example.isolation

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.view.Display
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import androidx.annotation.RequiresApi
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class InputAccessibilityService : AccessibilityService() {

    interface MacroListener {
        fun onStatus(message: String)
    }

    companion object {
        private var instance: InputAccessibilityService? = null
        private var macroListener: MacroListener? = null

        fun setMacroListener(listener: MacroListener?) {
            macroListener = listener
        }

        fun isEnabled(context: Context): Boolean {
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            val serviceName = "${context.packageName}/${InputAccessibilityService::class.java.canonicalName}"
            return enabledServices.contains(serviceName)
        }

        fun showInputMethod(context: Context) {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return
            }
            val node = service.findFocusedInputNode()
            if (node != null) {
                node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            } else {
                Toast.makeText(context, "未找到输入框", Toast.LENGTH_SHORT).show()
            }
        }

        fun injectKey(context: Context, key: String) {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return
            }
            val node = service.findFocusedInputNode()
            if (node != null) {
                val currentText = node.text?.toString() ?: ""
                val newText = currentText + key
                val arguments = Bundle().apply {
                    putCharSequence(
                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                        newText
                    )
                }
                node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
            } else {
                Toast.makeText(context, "未找到输入框", Toast.LENGTH_SHORT).show()
            }
        }

        fun injectBackspace(context: Context) {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return
            }
            val node = service.findFocusedInputNode()
            if (node != null) {
                val currentText = node.text?.toString() ?: ""
                if (currentText.isNotEmpty()) {
                    val newText = currentText.substring(0, currentText.length - 1)
                    val arguments = Bundle().apply {
                        putCharSequence(
                            AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                            newText
                        )
                    }
                    node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
                }
            } else {
                Toast.makeText(context, "未找到输入框", Toast.LENGTH_SHORT).show()
            }
        }

        fun startRecording(): Boolean {
            return instance?.beginRecording() ?: false
        }

        fun stopRecording(): List<Map<String, Any>> {
            return instance?.finishRecording() ?: emptyList()
        }

        fun executeMacro(
            steps: List<Map<String, Any>>,
            loop: Boolean,
            smartRecognition: Boolean
        ): Boolean {
            val service = instance ?: return false
            service.executor.execute {
                service.runMacro(steps, loop, smartRecognition)
            }
            return true
        }

        fun cancelExecution() {
            instance?.cancelExecutionFlag = true
        }

        fun dispatchClick(x: Int, y: Int): Boolean {
            val service = instance ?: return false
            return service.dispatchClickInternal(x, y)
        }

        fun isExecuting(): Boolean {
            return instance?.isExecuting ?: false
        }
    }

    private var recording = false
    private val recordedSteps = mutableListOf<Map<String, Any>>()
    private var lastRecordTime = 0L

    @Volatile
    private var isExecuting = false

    @Volatile
    private var cancelExecutionFlag = false

    private val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
    private val screenshotThread = HandlerThread("MacroScreenshot").apply { start() }
    private val screenshotHandler = Handler(screenshotThread.looper)
    private val pendingEvents = AtomicInteger(0)

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (!recording || event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_VIEW_CLICKED) return

        val source = event.source ?: return
        val packageName = event.packageName?.toString()
        if (packageName == this.packageName) {
            source.recycle()
            return
        }

        pendingEvents.incrementAndGet()
        screenshotHandler.post {
            try {
                val step = createStep(source, packageName)
                synchronized(recordedSteps) { recordedSteps.add(step) }
            } finally {
                source.recycle()
                pendingEvents.decrementAndGet()
            }
        }
    }

    override fun onInterrupt() {
        instance = null
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        executor.shutdown()
        screenshotThread.quitSafely()
    }

    private fun findFocusedInputNode(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
    }

    private fun beginRecording(): Boolean {
        if (recording) return false
        recording = true
        synchronized(recordedSteps) { recordedSteps.clear() }
        lastRecordTime = System.currentTimeMillis()
        return true
    }

    private fun finishRecording(): List<Map<String, Any>> {
        recording = false
        // wait for pending screenshot tasks
        var attempts = 0
        while (pendingEvents.get() > 0 && attempts < 50) {
            Thread.sleep(100)
            attempts++
        }
        return synchronized(recordedSteps) { ArrayList(recordedSteps) }
    }

    private fun createStep(source: AccessibilityNodeInfo, packageName: String?): Map<String, Any> {
        val now = System.currentTimeMillis()
        val delay = if (lastRecordTime == 0L) 0 else (now - lastRecordTime).toInt()
        lastRecordTime = now

        val bounds = Rect().also { source.getBoundsInScreen(it) }
        val centerX = (bounds.left + bounds.right) / 2
        val centerY = (bounds.top + bounds.bottom) / 2

        val target = mutableMapOf<String, Any>(
            "resourceId" to (source.viewIdResourceName ?: ""),
            "text" to (source.text?.toString() ?: ""),
            "contentDescription" to (source.contentDescription?.toString() ?: ""),
            "className" to (source.className?.toString() ?: ""),
            "bounds" to listOf(bounds.left, bounds.top, bounds.right, bounds.bottom)
        )

        val pixelColor = capturePixelColor(centerX, centerY)

        val step = mutableMapOf<String, Any>(
            "type" to "clickNode",
            "delay" to delay.coerceAtLeast(0),
            "target" to target
        )
        if (pixelColor != null) {
            step["pixelColor"] = mapOf(
                "x" to centerX,
                "y" to centerY,
                "color" to pixelColor
            )
        }
        return step
    }

    private fun capturePixelColor(x: Int, y: Int): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val latch = CountDownLatch(1)
            var color: Int? = null
            val executor = Executor { command -> screenshotHandler.post(command) }
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                executor,
                object : AccessibilityService.TakeScreenshotCallback {
                    override fun onSuccess(screenshot: AccessibilityService.Screenshot) {
                        try {
                            val bitmap = screenshot.bitmap
                            if (x in 0 until bitmap.width && y in 0 until bitmap.height) {
                                color = bitmap.getPixel(x, y)
                            }
                            bitmap.recycle()
                        } catch (_: Exception) {
                        }
                        latch.countDown()
                    }

                    override fun onFailure(errorCode: Int) {
                        latch.countDown()
                    }
                }
            )
            latch.await(2, TimeUnit.SECONDS)
            color
        } catch (e: Exception) {
            null
        }
    }

    private fun runMacro(steps: List<Map<String, Any>>, loop: Boolean, smartRecognition: Boolean) {
        isExecuting = true
        cancelExecutionFlag = false
        var cycleCount = 0
        do {
            cycleCount++
            reportStatus("新循环开始 (#$cycleCount)")
            for ((index, step) in steps.withIndex()) {
                if (cancelExecutionFlag) break
                val stepNumber = index + 1
                reportStatus("执行第${stepNumber}步")

                val delay = (step["delay"] as? Number)?.toLong() ?: 0L
                if (delay > 0) Thread.sleep(delay)

                if (smartRecognition) {
                    @Suppress("UNCHECKED_CAST")
                    val pixelColor = step["pixelColor"] as? Map<String, Any>
                    if (pixelColor != null) {
                        reportStatus("正在等待")
                        waitForPixelColor(pixelColor)
                    }
                }

                executeStep(step)
            }
            if (cancelExecutionFlag) {
                reportStatus("已停止")
                break
            }
            reportStatus("任务完成")
            if (loop) Thread.sleep(800)
        } while (loop && !cancelExecutionFlag)
        isExecuting = false
    }

    private fun waitForPixelColor(pixelColor: Map<String, Any>) {
        val x = (pixelColor["x"] as? Number)?.toInt() ?: return
        val y = (pixelColor["y"] as? Number)?.toInt() ?: return
        val expected = (pixelColor["color"] as? Number)?.toInt() ?: return

        val start = System.currentTimeMillis()
        while (System.currentTimeMillis() - start < 10000) {
            if (cancelExecutionFlag) return
            val current = capturePixelColor(x, y)
            if (current != null && colorsMatch(current, expected)) {
                return
            }
            Thread.sleep(300)
        }
    }

    private fun colorsMatch(a: Int, b: Int): Boolean {
        val threshold = 20
        return kotlin.math.abs(android.graphics.Color.red(a) - android.graphics.Color.red(b)) <= threshold &&
                kotlin.math.abs(android.graphics.Color.green(a) - android.graphics.Color.green(b)) <= threshold &&
                kotlin.math.abs(android.graphics.Color.blue(a) - android.graphics.Color.blue(b)) <= threshold
    }

    private fun executeStep(step: Map<String, Any>) {
        val type = step["type"] as? String ?: return
        when (type) {
            "clickNode" -> {
                @Suppress("UNCHECKED_CAST")
                val target = step["target"] as? Map<String, Any>
                if (target != null) {
                    val node = findNode(target)
                    if (node != null) {
                        node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        node.recycle()
                    } else {
                        @Suppress("UNCHECKED_CAST")
                        val bounds = target["bounds"] as? List<Int>
                        if (bounds != null && bounds.size == 4) {
                            val x = (bounds[0] + bounds[2]) / 2
                            val y = (bounds[1] + bounds[3]) / 2
                            dispatchClickInternal(x, y)
                        }
                    }
                }
            }
            "clickPoint" -> {
                @Suppress("UNCHECKED_CAST")
                val point = step["point"] as? Map<String, Any>
                val x = (point?.get("x") as? Number)?.toInt() ?: return
                val y = (point?.get("y") as? Number)?.toInt() ?: return
                dispatchClickInternal(x, y)
            }
            "swipe" -> {
                @Suppress("UNCHECKED_CAST")
                val start = step["start"] as? Map<String, Any>
                @Suppress("UNCHECKED_CAST")
                val end = step["end"] as? Map<String, Any>
                val x1 = (start?.get("x") as? Number)?.toInt() ?: return
                val y1 = (start?.get("y") as? Number)?.toInt() ?: return
                val x2 = (end?.get("x") as? Number)?.toInt() ?: return
                val y2 = (end?.get("y") as? Number)?.toInt() ?: return
                val duration = (step["duration"] as? Number)?.toLong() ?: 300
                dispatchSwipe(x1, y1, x2, y2, duration)
            }
            "wait" -> {
                val duration = (step["duration"] as? Number)?.toLong()
                    ?: (step["delay"] as? Number)?.toLong() ?: 0
                Thread.sleep(duration.coerceAtLeast(0))
            }
            "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
            "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
            "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
            "launchApp" -> {
                val packageName = step["packageName"] as? String ?: return
                launchApp(packageName)
            }
            "inputText" -> {
                val text = step["text"] as? String ?: return
                val node = findFocusedInputNode()
                if (node != null) {
                    val args = Bundle().apply {
                        putCharSequence(
                            AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                            text
                        )
                    }
                    node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                    node.recycle()
                }
            }
        }
    }

    private fun findNode(target: Map<String, Any>): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        val resourceId = target["resourceId"] as? String
        val text = target["text"] as? String
        val contentDesc = target["contentDescription"] as? String
        val className = target["className"] as? String
        @Suppress("UNCHECKED_CAST")
        val bounds = target["bounds"] as? List<Int>

        if (!resourceId.isNullOrEmpty()) {
            val nodes = root.findAccessibilityNodeInfosByViewId(resourceId)
            if (nodes.isNotEmpty()) return nodes[0]
        }

        if (!text.isNullOrEmpty() || !contentDesc.isNullOrEmpty()) {
            val found = dfsFind(root) { node ->
                node.text?.toString() == text || node.contentDescription?.toString() == contentDesc
            }
            if (found != null) return found
        }

        if (!className.isNullOrEmpty() && bounds != null && bounds.size == 4) {
            val targetRect = Rect(bounds[0], bounds[1], bounds[2], bounds[3])
            val found = dfsFind(root) { node ->
                val rect = Rect().also { node.getBoundsInScreen(it) }
                node.className?.toString() == className && Rect.intersects(rect, targetRect)
            }
            if (found != null) return found
        }

        return null
    }

    private inline fun dfsFind(root: AccessibilityNodeInfo, predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
        if (predicate(root)) return root
        for (i in 0 until root.childCount) {
            val child = root.getChild(i) ?: continue
            val found = dfsFind(child, predicate)
            if (found != null) return found
        }
        return null
    }

    private fun dispatchClickInternal(x: Int, y: Int): Boolean {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 100)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return dispatchGesture(gesture, null, null)
    }

    private fun dispatchSwipe(x1: Int, y1: Int, x2: Int, y2: Int, duration: Long) {
        val path = Path().apply {
            moveTo(x1.toFloat(), y1.toFloat())
            lineTo(x2.toFloat(), y2.toFloat())
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, duration.coerceIn(100, 2000))
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, null, null)
    }

    private fun launchApp(packageName: String) {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        if (intent != null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        }
    }

    private fun reportStatus(message: String) {
        macroListener?.onStatus(message)
    }
}
