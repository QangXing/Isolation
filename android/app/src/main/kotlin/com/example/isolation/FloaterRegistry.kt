package com.example.isolation

class FloaterRegistry {
    data class Handler(val event: String, val children: List<Map<String, Any>>, val elseChildren: List<Map<String, Any>>?)

    private val handlers = mutableMapOf<String, MutableList<Handler>>()

    fun clear() = handlers.clear()

    /** 普通事件注册（用于宏执行器内的 floater 事件）。 */
    fun register(event: String, children: List<Map<String, Any>>, elseChildren: List<Map<String, Any>>? = null) {
        handlers.getOrPut(event) { mutableListOf() }.add(Handler(event, children, elseChildren))
    }

    /** 按球名隔离的事件注册（用于多球插件），避免主/副球点击事件串扰。key 格式："ballName:event"。 */
    fun registerBallEvent(ballName: String, event: String, children: List<Map<String, Any>>, elseChildren: List<Map<String, Any>>? = null) {
        val key = "$ballName:$event"
        handlers.getOrPut(key) { mutableListOf() }.add(Handler(event, children, elseChildren))
    }

    fun get(event: String): List<Handler> = handlers[event] ?: emptyList()

    fun getBallEvent(ballName: String, event: String): List<Handler> = handlers["$ballName:$event"] ?: emptyList()
}
