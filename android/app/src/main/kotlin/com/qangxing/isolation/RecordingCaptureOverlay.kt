package com.qangxing.isolation

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Path
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Toast

/**
 * 全屏透明触摸捕获层：录制中拦截所有触摸，判定手势（点击 / 长按 / 滑动），
 * 产出 DSL 步骤，并尽量通过辅助服务的 [android.accessibilityservice.GestureDescription]
 * 原样回放给系统，保证目标 App 正常响应。
 *
 * 层级约定：本层由 [RecordingSession.start] 先挂载，录制悬浮球后挂载，
 * 因此触摸到主球/副球时由悬浮球窗口优先处理，不会落到本层、也不会产生录制步骤。
 */
class RecordingCaptureOverlay private constructor(context: Context) : View(context) {

    companion object {
        private const val TAG = "RecordingCaptureOverlay"
        /** 判定为点击的最大位移（px） */
        private const val CLICK_SLOP_PX = 24
        /** 超过该时长且未移动 → 长按 */
        private const val LONG_PRESS_MS = 500L
        /** 回放长按的最大时长（过长的按住无意义，反而拖慢回放） */
        private const val MAX_LONG_PRESS_REPLAY_MS = 800L
        /** 点击回放的最长本地屏蔽窗口（ms），手势实际完成后会立即解除屏蔽 */
        private const val MAX_TAP_SUPPRESS_MS = 120L
        /** 长按回放的最长本地屏蔽窗口（ms） */
        private const val MAX_LONG_PRESS_SUPPRESS_MS = 350L
        /** 滑动回放的最长本地屏蔽窗口（ms） */
        private const val MAX_SWIPE_SUPPRESS_MS = 500L

        @Volatile
        private var instance: RecordingCaptureOverlay? = null

        /** 挂载捕获层。失败返回 false。 */
        fun show(context: Context): Boolean {
            if (instance != null) return true
            val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
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
            }
            val overlay = RecordingCaptureOverlay(context.applicationContext)
            return try {
                wm.addView(overlay, params)
                instance = overlay
                true
            } catch (e: Exception) {
                Log.e(TAG, "添加捕获层失败", e)
                false
            }
        }

        /** 移除捕获层（暂停录制 / 结束录制时调用） */
        fun hide() {
            val overlay = instance ?: return
            instance = null
            try {
                val wm = overlay.context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                wm.removeView(overlay)
            } catch (e: Exception) {
                Log.e(TAG, "移除捕获层失败", e)
            }
        }
    }

    private var downX = 0f
    private var downY = 0f
    private var downTime = 0L
    /** 回放手势期间屏蔽本层触摸，避免把注入的手势再次录制成新步骤。 */
    private var suppressUntil = 0L
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun suppressDuringReplay(maxDuration: Long) {
        suppressUntil = SystemClock.elapsedRealtime() + maxDuration
    }

    private fun endSuppressReplay() {
        suppressUntil = 0L
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (SystemClock.elapsedRealtime() < suppressUntil) return true
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                downTime = event.eventTime
                return true
            }
            MotionEvent.ACTION_MOVE -> return true
            MotionEvent.ACTION_UP -> {
                val endX = event.x
                val endY = event.y
                val duration = (event.eventTime - downTime).coerceAtLeast(0L)
                val dist = kotlin.math.hypot(
                    (endX - downX).toDouble(),
                    (endY - downY).toDouble()
                ).toFloat()
                if (dist <= CLICK_SLOP_PX) {
                    val x = downX.toInt()
                    val y = downY.toInt()
                    if (duration >= LONG_PRESS_MS) {
                        // 长按
                        RecordingSession.onLongPressCaptured(x, y, duration)
                        if (RecordingSession.replayGestures) {
                            val replay = duration.coerceAtMost(MAX_LONG_PRESS_REPLAY_MS)
                            suppressDuringReplay(MAX_LONG_PRESS_SUPPRESS_MS)
                            replayLongPress(x, y, replay)
                        }
                    } else {
                        // 点击：记录坐标点击；回放产生的 TYPE_VIEW_CLICKED 事件会补全节点信息
                        RecordingSession.onTapCaptured(x, y)
                        if (RecordingSession.replayGestures) {
                            suppressDuringReplay(MAX_TAP_SUPPRESS_MS)
                            replayTap(x, y)
                        }
                    }
                } else {
                    // 滑动
                    val sx = downX.toInt()
                    val sy = downY.toInt()
                    RecordingSession.onSwipeCaptured(sx, sy, endX.toInt(), endY.toInt(), duration)
                    if (RecordingSession.replayGestures) {
                        suppressDuringReplay(MAX_SWIPE_SUPPRESS_MS)
                        replaySwipe(sx, sy, endX.toInt(), endY.toInt(), duration)
                    }
                }
                return true
            }
            MotionEvent.ACTION_CANCEL -> return true
        }
        return true
    }

    private fun onReplayResult(success: Boolean, action: String) {
        endSuppressReplay()
        if (!success) {
            Log.w(TAG, "$action 回放被系统取消，目标应用可能未响应")
            mainHandler.post {
                Toast.makeText(context, "点击未生效，请检查辅助功能是否已开启", Toast.LENGTH_SHORT).show()
            }
        }
    }

    // ── 回放：把捕获到的手势原样派发给系统 ──

    private fun replayTap(x: Int, y: Int) {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        // 点击回放不抑制辅助事件：需要 TYPE_VIEW_CLICKED 补全节点信息
        val dispatched = InputAccessibilityService.dispatchReplayGesture(path, 100L, suppressEvents = false) { success ->
            onReplayResult(success, "点击")
        }
        if (!dispatched) {
            // 服务未就绪时 dispatchGesture 直接返回 false，不会触发回调，需要手动解除屏蔽
            endSuppressReplay()
            mainHandler.post {
                Toast.makeText(context, "辅助功能未就绪，请点击录制参数页的\"检查权限\"", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun replayLongPress(x: Int, y: Int, duration: Long) {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val dispatched = InputAccessibilityService.dispatchReplayGesture(path, duration, suppressEvents = true) { success ->
            onReplayResult(success, "长按")
        }
        if (!dispatched) endSuppressReplay()
    }

    private fun replaySwipe(sx: Int, sy: Int, ex: Int, ey: Int, duration: Long) {
        val path = Path().apply {
            moveTo(sx.toFloat(), sy.toFloat())
            lineTo(ex.toFloat(), ey.toFloat())
        }
        val replayDuration = duration.coerceAtMost(2000L)
        val dispatched = InputAccessibilityService.dispatchReplayGesture(path, replayDuration, suppressEvents = true) { success ->
            onReplayResult(success, "滑动")
        }
        if (!dispatched) endSuppressReplay()
    }
}
