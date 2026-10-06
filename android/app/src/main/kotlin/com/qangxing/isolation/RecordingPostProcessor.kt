package com.qangxing.isolation

/**
 * 录制指令后处理器：把 [RecordingSession] 收集的原始步骤按录制模式转换为最终 DSL 指令。
 *
 * - 简单模式（simple）：只产出确定性最高的基础指令 click / longPressAt / swipe / back / home；
 * - 复杂模式（complex）：对有点击节点补全的步骤保留为 clickNode（Flutter 侧 convertLegacySteps
 *   会自动转换为 waitForColor + findText 增强指令），并对系统键补充 wait 等待步骤，让宏更稳健。
 */
object RecordingPostProcessor {

    fun process(
        raw: List<RecordingSession.RawStep>,
        mode: RecordingSession.Mode,
        captureColors: Boolean
    ): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        for ((index, rs) in raw.withIndex()) {
            val step = rs.step
            val type = step["type"] as? String ?: continue

            // 输出当前步骤本身（不再携带 delay 字段）
            when (type) {
                "click", "clickNode" -> out.add(buildClickStep(step, mode, captureColors))
                // 录制中的"标记"落为一条 print 注释步骤，便于在编辑页定位；不带 delay，不打乱后续节奏
                "mark" -> out.add(mapOf("type" to "print", "message" to "▶ ${step["name"] ?: "标记"}"))
                "longPressAt", "swipe" -> out.add(nonNull(step).minus("delay"))
                "back", "home" -> {
                    out.add(nonNull(step).minus("delay"))
                    if (mode == RecordingSession.Mode.COMPLEX) {
                        // 系统键后等待页面稳定，避免下一操作落在转场动画上
                        out.add(mapOf("type" to "wait", "duration" to 800L))
                    }
                }
            }

            // 把步骤间延迟作为后置 wait：当前步骤与下一步之间的间隔，跟在当步骤后面。
            // 最后一步到结束录制的间隔由 RecordingSession.finish 单独补齐，避免重复。
            val nextDelay = (raw.getOrNull(index + 1)?.step?.get("delay") as? Number)?.toLong() ?: 0L
            if (nextDelay > 0) {
                out.add(mapOf("type" to "wait", "duration" to nextDelay))
            }
        }
        return out
    }

    private fun buildClickStep(
        step: Map<String, Any?>,
        mode: RecordingSession.Mode,
        captureColors: Boolean
    ): Map<String, Any> {
        // 复杂模式下辅助服务已把点击补全为 clickNode（含 target / color）
        if (mode == RecordingSession.Mode.COMPLEX && step["type"] == "clickNode") {
            val clickNode = mutableMapOf<String, Any>(
                "type" to "clickNode"
            )
            step["target"]?.let { clickNode["target"] = it }
            if (captureColors) step["color"]?.let { clickNode["color"] = it }
            return clickNode
        }
        // 简单模式（或未补全的复杂模式点击）：输出坐标 click
        return nonNull(mapOf(
            "type" to "click",
            "x" to step["x"],
            "y" to step["y"]
        ))
    }

    private fun nonNull(step: Map<String, Any?>): Map<String, Any> {
        return step.filterValues { it != null }.mapValues { it.value!! }
    }
}
