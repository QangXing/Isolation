package com.example.isolation

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Point
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class FloatingBallService : Service(), MacroExecutorListener {
    companion object {
        const val ACTION_SHOW = "ACTION_SHOW"
        const val ACTION_HIDE = "ACTION_HIDE"
        const val CHANNEL_ID = "isolation_floating_ball"
        const val NOTIFICATION_ID = 1
        const val ENABLED_MACRO_FILE = "enabled_macro.json"
        private const val BALL_SIZE_DP = 56
        private const val BUBBLE_GAP_DP = 12
        private const val BUBBLE_AUTO_HIDE_MS = 2500L
        private const val CLICK_SLOP_PX = 12
        private const val LONG_CLICK_TIMEOUT_MS = 400L

        private const val PREF_NAME = "isolation_floating_ball"
        private const val KEY_CUSTOM_ICON = "custom_icon_path"

        @Volatile
        private var instance: FloatingBallService? = null

        /** 获取当前运行的服务实例，用于在前台服务上下文中初始化屏幕录制。 */
        fun getInstance(): FloatingBallService? = instance

        /**
         * 显示一次点击动画。坐标为屏幕像素坐标系（左上角原点）。
         * 即使悬浮球服务未运行也不会崩溃。
         */
        fun showClickAnimation(x: Float, y: Float) {
            instance?.postTouchEffect(TouchEffect.Click(x, y))
        }

        /**
         * 显示一次滑动动画。坐标为屏幕像素坐标系（左上角原点）。
         */
        fun showSwipeAnimation(startX: Float, startY: Float, endX: Float, endY: Float) {
            instance?.postTouchEffect(TouchEffect.Swipe(startX, startY, endX, endY))
        }

        private fun prefs(context: Context): SharedPreferences {
            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        }

        /**
         * 设置或清除悬浮球自定义图标路径。传入 null 表示恢复默认。
         * 若服务正在运行，会立即刷新显示。
         */
        fun setCustomIcon(context: Context, imagePath: String?): Boolean {
            prefs(context).edit().putString(KEY_CUSTOM_ICON, imagePath).apply()
            if (imagePath == null) {
                instance?.applyDefaultIcon()
            } else {
                instance?.applyCustomIcon(imagePath)
            }
            return true
        }

        fun getCustomIcon(context: Context): String? {
            return prefs(context).getString(KEY_CUSTOM_ICON, null)
        }
    }

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var floatingParams: WindowManager.LayoutParams? = null
    private var bubbleView: TextView? = null

    // 当前执行宏是否开启调试模式，用于控制是否显示每步默认提示
    private var macroDebugMode = false
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var keyboardView: KeyboardOverlayView? = null
    private var animationOverlay: TouchEffectOverlay? = null

    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var downTime = 0L
    private var hasMoved = false
    private var longClickFired = false

    private val mainHandler = Handler(Looper.getMainLooper())
    private val bubbleHideRunnable = Runnable { hideBubble() }
    private val longClickRunnable = Runnable {
        if (!hasMoved && !longClickFired) {
            longClickFired = true
            openMainActivity()
        }
    }

    private val ballSizePx: Int by lazy {
        val density = resources.displayMetrics.density
        (BALL_SIZE_DP * density).toInt()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        MacroExecutor.addListener(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 兜底：START_STICKY 重启时 intent 可能为 null，只要悬浮球没在显示就重新显示
        if (intent == null) {
            if (Settings.canDrawOverlays(this) && floatingView == null) {
                showFloatingBall()
            }
            return START_STICKY
        }
        when (intent.action) {
            ACTION_SHOW -> showFloatingBall()
            ACTION_HIDE -> {
                hideFloatingBall()
                hideKeyboard()
                stopForegroundService()
                stopSelf()
            }
        }
        return START_STICKY
    }

    /**
     * 在前台服务上下文中初始化屏幕录制。
     * Android 14+ 要求 VirtualDisplay 必须由带有 mediaProjection 前台服务类型的 Service 创建。
     */
    fun initScreenCapture(resultCode: Int, data: Intent?): Boolean {
        return try {
            ScreenCaptureHelper.onActivityResult(this, resultCode, data)
        } catch (e: Exception) {
            android.util.Log.e("FloatingBallService", "初始化屏幕录制失败", e)
            false
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "悬浮球服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "保持悬浮球在屏幕上显示"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun startForegroundNotification() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("isolation")
            .setContentText("悬浮球宏正在运行")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun stopForegroundService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun showFloatingBall() {
        if (floatingView != null) return
        if (!Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "请先授予悬浮窗权限", Toast.LENGTH_SHORT).show()
            return
        }

        startForegroundNotification()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 100
            y = 300
        }
        floatingParams = params
        clampToScreen(params)

        floatingView = LayoutInflater.from(this).inflate(R.layout.floating_ball, null)
        val ball = floatingView!!.findViewById<ImageView>(R.id.floating_ball_image)
        applyCustomIconOrDefault()
        ball.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    downTime = System.currentTimeMillis()
                    hasMoved = false
                    longClickFired = false
                    ball.animate().scaleX(0.9f).scaleY(0.9f).setDuration(100).start()
                    mainHandler.postDelayed(longClickRunnable, LONG_CLICK_TIMEOUT_MS)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (kotlin.math.abs(dx) > CLICK_SLOP_PX || kotlin.math.abs(dy) > CLICK_SLOP_PX) {
                        hasMoved = true
                        mainHandler.removeCallbacks(longClickRunnable)
                    }
                    params.x = initialX + dx.toInt()
                    params.y = initialY + dy.toInt()
                    clampToScreen(params)
                    try {
                        windowManager?.updateViewLayout(floatingView, params)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    mainHandler.removeCallbacks(longClickRunnable)
                    ball.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (!longClickFired &&
                        kotlin.math.abs(dx) < CLICK_SLOP_PX &&
                        kotlin.math.abs(dy) < CLICK_SLOP_PX
                    ) {
                        onBallSingleClick()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    mainHandler.removeCallbacks(longClickRunnable)
                    ball.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    true
                }
                else -> false
            }
        }

        try {
            windowManager?.addView(floatingView, params)
            ensureAnimationOverlay()
        } catch (e: Exception) {
            e.printStackTrace()
            Toast.makeText(this, "悬浮球显示失败: ${e.message}", Toast.LENGTH_LONG).show()
            floatingView = null
            floatingParams = null
        }
    }

    private fun ensureAnimationOverlay() {
        if (animationOverlay != null) return
        val wm = windowManager ?: return
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }
        animationOverlay = TouchEffectOverlay(this).apply {
            post {
                try {
                    wm.addView(this, params)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    private fun hideAnimationOverlay() {
        val overlay = animationOverlay ?: return
        animationOverlay = null
        try {
            windowManager?.removeView(overlay)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * 根据 SharedPreferences 中保存的路径，为悬浮球应用自定义图标或默认图标。
     */
    private fun applyCustomIconOrDefault() {
        val customPath = prefs(this).getString(KEY_CUSTOM_ICON, null)
        if (customPath != null && File(customPath).exists()) {
            applyCustomIcon(customPath)
        } else {
            applyDefaultIcon()
        }
    }

    private fun applyCustomIcon(imagePath: String) {
        val ball = floatingView?.findViewById<ImageView>(R.id.floating_ball_image) ?: return
        try {
            val bitmap = BitmapFactory.decodeFile(imagePath)
            if (bitmap != null) {
                ball.setImageBitmap(bitmap)
            } else {
                applyDefaultIcon()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            applyDefaultIcon()
        }
    }

    private fun applyDefaultIcon() {
        val ball = floatingView?.findViewById<ImageView>(R.id.floating_ball_image) ?: return
        ball.setImageResource(R.drawable.floating_ball_bg)
    }

    internal fun postTouchEffect(effect: TouchEffect) {
        mainHandler.post {
            animationOverlay?.postEffect(effect)
        }
    }

    /** 把悬浮球坐标限制在屏幕范围内，避免被拖到看不见的地方 */
    private fun clampToScreen(params: WindowManager.LayoutParams) {
        val size = screenSize()
        val maxX = size.x - ballSizePx
        val maxY = size.y - ballSizePx
        if (params.x < 0) params.x = 0
        if (params.x > maxX) params.x = maxX
        if (params.y < 0) params.y = 0
        if (params.y > maxY) params.y = maxY
    }

    /**
     * 返回应用可用区域（不含系统状态栏/导航栏），用于 clamp 悬浮球位置。
     * 用 getDisplayMetrics 而非 getRealMetrics：后者包含物理屏幕全区域，
     * 会让悬浮球被拖到状态栏或导航栏下方被系统 UI 遮挡。
     */
    private fun screenSize(): Point {
        val out = Point()
        val wm = windowManager ?: return out
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getMetrics(metrics)
        out.x = metrics.widthPixels
        out.y = metrics.heightPixels
        return out
    }

    private fun hideFloatingBall() {
        if (floatingView != null) {
            try {
                windowManager?.removeView(floatingView)
            } catch (e: Exception) {
                e.printStackTrace()
            }
            floatingView = null
            floatingParams = null
        }
        hideBubble()
        hideAnimationOverlay()
    }

    private fun hideKeyboard() {
        keyboardView?.hide()
        keyboardView = null
    }

    private fun openMainActivity() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivity(intent)
    }

    /**
     * 悬浮球单击的统一处理：
     * - 宏运行中：累加三连击计数，达 3 次则停止
     * - 宏未运行：检查辅助功能与已启用宏，启动执行
     */
    private fun onBallSingleClick() {
        if (MacroExecutor.isRunning()) {
            MacroExecutor.notifyFloatingBallClick(this)
            return
        }
        runEnabledMacro()
    }

    private fun runEnabledMacro() {
        val state = InputAccessibilityService.readinessState(this)
        when (state) {
            1 -> {
                Toast.makeText(this, "请先开启辅助功能", Toast.LENGTH_SHORT).show()
                return
            }
            2 -> {
                Toast.makeText(this, "辅助服务启动中", Toast.LENGTH_SHORT).show()
                return
            }
        }
        val macro = loadEnabledMacro()
        if (macro == null || macro.steps.isEmpty()) {
            Toast.makeText(this, "未启用宏", Toast.LENGTH_SHORT).show()
            return
        }
        macroDebugMode = macro.settings["debugMode"] as? Boolean ?: false
        InputAccessibilityService.executeMacro(this, macro.settings, macro.steps)
    }

    override fun onMacroStatus(message: String) {
        mainHandler.post {
            val isCompletion = message == "任务完成" ||
                message == "任务已停止" ||
                message == "宏已停止" ||
                message.startsWith("任务异常")
            if (isCompletion) {
                macroDebugMode = false
            }
            // 调试模式显示每步默认提示；无限循环被三连击停止时也必须显示默认提示
            if (macroDebugMode || message == "宏已停止") {
                showBubble(message)
            }
        }
    }

    override fun onMacroPrint(message: String) {
        mainHandler.post {
            showBubble(message)
        }
    }

    /**
     * 在悬浮球附近显示气泡。自动选择左右方向，水平/垂直方向均做边界裁剪，
     * 确保 print 消息不会被截断或跑到屏幕外。
     */
    private fun showBubble(message: String) {
        if (windowManager == null || floatingView == null) return

        val density = resources.displayMetrics.density
        val gap = (BUBBLE_GAP_DP * density).toInt()
        val screen = screenSize()
        val ballParams = floatingParams ?: return

        // 悬浮球中心坐标（屏幕坐标系）
        val ballCenterX = ballParams.x + ballSizePx / 2
        val ballCenterY = ballParams.y + ballSizePx / 2

        // 先确保气泡存在，能拿到尺寸
        if (bubbleView == null) {
            val bgDrawable = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.RECTANGLE
                setColor(0xF2FFFFFF.toInt())
                cornerRadius = 12 * density
                setStroke(1, 0x33000000)
            }
            bubbleView = TextView(this).apply {
                background = bgDrawable
                setPadding((16 * density).toInt(), (10 * density).toInt(),
                           (16 * density).toInt(), (10 * density).toInt())
                setTextColor(android.graphics.Color.BLACK)
                textSize = 13f
                maxLines = 4
                ellipsize = android.text.TextUtils.TruncateAt.END
            }
            bubbleParams = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else
                    WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
            }
            try {
                windowManager?.addView(bubbleView, bubbleParams)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        bubbleView?.text = message
        bubbleView?.visibility = View.VISIBLE

        // 触发一次测量，最大宽度限制为屏幕宽度的 70%，避免过长消息撑满全屏
        val maxBubbleW = (screen.x * 0.7).toInt()
        bubbleView?.measure(
            View.MeasureSpec.makeMeasureSpec(maxBubbleW, View.MeasureSpec.AT_MOST),
            View.MeasureSpec.makeMeasureSpec(screen.y, View.MeasureSpec.AT_MOST)
        )
        val bubbleW = bubbleView?.measuredWidth ?: 0
        val bubbleH = bubbleView?.measuredHeight ?: 0

        // 默认放在悬浮球右侧；右侧空间不足则放左侧
        val putRight = ballCenterX + ballSizePx / 2 + gap + bubbleW <= screen.x
        var bubbleX = if (putRight) {
            ballParams.x + ballSizePx + gap
        } else {
            ballParams.x - gap - bubbleW
        }

        // 水平方向裁剪，确保不会超出屏幕
        if (bubbleX < 0) bubbleX = 0
        if (bubbleX + bubbleW > screen.x) bubbleX = screen.x - bubbleW

        // 垂直方向：相对悬浮球中心对齐，并做边界裁剪
        var bubbleY = ballCenterY - bubbleH / 2
        if (bubbleY < 0) bubbleY = 0
        if (bubbleY + bubbleH > screen.y) bubbleY = screen.y - bubbleH

        bubbleParams?.apply {
            x = bubbleX
            y = bubbleY
        }
        try {
            windowManager?.updateViewLayout(bubbleView, bubbleParams)
        } catch (e: Exception) {
            e.printStackTrace()
        }

        mainHandler.removeCallbacks(bubbleHideRunnable)
        mainHandler.postDelayed(bubbleHideRunnable, BUBBLE_AUTO_HIDE_MS)
    }

    private fun hideBubble() {
        mainHandler.removeCallbacks(bubbleHideRunnable)
        bubbleView?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        bubbleView = null
        bubbleParams = null
    }

    private fun loadEnabledMacro(): MacroFile? {
        val file = File(filesDir, ENABLED_MACRO_FILE)
        if (!file.exists()) return null
        return try {
            val json = file.readText()
            val obj = JSONObject(json)
            val settings = jsonObjectToMap(obj.getJSONObject("settings"))
            val stepsArray = obj.getJSONArray("steps")
            val steps = mutableListOf<Map<String, Any>>()
            for (i in 0 until stepsArray.length()) {
                steps.add(jsonObjectToMap(stepsArray.getJSONObject(i)))
            }
            MacroFile(settings, steps)
        } catch (e: Exception) {
            // Fallback to legacy list format
            try {
                val array = JSONArray(file.readText())
                val steps = mutableListOf<Map<String, Any>>()
                for (i in 0 until array.length()) {
                    steps.add(jsonObjectToMap(array.getJSONObject(i)))
                }
                MacroFile(emptyMap(), steps)
            } catch (e2: Exception) {
                null
            }
        }
    }

    private data class MacroFile(
        val settings: Map<String, Any>,
        val steps: List<Map<String, Any>>
    )

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

    override fun onDestroy() {
        mainHandler.removeCallbacks(longClickRunnable)
        mainHandler.removeCallbacks(bubbleHideRunnable)
        // 服务销毁时若有宏在跑，强制停止，避免泄漏
        MacroExecutor.stopActive()
        hideFloatingBall()
        hideKeyboard()
        MacroExecutor.removeListener(this)
        instance = null
        super.onDestroy()
    }
}
