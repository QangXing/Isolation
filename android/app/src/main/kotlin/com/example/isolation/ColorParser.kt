package com.example.isolation

/** 把 DSL 中的颜色字面量解析为 0xRRGGBB 整数。支持 0xFF0000 / #FF0000 / 16711680 */
internal object ColorParser {
    fun parseColor(value: Any): Int {
        return when (value) {
            is Number -> value.toInt()
            is String -> {
                val s = value.removePrefix("#")
                if (s.startsWith("0x") || s.startsWith("0X")) {
                    s.substring(2).toInt(16)
                } else if (s.length == 6 || s.length == 8) {
                    s.toInt(16)
                } else {
                    s.toIntOrNull() ?: 0
                }
            }
            else -> 0
        }
    }
}
