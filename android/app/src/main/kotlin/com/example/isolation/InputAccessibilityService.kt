package com.example.isolation

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Rect
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import java.util.concurrent.atomic.AtomicBoolean

class InputAccessibilityService : AccessibilityService() {

    companion object {
        private var instance: InputAccessibilityService? = null

        fun isEnabled(context: Context): Boolean {
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            val serviceName = "${context.packageName}/${InputAccessibilityService::class.java.canonicalName}"
            return enabledServices.contains(serviceName)
        }

        fun startRecording(context: Context, captureColors: Boolean = false): Boolean {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return false
            }
            return service.startRecordingInternal(captureColors)
        }

        fun stopRecording(context: Context): List<Map<String, Any>> {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return emptyList()
            }
            return service.stopRecordingInternal()
        }

        fun executeMacro(
            context: Context,
            settings: Map<String, Any>,
            steps: List<Map<String, Any>>
        ): Boolean {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return false
            }
            service.executeMacroInternal(settings, steps)
            return true
        }

        fun dispatchClick(context: Context, x: Int, y: Int): Boolean {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return false
            }
            return MacroExecutor(service).dispatchClickForCompanion(x, y)
        }

        // Legacy helpers for the old floating keyboard behavior (unused after macro migration)
        fun showInputMethod(context: Context) {
            val node = instance?.findFocusedInputNode()
            if (node != null) {
                node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            } else {
                Toast.makeText(context, "未找到输入框", Toast.LENGTH_SHORT).show()
            }
        }

        fun injectKey(context: Context, key: String) {
            val node = instance?.findFocusedInputNode()
            if (node != null) {
                val currentText = node.text?.toString() ?: ""
                val newText = currentText + key
                val args = android.os.Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, newText)
                }
                node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            } else {
                Toast.makeText(context, "未找到输入框", Toast.LENGTH_SHORT).show()
            }
        }

        fun injectBackspace(context: Context) {
            val node = instance?.findFocusedInputNode()
            if (node != null) {
                val currentText = node.text?.toString() ?: ""
                if (currentText.isNotEmpty()) {
                    val newText = currentText.substring(0, currentText.length - 1)
                    val args = android.os.Bundle().apply {
                        putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, newText)
                    }
                    node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                }
            } else {
                Toast.makeText(context, "未找到输入框", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private var recording = AtomicBoolean(false)
    private val recordedSteps = mutableListOf<RecordedStep>()
    private var lastEventTime: Long = 0L
    private var captureColors: Boolean = false

    private data class RecordedStep(
        val timestamp: Long,
        val step: Map<String, Any>
    )

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        if (!recording.get()) return
        if (event.eventType != AccessibilityEvent.TYPE_VIEW_CLICKED) return

        val source = event.source ?: return
        val packageName = event.packageName?.toString() ?: return
        if (packageName == this@InputAccessibilityService.packageName) return

        val bounds = Rect()
        source.getBoundsInScreen(bounds)

        val target = mutableMapOf<String, Any?>(
            "resourceId" to source.viewIdResourceName,
            "text" to (source.text?.toString()),
            "contentDescription" to (source.contentDescription?.toString()),
            "className" to (source.className?.toString()),
            "bounds" to listOf(bounds.left, bounds.top, bounds.right, bounds.bottom),
            "packageName" to packageName
        )

        val centerX = (bounds.left + bounds.right) / 2
        val centerY = (bounds.top + bounds.bottom) / 2

        val step = mutableMapOf<String, Any?>(
            "type" to "clickNode",
            "delay" to computeDelay(),
            "target" to target.filterValues { it != null }
        )

        if (captureColors) {
            val color = ScreenCaptureHelper.captureColor(this, centerX, centerY)
            if (color != null) {
                step["color"] = mapOf(
                    "x" to centerX,
                    "y" to centerY,
                    "color" to color
                )
            }
        }

        recordedSteps.add(RecordedStep(System.currentTimeMillis(), step.filterValues { it != null }))
    }

    override fun onInterrupt() {
        instance = null
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    private fun computeDelay(): Long {
        val now = System.currentTimeMillis()
        val delay = if (lastEventTime == 0L) 0L else now - lastEventTime
        lastEventTime = now
        return delay
    }

    private fun startRecordingInternal(captureColors: Boolean = false): Boolean {
        if (recording.getAndSet(true)) return false
        recordedSteps.clear()
        lastEventTime = 0L
        this.captureColors = captureColors
        return true
    }

    private fun stopRecordingInternal(): List<Map<String, Any>> {
        recording.set(false)
        captureColors = false
        return recordedSteps.map { it.step }
    }

    private fun executeMacroInternal(settings: Map<String, Any>, steps: List<Map<String, Any>>) {
        MacroExecutor(this).execute(settings, steps)
    }

    private fun findFocusedInputNode(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
    }
}
