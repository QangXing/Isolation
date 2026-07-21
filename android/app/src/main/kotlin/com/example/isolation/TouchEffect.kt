package com.example.isolation

/**
 * 宏执行时在屏幕上显示的触摸反馈效果。
 * 坐标均为屏幕像素坐标系（左上角为原点）。
 */
sealed class TouchEffect {
    /**
     * 点击效果：在 [x], [y] 处显示一个扩散并淡出的圆环。
     */
    data class Click(val x: Float, val y: Float) : TouchEffect()

    /**
     * 滑动效果：从 [startX], [startY] 到 [endX], [endY] 绘制一条渐隐的轨迹，
     * 并在起点和终点各显示一个小圆点。
     */
    data class Swipe(
        val startX: Float,
        val startY: Float,
        val endX: Float,
        val endY: Float
    ) : TouchEffect()
}
