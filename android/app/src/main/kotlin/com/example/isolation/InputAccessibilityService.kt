package com.example.isolation

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.os.CountDownLatch
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import java.util.concurrent.TimeUnit
import kotlin.math.abs

class InputAccessibilityService : AccessibilityService() {

    data class RecordedStep(
        val delayMs: Int,
        val x: Int,
        val y: Int,
        val color: Int?
    )

    data class MacroStep(
        val delayMs: Int,
        val x: Int,
        val y: Int,
        val color: Int?
    )

    companion object {
        private var instance: InputAccessibilityService? = null

        private var recording = false
        private var executing = false
        private var stopRequested = false

        private var macroLoop = false
        private var macroSmartRecognition = false
        private var currentMacroId = ""
        private var currentMacroSteps: List<MacroStep> = emptyList()

        private val recordedSteps = mutableListOf<RecordedStep>()
        private var lastRecordTime = 0L

        private val mainHandler = Handler(Looper.getMainLooper())
        private const val COLOR_MATCH_TOLERANCE = 20
        private const val WAIT_COLOR_TIMEOUT_MS = 30000L
        private const val WAIT_COLOR_INTERVAL_MS = 200L

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

        fun startRecording(context: Context): Boolean {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return false
            }
            if (executing) {
                Toast.makeText(context, "正在执行宏，无法录制", Toast.LENGTH_SHORT).show()
                return false
            }
            synchronized(recordedSteps) {
                recordedSteps.clear()
            }
            recording = true
            lastRecordTime = 0L
            FloatingBallService.showToast(context, "开始录制")
            return true
        }

        fun stopRecording(context: Context): List<Map<String, Any>> {
            recording = false
            lastRecordTime = 0L
            val stepsCopy = synchronized(recordedSteps) {
                val copy = recordedSteps.toList()
                recordedSteps.clear()
                copy
            }
            FloatingBallService.showToast(context, "已停止录制，共 ${stepsCopy.size} 步")
            return stepsCopy.map {
                mutableMapOf<String, Any>(
                    "delayMs" to it.delayMs,
                    "x" to it.x,
                    "y" to it.y
                ).apply {
                    it.color?.let { c -> put("color", c) }
                }
            }
        }

        fun isRecording(): Boolean = recording

        fun isExecuting(): Boolean = executing

        fun hasCurrentMacro(): Boolean = currentMacroId.isNotEmpty() && currentMacroSteps.isNotEmpty()

        fun executeMacro(
            context: Context,
            macroId: String,
            rawSteps: List<Map<String, Any>>?,
            loop: Boolean,
            smartRecognition: Boolean
        ) {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return
            }
            if (recording) {
                Toast.makeText(context, "正在录制中，无法执行", Toast.LENGTH_SHORT).show()
                return
            }
            if (executing) {
                stopExecution(context)
                return
            }

            val steps = rawSteps?.let { parseSteps(it) } ?: currentMacroSteps
            if (steps.isEmpty()) {
                Toast.makeText(context, "宏步骤为空", Toast.LENGTH_SHORT).show()
                return
            }

            currentMacroId = macroId
            macroLoop = loop
            macroSmartRecognition = smartRecognition
            currentMacroSteps = steps
            stopRequested = false
            executing = true

            FloatingBallService.showToast(context, "开始执行宏")
            service.executeStepsInternal(steps)
        }

        fun executeCurrentMacro(context: Context) {
            if (currentMacroId.isEmpty() || currentMacroSteps.isEmpty()) {
                Toast.makeText(context, "未设置当前宏，请在应用内启用宏", Toast.LENGTH_SHORT).show()
                return
            }
            if (recording) {
                Toast.makeText(context, "正在录制中", Toast.LENGTH_SHORT).show()
                return
            }
            if (executing) {
                stopExecution(context)
                return
            }
            executeMacro(context, currentMacroId, null, macroLoop, macroSmartRecognition)
        }

        fun stopExecution(context: Context): Boolean {
            if (!executing) return false
            stopRequested = true
            executing = false
            FloatingBallService.showToast(context, "已停止执行")
            return true
        }

        fun setMacroConfig(
            macroId: String,
            loop: Boolean,
            smartRecognition: Boolean,
            rawSteps: List<Map<String, Any>>?
        ) {
            currentMacroId = macroId
            macroLoop = loop
            macroSmartRecognition = smartRecognition
            currentMacroSteps = parseSteps(rawSteps)
        }

        private fun parseSteps(raw: List<Map<String, Any>>?): List<MacroStep> {
            return raw?.map {
                MacroStep(
                    delayMs = (it["delayMs"] as? Number)?.toInt() ?: 0,
                    x = (it["x"] as? Number)?.toInt() ?: 0,
                    y = (it["y"] as? Number)?.toInt() ?: 0,
                    color = (it["color"] as? Number)?.toInt()
                )
            } ?: emptyList()
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (recording && event?.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED) {
            handleRecordedClick(event)
        }
    }

    override fun onInterrupt() {
        instance = null
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        stopRequested = true
        executing = false
        recording = false
    }

    private fun handleRecordedClick(event: AccessibilityEvent) {
        val node = event.source ?: return
        val rect = android.graphics.Rect()
        try {
            node.getBoundsInScreen(rect)
        } catch (_: Exception) {
            return
        } finally {
            node.recycle()
        }

        val x = rect.centerX()
        val y = rect.centerY()
        val now = SystemClock.elapsedRealtime()
        val delayMs = if (lastRecordTime == 0L) 0 else (now - lastRecordTime).toInt()
        lastRecordTime = now

        Thread {
            val color = captureColor(x, y)
            val stepIndex = synchronized(recordedSteps) {
                recordedSteps.add(RecordedStep(delayMs, x, y, color))
                recordedSteps.size
            }
            mainHandler.post {
                FloatingBallService.showToast(this, "已记录第 $stepIndex 步")
            }
        }.start()
    }

    private fun findFocusedInputNode(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
    }

    private fun executeStepsInternal(steps: List<MacroStep>) {
        Thread {
            try {
                do {
                    for ((index, step) in steps.withIndex()) {
                        if (stopRequested) break

                        reportStep(index + 1, steps.size)
                        Thread.sleep(step.delayMs.coerceAtLeast(0).toLong())
                        if (stopRequested) break

                        if (macroSmartRecognition && step.color != null) {
                            waitForColor(step.x, step.y, step.color)
                        }
                        if (stopRequested) break

                        dispatchClick(step.x, step.y)
                    }

                    if (macroLoop && !stopRequested) {
                        reportLoopStart()
                    }
                } while (macroLoop && !stopRequested)
            } catch (_: InterruptedException) {
                // ignore
            } finally {
                executing = false
                reportComplete()
            }
        }.start()
    }

    private fun reportStep(step: Int, total: Int) {
        FloatingBallService.showToast(this, "执行第 $step / $total 步")
    }

    private fun reportWaiting() {
        FloatingBallService.showToast(this, "正在等待")
    }

    private fun reportLoopStart() {
        FloatingBallService.showToast(this, "新循环开始")
    }

    private fun reportComplete() {
        FloatingBallService.showToast(this, "任务完成")
    }

    private fun waitForColor(x: Int, y: Int, expectedColor: Int) {
        val start = SystemClock.elapsedRealtime()
        var waitingReported = false
        while (!stopRequested && SystemClock.elapsedRealtime() - start < WAIT_COLOR_TIMEOUT_MS) {
            val current = captureColor(x, y)
            if (current != null && colorMatches(current, expectedColor)) {
                return
            }
            if (!waitingReported) {
                reportWaiting()
                waitingReported = true
            }
            Thread.sleep(WAIT_COLOR_INTERVAL_MS)
        }
    }

    private fun colorMatches(current: Int, expected: Int): Boolean {
        val aDiff = abs((current shr 24 and 0xFF) - (expected shr 24 and 0xFF))
        val rDiff = abs((current shr 16 and 0xFF) - (expected shr 16 and 0xFF))
        val gDiff = abs((current shr 8 and 0xFF) - (expected shr 8 and 0xFF))
        val bDiff = abs((current and 0xFF) - (expected and 0xFF))
        return rDiff <= COLOR_MATCH_TOLERANCE &&
                gDiff <= COLOR_MATCH_TOLERANCE &&
                bDiff <= COLOR_MATCH_TOLERANCE &&
                aDiff <= COLOR_MATCH_TOLERANCE
    }

    private fun dispatchClick(x: Int, y: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 80))
            .build()
        dispatchGesture(gesture, null, null)
    }

    private fun captureColor(x: Int, y: Int): Int? {
        val bitmap = takeScreenshotSync() ?: return null
        val safeX = x.coerceIn(0, bitmap.width - 1)
        val safeY = y.coerceIn(0, bitmap.height - 1)
        val color = bitmap.getPixel(safeX, safeY)
        bitmap.recycle()
        return color
    }

    private fun takeScreenshotSync(): Bitmap? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val service = instance ?: return null
        val latch = CountDownLatch(1)
        var bitmap: Bitmap? = null
        try {
            service.takeScreenshot(
                Display.DEFAULT_DISPLAY,
                mainExecutor
            ) { screenshotResult ->
                bitmap = screenshotResult.bitmap
                latch.countDown()
            }
        } catch (_: Exception) {
            return null
        }
        latch.await(2, TimeUnit.SECONDS)
        return bitmap
    }
}
