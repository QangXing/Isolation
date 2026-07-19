package com.example.isolation

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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

        fun startRecording(context: Context): Boolean {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return false
            }
            return service.startRecordingInternal()
        }

        fun stopRecording(context: Context): List<Map<String, Any>> {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return emptyList()
            }
            return service.stopRecordingInternal()
        }

        fun executeMacro(context: Context, steps: List<Map<String, Any>>): Boolean {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return false
            }
            service.executeMacroInternal(steps)
            return true
        }

        fun dispatchClick(context: Context, x: Int, y: Int): Boolean {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return false
            }
            return service.dispatchClickInternal(x, y)
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
                val args = Bundle().apply {
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
                    val args = Bundle().apply {
                        putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, newText)
                    }
                    node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                }
            } else {
                Toast.makeText(context, "未找到输入框", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var recording = AtomicBoolean(false)
    private val recordedSteps = mutableListOf<RecordedStep>()
    private var lastEventTime: Long = 0L

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

        val now = System.currentTimeMillis()
        val delay = if (lastEventTime == 0L) 0L else now - lastEventTime
        lastEventTime = now

        val step = mapOf(
            "type" to "clickNode",
            "delay" to delay,
            "target" to target.filterValues { it != null }
        )
        recordedSteps.add(RecordedStep(now, step))
    }

    override fun onInterrupt() {
        instance = null
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    private fun startRecordingInternal(): Boolean {
        if (recording.getAndSet(true)) return false
        recordedSteps.clear()
        lastEventTime = 0L
        return true
    }

    private fun stopRecordingInternal(): List<Map<String, Any>> {
        recording.set(false)
        return recordedSteps.map { it.step }
    }

    private fun executeMacroInternal(steps: List<Map<String, Any>>) {
        Thread {
            for (step in steps) {
                val delay = (step["delay"] as? Number)?.toLong() ?: 0L
                if (delay > 0) Thread.sleep(delay)

                when (step["type"] as? String) {
                    "clickNode" -> executeClickNode(step)
                    "clickPoint" -> executeClickPoint(step)
                    "launchApp" -> executeLaunchApp(step)
                    "inputText" -> executeInputText(step)
                    "wait" -> {
                        val duration = (step["duration"] as? Number)?.toLong() ?: 0L
                        if (duration > 0) Thread.sleep(duration)
                    }
                    "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
                    "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
                    "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
                }
            }
        }.start()
    }

    private fun executeClickNode(step: Map<String, Any>) {
        val target = step["target"] as? Map<String, Any> ?: return
        val boundsList = target["bounds"] as? List<*>
        val fallbackBounds = boundsList?.mapNotNull { it as? Int }

        val root = rootInActiveWindow ?: return
        val node = findMatchingNode(root, target)

        if (node != null) {
            val clicked = node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            if (clicked) return
        }

        // Fallback to bounds center coordinate
        if (fallbackBounds != null && fallbackBounds.size == 4) {
            val centerX = (fallbackBounds[0] + fallbackBounds[2]) / 2
            val centerY = (fallbackBounds[1] + fallbackBounds[3]) / 2
            dispatchClickInternal(centerX, centerY)
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

        // Priority 1: resourceId
        if (!resourceId.isNullOrEmpty()) {
            allNodes.firstOrNull { it.viewIdResourceName == resourceId }?.let { return it }
        }

        // Priority 2: text or contentDescription
        if (!text.isNullOrEmpty()) {
            allNodes.firstOrNull { it.text?.toString() == text || it.contentDescription?.toString() == text }
                ?.let { return it }
        }
        if (!contentDescription.isNullOrEmpty()) {
            allNodes.firstOrNull { it.contentDescription?.toString() == contentDescription }
                ?.let { return it }
        }

        // Priority 3: className + bounds overlap
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
        dispatchClickInternal(x, y)
    }

    private fun executeLaunchApp(step: Map<String, Any>) {
        val packageName = step["packageName"] as? String ?: return
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun executeInputText(step: Map<String, Any>) {
        val text = step["text"] as? String ?: return
        val root = rootInActiveWindow ?: return
        val node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (node != null) {
            val args = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            }
            node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        }
    }

    private fun dispatchClickInternal(x: Int, y: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path().apply {
            moveTo(x.toFloat(), y.toFloat())
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    private fun findFocusedInputNode(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
    }
}
