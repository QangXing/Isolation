package com.qangxing.isolation

/** 把 DSL 中的颜色字面量解析为 0xRRGGBB 整数。支持 0xFF0000 / #FF0000 / 16711680 */
internal object ColorParser {
    fun parseColor(value: Any): Int {
        return when (value) {
            is Number -> value.toInt()
            is String -> {
                val s = value.removePrefix("#")
                if (s.startsWith("0x") || s.startsWith("0X")) {
                    // 8 位 ARGB 超过 Int.MAX_VALUE，按无符号解析再截断为 Int
                    s.substring(2).toLong(16).toInt()
                } else if (s.length == 6 || s.length == 8) {
                    s.toLong(16).toInt()
                } else {
                    s.toIntOrNull() ?: 0
                }
            }
            else -> 0
        }
    }
}
