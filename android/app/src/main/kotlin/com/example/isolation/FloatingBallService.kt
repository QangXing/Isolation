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
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.TypedValue
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.DisplayMetrics
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.widget.ImageView
import androidx.core.app.ServiceCompat
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class FloatingBallService : Service(), MacroExecutorListener {
    companion object {
        private const val TAG = "FloatingBallService"
        const val ACTION_SHOW = "ACTION_SHOW"
        const val ACTION_HIDE = "ACTION_HIDE"
        const val ACTION_PREPARE = "ACTION_PREPARE"
        const val CHANNEL_ID = "isolation_floating_ball"
        const val NOTIFICATION_ID = 1
        const val ENABLED_MACRO_FILE = "enabled_macro.json"

        /** Android 14+ 前台服务类型：平时仅使用 specialUse，避免 mediaProjection 类型在没有活跃投影时触发 SecurityException */
        private val NORMAL_FGS_TYPES: Int
            get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            } else 0

        /** 屏幕录制时再把前台服务类型升级为 specialUse|mediaProjection */
        private val SCREEN_CAPTURE_FGS_TYPES: Int
            get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            } else 0

        private const val BALL_SIZE_DP = 56
        private const val BUBBLE_GAP_DP = 12
        private const val BUBBLE_AUTO_HIDE_MS = 2500L
        private const val CLICK_SLOP_PX = 12
        private const val LONG_CLICK_TIMEOUT_MS = 400L

        private const val PREF_NAME = "isolation_floating_ball"
        private const val KEY_CUSTOM_ICON = "custom_icon_path"

        private const val DEFAULT_FLOATER_CONFIG_KEY = "default_floater_config"
        private const val FLUTTER_SHARED_PREFS_NAME = "FlutterSharedPreferences"

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

        private fun flutterPrefs(context: Context): SharedPreferences {
            return context.getSharedPreferences(FLUTTER_SHARED_PREFS_NAME, Context.MODE_PRIVATE)
        }

        /** 应用完整的悬浮球配置（圆角、大小、图片）。 */
        fun applyFloaterConfig(cornerRadiusDp: Int, sizeDp: Int, imagePath: String?) {
            instance?.applyFloaterConfigInternal(cornerRadiusDp, sizeDp, imagePath)
        }

        /** 仅更新悬浮球圆角半径（dp）。 */
        fun applyCornerRadius(value: Int) {
            instance?.applyCornerRadiusInternal(value)
        }

        /** 仅更新悬浮球大小（dp）。 */
        fun applySize(value: Int) {
            instance?.applySizeInternal(value)
        }

        /** 仅更新悬浮球图片。 */
        fun applyImage(path: String?) {
            instance?.applyImageInternal(path)
        }

        /** 注册多球插件。 */
        fun registerFloaters(context: Context, program: Map<String, Any>, assetsDir: String?): Boolean {
            return instance?.registerFloatersInternal(context, program, assetsDir) ?: false
        }

        /** 获取指定名称插件球的位置。 */
        fun getFloaterPosition(name: String): Map<String, Int>? {
            return instance?.getPluginBallPosition(name)
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

    private var ballSizePx: Int = 0

    // ── 多球插件支持 ──
    private data class PluginBall(
        val name: String,
        var view: View,
        var params: WindowManager.LayoutParams,
        var sizeDp: Int,
        var cornerRadiusDp: Int,
        var imagePath: String?,
        var visible: Boolean
    )

    private val pluginBalls = mutableMapOf<String, PluginBall>()
    private val pluginFloaterRegistry = FloaterRegistry()
    private var pluginAssetsDir: String? = null
    private val pluginVariables = mutableMapOf<String, Variable>()

    private fun dpToPx(dp: Int): Int {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, dp.toFloat(), resources.displayMetrics).toInt()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        ballSizePx = dpToPx(BALL_SIZE_DP)
        createNotificationChannel()
        // Android 14 (API 34) + 要求 startForegroundService 后 10 秒内必须调用 startForeground，
        // 否则会抛出 ForegroundServiceDidNotStartInTimeException。
        // 把 startForeground 前置到 onCreate，保证在任何 onStartCommand 逻辑前完成。
        try {
            startForegroundNotification(NORMAL_FGS_TYPES)
        } catch (e: Exception) {
            Log.e(TAG, "onCreate 启动前台通知失败", e)
            // 即使启动通知失败也不立刻 stopSelf，防止 startForegroundService 抛异常后状态不一致；
            // 后续 onStartCommand 仍会再次尝试。
        }
        MacroExecutor.addListener(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 兜底：Android 12+ 部分厂商在 onCreate 之后仍要求通过 onStartCommand 再调用一次 startForeground，
        // 这里再次尝试，失败不影响业务逻辑
        try {
            startForegroundNotification(NORMAL_FGS_TYPES)
        } catch (e: Exception) {
            Log.e(TAG, "onStartCommand 前台通知再次调用失败，继续运行", e)
        }

        try {
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
                ACTION_PREPARE -> {
                    // 仅保持前台服务运行，用于在 Android 14+ 中承载屏幕录制，不显示悬浮球
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "处理悬浮球意图失败: ${intent?.action}", e)
        }
        return START_STICKY
    }

    /**
     * 在前台服务上下文中初始化屏幕录制。
     * Android 14+ 要求 VirtualDisplay 必须由带有 mediaProjection 前台服务类型的 Service 创建。
     */
    fun initScreenCapture(resultCode: Int, data: Intent?): Boolean {
        return try {
            // Android 14+ 需要在创建 VirtualDisplay 前，先把前台服务类型升级为 mediaProjection。
            // 为避免 SecurityException，在 ScreenCaptureHelper 已获得 MediaProjection 实例后再升级。
            val ok = ScreenCaptureHelper.onActivityResult(this, resultCode, data) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    startForegroundNotification(SCREEN_CAPTURE_FGS_TYPES)
                }
            }
            if (!ok && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // 屏幕录制未成功，降级回普通 specialUse 类型
                startForegroundNotification(NORMAL_FGS_TYPES)
            }
            ok
        } catch (e: Exception) {
            android.util.Log.e("FloatingBallService", "初始化屏幕录制失败", e)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                try { startForegroundNotification(NORMAL_FGS_TYPES) } catch (_: Exception) {}
            }
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

    private fun startForegroundNotification(serviceTypes: Int = NORMAL_FGS_TYPES) {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // Android 13 (API 33) POST_NOTIFICATIONS 运行时权限：未授权时 NotificationManager 可能拒绝显示通知，
        // 但 startForeground 本身仍必须调用（否则 Android 14 会抛 FGS 未启动异常）。
        // 通过 NotificationCompat 设置 foregroundServiceBehavior 为 IMMEDIATE，
        // 并使用 FOREGROUND_SERVICE_IMMEDIATE 避免 Android 12+ 延迟显示。
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("isolation")
            .setContentText("悬浮球宏正在运行")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            // Android 12+ (API 31) 前台服务延迟启动豁免，确保调用 startForeground 后立即生效
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // Android 14+：严格检查前台服务类型必须与 Manifest 中声明的子集一致
                ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, serviceTypes)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // 部分厂商 ROM（如华为、小米、OPPO）在无通知权限时会抛 SecurityException 或其他 RuntimeException，
            // 这里兜底降级：若 ServiceCompat 失败，重试使用基础 startForeground（不带类型）
            Log.w(TAG, "startForeground 首次调用失败(${e.javaClass.simpleName}: ${e.message})，尝试降级启动", e)
            try {
                startForeground(NOTIFICATION_ID, notification)
            } catch (e2: Exception) {
                Log.e(TAG, "startForeground 降级启动也失败，服务将继续运行但可能被系统杀死", e2)
            }
        }
    }

    private fun stopForegroundService() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: Exception) {
            Log.w(TAG, "stopForeground 调用失败，忽略", e)
        }
    }

    private fun showFloatingBall() {
        if (floatingView != null) return
        if (!Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "请先授予悬浮窗权限", Toast.LENGTH_SHORT).show()
            return
        }

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

        // 读取并应用默认悬浮球配置（兜底：出错时仍使用旧逻辑，避免闪退）
        try {
            val config = loadDefaultFloaterConfig()
            applyFloaterConfigInternal(
                config.cornerRadius,
                config.size,
                config.imagePath ?: getCustomIcon(this)
            )
        } catch (e: Exception) {
            Log.e(TAG, "应用默认悬浮球配置失败", e)
            applyCustomIconOrDefault()
        }

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
        // 清除 src，让外层 FrameLayout 的背景按当前圆角显示为默认悬浮球
        ball.setImageDrawable(null)
    }

    private fun applyFloaterConfigInternal(cornerRadiusDp: Int, sizeDp: Int, imagePath: String?) {
        applySizeInternal(sizeDp)
        applyCornerRadiusInternal(cornerRadiusDp)
        applyImageInternal(imagePath)
    }

    private fun applySizeInternal(sizeDp: Int) {
        val sizePx = dpToPx(sizeDp)
        ballSizePx = sizePx
        val params = floatingParams ?: return
        params.width = sizePx
        params.height = sizePx
        if (floatingView?.parent != null) {
            try {
                windowManager?.updateViewLayout(floatingView, params)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun applyCornerRadiusInternal(cornerRadiusDp: Int) {
        val view = floatingView ?: return
        val background = view.background as? GradientDrawable ?: return
        background.setCornerRadius(
            TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, cornerRadiusDp.toFloat(), resources.displayMetrics
            )
        )
        view.invalidate()
    }

    private fun applyImageInternal(imagePath: String?) {
        val ball = floatingView?.findViewById<ImageView>(R.id.floating_ball_image) ?: return
        Log.d(TAG, "应用默认悬浮球图片: $imagePath")
        if (imagePath != null && File(imagePath).exists()) {
            try {
                val bitmap = BitmapFactory.decodeFile(imagePath)
                if (bitmap != null) {
                    ball.setImageBitmap(bitmap)
                    Log.d(TAG, "默认悬浮球图片加载成功")
                } else {
                    Log.w(TAG, "默认悬浮球图片解码失败: $imagePath")
                    ball.setImageDrawable(null)
                }
            } catch (e: Exception) {
                Log.w(TAG, "默认悬浮球图片加载异常: $imagePath", e)
                ball.setImageDrawable(null)
            }
        } else {
            Log.d(TAG, "默认悬浮球图片路径为空或不存在: $imagePath")
            ball.setImageDrawable(null)
        }
    }

    private fun loadDefaultFloaterConfig(): FloaterConfig {
        val raw = flutterPrefs(this).getString(DEFAULT_FLOATER_CONFIG_KEY, null) ?: return FloaterConfig()
        return try {
            val json = JSONObject(raw)
            FloaterConfig(
                cornerRadius = json.optInt("cornerRadius", 28),
                size = json.optInt("size", 56),
                imagePath = if (json.has("imagePath")) json.getString("imagePath") else null
            )
        } catch (e: Exception) {
            FloaterConfig()
        }
    }

    private data class FloaterConfig(
        val cornerRadius: Int = 28,
        val size: Int = 56,
        val imagePath: String? = null
    )

    // ── 多球插件内部实现 ──

    private fun registerFloatersInternal(context: Context, program: Map<String, Any>, assetsDir: String?): Boolean {
        try {
            pluginAssetsDir = assetsDir
            pluginFloaterRegistry.clear()
            pluginVariables.clear()

            // 每次启用球插件时刷新默认悬浮球状态，确保后续回退参数使用最新值
            val config = loadDefaultFloaterConfig()
            applyFloaterConfigInternal(config.cornerRadius, config.size, config.imagePath)

            // 注册 found 函数，用于表达式中获取球坐标
            val foundHandler: (String, List<Map<String, Any>>, Map<String, Variable>) -> Variable? = { name, args, variables ->
                if (name != "found") null
                else {
                    val ballName = extractStringFromArg(args.getOrNull(0), variables)
                    val axis = extractStringFromArg(args.getOrNull(1), variables) ?: "x"
                    val pos = ballName?.let { getPluginBallPosition(it) }
                    if (pos == null) null
                    else {
                        val value = if (axis == "y") pos["y"] ?: 0 else pos["x"] ?: 0
                        Variable.Number(value.toDouble())
                    }
                }
            }
            ExpressionEvaluator.callHandler = foundHandler

            @Suppress("UNCHECKED_CAST")
            val balls = program["balls"] as? List<Map<String, Any>> ?: emptyList()
            @Suppress("UNCHECKED_CAST")
            val steps = program["steps"] as? List<Map<String, Any>> ?: emptyList()

            // 注册每个球内的事件处理器（支持 floater 旧写法以及 singleClick/doubleClick/tripleClick/longPress）
            for (ball in balls) {
                val name = ball["name"] as? String ?: continue
                @Suppress("UNCHECKED_CAST")
                val ballSteps = ball["steps"] as? List<Map<String, Any>> ?: emptyList()
                for (step in ballSteps) {
                    val type = step["type"] as? String ?: continue
                    val event = when (type) {
                        "floater" -> step["event"] as? String
                        "singleClick", "doubleClick", "tripleClick", "longPress" -> type
                        else -> null
                    } ?: continue
                    @Suppress("UNCHECKED_CAST")
                    val children = step["children"] as? List<Map<String, Any>>
                    @Suppress("UNCHECKED_CAST")
                    val elseChildren = step["else"] as? List<Map<String, Any>>
                    val actionChildren = eventStepsForAction(step["action"] as? String)
                    pluginFloaterRegistry.register(event, children ?: actionChildren ?: emptyList(), elseChildren)
                }
            }

            // 创建或更新每个球
            for (ball in balls) {
                createOrUpdatePluginBall(context, ball)
            }

            // 执行全局流程步骤
            executeFloaterSteps(steps)

            return true
        } catch (e: Exception) {
            Log.e(TAG, "注册多球插件失败", e)
            return false
        }
    }

    private fun getPluginBallPosition(name: String): Map<String, Int>? {
        val ball = pluginBalls[name] ?: return null
        return mapOf("x" to ball.params.x, "y" to ball.params.y)
    }

    private fun eventStepsForAction(action: String?): List<Map<String, Any>>? {
        return when (action) {
            "Launch_macro" -> listOf(mapOf("type" to "launch_macro"))
            "Turn_off_macros" -> listOf(mapOf("type" to "turn_off_macros"))
            else -> null
        }
    }

    private fun createOrUpdatePluginBall(context: Context, ball: Map<String, Any>) {
        val name = ball["name"] as? String ?: return
        val role = ball["role"] as? String ?: "deputy"
        val defaultConfig = loadDefaultFloaterConfig()
        val sizeDp = (ball["size"] as? Number)?.toInt() ?: defaultConfig.size
        val cornerRadiusDp = (ball["cornerRadius"] as? Number)?.toInt() ?: defaultConfig.cornerRadius
        val imageName = ball["image"] as? String
        val imagePath = imageName?.let { resolveAssetPath(it) } ?: defaultConfig.imagePath
        val visible = ball["visible"] as? Boolean ?: (role == "main")

        val defaultLocationX = floatingParams?.x ?: 100
        val defaultLocationY = floatingParams?.y ?: 300
        val locationX = resolveIntValue(ball["locationX"], if (role == "main") defaultLocationX else 0)
        val locationY = resolveIntValue(ball["locationY"], if (role == "main") defaultLocationY else 0)

        val wm = windowManager ?: (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).also {
            windowManager = it
        }

        val existing = pluginBalls[name]
        if (existing != null) {
            existing.sizeDp = sizeDp
            existing.cornerRadiusDp = cornerRadiusDp
            existing.imagePath = imagePath
            existing.visible = visible
            applyPluginBallConfig(existing)
            updatePluginBallPosition(name, locationX, locationY)
            setPluginBallVisible(name, visible)
            return
        }

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
            x = locationX
            y = locationY
        }

        val view = LayoutInflater.from(context).inflate(R.layout.floating_ball, null)
        val pluginBall = PluginBall(name, view, params, sizeDp, cornerRadiusDp, imagePath, visible)
        applyPluginBallConfig(pluginBall)
        setupPluginBallTouch(pluginBall)

        try {
            wm.addView(view, params)
            pluginBalls[name] = pluginBall
            if (!visible) {
                view.visibility = View.GONE
            }
        } catch (e: Exception) {
            Log.e(TAG, "创建插件球失败: $name", e)
        }
    }

    private fun applyPluginBallConfig(ball: PluginBall) {
        val sizePx = dpToPx(ball.sizeDp)
        ball.params.width = sizePx
        ball.params.height = sizePx

        val view = ball.view
        val background = view.background as? GradientDrawable
        background?.setCornerRadius(
            TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, ball.cornerRadiusDp.toFloat(), resources.displayMetrics
            )
        )
        view.invalidate()

        val imageView = view.findViewById<ImageView>(R.id.floating_ball_image)
        val path = ball.imagePath
        Log.d(TAG, "应用球配置: ${ball.name}, imagePath=$path")
        if (path != null && File(path).exists()) {
            try {
                val bitmap = BitmapFactory.decodeFile(path)
                if (bitmap != null) {
                    imageView.setImageBitmap(bitmap)
                    Log.d(TAG, "球图片加载成功: ${ball.name}")
                } else {
                    Log.w(TAG, "球图片解码失败: $path")
                    imageView.setImageDrawable(null)
                }
            } catch (e: Exception) {
                Log.w(TAG, "球图片加载异常: $path", e)
                imageView.setImageDrawable(null)
            }
        } else {
            Log.d(TAG, "球图片路径为空或不存在: $path")
            imageView.setImageDrawable(null)
        }

        if (view.parent != null) {
            try {
                windowManager?.updateViewLayout(view, ball.params)
            } catch (e: Exception) {
                Log.w(TAG, "更新插件球布局失败: ${ball.name}", e)
            }
        }
    }

    private fun setupPluginBallTouch(ball: PluginBall) {
        val view = ball.view
        val handler = Handler(Looper.getMainLooper())
        val touchState = object {
            var initialX = 0
            var initialY = 0
            var initialTouchX = 0f
            var initialTouchY = 0f
            var hasMoved = false
            var longPressed = false
            var clickCount = 0
            var lastClickTime = 0L
            var pendingClickRunnable: Runnable? = null
        }
        val multiClickThresholdMs = 300L

        fun resetClicks() {
            touchState.clickCount = 0
            touchState.pendingClickRunnable?.let { handler.removeCallbacks(it) }
            touchState.pendingClickRunnable = null
        }

        fun dispatchClickEvent(clicks: Int) {
            val event = when (clicks) {
                1 -> "singleClick"
                2 -> "doubleClick"
                3 -> "tripleClick"
                else -> null
            }
            if (event != null) dispatchPluginBallEvent(ball.name, event)
        }

        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    touchState.initialX = ball.params.x
                    touchState.initialY = ball.params.y
                    touchState.initialTouchX = event.rawX
                    touchState.initialTouchY = event.rawY
                    touchState.hasMoved = false
                    touchState.longPressed = false
                    view.animate().scaleX(0.9f).scaleY(0.9f).setDuration(100).start()

                    handler.postDelayed({
                        if (!touchState.hasMoved && !touchState.longPressed) {
                            touchState.longPressed = true
                            resetClicks()
                            view.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
                            dispatchPluginBallEvent(ball.name, "longPress")
                        }
                    }, LONG_CLICK_TIMEOUT_MS)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - touchState.initialTouchX
                    val dy = event.rawY - touchState.initialTouchY
                    if (kotlin.math.abs(dx) > CLICK_SLOP_PX || kotlin.math.abs(dy) > CLICK_SLOP_PX) {
                        touchState.hasMoved = true
                    }
                    ball.params.x = touchState.initialX + dx.toInt()
                    ball.params.y = touchState.initialY + dy.toInt()
                    clampPluginBallToScreen(ball)
                    try {
                        windowManager?.updateViewLayout(view, ball.params)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    view.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    handler.removeCallbacksAndMessages(null)
                    if (touchState.longPressed || touchState.hasMoved) {
                        resetClicks()
                        return@setOnTouchListener true
                    }

                    val now = SystemClock.elapsedRealtime()
                    if (now - touchState.lastClickTime > multiClickThresholdMs) {
                        touchState.clickCount = 0
                    }
                    touchState.clickCount++
                    touchState.lastClickTime = now

                    if (touchState.clickCount >= 3) {
                        resetClicks()
                        dispatchClickEvent(3)
                    } else {
                        val runnable = Runnable {
                            val count = touchState.clickCount
                            resetClicks()
                            dispatchClickEvent(count)
                        }
                        touchState.pendingClickRunnable = runnable
                        handler.postDelayed(runnable, multiClickThresholdMs)
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    view.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    handler.removeCallbacksAndMessages(null)
                    resetClicks()
                    true
                }
                else -> false
            }
        }
    }

    private fun dispatchPluginBallEvent(name: String, event: String) {
        val handlers = pluginFloaterRegistry.get(event)
        if (handlers.isEmpty()) return
        for (handler in handlers) {
            // 在后台线程执行事件步骤，避免阻塞主线程
            Thread {
                executeFloaterSteps(handler.children)
            }.start()
        }
    }

    private fun updatePluginBallPosition(name: String, x: Int, y: Int) {
        val ball = pluginBalls[name] ?: return
        ball.params.x = x
        ball.params.y = y
        clampPluginBallToScreen(ball)
        try {
            windowManager?.updateViewLayout(ball.view, ball.params)
        } catch (e: Exception) {
            Log.w(TAG, "移动插件球失败: $name", e)
        }
    }

    private fun setPluginBallVisible(name: String, visible: Boolean) {
        val ball = pluginBalls[name] ?: return
        ball.visible = visible
        ball.view.visibility = if (visible) View.VISIBLE else View.GONE
    }

    private fun clampPluginBallToScreen(ball: PluginBall) {
        val size = screenSize()
        val sizePx = ball.params.width
        val maxX = size.x - sizePx
        val maxY = size.y - sizePx
        if (ball.params.x < 0) ball.params.x = 0
        if (ball.params.x > maxX) ball.params.x = maxX
        if (ball.params.y < 0) ball.params.y = 0
        if (ball.params.y > maxY) ball.params.y = maxY
    }

    private fun resolveIntValue(value: Any?, defaultValue: Int): Int {
        return when (value) {
            is Int -> value
            is Number -> value.toInt()
            is Map<*, *> -> {
                @Suppress("UNCHECKED_CAST")
                val expr = value as Map<String, Any>
                val result = ExpressionEvaluator.evaluate(expr, pluginVariables)
                (result as? Variable.Number)?.value?.toInt() ?: defaultValue
            }
            else -> defaultValue
        }
    }

    private fun extractStringFromArg(arg: Any?, variables: Map<String, Variable>): String? {
        return when (arg) {
            is String -> arg
            is Map<*, *> -> {
                @Suppress("UNCHECKED_CAST")
                val map = arg as Map<String, Any>
                when (map["op"]) {
                    "literal" -> map["value"] as? String
                    "var" -> {
                        val varName = map["name"] as? String ?: return null
                        when (val v = variables[varName]) {
                            is Variable.Number -> v.value.toString()
                            else -> null
                        }
                    }
                    else -> null
                }
            }
            else -> null
        }
    }

    private fun resolveAssetPath(fileName: String): String? {
        val dir = pluginAssetsDir ?: run {
            Log.w(TAG, "插件资源目录未设置，无法解析: $fileName")
            return null
        }
        val dirFile = File(dir)
        val file = File(dir, fileName)
        Log.d(TAG, "解析资源路径: ${file.absolutePath}, 存在=${file.exists()}")
        if (file.exists()) return file.absolutePath

        // 若精确匹配失败，尝试不区分大小写匹配，兼容 asset.jpg / ASSET.JPG
        val lower = fileName.lowercase()
        val candidates = dirFile.listFiles()?.filter { it.name.lowercase() == lower }
        if (!candidates.isNullOrEmpty()) {
            Log.d(TAG, "不区分大小写匹配资源: ${candidates[0].absolutePath}")
            return candidates[0].absolutePath
        }
        return null
    }

    private fun executeFloaterSteps(steps: List<Map<String, Any>>) {
        for (step in steps) {
            executeFloaterStep(step)
        }
    }

    private fun executeFloaterStep(step: Map<String, Any>) {
        when (step["type"]) {
            "assign", "let", "var" -> {
                val name = step["name"] as? String ?: return
                @Suppress("UNCHECKED_CAST")
                val valueExpr = step["value"] as? Map<String, Any>
                val value = valueExpr?.let { ExpressionEvaluator.evaluate(it, pluginVariables) }
                if (value != null) pluginVariables[name] = value
            }
            "found" -> {
                val assignTo = step["assignTo"] as? String ?: return
                val name = step["name"] as? String ?: return
                val axis = step["axis"] as? String ?: return
                val pos = getPluginBallPosition(name) ?: return
                val value = if (axis == "y") pos["y"] ?: 0 else pos["x"] ?: 0
                pluginVariables[assignTo] = Variable.Number(value.toDouble())
            }
            "location" -> {
                val name = step["name"] as? String ?: return
                val x = resolveIntValue(step["x"], 0)
                val y = resolveIntValue(step["y"], 0)
                updatePluginBallPosition(name, x, y)
            }
            "status" -> {
                val name = step["name"] as? String ?: return
                val state = step["state"] as? String ?: return
                setPluginBallVisible(name, state == "show")
            }
            "print" -> {
                val message = step["message"] as? String ?: return
                showBubble(message)
            }
            "launch" -> {
                val packageName = step["packageName"] as? String ?: return
                val intent = packageManager.getLaunchIntentForPackage(packageName)
                if (intent != null) {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    startActivity(intent)
                } else {
                    showBubble("launch: 无法启动 $packageName")
                }
            }
            "launch_macro" -> runEnabledMacro()
            "turn_off_macros" -> MacroExecutor.stopActive()
            "for" -> executeFloaterFor(step)
            "if" -> executeFloaterIf(step)
            else -> Log.w(TAG, "未支持的球步骤类型: ${step["type"]}")
        }
    }

    private fun executeFloaterFor(step: Map<String, Any>) {
        @Suppress("UNCHECKED_CAST")
        val condition = step["condition"] as? Map<String, Any>
        if (condition != null) {
            @Suppress("UNCHECKED_CAST")
            val init = step["init"] as? Map<String, Any>
            @Suppress("UNCHECKED_CAST")
            val update = step["update"] as? Map<String, Any>
            @Suppress("UNCHECKED_CAST")
            val children = (step["children"] as? List<Map<String, Any>>) ?: return
            init?.let { executeFloaterStep(it) }
            while (ExpressionEvaluator.toBoolean(ExpressionEvaluator.evaluate(condition, pluginVariables))) {
                executeFloaterSteps(children)
                update?.let { executeFloaterStep(it) }
            }
            return
        }
        val count = (step["count"] as? Number)?.toInt() ?: 1
        @Suppress("UNCHECKED_CAST")
        val children = (step["children"] as? List<Map<String, Any>>) ?: return
        for (i in 1..count) {
            executeFloaterSteps(children)
        }
    }

    private fun executeFloaterIf(step: Map<String, Any>) {
        @Suppress("UNCHECKED_CAST")
        val condition = step["condition"] as? Map<String, Any>
        @Suppress("UNCHECKED_CAST")
        val expression = step["expression"] as? Map<String, Any>
        val condExpr = condition ?: expression ?: return
        val result = ExpressionEvaluator.evaluate(condExpr, pluginVariables)
        val bool = ExpressionEvaluator.toBoolean(result)
        @Suppress("UNCHECKED_CAST")
        val thenChildren = (step["then"] as? List<Map<String, Any>>)
        @Suppress("UNCHECKED_CAST")
        val elseChildren = (step["else"] as? List<Map<String, Any>>)
        if (bool) {
            thenChildren?.let { executeFloaterSteps(it) }
        } else {
            elseChildren?.let { executeFloaterSteps(it) }
        }
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
