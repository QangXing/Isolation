package com.qangxing.isolation

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Point
import android.graphics.Rect
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
import android.animation.ValueAnimator
import android.content.ComponentCallbacks
import android.content.res.Configuration
import android.view.Choreographer
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.AccelerateInterpolator
import android.view.animation.BounceInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.view.animation.OvershootInterpolator
import kotlin.math.sin
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.core.app.ServiceCompat
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import com.bumptech.glide.Glide
import com.bumptech.glide.load.resource.gif.GifDrawable
import com.bumptech.glide.request.target.CustomTarget
import com.bumptech.glide.request.transition.Transition
import android.graphics.drawable.Drawable
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

        /** 录制悬浮球副球尺寸（dp），比旧版更大，方便点按 */
        private const val REC_SUB_BALL_SIZE_DP = 52
        /** 径向展开时主球中心到副球中心的距离（dp） */
        private const val REC_RADIAL_RADIUS_DP = 96
        /** 径向展开的动画时长（ms） */
        private const val REC_EXPAND_ANIM_MS = 260L
        /** 副球依次弹出的错落间隔（ms） */
        private const val REC_STAGGER_MS = 40L

        private const val PREF_NAME = "isolation_floating_ball"
        private const val KEY_CUSTOM_ICON = "custom_icon_path"

        private const val DEFAULT_FLOATER_CONFIG_KEY = "default_floater_config"
        private const val FLUTTER_SHARED_PREFS_NAME = "FlutterSharedPreferences"

        @Volatile
        private var instance: FloatingBallService? = null

        /** 获取当前运行的服务实例，用于在前台服务上下文中初始化屏幕录制。 */
        fun getInstance(): FloatingBallService? = instance

        /**
         * 返回当前录制悬浮球的屏幕排除区域（主球 + 已展开的副球）。
         * Shizuku 高级录制模式读取系统输入事件时，需要过滤掉落在录制球上的触摸，
         * 避免把暂停/结束等操作误录为宏步骤。
         */
        fun getRecordingBallExclusionRects(): List<Rect> {
            val svc = instance ?: return emptyList()
            val out = mutableListOf<Rect>()
            svc.recordingMainBall.params?.let { p ->
                out.add(Rect(p.x, p.y, p.x + p.width, p.y + p.height))
            }
            if (svc.recordingSubBallsVisible) {
                svc.recordingSubViews.forEach { ball ->
                    ball.params?.let { p ->
                        out.add(Rect(p.x, p.y, p.x + p.width, p.y + p.height))
                    }
                }
            }
            return out
        }

        /**
         * 当前是否存在可显示气泡的悬浮球 overlay。
         * 供辅助服务判断 print 是否需要 Toast 兜底（进程被杀后服务重建期间无球可挂载）。
         */
        fun hasVisibleBall(): Boolean {
            val svc = instance ?: return false
            if (svc.windowManager == null) return false
            if (svc.floatingView != null) return true
            return svc.pluginBalls.values.any { it.visible }
        }

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

        /** 清除所有插件球（用于禁用编程球时）。 */
        fun unregisterFloaters() {
            instance?.clearAllPluginBalls()
        }

        /** 获取指定名称插件球的位置。 */
        fun getFloaterPosition(name: String): Map<String, Int>? {
            return instance?.getPluginBallPosition(name)
        }

        // ── 录制悬浮球（主球 + 副球） ──

        /**
         * 确保悬浮球服务在运行，用于承载录制球。
         * 从录制参数页发起录制时，服务可能尚未启动。
         */
        fun ensureServiceRunning(ctx: Context) {
            if (instance != null) return
            try {
                val intent = Intent(ctx, FloatingBallService::class.java).setAction(ACTION_SHOW)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ctx.startForegroundService(intent)
                } else {
                    ctx.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "拉起悬浮球服务失败", e)
            }
        }

        /** 录制开始前收起默认悬浮球，返回是否原本可见（结束录制后按需恢复）。 */
        fun hideDefaultBallForRecording(): Boolean {
            return instance?.hideDefaultBallForRecordingInternal() ?: false
        }

        /** 挂载录制悬浮球（主球 + 暂停/继续 + 结束）。服务未运行时暂存，待服务创建后挂载。 */
        fun ensureRecordingBalls(ctx: Context) {
            val svc = instance
            if (svc != null) {
                svc.ensureRecordingBallsInternal(ctx)
            } else {
                pendingRecordingBallContext = ctx.applicationContext
            }
        }

        /** 录制状态变化（暂停/继续）时同步副球图标。 */
        fun updateRecordingBallState() {
            instance?.updateRecordingBallStateInternal()
        }

        /** 结束/取消录制：移除录制球，并按需恢复默认悬浮球。 */
        fun endRecordingMode(restoreDefaultBall: Boolean) {
            instance?.endRecordingModeInternal(restoreDefaultBall)
        }

        /** 服务尚未创建时暂存的录制球挂载上下文。 */
        @Volatile
        private var pendingRecordingBallContext: Context? = null
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

    // ── 录制悬浮球（主球 + 径向展开的功能副球） ──
    private data class RecordingBall(
        var view: View?,
        var params: WindowManager.LayoutParams?,
        var icon: ImageView?
    )

    /** 径向展开项：id / 图标 / 背景色 / 点击行为 */
    private data class RecordingAction(
        val id: String,
        val icon: Bitmap,
        val bgColor: Int,
        val onClick: () -> Unit
    )

    private var recordingMainBall = RecordingBall(null, null, null)
    /** 展开的功能副球视图与参数，与 [recordingActions] 一一对应 */
    private val recordingSubViews = mutableListOf<RecordingBall>()
    private var recordingActions = listOf<RecordingAction>()
    private var recordingSubBallsVisible = false
    private var recordingPauseIcon: ImageView? = null
    private var defaultBallVisibleBeforeRecording = false

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
        if (pluginModeActive) return@Runnable
        if (!hasMoved && !longClickFired) {
            longClickFired = true
            openMainActivity()
        }
    }

    private var ballSizePx: Int = 0

    // ── 多球插件支持 ──
    internal data class PluginBall(
        val name: String,
        var view: View,
        var params: WindowManager.LayoutParams,
        var sizeDp: Int,
        var cornerRadiusDp: Int,
        var imagePath: String?,
        var visible: Boolean,
        var followTarget: String? = null,
        var followDx: Int = 0,
        var followDy: Int = 0,
        var draggable: Boolean = false,
        var opacity: Float = 1f,
        var eventHandlers: MutableMap<String, () -> Unit> = mutableMapOf()
    ) {
        /** 是否为主球 */
        val isMain: Boolean
            get() = name == "main"
    }

    /** 气泡定位锚点：优先使用主球，其次默认悬浮球。 */
    private data class BallAnchor(
        val params: WindowManager.LayoutParams,
        val sizePx: Int
    )

    internal val pluginBalls = mutableMapOf<String, PluginBall>()
    private var floaterV2Engine: com.qangxing.isolation.floater.FloaterV2Engine? = null

    private fun bubbleAnchor(): BallAnchor? {
        // 优先使用可见的主球
        val main = pluginBalls.values.firstOrNull { it.isMain && it.visible }
            ?: pluginBalls.values.firstOrNull { it.visible }
        if (main != null) {
            return BallAnchor(main.params, dpToPx(main.sizeDp))
        }
        // 回退到默认悬浮球
        floatingParams?.let {
            return BallAnchor(it, ballSizePx)
        }
        return null
    }
    private val pluginFloaterRegistry = FloaterRegistry()
    private var pluginAssetsDir: String? = null
    private val pluginVariables = mutableMapOf<String, Variable>()

    /** 编程球启用后，禁用默认悬浮球的那一套点击事件，避免与球文件内置事件冲突。 */
    private var pluginModeActive = false

    /** 批量收集插件球位置变更，在下一帧 vsync 统一提交，避免多次 updateViewLayout 与屏幕刷新错位。 */
    private val pendingBallUpdates = mutableMapOf<String, PluginBall>()
    private val ballUpdateFrameCallback = Choreographer.FrameCallback { applyPendingPluginBallUpdates() }

    /** 屏幕方向/尺寸变化监听，用于实时重新 clamp 编程球位置。 */
    private val pluginConfigCallback = object : ComponentCallbacks {
        override fun onConfigurationChanged(newConfig: Configuration) {
            applyConfigurationChangeToPluginBalls()
        }
        override fun onLowMemory() {}
    }

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
        MacroStatusNotifier.refreshState(this)
        registerComponentCallbacks(pluginConfigCallback)
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
            // 服务创建后补挂载录制球（录制参数页先于服务启动发起录制时）
            mountPendingRecordingBalls()
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

    /**
     * 用缓存的系统授权静默恢复屏幕录制（不弹系统授权框）。
     * 供宏执行前调用；恢复失败（授权被撤销/系统不支持复用）返回 false，由调用方走正常授权流程。
     */
    fun tryRestoreScreenCapture(): Boolean {
        return try {
            val ok = ScreenCaptureHelper.tryRestore(this) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    startForegroundNotification(SCREEN_CAPTURE_FGS_TYPES)
                }
            }
            if (!ok && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForegroundNotification(NORMAL_FGS_TYPES)
            }
            ok
        } catch (e: Exception) {
            android.util.Log.e(TAG, "静默恢复屏幕录制失败", e)
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
            .setSmallIcon(R.drawable.ic_notification)
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
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
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
        loadImageInto(ball, imagePath)
    }

    private fun applyDefaultIcon() {
        val ball = floatingView?.findViewById<ImageView>(R.id.floating_ball_image) ?: return
        // 清除 src，让外层 FrameLayout 的背景按当前圆角显示为默认悬浮球
        ball.setImageDrawable(null)
        restoreDefaultFloaterBackground(floatingView)
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
        loadImageInto(ball, imagePath)
    }

    /** 使用 Glide 加载图片/GIF，失败后清空 ImageView。加载自定义图片时移除白色底，透明区域直接透出。 */
    private fun loadImageInto(imageView: ImageView, path: String?) {
        // 容器即 inflate 的 floating_ball 根布局（FrameLayout），其背景决定透明区域显示效果
        loadImageInto(imageView, path, imageView.parent as? View ?: floatingView)
    }

    /** 指定容器的图片加载，插件球在 addView 前 parent 为空时使用显式传入的根布局。 */
    private fun loadImageInto(imageView: ImageView, path: String?, container: View?) {
        // 替换图片前停掉旧 GIF，避免多个 GifDrawable 同时跑帧
        stopGif(imageView)
        if (path != null && File(path).exists()) {
            try {
                // 动画 Drawable（GIF/WebP）与 clipToOutline 兼容性差，加载自定义图时先关闭裁剪
                container?.clipToOutline = false
                clearFloaterBackground(container)
                // 悬浮球是长期存在的悬浮窗，使用 applicationContext 加载，
                // 避免请求被绑到易销毁的 Context 上
                val glide = Glide.with(imageView.context.applicationContext)
                // 对 GIF 显式按 GIF 加载，避免 Glide 尝试转成 Bitmap 导致透明/动画异常
                if (path.lowercase().endsWith(".gif")) {
                    // 不用 into(ImageView)：ViewTarget 会让动画随 View/生命周期暂停，
                    // 导致切到其他 App 后悬浮球 GIF 静止。改为拿到 GifDrawable 后自行 start，
                    // 动画帧循环由 GifDrawable 自己驱动，不受前后台切换影响。
                    glide.asGif().load(File(path)).into(object : CustomTarget<GifDrawable>() {
                        override fun onResourceReady(resource: GifDrawable, transition: Transition<in GifDrawable>?) {
                            resource.setLoopCount(GifDrawable.LOOP_FOREVER)
                            imageView.setImageDrawable(resource)
                            resource.start()
                        }

                        override fun onLoadCleared(placeholder: Drawable?) {
                            imageView.setImageDrawable(placeholder)
                        }
                    })
                } else {
                    glide.load(File(path)).into(imageView)
                }
            } catch (e: Throwable) {
                Log.w(TAG, "Glide 加载图片失败: $path", e)
                imageView.setImageDrawable(null)
                restoreDefaultFloaterBackground(container)
            }
        } else {
            imageView.setImageDrawable(null)
            restoreDefaultFloaterBackground(container)
        }
    }

    /** 停止 ImageView 上正在播放的 GIF（若有），释放其帧回调。 */
    private fun stopGif(imageView: ImageView) {
        (imageView.drawable as? GifDrawable)?.stop()
    }

    /** 设置悬浮球容器背景为透明，避免 PNG 的透明部分被白色底填充。 */
    private fun clearFloaterBackground(container: View?) {
        val background = container?.background as? GradientDrawable ?: return
        background.setColor(android.graphics.Color.TRANSPARENT)
        background.setStroke(0, android.graphics.Color.TRANSPARENT)
        container.invalidate()
    }

    /** 恢复默认悬浮球的白色圆角底（无自定义图片时使用）。 */
    private fun restoreDefaultFloaterBackground(container: View?) {
        container?.clipToOutline = true
        val background = container?.background as? GradientDrawable ?: return
        background.setColor(0xE6FFFFFF.toInt())
        background.setStroke(dpToPx(1), 0xB3FFFFFF.toInt())
        container.invalidate()
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
            // 先清除旧插件球，保证同时只有一个编程球在运行
            clearAllPluginBalls()

            pluginAssetsDir = assetsDir
            pluginFloaterRegistry.clear()
            pluginVariables.clear()
            pluginModeActive = true

            // 启用编程球前先隐藏默认悬浮球，避免默认球与主/副球重叠显示
            hideDefaultFloatingBall()

            val dslVersion = (program["dslVersion"] as? Number)?.toInt() ?: 1
            if (dslVersion == 2) {
                val engine = com.qangxing.isolation.floater.FloaterV2Engine(this)
                floaterV2Engine = engine
                engine.load(program)
                return true
            }

            // 加载默认悬浮球配置，供未声明外观参数的球回退使用
            val config = loadDefaultFloaterConfig()

            // 注册 found / screen / dp 函数，用于表达式中获取球坐标、屏幕尺寸与 dp 转 px。
            val callHandler: (String, List<Map<String, Any>>, Map<String, Variable>) -> Variable? = { name, args, variables ->
                when (name) {
                    "found" -> {
                        val ballName = extractStringFromArg(args.getOrNull(0), variables)
                        val axis = extractStringFromArg(args.getOrNull(1), variables) ?: "x"
                        val pos = ballName?.let { getPluginBallPosition(it) }
                        if (pos == null) null
                        else {
                            val value = when (axis.lowercase()) {
                                "y" -> pos["y"] ?: 0
                                "width", "w" -> pos["width"] ?: 0
                                "height", "h" -> pos["height"] ?: 0
                                else -> pos["x"] ?: 0
                            }
                            Variable.Number(value.toDouble())
                        }
                    }
                    "screen" -> {
                        val axis = extractStringFromArg(args.getOrNull(0), variables) ?: "width"
                        val size = screenSize()
                        val value = when (axis) {
                            "width", "w" -> size.x
                            "height", "h" -> size.y
                            "centerX", "cx" -> size.x / 2
                            "centerY", "cy" -> size.y / 2
                            else -> 0
                        }
                        Variable.Number(value.toDouble())
                    }
                    "dp", "dp2px" -> {
                        val dp = args.getOrNull(0)?.let { ExpressionEvaluator.evaluate(it, variables) }
                            ?.let { if (it is Variable.Number) it.value else null } ?: 0.0
                        Variable.Number(dpToPx(dp.toInt()).toDouble())
                    }
                    else -> null
                }
            }
            ExpressionEvaluator.callHandler = callHandler

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
                    pluginFloaterRegistry.registerBallEvent(name, event, children ?: actionChildren ?: emptyList(), elseChildren)
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
        return mapOf(
            "x" to ball.params.x,
            "y" to ball.params.y,
            "width" to ball.params.width,
            "height" to ball.params.height
        )
    }

    internal fun clearAllPluginBalls() {
        floaterV2Engine?.unload()
        floaterV2Engine = null

        val wm = windowManager
        for ((_, ball) in pluginBalls) {
            try {
                if (wm != null && ball.view.parent != null) {
                    wm.removeView(ball.view)
                }
            } catch (e: Exception) {
                Log.w(TAG, "移除旧插件球失败: ${ball.name}", e)
            }
        }
        pluginBalls.clear()
        pendingBallUpdates.clear()
        try { Choreographer.getInstance().removeFrameCallback(ballUpdateFrameCallback) } catch (_: Exception) {}
        pluginModeActive = false
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
        val followTarget = ball["followTarget"] as? String
        val followDx = (ball["followDx"] as? Number)?.toInt() ?: 0
        val followDy = (ball["followDy"] as? Number)?.toInt() ?: 0

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
            existing.followTarget = followTarget
            existing.followDx = followDx
            existing.followDy = followDy
            applyPluginBallConfig(existing)
            updatePluginBallPosition(name, locationX, locationY)
            setPluginBallVisible(name, visible)
            return
        }

        // 如果声明了跟随某球且目标已存在，初始位置放在目标相对偏移处
        val leader = followTarget?.let { pluginBalls[it] }
        val initialX = leader?.let { it.params.x + followDx } ?: locationX
        val initialY = leader?.let { it.params.y + followDy } ?: locationY

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
            x = initialX
            y = initialY
        }

        val view = LayoutInflater.from(context).inflate(R.layout.floating_ball, null)
        val pluginBall = PluginBall(name, view, params, sizeDp, cornerRadiusDp, imagePath, visible, followTarget, followDx, followDy)
        applyPluginBallConfig(pluginBall)
        setupPluginBallTouch(pluginBall)

        try {
            wm.addView(view, params)
            pluginBalls[name] = pluginBall
            if (!visible) {
                view.visibility = View.GONE
            }
            // 创建完成后同步一次跟随位置（若目标球尚未创建，则等目标球创建/移动时自然同步）
            leader?.let {
                updatePluginBallPosition(name, it.params.x + followDx, it.params.y + followDy)
            }
        } catch (e: Exception) {
            Log.e(TAG, "创建插件球失败: $name", e)
        }
    }

    /**
     * v2 DSL 专用：直接通过参数创建或更新插件球。
     */
    internal fun createOrUpdatePluginBall(
        name: String,
        role: String,
        sizeDp: Int,
        cornerRadiusDp: Int,
        imagePath: String?,
        initialX: Int,
        initialY: Int,
        visible: Boolean,
        draggable: Boolean,
        opacity: Float
    ) {
        val wm = windowManager ?: (getSystemService(Context.WINDOW_SERVICE) as WindowManager).also {
            windowManager = it
        }

        val existing = pluginBalls[name]
        if (existing != null) {
            existing.sizeDp = sizeDp
            existing.cornerRadiusDp = cornerRadiusDp
            existing.imagePath = imagePath
            existing.visible = visible
            existing.draggable = draggable
            existing.opacity = opacity
            existing.view.alpha = opacity
            applyPluginBallConfig(existing)
            updatePluginBallPosition(name, initialX, initialY)
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
            x = initialX
            y = initialY
        }

        val view = LayoutInflater.from(this).inflate(R.layout.floating_ball, null)
        val pluginBall = PluginBall(
            name, view, params, sizeDp, cornerRadiusDp, imagePath, visible,
            draggable = draggable, opacity = opacity
        )
        applyPluginBallConfig(pluginBall)
        setupPluginBallTouch(pluginBall)
        view.alpha = opacity

        try {
            wm.addView(view, params)
            pluginBalls[name] = pluginBall
            if (!visible) view.visibility = View.GONE
        } catch (e: Exception) {
            Log.e(TAG, "v2 创建插件球失败: $name", e)
        }
    }

    internal fun removePluginBall(name: String) {
        val ball = pluginBalls.remove(name) ?: return
        try {
            if (ball.view.parent != null) {
                windowManager?.removeView(ball.view)
            }
        } catch (e: Exception) {
            Log.w(TAG, "移除插件球失败: $name", e)
        }
        pendingBallUpdates.remove(name)
    }

    internal fun setPluginBallEventHandler(name: String, event: String, handler: () -> Unit) {
        pluginBalls[name]?.eventHandlers?.put(event, handler)
    }

    internal fun getPluginBallParams(name: String): Map<String, Any>? {
        val ball = pluginBalls[name] ?: return null
        return mapOf(
            "x" to ball.params.x,
            "y" to ball.params.y,
            "width" to ball.params.width,
            "height" to ball.params.height,
            "visible" to ball.visible
        )
    }

    internal fun updatePluginBallOpacity(name: String, opacity: Float) {
        pluginBalls[name]?.let { ball ->
            ball.opacity = opacity
            ball.view.alpha = opacity
        }
    }

    internal fun updatePluginBallSize(name: String, sizeDp: Int) {
        pluginBalls[name]?.let { ball ->
            ball.sizeDp = sizeDp
            applyPluginBallConfig(ball)
        }
    }

    /**
     * 动画移动插件球到目标位置。
     */
    internal fun animatePluginBallPosition(
        name: String,
        fromX: Int,
        fromY: Int,
        toX: Int,
        toY: Int,
        durationMs: Long,
        interpolator: android.animation.TimeInterpolator,
        onEnd: (() -> Unit)? = null
    ) {
        val ball = pluginBalls[name] ?: run {
            onEnd?.invoke()
            return
        }
        mainHandler.post {
            val animator = android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
                duration = durationMs
                setInterpolator(interpolator)
                addUpdateListener { animation ->
                    val t = animation.animatedValue as Float
                    val x = (fromX + (toX - fromX) * t).toInt()
                    val y = (fromY + (toY - fromY) * t).toInt()
                    updatePluginBallPosition(name, x, y)
                }
                addListener(object : android.animation.Animator.AnimatorListener {
                    override fun onAnimationStart(animation: android.animation.Animator) {}
                    override fun onAnimationEnd(animation: android.animation.Animator) {
                        onEnd?.invoke()
                    }
                    override fun onAnimationCancel(animation: android.animation.Animator) {
                        onEnd?.invoke()
                    }
                    override fun onAnimationRepeat(animation: android.animation.Animator) {}
                })
            }
            animator.start()
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
        Log.d(TAG, "应用球配置: ${ball.name}, imagePath=${ball.imagePath}")
        loadImageInto(imageView, ball.imagePath, view)

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
                    if (!ball.draggable) {
                        // 不可拖拽时忽略移动，但仍消费事件以保留点击识别
                        return@setOnTouchListener true
                    }
                    val dx = event.rawX - touchState.initialTouchX
                    val dy = event.rawY - touchState.initialTouchY
                    if (kotlin.math.abs(dx) > CLICK_SLOP_PX || kotlin.math.abs(dy) > CLICK_SLOP_PX) {
                        touchState.hasMoved = true
                    }
                    val newX = touchState.initialX + dx.toInt()
                    val newY = touchState.initialY + dy.toInt()
                    updatePluginBallPosition(ball.name, newX, newY)
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

    internal fun dispatchPluginBallEvent(name: String, event: String) {
        // v2 事件处理器
        pluginBalls[name]?.eventHandlers?.get(event)?.let { handler ->
            mainHandler.post(handler)
        }

        // v1 事件注册表
        val handlers = pluginFloaterRegistry.getBallEvent(name, event)
        for (handler in handlers) {
            // 事件步骤包含 UI 操作（Toast、startActivity、showBubble、executeMacro 等），
            // 必须在主线程执行，否则会导致新建编程球点击闪退。
            mainHandler.post {
                executeFloaterSteps(handler.children, currentBall = name)
            }
        }
    }

    internal fun updatePluginBallPosition(name: String, x: Int, y: Int, visited: MutableSet<String> = mutableSetOf()) {
        if (!visited.add(name)) return
        val ball = pluginBalls[name] ?: return
        ball.params.x = x
        ball.params.y = y
        clampPluginBallToScreen(ball)
        pendingBallUpdates[name] = ball
        schedulePluginBallFrameUpdate()

        // 该球被移动后，同步更新所有以它为目标的跟随球
        for ((followerName, follower) in pluginBalls) {
            if (follower.followTarget == name) {
                updatePluginBallPosition(followerName, ball.params.x + follower.followDx, ball.params.y + follower.followDy, visited)
            }
        }
    }

    /** 将 pending 的插件球位置变更统一提交到 WindowManager，跟随 Choreographer 帧刷新。 */
    private fun schedulePluginBallFrameUpdate() {
        val choreographer = try { Choreographer.getInstance() } catch (_: Exception) { return }
        choreographer.removeFrameCallback(ballUpdateFrameCallback)
        choreographer.postFrameCallback(ballUpdateFrameCallback)
    }

    private fun applyPendingPluginBallUpdates() {
        if (pendingBallUpdates.isEmpty()) return
        for ((name, ball) in pendingBallUpdates) {
            try {
                if (ball.view.parent != null) {
                    windowManager?.updateViewLayout(ball.view, ball.params)
                }
            } catch (e: Exception) {
                Log.w(TAG, "移动插件球失败: $name", e)
            }
        }
        pendingBallUpdates.clear()
    }

    /** 配置变化（转屏、分屏、折叠展开）后重新 clamp 所有插件球并刷新。 */
    private fun applyConfigurationChangeToPluginBalls() {
        if (pluginBalls.isEmpty()) return
        for ((name, ball) in pluginBalls) {
            clampPluginBallToScreen(ball)
            pendingBallUpdates[name] = ball
        }
        schedulePluginBallFrameUpdate()
    }

    internal fun setPluginBallVisible(name: String, visible: Boolean) {
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

    private fun executeFloaterSteps(steps: List<Map<String, Any>>, currentBall: String? = null) {
        var i = 0
        while (i < steps.size) {
            val merge = tryMergeXYAnimation(steps, i)
            if (merge != null) {
                executeXYAnimationMerged(merge.first, currentBall)
                i = merge.second
            } else {
                executeFloaterStep(steps[i], currentBall)
                i++
            }
        }
    }

    /**
     * 检测连续两条 animate 是否是对同一个球的 x/y 位移动画，如果是则合并为一条 animate_xy，
     * 让 x 和 y 在同一个 ValueAnimator 中同步更新，避免两轴不同步导致的路径扭曲。
     */
    private fun tryMergeXYAnimation(steps: List<Map<String, Any>>, index: Int): Pair<Map<String, Any>, Int>? {
        if (index + 1 >= steps.size) return null
        val a = steps[index]
        val b = steps[index + 1]
        if (a["type"] != "animate" || b["type"] != "animate") return null
        val nameA = a["name"] as? String ?: return null
        val nameB = b["name"] as? String ?: return null
        if (nameA != nameB) return null
        val propA = (a["property"] as? String)?.lowercase() ?: return null
        val propB = (b["property"] as? String)?.lowercase() ?: return null
        if (!((propA == "x" && propB == "y") || (propA == "y" && propB == "x"))) return null
        val xStep = if (propA == "x") a else b
        val yStep = if (propA == "y") a else b
        return mapOf(
            "type" to "animate_xy",
            "name" to nameA,
            "x" to (xStep["to"] ?: 0),
            "y" to (yStep["to"] ?: 0),
            "duration" to (a["duration"] as? Number ?: b["duration"] as? Number ?: 300),
            "easing" to (a["easing"] as? String ?: b["easing"] as? String ?: "linear")
        ) to (index + 2)
    }

    private fun executeXYAnimationMerged(step: Map<String, Any>, currentBall: String?) {
        val name = step["name"] as? String ?: return
        val ball = pluginBalls[name] ?: return
        val fromX = ball.params.x
        val fromY = ball.params.y
        val toX = resolveIntValue(step["x"], fromX)
        val toY = resolveIntValue(step["y"], fromY)
        val duration = resolveIntValue(step["duration"], 300).coerceAtLeast(0).toLong()
        val interpolator = when ((step["easing"] as? String)?.lowercase()) {
            "linear" -> LinearInterpolator()
            "accelerate" -> AccelerateInterpolator()
            "decelerate" -> DecelerateInterpolator()
            "bounce" -> BounceInterpolator()
            else -> OvershootInterpolator(1.6f)
        }
        ValueAnimator.ofFloat(0f, 1f).apply {
            this.duration = duration
            this.interpolator = interpolator
            addUpdateListener { anim ->
                val t = anim.animatedValue as Float
                val x = (fromX + (toX - fromX) * t).toInt()
                val y = (fromY + (toY - fromY) * t).toInt()
                updatePluginBallPosition(name, x, y)
            }
            start()
        }
    }

    private fun executeFloaterStep(step: Map<String, Any>, currentBall: String? = null) {
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
                val value = when (axis.lowercase()) {
                    "y" -> pos["y"] ?: 0
                    "width", "w" -> pos["width"] ?: 0
                    "height", "h" -> pos["height"] ?: 0
                    else -> pos["x"] ?: 0
                }
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
            "toggle" -> {
                val name = step["name"] as? String ?: return
                val ball = pluginBalls[name] ?: return
                setPluginBallVisible(name, !ball.visible)
            }
            "change" -> executeChange(step, currentBall)
            "print" -> {
                val message = when (val msg = step["message"]) {
                    is String -> msg
                    is Map<*, *> -> {
                        @Suppress("UNCHECKED_CAST")
                        val expr = msg as Map<String, Any>
                        when (val result = ExpressionEvaluator.evaluate(expr, pluginVariables)) {
                            is Variable.Number -> result.value.toString()
                            is Variable.Point -> "(${result.x}, ${result.y})"
                            is Variable.Color -> "#${Integer.toHexString(result.value)}"
                            else -> return
                        }
                    }
                    else -> return
                }
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
            "bounce", "shake", "pulse", "animate" -> executeBallAnimation(step)
            "animate_xy" -> executeXYAnimationMerged(step, currentBall)
            "for" -> executeFloaterFor(step, currentBall)
            "if" -> executeFloaterIf(step, currentBall)
            else -> Log.w(TAG, "未支持的球步骤类型: ${step["type"]}")
        }
    }

    /**
     * 运行时修改插件球外观参数：size / cornerRadius / image / opacity。
     * 未显式指定球名时，使用 currentBall（即触发当前事件的球）。
     */
    private fun executeChange(step: Map<String, Any>, currentBall: String?) {
        val explicitName = step["name"] as? String
        val targetName = if (!explicitName.isNullOrEmpty()) explicitName else currentBall
        if (targetName == null || targetName.isEmpty()) {
            Log.w(TAG, "change 指令未指定球名，且无当前球上下文")
            return
        }
        val ball = pluginBalls[targetName] ?: run {
            Log.w(TAG, "change 指令目标球不存在: $targetName")
            return
        }

        var needsConfigApply = false
        if (step.containsKey("size")) {
            ball.sizeDp = resolveIntValue(step["size"], ball.sizeDp)
            needsConfigApply = true
        }
        if (step.containsKey("cornerRadius")) {
            ball.cornerRadiusDp = resolveIntValue(step["cornerRadius"], ball.cornerRadiusDp)
            needsConfigApply = true
        }
        if (step.containsKey("image")) {
            val imageName = step["image"] as? String
            ball.imagePath = imageName?.let { resolveAssetPath(it) }
            needsConfigApply = true
        }
        if (step.containsKey("opacity")) {
            val opacity = resolveFloatValue(step["opacity"], ball.view.alpha)
            ball.view.alpha = opacity.coerceIn(0f, 1f)
        }

        if (needsConfigApply) {
            applyPluginBallConfig(ball)
        }
    }

    /**
     * 球动画指令：bounce / shake / pulse / animate。
     * 与录制悬浮球的径向展开同一套视觉语言（ValueAnimator + Overshoot 回弹）。
     * 位移类动画逐帧更新 WindowManager.LayoutParams，跟随球会随动；缩放类直接作用于 view。
     */
    private fun executeBallAnimation(step: Map<String, Any>) {
        val name = step["name"] as? String ?: return
        val ball = pluginBalls[name] ?: return
        val view = ball.view
        val type = step["type"] as? String ?: return
        val defaultDuration = when (type) {
            "bounce" -> 600
            "shake" -> 500
            else -> 300
        }
        val duration = resolveIntValue(step["duration"], defaultDuration).coerceAtLeast(0).toLong()
        when (type) {
            // 弹跳：垂直上移 height 后落回原位（正弦曲线，两端速度为零）
            "bounce" -> {
                val height = resolveFloatValue(step["height"], 48f)
                val startY = ball.params.y
                ValueAnimator.ofFloat(0f, 1f).apply {
                    this.duration = duration
                    interpolator = LinearInterpolator()
                    addUpdateListener { anim ->
                        val f = anim.animatedValue as Float
                        val offset = (-height * sin(Math.PI * f)).toInt()
                        updatePluginBallPosition(name, ball.params.x, startY + offset)
                    }
                    start()
                }
            }
            // 抖动：水平方向 3 个周期的衰减振荡
            "shake" -> {
                val amplitude = resolveFloatValue(step["amplitude"], 20f)
                val startX = ball.params.x
                ValueAnimator.ofFloat(0f, 1f).apply {
                    this.duration = duration
                    interpolator = LinearInterpolator()
                    addUpdateListener { anim ->
                        val f = anim.animatedValue as Float
                        val offset = (amplitude * (1f - f) * sin(6 * Math.PI * f)).toInt()
                        updatePluginBallPosition(name, startX + offset, ball.params.y)
                    }
                    start()
                }
            }
            // 脉冲：放大到 scale 再恢复（录制球展开时主球的提示动作）
            "pulse" -> {
                val target = resolveFloatValue(step["scale"], 1.15f)
                ValueAnimator.ofFloat(0f, 1f).apply {
                    this.duration = duration
                    interpolator = LinearInterpolator()
                    addUpdateListener { anim ->
                        val f = anim.animatedValue as Float
                        val s = 1f + (target - 1f) * sin(Math.PI * f).toFloat()
                        view.scaleX = s
                        view.scaleY = s
                    }
                    start()
                }
            }
            // 通用属性动画：animate("球名", "属性", 目标值, 时长, 缓动)
            "animate" -> {
                val property = (step["property"] as? String)?.lowercase() ?: return
                val interpolator = when ((step["easing"] as? String)?.lowercase()) {
                    "linear" -> LinearInterpolator()
                    "accelerate" -> AccelerateInterpolator()
                    "decelerate" -> DecelerateInterpolator()
                    "bounce" -> BounceInterpolator()
                    else -> OvershootInterpolator(1.6f)
                }
                when (property) {
                    "x", "y" -> {
                        val from = if (property == "x") ball.params.x else ball.params.y
                        val to = resolveIntValue(step["to"], from)
                        ValueAnimator.ofInt(from, to).apply {
                            this.duration = duration
                            this.interpolator = interpolator
                            addUpdateListener { anim ->
                                val v = anim.animatedValue as Int
                                if (property == "x") updatePluginBallPosition(name, v, ball.params.y)
                                else updatePluginBallPosition(name, ball.params.x, v)
                            }
                            start()
                        }
                    }
                    "alpha" -> view.animate().alpha(resolveFloatValue(step["to"], 1f))
                        .setDuration(duration).setInterpolator(interpolator).start()
                    "scale", "scalex", "scaley" -> {
                        val to = resolveFloatValue(step["to"], 1f)
                        val animator = view.animate().setDuration(duration).setInterpolator(interpolator)
                        if (property != "scaley") animator.scaleX(to)
                        if (property != "scalex") animator.scaleY(to)
                        animator.start()
                    }
                    "rotation" -> view.animate().rotation(resolveFloatValue(step["to"], 0f))
                        .setDuration(duration).setInterpolator(interpolator).start()
                    else -> Log.w(TAG, "不支持的球动画属性: $property")
                }
            }
        }
    }

    private fun resolveFloatValue(value: Any?, defaultValue: Float): Float {
        return when (value) {
            is Number -> value.toFloat()
            is Map<*, *> -> {
                @Suppress("UNCHECKED_CAST")
                val expr = value as Map<String, Any>
                val result = ExpressionEvaluator.evaluate(expr, pluginVariables)
                (result as? Variable.Number)?.value?.toFloat() ?: defaultValue
            }
            else -> defaultValue
        }
    }

    private fun executeFloaterFor(step: Map<String, Any>, currentBall: String? = null) {
        @Suppress("UNCHECKED_CAST")
        val condition = step["condition"] as? Map<String, Any>
        if (condition != null) {
            @Suppress("UNCHECKED_CAST")
            val init = step["init"] as? Map<String, Any>
            @Suppress("UNCHECKED_CAST")
            val update = step["update"] as? Map<String, Any>
            @Suppress("UNCHECKED_CAST")
            val children = (step["children"] as? List<Map<String, Any>>) ?: return
            init?.let { executeFloaterStep(it, currentBall) }
            while (ExpressionEvaluator.toBoolean(ExpressionEvaluator.evaluate(condition, pluginVariables))) {
                executeFloaterSteps(children, currentBall)
                update?.let { executeFloaterStep(it, currentBall) }
            }
            return
        }
        val count = (step["count"] as? Number)?.toInt() ?: 1
        @Suppress("UNCHECKED_CAST")
        val children = (step["children"] as? List<Map<String, Any>>) ?: return
        for (i in 1..count) {
            executeFloaterSteps(children, currentBall)
        }
    }

    private fun executeFloaterIf(step: Map<String, Any>, currentBall: String? = null) {
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
            thenChildren?.let { executeFloaterSteps(it, currentBall) }
        } else {
            elseChildren?.let { executeFloaterSteps(it, currentBall) }
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
     * 返回当前应用可用区域（不含系统状态栏/导航栏），用于 clamp 悬浮球位置。
     * Android R+ 使用 WindowMetrics 获取最新可用区域；旧设备回退到 getMetrics。
     */
    private fun screenSize(): Point {
        val out = Point()
        val wm = windowManager ?: return out
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.currentWindowMetrics.bounds
            out.set(bounds.width(), bounds.height())
            out
        } else {
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getMetrics(metrics)
            out.x = metrics.widthPixels
            out.y = metrics.heightPixels
            out
        }
    }

    internal fun getScreenUsableSize(): android.util.Size {
        val point = screenSize()
        return android.util.Size(point.x, point.y)
    }

    // ── 录制悬浮球内部实现 ──

    private fun mountPendingRecordingBalls() {
        val ctx = pendingRecordingBallContext ?: return
        pendingRecordingBallContext = null
        ensureRecordingBallsInternal(ctx)
    }

    private fun hideDefaultBallForRecordingInternal(): Boolean {
        val wasVisible = floatingView != null
        if (wasVisible) {
            defaultBallVisibleBeforeRecording = true
            hideDefaultFloatingBall()
        }
        return wasVisible
    }

    /**
     * 挂载录制悬浮球：主球（单击径向展开/收起功能副球）。
     * 球窗口都是独立 overlay，层级高于全屏捕获层，
     * 因此触摸球本身不会落入捕获层、也不会产生录制步骤。
     */
    private fun ensureRecordingBallsInternal(ctx: Context) {
        if (recordingMainBall.view != null) return
        if (windowManager == null) {
            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        }
        // 收起默认悬浮球，避免与录制球重叠
        if (floatingView != null) {
            defaultBallVisibleBeforeRecording = true
            hideDefaultFloatingBall()
        }

        val wm = windowManager ?: return
        val ballSizePx = dpToPx(BALL_SIZE_DP)
        val subSizePx = dpToPx(REC_SUB_BALL_SIZE_DP)
        val screen = screenSize()
        val startX = screen.x - ballSizePx - dpToPx(16)
        val startY = (screen.y - ballSizePx) / 2

        // 功能项定义（顺序即展开顺序）：暂停/继续 → 标记 → 取消 → 结束保存
        recordingActions = listOf(
            RecordingAction("pause", makePauseIcon(subSizePx), 0xFFFFFFFF.toInt()) {
                when (RecordingSession.state) {
                    RecordingSession.State.RECORDING -> RecordingSession.pause()
                    RecordingSession.State.PAUSED -> RecordingSession.resume()
                    else -> RecordingSession.pause()
                }
            },
            RecordingAction("mark", makeMarkIcon(subSizePx), 0xFF1E88E5.toInt()) {
                RecordingSession.addMark()
                showBubble("已插入标记")
            },
            RecordingAction("cancel", makeCancelIcon(subSizePx), 0xFF757575.toInt()) {
                RecordingSession.cancel()
            },
            RecordingAction("finish", makeFinishIcon(subSizePx), 0xFFE53935.toInt()) {
                RecordingSession.finish()
            }
        )

        // 主球
        val mainParams = recordingWindowParams(startX, startY, ballSizePx)
        val mainBall = createRecordingBallView(ctx, makeRecordIcon(ballSizePx), 0xFF37474F.toInt(), ballSizePx)
        recordingMainBall = RecordingBall(mainBall.view, mainParams, mainBall.icon)
        setupRecordingMainBallTouch(mainBall.view!!)
        try { wm.addView(mainBall.view, mainParams) } catch (e: Exception) { Log.e(TAG, "添加录制主球失败", e) }

        // 功能副球：初始与主球同位、隐藏，展开时沿弧线弹出
        recordingSubViews.clear()
        recordingActions.forEachIndexed { index, action ->
            val p = recordingWindowParams(startX, startY, subSizePx)
            val ball = createRecordingBallView(ctx, action.icon, action.bgColor, subSizePx)
            val v = ball.view!!
            if (action.id == "pause") recordingPauseIcon = ball.icon
            v.visibility = View.GONE
            v.setOnClickListener {
                action.onClick()
                // 结束/取消会销毁录制球；暂停/标记后收起菜单
                if (action.id == "pause" || action.id == "mark") collapseRecordingSubBalls()
            }
            try { wm.addView(v, p) } catch (e: Exception) { Log.e(TAG, "添加录制副球失败", e) }
            recordingSubViews.add(RecordingBall(v, p, ball.icon))
        }
        updateRecordingSubTargets()
        recordingSubBallsVisible = false
    }

    /** 录制状态变化时同步暂停/继续副球图标。 */
    private fun updateRecordingBallStateInternal() {
        val icon = recordingPauseIcon ?: return
        val sizePx = dpToPx(REC_SUB_BALL_SIZE_DP)
        when (RecordingSession.state) {
            RecordingSession.State.RECORDING -> icon.setImageBitmap(makePauseIcon(sizePx))
            RecordingSession.State.PAUSED -> icon.setImageBitmap(makePlayIcon(sizePx))
            else -> icon.setImageBitmap(makeRecordIcon(sizePx))
        }
    }

    /** 结束/取消录制：移除全部录制球，并按需恢复默认悬浮球。 */
    private fun endRecordingModeInternal(restoreDefaultBall: Boolean) {
        val wm = windowManager
        val all = mutableListOf(recordingMainBall)
        all.addAll(recordingSubViews)
        all.forEach { ball ->
            ball.view?.let { v ->
                try {
                    if (wm != null && v.parent != null) wm.removeView(v)
                } catch (e: Exception) {
                    Log.w(TAG, "移除录制球失败", e)
                }
            }
        }
        recordingMainBall = RecordingBall(null, null, null)
        recordingSubViews.clear()
        recordingActions = emptyList()
        recordingPauseIcon = null
        recordingSubBallsVisible = false
        if ((restoreDefaultBall || defaultBallVisibleBeforeRecording) && Settings.canDrawOverlays(this)) {
            defaultBallVisibleBeforeRecording = false
            if (floatingView == null) {
                showFloatingBall()
            }
        }
    }

    private fun recordingWindowParams(x: Int, y: Int, sizePx: Int): WindowManager.LayoutParams {
        return WindowManager.LayoutParams(
            sizePx,
            sizePx,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            this.x = x
            this.y = y
        }
    }

    /** 创建单个录制球视图：圆底容器 + 居中图标。 */
    private fun createRecordingBallView(ctx: Context, icon: Bitmap, bgColor: Int, sizePx: Int): RecordingBall {
        val root = FrameLayout(ctx)
        val bg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(bgColor)
            setStroke(dpToPx(1), 0x33FFFFFF.toInt())
        }
        root.background = bg
        val image = ImageView(ctx).apply {
            setImageBitmap(icon)
            setPadding((sizePx * 0.24f).toInt(), (sizePx * 0.24f).toInt(), (sizePx * 0.24f).toInt(), (sizePx * 0.24f).toInt())
        }
        root.addView(image, FrameLayout.LayoutParams(sizePx, sizePx))
        return RecordingBall(root, null, image)
    }

    private fun bitmap(sizePx: Int, draw: (Canvas, Paint) -> Unit): Bitmap {
        val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        draw(canvas, paint)
        return bmp
    }

    /** 录制中主球图标：红色圆点。 */
    private fun makeRecordIcon(sizePx: Int): Bitmap {
        return bitmap(sizePx) { c, p ->
            p.color = 0xFFFF5252.toInt()
            c.drawCircle(sizePx / 2f, sizePx / 2f, sizePx * 0.24f, p)
        }
    }

    /** 暂停图标：两道竖杠。 */
    private fun makePauseIcon(sizePx: Int): Bitmap {
        return bitmap(sizePx) { c, p ->
            p.color = android.graphics.Color.BLACK
            val cx = sizePx / 2f
            val cy = sizePx / 2f
            val bw = sizePx * 0.13f
            val bh = sizePx * 0.42f
            c.drawRect(cx - sizePx * 0.24f, cy - bh / 2, cx - sizePx * 0.24f + bw, cy + bh / 2, p)
            c.drawRect(cx + sizePx * 0.24f - bw, cy - bh / 2, cx + sizePx * 0.24f, cy + bh / 2, p)
        }
    }

    /** 继续图标：右向三角。 */
    private fun makePlayIcon(sizePx: Int): Bitmap {
        return bitmap(sizePx) { c, p ->
            p.color = android.graphics.Color.BLACK
            val cx = sizePx / 2f
            val cy = sizePx / 2f
            val tri = Path().apply {
                moveTo(cx - sizePx * 0.16f, cy - sizePx * 0.30f)
                lineTo(cx + sizePx * 0.26f, cy)
                lineTo(cx - sizePx * 0.16f, cy + sizePx * 0.30f)
                close()
            }
            c.drawPath(tri, p)
        }
    }

    /** 结束图标：白色方块。 */
    private fun makeFinishIcon(sizePx: Int): Bitmap {
        return bitmap(sizePx) { c, p ->
            p.color = android.graphics.Color.WHITE
            val s = sizePx * 0.32f
            val cx = sizePx / 2f
            val cy = sizePx / 2f
            c.drawRect(cx - s / 2, cy - s / 2, cx + s / 2, cy + s / 2, p)
        }
    }

    /** 标记图标：白色旗标。 */
    private fun makeMarkIcon(sizePx: Int): Bitmap {
        return bitmap(sizePx) { c, p ->
            p.color = android.graphics.Color.WHITE
            p.strokeWidth = sizePx * 0.06f
            p.style = Paint.Style.STROKE
            p.strokeCap = Paint.Cap.ROUND
            val cx = sizePx / 2f
            val cy = sizePx / 2f
            // 旗杆
            c.drawLine(cx - sizePx * 0.14f, cy - sizePx * 0.26f, cx - sizePx * 0.14f, cy + sizePx * 0.28f, p)
            // 旗面
            p.style = Paint.Style.FILL
            val flag = Path().apply {
                moveTo(cx - sizePx * 0.14f, cy - sizePx * 0.26f)
                lineTo(cx + sizePx * 0.22f, cy - sizePx * 0.16f)
                lineTo(cx - sizePx * 0.14f, cy - sizePx * 0.04f)
                close()
            }
            c.drawPath(flag, p)
        }
    }

    /** 取消图标：白色叉。 */
    private fun makeCancelIcon(sizePx: Int): Bitmap {
        return bitmap(sizePx) { c, p ->
            p.color = android.graphics.Color.WHITE
            p.strokeWidth = sizePx * 0.07f
            p.strokeCap = Paint.Cap.ROUND
            val s = sizePx * 0.18f
            val cx = sizePx / 2f
            val cy = sizePx / 2f
            c.drawLine(cx - s, cy - s, cx + s, cy + s, p)
            c.drawLine(cx + s, cy - s, cx - s, cy + s, p)
        }
    }

    /** 主球触摸：拖动移动，单击展开/收起副球。拖动与点击均不产生录制步骤（球窗口位于捕获层之上）。 */
    private fun setupRecordingMainBallTouch(view: View) {
        val params = recordingMainBall.params ?: return
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var hasMoved = false

        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    hasMoved = false
                    view.animate().scaleX(0.9f).scaleY(0.9f).setDuration(100).start()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (!hasMoved && (kotlin.math.abs(dx) > CLICK_SLOP_PX || kotlin.math.abs(dy) > CLICK_SLOP_PX)) {
                        hasMoved = true
                        // 开始拖动时收起菜单，避免副球追着手势乱飞
                        if (recordingSubBallsVisible) collapseRecordingSubBalls()
                    }
                    params.x = initialX + dx.toInt()
                    params.y = initialY + dy.toInt()
                    clampToScreen(params)
                    updateRecordingSubTargets()
                    try {
                        windowManager?.updateViewLayout(view, params)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    view.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    if (!hasMoved) {
                        toggleRecordingSubBalls()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    view.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    true
                }
                else -> false
            }
        }
    }

    /** 副球点击：暂停/继续 或 结束录制。 */
    private fun setupRecordingSubBallClick(view: View, isFinish: Boolean) {
        view.setOnClickListener {
            if (isFinish) {
                RecordingSession.finish()
            } else {
                when (RecordingSession.state) {
                    RecordingSession.State.RECORDING -> RecordingSession.pause()
                    RecordingSession.State.PAUSED -> RecordingSession.resume()
                    else -> RecordingSession.pause()
                }
            }
        }
    }

    /** 主球单击：展开则收起，收起则径向展开。 */
    private fun toggleRecordingSubBalls() {
        if (recordingSubBallsVisible) collapseRecordingSubBalls() else expandRecordingSubBalls()
    }

    /**
     * 计算各副球展开后的目标左上角坐标（绕主球弧线排布）。
     * 依据主球所在屏幕方位智能选方向：靠右向左展开、靠上向下展开，避免出屏。
     */
    private fun recordingSubTargets(): List<Point> {
        val main = recordingMainBall.params ?: return emptyList()
        val screen = screenSize()
        val subSize = dpToPx(REC_SUB_BALL_SIZE_DP)
        val radius = dpToPx(REC_RADIAL_RADIUS_DP)
        val mainCx = main.x + main.width / 2f
        val mainCy = main.y + main.height / 2f

        val dirX = if (mainCx > screen.x / 2f) -1f else 1f   // 右半屏向左展开
        val dirY = if (mainCy > screen.y / 2f) -1f else 1f   // 下半屏向上展开
        val n = recordingSubViews.size
        if (n == 0) return emptyList()
        // 90° 扇形内均匀分布，从主轴方向开始向垂直方向扫
        val startAngle = if (dirX < 0) 180.0 else 0.0
        val sweep = if (dirY < 0) -90.0 else 90.0
        val out = mutableListOf<Point>()
        for (i in 0 until n) {
            val t = if (n == 1) 0.5 else i / (n - 1).toDouble()
            val angleDeg = startAngle + sweep * t
            val rad = Math.toRadians(angleDeg)
            val cx = mainCx + (radius * kotlin.math.cos(rad)).toFloat()
            val cy = mainCy + (radius * kotlin.math.sin(rad)).toFloat()
            out.add(Point((cx - subSize / 2f).toInt(), (cy - subSize / 2f).toInt()))
        }
        return out
    }

    /** 展开副球：从主球位置沿弧线弹出，带回弹与错落。 */
    private fun expandRecordingSubBalls() {
        if (recordingSubViews.isEmpty()) return
        recordingSubBallsVisible = true
        val targets = recordingSubTargets()
        val main = recordingMainBall.params ?: return
        recordingSubViews.forEachIndexed { index, ball ->
            val v = ball.view ?: return@forEachIndexed
            val p = ball.params ?: return@forEachIndexed
            val target = targets.getOrNull(index) ?: return@forEachIndexed
            // 初始：叠在主球位置、缩小透明
            p.x = main.x + (main.width - p.width) / 2
            p.y = main.y + (main.height - p.height) / 2
            v.visibility = View.VISIBLE
            v.alpha = 0f
            v.scaleX = 0.3f
            v.scaleY = 0.3f
            updateBallLayout(v, p)

            val startX = p.x
            val startY = p.y
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = REC_EXPAND_ANIM_MS
                startDelay = index * REC_STAGGER_MS
                interpolator = OvershootInterpolator(1.6f)
                addUpdateListener { anim ->
                    val f = anim.animatedValue as Float
                    p.x = (startX + (target.x - startX) * f).toInt()
                    p.y = (startY + (target.y - startY) * f).toInt()
                    updateBallLayout(v, p)
                }
                start()
            }
            v.animate().alpha(1f).scaleX(1f).scaleY(1f)
                .setDuration(REC_EXPAND_ANIM_MS)
                .setStartDelay(index * REC_STAGGER_MS)
                .setInterpolator(OvershootInterpolator(1.6f))
                .start()
        }
        // 主球轻微放大提示已展开
        recordingMainBall.view?.animate()?.scaleX(1.08f)?.scaleY(1.08f)?.setDuration(150)?.start()
    }

    /** 收起副球：缩回主球位置并隐藏。 */
    private fun collapseRecordingSubBalls() {
        recordingSubBallsVisible = false
        val main = recordingMainBall.params
        recordingSubViews.forEachIndexed { index, ball ->
            val v = ball.view ?: return@forEachIndexed
            val p = ball.params ?: return@forEachIndexed
            val endX = if (main != null) main.x + (main.width - p.width) / 2 else p.x
            val endY = if (main != null) main.y + (main.height - p.height) / 2 else p.y
            val startX = p.x
            val startY = p.y
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 180
                startDelay = index * 25L
                addUpdateListener { anim ->
                    val f = anim.animatedValue as Float
                    p.x = (startX + (endX - startX) * f).toInt()
                    p.y = (startY + (endY - startY) * f).toInt()
                    updateBallLayout(v, p)
                }
                start()
            }
            v.animate().alpha(0f).scaleX(0.3f).scaleY(0.3f)
                .setDuration(180)
                .setStartDelay(index * 25L)
                .withEndAction { v.visibility = View.GONE }
                .start()
        }
        recordingMainBall.view?.animate()?.scaleX(1f)?.scaleY(1f)?.setDuration(150)?.start()
    }

    /** 拖动主球时，展开状态下副球实时跟随到弧线目标位。 */
    private fun updateRecordingSubTargets() {
        if (!recordingSubBallsVisible) return
        val targets = recordingSubTargets()
        recordingSubViews.forEachIndexed { index, ball ->
            val p = ball.params ?: return@forEachIndexed
            val v = ball.view ?: return@forEachIndexed
            val target = targets.getOrNull(index) ?: return@forEachIndexed
            p.x = target.x
            p.y = target.y
            updateBallLayout(v, p)
        }
    }

    private fun updateBallLayout(v: View, p: WindowManager.LayoutParams) {
        try {
            windowManager?.updateViewLayout(v, p)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun hideFloatingBall() {
        clearAllPluginBalls()
        // 同时清理录制悬浮球（录制中关闭服务时）
        endRecordingModeInternal(restoreDefaultBall = false)
        hideDefaultFloatingBall()
        hideBubble()
        hideAnimationOverlay()
    }

    /** 仅隐藏默认悬浮球视图，不停掉服务。用于启用编程球时保留服务并显示主/副球。 */
    private fun hideDefaultFloatingBall() {
        if (floatingView != null) {
            try {
                windowManager?.removeView(floatingView)
            } catch (e: Exception) {
                e.printStackTrace()
            }
            floatingView = null
            floatingParams = null
        }
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
        if (pluginModeActive) return
        if (MacroExecutor.isRunning()) {
            MacroExecutor.notifyFloatingBallClick(this)
            return
        }
        runEnabledMacro()
    }

    private fun runEnabledMacro() {
        if (MacroExecutor.isRunning()) {
            Log.w(TAG, "已有宏在运行，忽略本次执行请求")
            return
        }
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
        InputAccessibilityService.executeMacro(
            this, macro.settings, macro.steps, pluginId = enabledMacroId()
        )
    }

    /**
     * 解析当前启用宏的 id，用于把执行日志归属到正确的宏。
     * 优先读取 Flutter 侧写入的旁路文件（不受 shared_preferences key 前缀差异影响），
     * 解析失败时回退到 FlutterSharedPreferences 中的插件列表。
     */
    private fun enabledMacroId(): String? {
        // 旁路文件：plugin_provider 写 enabled_macro.json 时同步写入，最可靠
        val idFile = File(filesDir, "enabled_macro_plugin_id")
        if (idFile.exists()) {
            val id = idFile.readText().trim()
            if (id.isNotEmpty()) return id
        }
        val prefs = flutterPrefs(this)
        val raw = prefs.getString("isolation_plugins", null)
            ?: prefs.getString("flutter.isolation_plugins", null)
            ?: return null
        return try {
            val array = JSONArray(raw)
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                if (obj.optBoolean("enabled", false) && obj.optString("type") != "floaterPlugin") {
                    val actions = obj.optJSONArray("actions") ?: continue
                    for (j in 0 until actions.length()) {
                        if (actions.getJSONObject(j).optString("type") == "macro") {
                            return obj.optString("id").ifEmpty { null }
                        }
                    }
                }
            }
            null
        } catch (e: Exception) {
            null
        }
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
    internal fun showBubble(message: String) {
        if (windowManager == null) return

        val density = resources.displayMetrics.density
        val gap = (BUBBLE_GAP_DP * density).toInt()
        val screen = screenSize()
        val anchor = bubbleAnchor() ?: return
        val ballParams = anchor.params
        val anchorSizePx = anchor.sizePx

        // 锚点球中心坐标（屏幕坐标系）
        val ballCenterX = ballParams.x + anchorSizePx / 2
        val ballCenterY = ballParams.y + anchorSizePx / 2

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

        // 默认放在锚点球上方；上方空间不足则放下方
        var bubbleY = ballParams.y - bubbleH - gap
        val putBelow = bubbleY < 0
        if (putBelow) {
            bubbleY = ballParams.y + anchorSizePx + gap
        }
        if (bubbleY + bubbleH > screen.y) bubbleY = screen.y - bubbleH
        if (bubbleY < 0) bubbleY = 0

        // 水平方向居中对齐，并裁剪到屏幕内
        var bubbleX = ballCenterX - bubbleW / 2
        if (bubbleX < 0) bubbleX = 0
        if (bubbleX + bubbleW > screen.x) bubbleX = screen.x - bubbleW

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
        // 必须先清理插件球，再清理默认球，防止孤儿视图残留
        clearAllPluginBalls()
        hideFloatingBall()
        hideKeyboard()
        MacroExecutor.removeListener(this)
        unregisterComponentCallbacks(pluginConfigCallback)
        instance = null
        MacroStatusNotifier.refreshState(this)
        super.onDestroy()
    }
}
