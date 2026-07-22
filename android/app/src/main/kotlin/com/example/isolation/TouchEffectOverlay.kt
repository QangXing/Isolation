package com.example.isolation

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View

/**
 * 全屏透明覆盖层，用于绘制宏执行时的点击/滑动反馈动画。
 *
 * 每个效果由一个 [ActiveEffect] 表示，通过 [postEffect] 加入队列，
 * 在约 500ms 内完成扩散/淡出后自动移除。
 */
class TouchEffectOverlay(context: Context) : View(context) {

    private val effects = mutableListOf<ActiveEffect>()
    private val pendingEffects = mutableListOf<TouchEffect>()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.DITHER_FLAG)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val invalidateRunnable = Runnable { invalidateAndSchedule() }
    @Volatile
    private var isOverlayAttached = false

    private companion object {
        const val CLICK_DURATION_MS = 450L
        const val SWIPE_DURATION_MS = 550L
        const val CLICK_START_RADIUS_DP = 6f
        const val CLICK_END_RADIUS_DP = 36f
        const val SWIPE_DOT_RADIUS_DP = 5f
        const val SWIPE_LINE_WIDTH_DP = 3f
        const val FRAME_INTERVAL_MS = 16L
    }

    init {
        // 使用软件渲染，保证 setShadowLayer 对圆/线等基础图形也能生效
        setLayerType(LAYER_TYPE_SOFTWARE, null)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        isOverlayAttached = true
        // 把 attach 前暂存的效果一次性放入队列，并启动刷新
        val now = SystemClock.elapsedRealtime()
        pendingEffects.forEach { effect ->
            val duration = when (effect) {
                is TouchEffect.Click -> CLICK_DURATION_MS
                is TouchEffect.Swipe -> SWIPE_DURATION_MS
            }
            effects.add(ActiveEffect(effect, now, duration))
        }
        pendingEffects.clear()
        if (effects.isNotEmpty()) {
            invalidateAndSchedule()
        }
    }

    /**
     * 重置画笔公共属性，避免阴影等状态泄漏到下一次绘制。
     */
    private fun resetPaint() {
        paint.reset()
        paint.isAntiAlias = true
        paint.isDither = true
    }

    fun postEffect(effect: TouchEffect) {
        if (!isOverlayAttached) {
            pendingEffects.add(effect)
            return
        }
        val now = SystemClock.elapsedRealtime()
        val duration = when (effect) {
            is TouchEffect.Click -> CLICK_DURATION_MS
            is TouchEffect.Swipe -> SWIPE_DURATION_MS
        }
        effects.add(ActiveEffect(effect, now, duration))
        invalidateAndSchedule()
    }

    private fun invalidateAndSchedule() {
        removeCallbacks(invalidateRunnable)
        invalidate()
        if (effects.isNotEmpty()) {
            postDelayed(invalidateRunnable, FRAME_INTERVAL_MS)
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val now = SystemClock.elapsedRealtime()
        val density = resources.displayMetrics.density
        val iterator = effects.iterator()
        var hasActive = false

        while (iterator.hasNext()) {
            val active = iterator.next()
            val elapsed = now - active.startTime
            val progress = (elapsed.toFloat() / active.duration).coerceIn(0f, 1f)

            if (elapsed >= active.duration) {
                iterator.remove()
                continue
            }
            hasActive = true

            when (val effect = active.effect) {
                is TouchEffect.Click -> drawClick(canvas, effect, progress, density)
                is TouchEffect.Swipe -> drawSwipe(canvas, effect, progress, density)
            }
        }

        if (hasActive) {
            postDelayed(invalidateRunnable, FRAME_INTERVAL_MS)
        }
    }

    private fun drawClick(
        canvas: Canvas,
        effect: TouchEffect.Click,
        progress: Float,
        density: Float
    ) {
        // 扩散：半径从 6dp -> 36dp
        val startRadius = CLICK_START_RADIUS_DP * density
        val endRadius = CLICK_END_RADIUS_DP * density
        val radius = startRadius + (endRadius - startRadius) * progress

        // 淡出：alpha 从 0.9 -> 0
        val alpha = ((1f - progress) * 0.9f * 255).toInt()

        // 先画深色轮廓/阴影，保证浅色背景也可见
        resetPaint()
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 5f * density
        paint.color = (0xFF000000).toInt()
        paint.alpha = alpha
        paint.setShadowLayer(6f * density, 0f, 0f, (0xFF000000).toInt())
        canvas.drawCircle(effect.x, effect.y, radius, paint)

        // 再画白色主环
        resetPaint()
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 3f * density
        paint.color = (0xFFFFFFFF).toInt()
        paint.alpha = alpha
        canvas.drawCircle(effect.x, effect.y, radius, paint)
    }

    private fun drawSwipe(
        canvas: Canvas,
        effect: TouchEffect.Swipe,
        progress: Float,
        density: Float
    ) {
        val dotRadius = SWIPE_DOT_RADIUS_DP * density
        val lineWidth = SWIPE_LINE_WIDTH_DP * density
        val alpha = ((1f - progress) * 0.85f * 255).toInt()

        // 深色轮廓
        resetPaint()
        paint.style = Paint.Style.FILL
        paint.color = (0xFF000000).toInt()
        paint.alpha = alpha
        paint.setShadowLayer(5f * density, 0f, 0f, (0xFF000000).toInt())
        canvas.drawCircle(effect.startX, effect.startY, dotRadius + 1.5f * density, paint)
        canvas.drawCircle(effect.endX, effect.endY, dotRadius + 1.5f * density, paint)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = lineWidth + 2.5f * density
        paint.strokeCap = Paint.Cap.ROUND
        canvas.drawLine(effect.startX, effect.startY, effect.endX, effect.endY, paint)

        // 白色主图形
        resetPaint()
        paint.style = Paint.Style.FILL
        paint.color = (0xFFFFFFFF).toInt()
        paint.alpha = alpha
        canvas.drawCircle(effect.startX, effect.startY, dotRadius, paint)
        canvas.drawCircle(effect.endX, effect.endY, dotRadius, paint)

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = lineWidth
        paint.strokeCap = Paint.Cap.ROUND
        canvas.drawLine(effect.startX, effect.startY, effect.endX, effect.endY, paint)
    }

    private data class ActiveEffect(
        val effect: TouchEffect,
        val startTime: Long,
        val duration: Long
    )
}
