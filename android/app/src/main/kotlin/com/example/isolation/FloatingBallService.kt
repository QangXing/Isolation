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
    }

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var bubbleView: TextView? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var keyboardView: KeyboardOverlayView? = null
    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private val mainHandler = Handler(Looper.getMainLooper())
    private val bubbleHideRunnable = Runnable { hideBubble() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        MacroExecutor.setListener(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
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

        floatingView = LayoutInflater.from(this).inflate(R.layout.floating_ball, null)
        val ball = floatingView!!.findViewById<ImageView>(R.id.floating_ball_image)
        ball.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    ball.animate().scaleX(0.9f).scaleY(0.9f).setDuration(100).start()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = initialX + (event.rawX - initialTouchX).toInt()
                    params.y = initialY + (event.rawY - initialTouchY).toInt()
                    windowManager?.updateViewLayout(floatingView, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    ball.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (kotlin.math.abs(dx) < 10 && kotlin.math.abs(dy) < 10) {
                        MacroExecutor.notifyFloatingBallClick(this)
                        runEnabledMacro()
                    }
                    true
                }
                else -> false
            }
        }
        ball.setOnLongClickListener {
            openMainActivity()
            true
        }

        windowManager?.addView(floatingView, params)
    }

    private fun hideFloatingBall() {
        if (floatingView != null) {
            windowManager?.removeView(floatingView)
            floatingView = null
        }
        hideBubble()
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

    private fun runEnabledMacro() {
        if (!InputAccessibilityService.isEnabled(this)) {
            Toast.makeText(this, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
            showBubble("辅助功能未开启")
            return
        }
        val macro = loadEnabledMacro()
        if (macro == null || macro.steps.isEmpty()) {
            Toast.makeText(this, "请先启用一个宏", Toast.LENGTH_SHORT).show()
            showBubble("未启用宏")
            return
        }
        showBubble("开始执行宏")
        InputAccessibilityService.executeMacro(this, macro.settings, macro.steps)
    }

    override fun onMacroStatus(message: String) {
        mainHandler.post {
            showBubble(message)
        }
    }

    private fun showBubble(message: String) {
        if (windowManager == null || floatingView == null) return

        if (bubbleView == null) {
            bubbleView = TextView(this).apply {
                setBackgroundResource(android.R.drawable.dialog_holo_light_frame)
                setPadding(24, 12, 24, 12)
                setTextColor(android.graphics.Color.BLACK)
                textSize = 13f
                maxLines = 2
            }
            bubbleParams = WindowManager.LayoutParams(
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
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        bubbleView?.text = message
        bubbleView?.visibility = View.VISIBLE

        val ballParams = floatingView?.layoutParams as? WindowManager.LayoutParams
        if (ballParams != null && bubbleParams != null) {
            bubbleParams!!.x = ballParams.x + (floatingView?.width ?: 0) + 16
            bubbleParams!!.y = ballParams.y
            try {
                windowManager?.updateViewLayout(bubbleView, bubbleParams)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        mainHandler.removeCallbacks(bubbleHideRunnable)
        mainHandler.postDelayed(bubbleHideRunnable, 2500)
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
        hideFloatingBall()
        hideKeyboard()
        MacroExecutor.setListener(null)
        super.onDestroy()
    }
}
