package com.example.isolation

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicBoolean

class InputAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "InputA11yService"
        private var instance: InputAccessibilityService? = null

        /** 服务在系统设置中是否已启用 */
        fun isEnabled(context: Context): Boolean {
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            val serviceName = "${context.packageName}/${InputAccessibilityService::class.java.name}"
            return enabledServices.split(':').any { it.trim() == serviceName }
        }

        /** 服务实例是否就绪（系统已启用且 onServiceConnected 已回调） */
        fun isReady(context: Context): Boolean {
            return isEnabled(context) && instance != null
        }

        /**
         * 统一的状态检查：返回当前为何种状态。
         * - 0：就绪
         * - 1：系统设置中未启用
         * - 2：系统设置已启用但服务实例尚未连上
         */
        fun readinessState(context: Context): Int {
            return if (!isEnabled(context)) 1
            else if (instance == null) 2
            else 0
        }

        /** 给用户看的友好提示，避免一直误报"请先开启辅助功能权限" */
        private fun notifyNotReady(context: Context): Boolean {
            val state = readinessState(context)
            when (state) {
                1 -> Toast.makeText(context, "请先在系统设置中开启辅助功能权限", Toast.LENGTH_SHORT).show()
                2 -> Toast.makeText(context, "辅助服务正在启动中，请稍后重试", Toast.LENGTH_SHORT).show()
            }
            return state == 0
        }

        fun startRecording(context: Context, captureColors: Boolean = false): Boolean {
            if (!notifyNotReady(context)) return false
            return instance!!.startRecordingInternal(captureColors)
        }

        fun stopRecording(context: Context): List<Map<String, Any>> {
            if (!notifyNotReady(context)) return emptyList()
            return instance!!.stopRecordingInternal()
        }

        fun executeMacro(
            context: Context,
            settings: Map<String, Any>,
            steps: List<Map<String, Any>>,
            assetsDir: String? = null
        ): Boolean {
            if (!notifyNotReady(context)) return false
            instance!!.executeMacroInternal(settings, steps, assetsDir)
            return true
        }

        fun dispatchClick(context: Context, x: Int, y: Int): Boolean {
            if (!notifyNotReady(context)) return false
            return instance!!.dispatchClickForCompanion(x, y)
        }

        /**
         * 触发一次服务状态轮询。AccessibilityService 由系统管理，无法手动 startService，
         * 但发送一个无障碍事件监听请求可让系统在合适时机回调 onServiceConnected。
         * 这里通过返回 readinessState 让调用方决策。
         */
        fun tryEnsureReady(context: Context): Int = readinessState(context)

        // Legacy helpers for the old floating keyboard behavior (unused after macro migration)
        fun showInputMethod(context: Context) {
            if (!notifyNotReady(context)) return
            val node = instance?.findFocusedInputNode()
            if (node != null) {
                node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            } else {
                Toast.makeText(context, "未找到输入框", Toast.LENGTH_SHORT).show()
            }
        }

        fun injectKey(context: Context, key: String) {
            if (!notifyNotReady(context)) return
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
            if (!notifyNotReady(context)) return
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

        recordedSteps.add(RecordedStep(System.currentTimeMillis(), step.filterValues { it != null }.mapValues { it.value as Any }))
    }

    override fun onInterrupt() {
        instance = null
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
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

    private fun executeMacroInternal(
        settings: Map<String, Any>,
        steps: List<Map<String, Any>>,
        assetsDir: String? = null
    ) {
        MacroExecutor(this, assetsDir).execute(settings, steps)
    }

    private fun dispatchClickForCompanion(x: Int, y: Int): Boolean {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) return false
        FloatingBallService.showClickAnimation(x.toFloat(), y.toFloat())
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        val result = AtomicBoolean(false)
        val latch = CountDownLatch(1)
        Handler(Looper.getMainLooper()).post {
            result.set(dispatchGesture(gesture, null, null))
            latch.countDown()
        }
        try { latch.await() } catch (_: InterruptedException) { /* ignore */ }
        return result.get()
    }

    private fun findFocusedInputNode(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
    }
}
