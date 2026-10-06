package com.qangxing.isolation.floater

import android.content.Context
import kotlin.math.roundToInt

/**
 * Floater DSL v2 类型系统。
 *
 * v2 在语法层面区分 dp/px/deg/ms/Point/Size/Color 等类型，
 * 执行时统一转换为运行时值（像素、毫秒、弧度、ARGB）。
 */
sealed class FloaterValue {
    abstract val type: FloaterType

    data class Dp(val value: Double) : FloaterValue() {
        override val type = FloaterType.Dp
        fun toPx(context: Context): Int = (value * context.resources.displayMetrics.density).roundToInt()
        fun toPxFloat(context: Context): Float = (value * context.resources.displayMetrics.density).toFloat()
    }

    data class Px(val value: Double) : FloaterValue() {
        override val type = FloaterType.Px
        fun toInt(): Int = value.roundToInt()
    }

    data class IntVal(val value: Int) : FloaterValue() {
        override val type = FloaterType.Int
    }

    data class FloatVal(val value: Double) : FloaterValue() {
        override val type = FloaterType.Float
    }

    data class Bool(val value: Boolean) : FloaterValue() {
        override val type = FloaterType.Bool
    }

    data class Str(val value: String) : FloaterValue() {
        override val type = FloaterType.String
    }

    data class Duration(val valueMs: Double) : FloaterValue() {
        override val type = FloaterType.Duration
        fun toLong(): Long = valueMs.toLong()
    }

    data class Angle(val valueDeg: Double) : FloaterValue() {
        override val type = FloaterType.Angle
        fun toRad(): Double = Math.toRadians(valueDeg)
    }

    data class Point(val x: FloaterValue, val y: FloaterValue) : FloaterValue() {
        override val type = FloaterType.Point

        fun toScreenPixels(context: Context): android.graphics.Point {
            val pxX = when (x) {
                is Dp -> x.toPx(context)
                is Px -> x.toInt()
                is IntVal -> x.value
                is FloatVal -> x.value.roundToInt()
                else -> 0
            }
            val pxY = when (y) {
                is Dp -> y.toPx(context)
                is Px -> y.toInt()
                is IntVal -> y.value
                is FloatVal -> y.value.roundToInt()
                else -> 0
            }
            return android.graphics.Point(pxX, pxY)
        }
    }

    data class Size(val width: FloaterValue, val height: FloaterValue) : FloaterValue() {
        override val type = FloaterType.Size

        fun toDpSize(context: Context): android.util.Size {
            val w = when (width) {
                is Dp -> width.toPx(context)
                is Px -> width.toInt()
                is IntVal -> width.value
                else -> 0
            }
            val h = when (height) {
                is Dp -> height.toPx(context)
                is Px -> height.toInt()
                is IntVal -> height.value
                else -> 0
            }
            return android.util.Size(w, h)
        }
    }

    data class Color(val argb: Int) : FloaterValue() {
        override val type = FloaterType.Color
    }

    /**
     * 扇形几何布局。
     */
    data class Fan(
        val center: Point,
        val radius: Dp,
        val startAngle: Angle,
        val sweep: Angle,
        val count: IntVal
    ) : FloaterValue() {
        override val type = FloaterType.Fan

        /** 第 [index] 个 slot 的中心坐标（像素）。 */
        fun slotCenterPx(context: Context, index: Int): android.graphics.Point {
            val n = count.value.coerceAtLeast(1)
            val step = if (n > 1) sweep.valueDeg / (n - 1) else 0.0
            val angleDeg = startAngle.valueDeg + step * index
            val rad = Math.toRadians(angleDeg)
            val radiusPx = radius.toPx(context)
            val centerPx = center.toScreenPixels(context)
            val x = centerPx.x + radiusPx * kotlin.math.cos(rad)
            val y = centerPx.y + radiusPx * kotlin.math.sin(rad)
            return android.graphics.Point(x.roundToInt(), y.roundToInt())
        }
    }

    /**
     * 环形几何布局。
     */
    data class Ring(
        val center: Point,
        val radius: Dp,
        val count: IntVal
    ) : FloaterValue() {
        override val type = FloaterType.Ring

        fun slotCenterPx(context: Context, index: Int): android.graphics.Point {
            val n = count.value.coerceAtLeast(1)
            val angleDeg = if (n > 1) 360.0 / n * index else 0.0
            val rad = Math.toRadians(angleDeg)
            val radiusPx = radius.toPx(context)
            val centerPx = center.toScreenPixels(context)
            val x = centerPx.x + radiusPx * kotlin.math.cos(rad)
            val y = centerPx.y + radiusPx * kotlin.math.sin(rad)
            return android.graphics.Point(x.roundToInt(), y.roundToInt())
        }
    }

    /**
     * 网格几何布局。
     */
    data class Grid(
        val origin: Point,
        val columns: IntVal,
        val spacing: Dp
    ) : FloaterValue() {
        override val type = FloaterType.Grid

        fun slotCenterPx(context: Context, index: Int): android.graphics.Point {
            val cols = columns.value.coerceAtLeast(1)
            val row = index / cols
            val col = index % cols
            val spacingPx = spacing.toPx(context)
            val originPx = origin.toScreenPixels(context)
            return android.graphics.Point(
                originPx.x + col * spacingPx,
                originPx.y + row * spacingPx
            )
        }
    }

    data object Unknown : FloaterValue() {
        override val type = FloaterType.Unknown
    }
}

enum class FloaterType {
    Dp, Px, Int, Float, Bool, String, Duration, Angle, Point, Size, Color, Fan, Ring, Grid, Unknown
}

fun String.toFloaterType(): FloaterType = when (this) {
    "Dp" -> FloaterType.Dp
    "Px" -> FloaterType.Px
    "Int" -> FloaterType.Int
    "Float" -> FloaterType.Float
    "Bool" -> FloaterType.Bool
    "String" -> FloaterType.String
    "Duration" -> FloaterType.Duration
    "Angle" -> FloaterType.Angle
    "Point" -> FloaterType.Point
    "Size" -> FloaterType.Size
    "Color" -> FloaterType.Color
    "Fan" -> FloaterType.Fan
    "Ring" -> FloaterType.Ring
    "Grid" -> FloaterType.Grid
    else -> FloaterType.Unknown
}

fun floaterValueFromJson(json: Map<String, Any?>): FloaterValue {
    val typeName = json["type"] as? String ?: return FloaterValue.Unknown
    val raw = json["value"]
    return when (typeName.toFloaterType()) {
        FloaterType.Dp -> FloaterValue.Dp((raw as Number).toDouble())
        FloaterType.Px -> FloaterValue.Px((raw as Number).toDouble())
        FloaterType.Int -> FloaterValue.IntVal((raw as Number).toInt())
        FloaterType.Float -> FloaterValue.FloatVal((raw as Number).toDouble())
        FloaterType.Bool -> FloaterValue.Bool(raw as Boolean)
        FloaterType.String -> FloaterValue.Str(raw as String)
        FloaterType.Duration -> FloaterValue.Duration((raw as Number).toDouble())
        FloaterType.Angle -> FloaterValue.Angle((raw as Number).toDouble())
        FloaterType.Point -> {
            val list = raw as List<*>
            FloaterValue.Point(
                floaterValueFromJson(list[0] as Map<String, Any?>),
                floaterValueFromJson(list[1] as Map<String, Any?>)
            )
        }
        FloaterType.Size -> {
            val list = raw as List<*>
            FloaterValue.Size(
                floaterValueFromJson(list[0] as Map<String, Any?>),
                floaterValueFromJson(list[1] as Map<String, Any?>)
            )
        }
        FloaterType.Color -> FloaterValue.Color(parseColor(raw as String))
        FloaterType.Fan -> {
            val map = raw as? Map<String, Any?> ?: return FloaterValue.Unknown
            if (map.containsKey("op")) return FloaterValue.Unknown
            FloaterValue.Fan(
                center = parsePointValue(map["center"]) ?: FloaterValue.Point(FloaterValue.Px(0.0), FloaterValue.Px(0.0)),
                radius = parseDpValue(map["radius"]) ?: FloaterValue.Dp(0.0),
                startAngle = parseAngleValue(map["startAngle"]) ?: FloaterValue.Angle(0.0),
                sweep = parseAngleValue(map["sweep"]) ?: FloaterValue.Angle(0.0),
                count = parseIntValue(map["count"]) ?: FloaterValue.IntVal(0)
            )
        }
        FloaterType.Ring -> {
            val map = raw as? Map<String, Any?> ?: return FloaterValue.Unknown
            if (map.containsKey("op")) return FloaterValue.Unknown
            FloaterValue.Ring(
                center = parsePointValue(map["center"]) ?: FloaterValue.Point(FloaterValue.Px(0.0), FloaterValue.Px(0.0)),
                radius = parseDpValue(map["radius"]) ?: FloaterValue.Dp(0.0),
                count = parseIntValue(map["count"]) ?: FloaterValue.IntVal(0)
            )
        }
        FloaterType.Grid -> {
            val map = raw as? Map<String, Any?> ?: return FloaterValue.Unknown
            if (map.containsKey("op")) return FloaterValue.Unknown
            FloaterValue.Grid(
                origin = parsePointValue(map["origin"]) ?: FloaterValue.Point(FloaterValue.Px(0.0), FloaterValue.Px(0.0)),
                columns = parseIntValue(map["columns"]) ?: FloaterValue.IntVal(1),
                spacing = parseDpValue(map["spacing"]) ?: FloaterValue.Dp(0.0)
            )
        }
        FloaterType.Unknown -> FloaterValue.Unknown
    }
}

private fun Map<String, Any?>.floaterValue(key: String): FloaterValue? {
    val value = this[key] as? Map<String, Any?> ?: return null
    return floaterValueFromJson(value)
}

private fun parseScalarValue(value: Any?): FloaterValue? {
    return when (value) {
        is FloaterValue -> value
        is Number -> FloaterValue.Dp(value.toDouble())
        is String -> FloaterValue.Str(value)
        is Boolean -> FloaterValue.Bool(value)
        is Map<*, *> -> {
            val map = value as Map<String, Any?>
            if (map.containsKey("op")) return null
            floaterValueFromJson(map)
        }
        else -> null
    }
}

private fun parsePointValue(value: Any?): FloaterValue.Point? {
    return when (value) {
        is FloaterValue.Point -> value
        is Map<*, *> -> floaterValueFromJson(value as Map<String, Any?>) as? FloaterValue.Point
        is List<*> -> {
            if (value.size >= 2) {
                val x = parseScalarValue(value[0])
                val y = parseScalarValue(value[1])
                if (x != null && y != null) FloaterValue.Point(x, y) else null
            } else null
        }
        else -> null
    }
}

private fun parseDpValue(value: Any?): FloaterValue.Dp? {
    return when (value) {
        is FloaterValue.Dp -> value
        is Number -> FloaterValue.Dp(value.toDouble())
        is Map<*, *> -> floaterValueFromJson(value as Map<String, Any?>) as? FloaterValue.Dp
        else -> null
    }
}

private fun parseAngleValue(value: Any?): FloaterValue.Angle? {
    return when (value) {
        is FloaterValue.Angle -> value
        is Number -> FloaterValue.Angle(value.toDouble())
        is Map<*, *> -> floaterValueFromJson(value as Map<String, Any?>) as? FloaterValue.Angle
        else -> null
    }
}

private fun parseIntValue(value: Any?): FloaterValue.IntVal? {
    return when (value) {
        is FloaterValue.IntVal -> value
        is Number -> FloaterValue.IntVal(value.toInt())
        is Map<*, *> -> floaterValueFromJson(value as Map<String, Any?>) as? FloaterValue.IntVal
        else -> null
    }
}

private fun parseColor(hex: String): Int {
    val clean = hex.removePrefix("#")
    return when (clean.length) {
        6 -> android.graphics.Color.parseColor("#$clean")
        8 -> {
            val a = clean.substring(0, 2).toInt(16)
            val r = clean.substring(2, 4).toInt(16)
            val g = clean.substring(4, 6).toInt(16)
            val b = clean.substring(6, 8).toInt(16)
            android.graphics.Color.argb(a, r, g, b)
        }
        else -> android.graphics.Color.BLACK
    }
}
