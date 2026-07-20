package com.example.isolation

import android.content.Context
import android.graphics.PixelFormat
import android.os.Build
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout

class KeyboardOverlayView(private val context: Context) {
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var keyboardView: View? = null
    private var params: WindowManager.LayoutParams? = null

    private val keysRow1 = listOf("q", "w", "e", "r", "t", "y", "u", "i", "o", "p")
    private val keysRow2 = listOf("a", "s", "d", "f", "g", "h", "j", "k", "l")
    private val keysRow3 = listOf("z", "x", "c", "v", "b", "n", "m")

    fun show() {
        if (keyboardView != null) return

        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = 120
        }

        keyboardView = LayoutInflater.from(context).inflate(R.layout.keyboard_overlay, null)
        setupKeys(keyboardView!!)
        setupDrag(keyboardView!!.findViewById(R.id.keyboard_drag_handle))

        windowManager.addView(keyboardView, params)
    }

    fun hide() {
        if (keyboardView != null) {
            windowManager.removeView(keyboardView)
            keyboardView = null
        }
    }

    private fun setupKeys(view: View) {
        val row1 = view.findViewById<LinearLayout>(R.id.keyboard_row1)
        val row2 = view.findViewById<LinearLayout>(R.id.keyboard_row2)
        val row3 = view.findViewById<LinearLayout>(R.id.keyboard_row3)

        keysRow1.forEach { addKey(row1, it) }
        keysRow2.forEach { addKey(row2, it) }
        keysRow3.forEach { addKey(row3, it) }

        view.findViewById<Button>(R.id.key_space).setOnClickListener {
            InputAccessibilityService.injectKey(context, " ")
        }
        view.findViewById<Button>(R.id.key_backspace).setOnClickListener {
            InputAccessibilityService.injectBackspace(context)
        }
        view.findViewById<Button>(R.id.key_enter).setOnClickListener {
            InputAccessibilityService.injectKey(context, "\n")
        }
        view.findViewById<Button>(R.id.key_close).setOnClickListener {
            hide()
        }
    }

    private fun addKey(row: LinearLayout, key: String) {
        val button = Button(context).apply {
            text = key
            textSize = 14f
            isAllCaps = false
            setTextColor(android.graphics.Color.BLACK)
            background = context.getDrawable(R.drawable.key_background)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                setMargins(4, 4, 4, 4)
            }
            setOnClickListener {
                animate().scaleX(0.9f).scaleY(0.9f).setDuration(80).withEndAction {
                    animate().scaleX(1f).scaleY(1f).setDuration(80).start()
                }.start()
                InputAccessibilityService.injectKey(context, key)
            }
        }
        row.addView(button)
    }

    private fun setupDrag(handle: View) {
        var initialY = 0
        var initialTouchY = 0f
        handle.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialY = params?.y ?: 0
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params?.y = initialY - (event.rawY - initialTouchY).toInt()
                    keyboardView?.let { windowManager.updateViewLayout(it, params) }
                    true
                }
                else -> false
            }
        }
    }
}
