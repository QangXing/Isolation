package com.qangxing.isolation

/**
 * 录制指令后处理器：把 [RecordingSession] 收集的原始步骤按录制模式转换为最终 DSL 指令。
 *
 * - 简单模式（simple）：只产出确定性最高的基础指令 click / longPressAt / swipe / back / home；
 * - 复杂模式（complex）：对有点击节点补全的步骤保留为 clickNode（Flutter 侧 convertLegacySteps
 *   会自动转换为 findText / ifColorAt 增强指令），并对系统键补充 wait 等待步骤，让宏更稳健。
 */
object RecordingPostProcessor {

    fun process(
        raw: List<RecordingSession.RawStep>,
        mode: RecordingSession.Mode,
        captureColors: Boolean
    ): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        for (rs in raw) {
            val step = rs.step
            val type = step["type"] as? String ?: continue
            val delay = (step["delay"] as? Number)?.toLong() ?: 0L
            when (type) {
                "click", "clickNode" -> out.add(buildClickStep(step, delay, mode, captureColors))
                "longPressAt", "swipe" -> out.add(nonNull(step))
                "back", "home" -> {
                    out.add(nonNull(step))
                    if (mode == RecordingSession.Mode.COMPLEX) {
                        // 系统键后等待页面稳定，避免下一操作落在转场动画上
                        out.add(mapOf("type" to "wait", "duration" to 800L))
                    }
                }
            }
        }
        return out
    }

    private fun buildClickStep(
        step: Map<String, Any?>,
        delay: Long,
        mode: RecordingSession.Mode,
        captureColors: Boolean
    ): Map<String, Any> {
        // 复杂模式下辅助服务已把点击补全为 clickNode（含 target / color）
        if (mode == RecordingSession.Mode.COMPLEX && step["type"] == "clickNode") {
            val clickNode = mutableMapOf<String, Any>(
                "type" to "clickNode",
                "delay" to delay
            )
            step["target"]?.let { clickNode["target"] = it }
            if (captureColors) step["color"]?.let { clickNode["color"] = it }
            return clickNode
        }
        // 简单模式（或未补全的复杂模式点击）：输出坐标 click
        return mapOf(
            "type" to "click",
            "x" to step["x"],
            "y" to step["y"],
            "delay" to delay
        )
    }

    private fun nonNull(step: Map<String, Any?>): Map<String, Any> {
        return step.filterValues { it != null }.mapValues { it.value!! }
    }
}
