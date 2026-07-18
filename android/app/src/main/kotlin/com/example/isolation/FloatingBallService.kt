package com.example.isolation

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat

class FloatingBallService : Service() {
    companion object {
        const val ACTION_SHOW = "ACTION_SHOW"
        const val ACTION_HIDE = "ACTION_HIDE"
        const val ACTION_TOAST = "ACTION_TOAST"
        const val EXTRA_TOAST_MESSAGE = "toast_message"
        const val CHANNEL_ID = "isolation_floating_ball"
        const val NOTIFICATION_ID = 1

        private var instance: FloatingBallService? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        fun showToast(context: Context, message: String) {
            val intent = Intent(context, FloatingBallService::class.java).apply {
                action = ACTION_TOAST
                putExtra(EXTRA_TOAST_MESSAGE, message)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var bubbleView: View? = null
    private var bubbleText: TextView? = null
    private var keyboardView: KeyboardOverlayView? = null
    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f

    private var clickCount = 0
    private var lastClickTime = 0L
    private var longPressed = false
    private val doubleClickTimeout = 300L
    private val longPressTimeout = 500L
    private val singleClickRunnable = Runnable {
        if (clickCount == 1) {
            onSingleClick()
        }
        clickCount = 0
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> showFloatingBall()
            ACTION_HIDE -> {
                hideFloatingBall()
                hideKeyboard()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
            }
            ACTION_TOAST -> {
                startForegroundNotification()
                if (floatingView == null) {
                    showFloatingBall()
                }
                val message = intent.getStringExtra(EXTRA_TOAST_MESSAGE) ?: ""
                if (message.isNotEmpty()) {
                    showBubble(message)
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        hideFloatingBall()
        hideKeyboard()
        super.onDestroy()
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
            .setContentText("悬浮球正在运行")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun showFloatingBall() {
        if (floatingView != null) return
        if (!Settings.canDrawOverlays(this)) return

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

        floatingView = LayoutInflater.from(this).inflate(R.layout.floating_ball, null)
        val ball = floatingView!!.findViewById<ImageView>(R.id.floating_ball_image)
        setupBallTouch(ball, params)
        ball.setOnLongClickListener {
            longPressed = true
            toggleKeyboard()
            true
        }

        windowManager?.addView(floatingView, params)
    }

    private fun setupBallTouch(ball: ImageView, params: WindowManager.LayoutParams) {
        val longPressRunnable = Runnable {
            longPressed = true
            ball.performLongClick()
        }

        ball.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    longPressed = false
                    ball.animate().scaleX(0.9f).scaleY(0.9f).setDuration(100).start()
                    mainHandler.postDelayed(longPressRunnable, longPressTimeout)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (kotlin.math.abs(dx) > 20 || kotlin.math.abs(dy) > 20) {
                        mainHandler.removeCallbacks(longPressRunnable)
                    }
                    params.x = initialX + dx.toInt()
                    params.y = initialY + dy.toInt()
                    windowManager?.updateViewLayout(floatingView, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    mainHandler.removeCallbacks(longPressRunnable)
                    ball.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (kotlin.math.abs(dx) < 15 && kotlin.math.abs(dy) < 15 && !longPressed) {
                        handleBallClick()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun handleBallClick() {
        val now = System.currentTimeMillis()
        clickCount++
        if (clickCount == 1) {
            mainHandler.postDelayed(singleClickRunnable, doubleClickTimeout)
        } else if (clickCount == 2 && now - lastClickTime < doubleClickTimeout) {
            mainHandler.removeCallbacks(singleClickRunnable)
            onDoubleClick()
            clickCount = 0
        }
        lastClickTime = now
    }

    private fun onSingleClick() {
        when {
            InputAccessibilityService.isRecording() -> {
                InputAccessibilityService.stopRecording(this)
                Toast.makeText(this, "已停止录制", Toast.LENGTH_SHORT).show()
            }
            InputAccessibilityService.isExecuting() -> {
                InputAccessibilityService.stopExecution(this)
            }
            InputAccessibilityService.hasCurrentMacro() -> {
                InputAccessibilityService.executeCurrentMacro(this)
            }
            else -> {
                InputAccessibilityService.showInputMethod(this)
            }
        }
    }

    private fun onDoubleClick() {
        if (InputAccessibilityService.isExecuting()) {
            InputAccessibilityService.stopExecution(this)
            Toast.makeText(this, "已停止循环", Toast.LENGTH_SHORT).show()
        } else {
            InputAccessibilityService.executeCurrentMacro(this)
        }
    }

    private fun hideFloatingBall() {
        if (floatingView != null) {
            windowManager?.removeView(floatingView)
            floatingView = null
        }
        hideBubble()
    }

    private fun showBubble(message: String) {
        if (windowManager == null || floatingView == null) return

        if (bubbleView == null) {
            bubbleView = LayoutInflater.from(this).inflate(R.layout.floating_ball_bubble, null)
            bubbleText = bubbleView!!.findViewById(R.id.bubble_text)
            val bubbleParams = WindowManager.LayoutParams(
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
            }
            try {
                windowManager?.addView(bubbleView, bubbleParams)
            } catch (_: Exception) {
                return
            }
        }

        bubbleText?.text = message
        updateBubblePosition()
        bubbleView?.visibility = View.VISIBLE
        bubbleView?.alpha = 0f
        bubbleView?.animate()?.alpha(1f)?.setDuration(150)?.start()

        mainHandler.removeCallbacks(hideBubbleRunnable)
        mainHandler.postDelayed(hideBubbleRunnable, 2500)
    }

    private val hideBubbleRunnable = Runnable {
        hideBubble()
    }

    private fun hideBubble() {
        bubbleView?.let {
            it.animate().alpha(0f).setDuration(150).withEndAction {
                it.visibility = View.GONE
            }.start()
        }
    }

    private fun updateBubblePosition() {
        val ball = floatingView ?: return
        val bubble = bubbleView ?: return
        val ballParams = ball.layoutParams as? WindowManager.LayoutParams ?: return
        val bubbleParams = bubble.layoutParams as? WindowManager.LayoutParams ?: return

        bubbleParams.x = ballParams.x + ball.width
        bubbleParams.y = ballParams.y
        windowManager?.updateViewLayout(bubble, bubbleParams)
    }

    private fun toggleKeyboard() {
        if (keyboardView == null) {
            showKeyboard()
        } else {
            hideKeyboard()
        }
    }

    private fun showKeyboard() {
        if (keyboardView != null) return
        keyboardView = KeyboardOverlayView(this)
        keyboardView?.show()
    }

    private fun hideKeyboard() {
        keyboardView?.hide()
        keyboardView = null
    }
}
