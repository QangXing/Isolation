package com.qangxing.isolation

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicBoolean

class InputAccessibilityService : AccessibilityService(), MacroExecutorListener {

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

        /**
         * 通过辅助服务向系统派发一次手势回放（录制捕获层原样回放给目标 App）。
         * [suppressEvents] 为 false 时（点击回放），系统产生的 TYPE_VIEW_CLICKED
         * 事件会回调 onAccessibilityEvent 用于补全最近一次点击的节点信息。
         * [onResult] 在回放完成或取消时回调，可用于提前结束本地屏蔽窗口。
         */
        fun dispatchReplayGesture(
            path: Path,
            duration: Long,
            suppressEvents: Boolean,
            onResult: ((Boolean) -> Unit)? = null
        ): Boolean {
            val svc = instance ?: return false.also { onResult?.invoke(false) }
            if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) {
                onResult?.invoke(false)
                return false
            }
            val gesture = GestureDescription.Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 0, duration.coerceAtLeast(1L)))
                .build()
            return svc.dispatchGesture(gesture, object : AccessibilityService.GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    onResult?.invoke(true)
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    onResult?.invoke(false)
                }
            }, null)
        }

        fun executeMacro(
            context: Context,
            settings: Map<String, Any>,
            steps: List<Map<String, Any>>,
            assetsDir: String? = null,
            pluginId: String? = null
        ): Boolean {
            if (!notifyNotReady(context)) return false
            return instance!!.executeMacroInternal(settings, steps, assetsDir, pluginId)
        }

        fun dispatchClick(context: Context, x: Int, y: Int): Boolean {
            if (!notifyNotReady(context)) return false
            return instance!!.dispatchClickForCompanion(x, y)
        }

        fun showClickAnimation(x: Float, y: Float) {
            instance?.postTouchEffect(TouchEffect.Click(x, y))
        }

        fun showSwipeAnimation(startX: Float, startY: Float, endX: Float, endY: Float) {
            instance?.postTouchEffect(TouchEffect.Swipe(startX, startY, endX, endY))
        }

        /**
         * 触发一次服务状态轮询。AccessibilityService 由系统管理，无法手动 startService，
         * 但发送一个无障碍事件监听请求可让系统在合适时机回调 onServiceConnected。
         * 这里通过返回 readinessState 让调用方决策。
         */
        fun tryEnsureReady(context: Context): Int = readinessState(context)

        // === 定时宏补执行（服务未就绪时暂存，onServiceConnected 后执行） ===

        private const val PREF_PENDING_SCHEDULE = "isolation_pending_schedule"
        private const val KEY_PLUGIN_ID = "pluginId"
        private const val KEY_MACRO_FILE = "macroFile"

        /** 定时触发时辅助服务尚未连上，暂存待执行宏，避免本次触发丢失。 */
        fun persistPendingSchedule(context: Context, pluginId: String, macroFile: String) {
            context.getSharedPreferences(PREF_PENDING_SCHEDULE, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_PLUGIN_ID, pluginId)
                .putString(KEY_MACRO_FILE, macroFile)
                .apply()
        }

        private fun consumePendingSchedule(context: Context): Pair<String, String>? {
            val prefs = context.getSharedPreferences(PREF_PENDING_SCHEDULE, Context.MODE_PRIVATE)
            val pluginId = prefs.getString(KEY_PLUGIN_ID, null) ?: return null
            val macroFile = prefs.getString(KEY_MACRO_FILE, null) ?: return null
            prefs.edit().remove(KEY_PLUGIN_ID).remove(KEY_MACRO_FILE).apply()
            return pluginId to macroFile
        }

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

    private val mainHandler = Handler(Looper.getMainLooper())
    private var touchEffectOverlay: TouchEffectOverlay? = null
    private val hideOverlayRunnable = Runnable { hideTouchEffectOverlay() }

    override fun onServiceConnected() {
        try {
            super.onServiceConnected()
            instance = this
            Log.d(TAG, "onServiceConnected")
            MacroStatusNotifier.refreshState(this)
            runPendingScheduledMacro()
        } catch (e: Exception) {
            Log.e(TAG, "onServiceConnected failed", e)
        }
    }

    /** 定时触发时服务未就绪被暂存的宏，连接后立即补执行。 */
    private fun runPendingScheduledMacro() {
        val pair = consumePendingSchedule(this) ?: return
        val (pluginId, macroFile) = pair
        if (MacroExecutor.isRunning()) {
            Log.w(TAG, "已有宏在运行，跳过暂存定时宏: $pluginId")
            return
        }
        // 尽力拉起悬浮球服务，让 print 能以气泡形式显示（失败则由 Toast 兜底）
        try {
            val intent = Intent(this, FloatingBallService::class.java)
                .setAction(FloatingBallService.ACTION_SHOW)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            Log.w(TAG, "拉起悬浮球服务失败，print 将走 Toast 兜底", e)
        }
        val macro = MacroScheduleReceiver.loadMacro(this, pluginId, macroFile)
        if (macro == null || macro.steps.isEmpty()) {
            Log.w(TAG, "暂存定时宏文件缺失，已丢弃: $pluginId")
            return
        }
        val pluginDir = MacroScheduleReceiver.pluginRoot(this, pluginId)
        val assetsDir = File(pluginDir, "assets").takeIf { it.exists() }?.absolutePath
        Log.d(TAG, "补执行暂存定时宏: $pluginId/$macroFile")
        executeMacroInternal(macro.settings, macro.steps, assetsDir, pluginId)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        val packageName = event.packageName?.toString() ?: return
        if (packageName == this@InputAccessibilityService.packageName) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_VIEW_CLICKED -> {
                val source = event.source ?: return
                val bounds = Rect()
                source.getBoundsInScreen(bounds)
                val centerX = (bounds.left + bounds.right) / 2
                val centerY = (bounds.top + bounds.bottom) / 2
                val target = mutableMapOf<String, Any?>(
                    "resourceId" to source.viewIdResourceName,
                    "text" to (source.text?.toString()),
                    "contentDescription" to (source.contentDescription?.toString()),
                    "className" to (source.className?.toString()),
                    "bounds" to listOf(bounds.left, bounds.top, bounds.right, bounds.bottom),
                    "packageName" to packageName
                )

                if (RecordingSession.isRecording()) {
                    if (RecordingSession.gestureMode) {
                        // 手势模式：捕获层回放的点击，补全最近一次坐标点击为 clickNode
                        RecordingSession.enrichLastClick(
                            target.filterValues { it != null },
                            centerX,
                            centerY
                        )
                    } else {
                        // 普通模式：直接由节点事件生成点击步骤
                        RecordingSession.onAccessibilityClickCaptured(
                            centerX,
                            centerY,
                            target.filterValues { it != null },
                            packageName
                        )
                    }
                }
            }
            AccessibilityEvent.TYPE_VIEW_LONG_CLICKED -> {
                val source = event.source ?: return
                val bounds = Rect()
                source.getBoundsInScreen(bounds)
                val centerX = (bounds.left + bounds.right) / 2
                val centerY = (bounds.top + bounds.bottom) / 2
                if (RecordingSession.isRecording() && !RecordingSession.gestureMode) {
                    RecordingSession.onLongPressCaptured(centerX, centerY, 600L)
                }
            }
            AccessibilityEvent.TYPE_VIEW_SCROLLED -> {
                val source = event.source ?: return
                val bounds = Rect()
                source.getBoundsInScreen(bounds)
                val centerX = (bounds.left + bounds.right) / 2
                val centerY = (bounds.top + bounds.bottom) / 2
                val deltaX = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) event.scrollDeltaX else 0
                val deltaY = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) event.scrollDeltaY else 0
                if (RecordingSession.isRecording() && !RecordingSession.gestureMode) {
                    RecordingSession.onScrollCaptured(centerX, centerY, deltaX, deltaY, packageName)
                }
            }
        }
    }

    /**
     * 录制中检测系统按键（返回键 / Home 键）。
     * 需要用户在系统辅助功能设置中开启"请求按键过滤"，未开启时仅返回键可被监听。
     */
    override fun onKeyEvent(event: android.view.KeyEvent): Boolean {
        if (event.action == android.view.KeyEvent.ACTION_UP) {
            when (event.keyCode) {
                android.view.KeyEvent.KEYCODE_BACK -> RecordingSession.onSystemKey("back")
                android.view.KeyEvent.KEYCODE_HOME -> RecordingSession.onSystemKey("home")
            }
        }
        return super.onKeyEvent(event)
    }

    override fun onInterrupt() {
        instance = null
    }

    override fun onUnbind(intent: Intent?): Boolean {
        cleanup()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        cleanup()
        super.onDestroy()
    }

    private fun cleanup() {
        instance = null
        MacroExecutor.removeListener(this)
        mainHandler.removeCallbacks(hideOverlayRunnable)
        hideTouchEffectOverlay()
        MacroStatusNotifier.refreshState(this)
    }

    private fun executeMacroInternal(
        settings: Map<String, Any>,
        steps: List<Map<String, Any>>,
        assetsDir: String? = null,
        pluginId: String? = null
    ): Boolean {
        // 已有宏在运行时不启动，返回 false 让调用方得知实际未启动
        if (MacroExecutor.isRunning()) return false
        MacroExecutor.addListener(this)
        mainHandler.removeCallbacks(hideOverlayRunnable)
        // 同步创建动画覆盖层（MethodChannel 默认在主线程），
        // 保证 macro 线程开始前 touchEffectOverlay 已实例化，动画可进入 pending 队列。
        ensureTouchEffectOverlay()
        return MacroExecutor(this, assetsDir).execute(settings, steps, pluginId)
    }

    private fun dispatchClickForCompanion(x: Int, y: Int): Boolean {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) return false
        postTouchEffect(TouchEffect.Click(x.toFloat(), y.toFloat()))
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

    // ---------- 宏执行触摸反馈动画 ----------

    override fun onMacroStatus(message: String) {
        // 宏结束或异常后延迟移除动画覆盖层，保留一段时间让最后一个动画播完
        if (message == "任务完成" || message == "任务已停止" || message.startsWith("任务异常")) {
            mainHandler.postDelayed(hideOverlayRunnable, 1000L)
        }
    }

    override fun onMacroPrint(message: String) {
        // 悬浮球未就绪（如进程被杀后服务重建期间）时没有气泡载体，
        // 用 Toast 兜底显示，避免 print 不可见；悬浮球就绪后仍由其气泡展示。
        if (!FloatingBallService.hasVisibleBall()) {
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        }
    }

    private fun postTouchEffect(effect: TouchEffect) {
        mainHandler.post {
            mainHandler.removeCallbacks(hideOverlayRunnable)
            ensureTouchEffectOverlay()
            touchEffectOverlay?.postEffect(effect)
        }
    }

    private fun ensureTouchEffectOverlay() {
        if (touchEffectOverlay != null) return
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }
        touchEffectOverlay = TouchEffectOverlay(this).apply {
            post {
                try {
                    wm.addView(this, params)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    private fun hideTouchEffectOverlay() {
        val overlay = touchEffectOverlay ?: return
        touchEffectOverlay = null
        try {
            val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            wm.removeView(overlay)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
