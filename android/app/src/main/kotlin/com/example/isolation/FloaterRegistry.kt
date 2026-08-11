package com.example.isolation

class FloaterRegistry {
    data class Handler(val event: String, val children: List<Map<String, Any>>, val elseChildren: List<Map<String, Any>>?)

    private val handlers = mutableMapOf<String, MutableList<Handler>>()

    fun clear() = handlers.clear()

    fun register(event: String, children: List<Map<String, Any>>, elseChildren: List<Map<String, Any>>? = null) {
        handlers.getOrPut(event) { mutableListOf() }.add(Handler(event, children, elseChildren))
    }

    fun get(event: String): List<Handler> = handlers[event] ?: emptyList()
}
