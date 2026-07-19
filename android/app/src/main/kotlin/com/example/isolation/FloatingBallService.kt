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
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject

class FloatingBallService : Service(), InputAccessibilityService.MacroListener {
    companion object {
        const val ACTION_SHOW = "ACTION_SHOW"
        const val ACTION_HIDE = "ACTION_HIDE"
        const val ACTION_UPDATE_MACRO = "ACTION_UPDATE_MACRO"
        const val CHANNEL_ID = "isolation_floating_ball"
        const val NOTIFICATION_ID = 1
    }

    private data class MacroConfig(
        val steps: List<Map<String, Any>>,
        val loop: Boolean,
        val smartRecognition: Boolean
    )

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var floatingParams: WindowManager.LayoutParams? = null
    private var bubbleView: TextView? = null
    private var keyboardView: KeyboardOverlayView? = null
    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var lastClickTime = 0L
    private var clickCount = 0
    private val hideBubbleRunnable = Runnable { hideBubble() }
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        InputAccessibilityService.setMacroListener(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> showFloatingBall()
            ACTION_UPDATE_MACRO -> {
                // macro config is read dynamically on click
            }
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
        }
        return START_STICKY
    }

    override fun onDestroy() {
        InputAccessibilityService.setMacroListener(null)
        hideFloatingBall()
        hideKeyboard()
        mainHandler.removeCallbacks(hideBubbleRunnable)
        super.onDestroy()
    }

    override fun onStatus(message: String) {
        mainHandler.post { showBubble(message) }
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

    private fun showFloatingBall() {
        if (floatingView != null) return
        if (!Settings.canDrawOverlays(this)) return

        startForegroundNotification()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        floatingParams = WindowManager.LayoutParams(
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
        val params = floatingParams!!
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
                        onBallClicked()
                    }
                    true
                }
                else -> false
            }
        }
        ball.setOnLongClickListener {
            toggleKeyboard()
            true
        }

        windowManager?.addView(floatingView, params)
    }

    private fun onBallClicked() {
        val now = System.currentTimeMillis()
        if (now - lastClickTime < 800) {
            clickCount++
        } else {
            clickCount = 1
        }
        lastClickTime = now

        if (InputAccessibilityService.isExecuting()) {
            InputAccessibilityService.cancelExecution()
            showBubble("已停止")
            return
        }

        if (clickCount >= 2) {
            showBubble("连点已停止")
            return
        }

        val macro = loadEnabledMacro()
        if (macro == null) {
            showBubble("请先启用一个宏")
            return
        }

        showBubble("开始执行")
        InputAccessibilityService.executeMacro(
            macro.steps,
            macro.loop,
            macro.smartRecognition
        )
    }

    private fun loadEnabledMacro(): MacroConfig? {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val json = prefs.getString("isolation_plugins", null) ?: return null
        return try {
            val plugins = JSONArray(json)
            for (i in 0 until plugins.length()) {
                val plugin = plugins.getJSONObject(i)
                if (!plugin.optBoolean("enabled", false)) continue
                val actions = plugin.optJSONArray("actions") ?: continue
                for (j in 0 until actions.length()) {
                    val action = actions.getJSONObject(j)
                    if (action.optString("type") != "macro") continue
                    val pluginId = plugin.optString("id")
                    val macroFile = action.optString("macroFile", "macro.json")
                    val loop = action.optBoolean("loop", false)
                    val smartRecognition = action.optBoolean("smartRecognition", false)
                    val steps = loadMacroSteps(pluginId, macroFile) ?: continue
                    return MacroConfig(steps, loop, smartRecognition)
                }
            }
            null
        } catch (e: Exception) {
            null
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun loadMacroSteps(pluginId: String, macroFile: String): List<Map<String, Any>>? {
        return try {
            // Flutter's getApplicationDocumentsDirectory() maps to
            // <dataDir>/app_flutter on Android, while filesDir is <dataDir>/files.
            val baseDir = filesDir.parentFile ?: return null
            val dir = java.io.File(baseDir, "app_flutter/plugins")
            val file = java.io.File(dir, "$pluginId/$macroFile")
            if (!file.exists()) return null
            val content = file.readText()
            val obj = JSONObject(content)
            val steps = obj.optJSONArray("steps") ?: return null
            val result = mutableListOf<Map<String, Any>>()
            for (i in 0 until steps.length()) {
                result.add(jsonToMap(steps.getJSONObject(i)) as Map<String, Any>)
            }
            result
        } catch (e: Exception) {
            null
        }
    }

    private fun jsonToMap(json: JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = json.get(key)
            map[key] = when (value) {
                is JSONObject -> jsonToMap(value)
                is JSONArray -> jsonToList(value)
                JSONObject.NULL -> null
                else -> value
            }
        }
        return map
    }

    private fun jsonToList(array: JSONArray): List<Any?> {
        val list = mutableListOf<Any?>()
        for (i in 0 until array.length()) {
            val value = array.get(i)
            list.add(when (value) {
                is JSONObject -> jsonToMap(value)
                is JSONArray -> jsonToList(value)
                JSONObject.NULL -> null
                else -> value
            })
        }
        return list
    }

    private fun showBubble(message: String) {
        val wm = windowManager ?: return
        if (floatingView == null || floatingParams == null) return
        val params = floatingParams!!

        if (bubbleView == null) {
            bubbleView = TextView(this).apply {
                setBackgroundResource(android.R.drawable.toast_frame)
                setPadding(24, 16, 24, 16)
                setTextColor(android.graphics.Color.WHITE)
                textSize = 13f
                alpha = 0f
            }
        }

        bubbleView?.text = message

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
            x = params.x + (floatingView?.width ?: 0)
            y = params.y
        }

        try {
            if (bubbleView?.parent == null) {
                wm.addView(bubbleView, bubbleParams)
            } else {
                wm.updateViewLayout(bubbleView, bubbleParams)
            }
            bubbleView?.animate()?.alpha(1f)?.setDuration(150)?.start()
        } catch (_: Exception) {
        }

        mainHandler.removeCallbacks(hideBubbleRunnable)
        mainHandler.postDelayed(hideBubbleRunnable, 2500)
    }

    private fun hideBubble() {
        bubbleView?.let {
            try {
                windowManager?.removeView(it)
            } catch (_: Exception) {
            }
        }
        bubbleView = null
    }

    private fun hideFloatingBall() {
        hideBubble()
        if (floatingView != null) {
            windowManager?.removeView(floatingView)
            floatingView = null
        }
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
