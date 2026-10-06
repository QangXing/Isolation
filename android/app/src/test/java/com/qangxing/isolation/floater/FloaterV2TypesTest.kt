package com.qangxing.isolation.floater

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FloaterV2TypesTest {

    @Test
    fun parse_basicTypes() {
        assertEquals(FloaterValue.Dp(12.0), floaterValueFromJson(mapOf("type" to "Dp", "value" to 12)))
        assertEquals(FloaterValue.Px(5.0), floaterValueFromJson(mapOf("type" to "Px", "value" to 5)))
        assertEquals(FloaterValue.IntVal(7), floaterValueFromJson(mapOf("type" to "Int", "value" to 7)))
        assertEquals(FloaterValue.FloatVal(3.14), floaterValueFromJson(mapOf("type" to "Float", "value" to 3.14)))
        assertEquals(FloaterValue.Bool(true), floaterValueFromJson(mapOf("type" to "Bool", "value" to true)))
        assertEquals(FloaterValue.Str("hello"), floaterValueFromJson(mapOf("type" to "String", "value" to "hello")))
        assertEquals(FloaterValue.Duration(260.0), floaterValueFromJson(mapOf("type" to "Duration", "value" to 260)))
        assertEquals(FloaterValue.Angle(90.0), floaterValueFromJson(mapOf("type" to "Angle", "value" to 90)))
    }

    @Test
    fun parse_pointAndSize() {
        val pointJson = mapOf(
            "type" to "Point",
            "value" to listOf(
                mapOf("type" to "Dp", "value" to 100),
                mapOf("type" to "Dp", "value" to 200)
            )
        )
        assertEquals(
            FloaterValue.Point(FloaterValue.Dp(100.0), FloaterValue.Dp(200.0)),
            floaterValueFromJson(pointJson)
        )

        val sizeJson = mapOf(
            "type" to "Size",
            "value" to listOf(
                mapOf("type" to "Dp", "value" to 48),
                mapOf("type" to "Dp", "value" to 56)
            )
        )
        assertEquals(
            FloaterValue.Size(FloaterValue.Dp(48.0), FloaterValue.Dp(56.0)),
            floaterValueFromJson(sizeJson)
        )
    }

    @Test
    fun parse_fanWithTypedMaps() {
        val fanJson = mapOf(
            "type" to "Fan",
            "value" to mapOf(
                "center" to mapOf("type" to "Point", "value" to listOf(
                    mapOf("type" to "Dp", "value" to 100),
                    mapOf("type" to "Dp", "value" to 200)
                )),
                "radius" to mapOf("type" to "Dp", "value" to 80),
                "startAngle" to mapOf("type" to "Angle", "value" to 0),
                "sweep" to mapOf("type" to "Angle", "value" to 90),
                "count" to mapOf("type" to "Int", "value" to 3)
            )
        )

        val value = floaterValueFromJson(fanJson) as FloaterValue.Fan
        assertEquals(FloaterValue.Dp(80.0), value.radius)
        assertEquals(FloaterValue.Angle(90.0), value.sweep)
        assertEquals(FloaterValue.IntVal(3), value.count)
    }

    @Test
    fun parse_fanWithLooseListsAndNumbers() {
        val fanJson = mapOf(
            "type" to "Fan",
            "value" to mapOf(
                "center" to listOf(100, 200),
                "radius" to 80,
                "startAngle" to 0,
                "sweep" to 90,
                "count" to 3
            )
        )

        val value = floaterValueFromJson(fanJson) as FloaterValue.Fan
        assertEquals(FloaterValue.Dp(80.0), value.radius)
        assertEquals(FloaterValue.Angle(90.0), value.sweep)
        assertEquals(FloaterValue.IntVal(3), value.count)
    }

    @Test
    fun parse_ringAndGrid() {
        val ringJson = mapOf(
            "type" to "Ring",
            "value" to mapOf(
                "center" to listOf(50, 50),
                "radius" to 100,
                "count" to 5
            )
        )
        val ring = floaterValueFromJson(ringJson) as FloaterValue.Ring
        assertEquals(FloaterValue.Dp(100.0), ring.radius)
        assertEquals(FloaterValue.IntVal(5), ring.count)

        val gridJson = mapOf(
            "type" to "Grid",
            "value" to mapOf(
                "origin" to listOf(0, 0),
                "columns" to 2,
                "spacing" to 16
            )
        )
        val grid = floaterValueFromJson(gridJson) as FloaterValue.Grid
        assertEquals(FloaterValue.IntVal(2), grid.columns)
        assertEquals(FloaterValue.Dp(16.0), grid.spacing)
    }

    @Test
    fun parse_deferredExpression_returnsUnknown() {
        val json = mapOf(
            "type" to "Fan",
            "value" to mapOf(
                "op" to "call",
                "name" to "Fan",
                "args" to listOf(mapOf("op" to "var", "name" to "mainBall.center"))
            )
        )
        assertTrue(floaterValueFromJson(json) is FloaterValue.Unknown)
    }
}
