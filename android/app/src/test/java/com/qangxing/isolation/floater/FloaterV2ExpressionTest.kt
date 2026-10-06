package com.qangxing.isolation.floater

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FloaterV2ExpressionTest {

    @Test
    fun fromJson_literal() {
        val expr = FloaterV2Expression.fromJson(mapOf("op" to "literal", "type" to "Dp", "value" to 56))
        assertTrue(expr is LiteralExpression)
        val literal = expr as LiteralExpression
        assertEquals(FloaterValue.Dp(56.0), literal.value)
    }

    @Test
    fun fromJson_var() {
        val expr = FloaterV2Expression.fromJson(mapOf("op" to "var", "name" to "mainBall.center"))
        assertTrue(expr is VarExpression)
        assertEquals("mainBall.center", (expr as VarExpression).name)
    }

    @Test
    fun fromJson_call() {
        val expr = FloaterV2Expression.fromJson(mapOf(
            "op" to "call",
            "name" to "Fan",
            "args" to listOf(
                mapOf("op" to "literal", "type" to "Dp", "value" to 100)
            ),
            "namedArgs" to mapOf(
                "radius" to mapOf("op" to "literal", "type" to "Dp", "value" to 80)
            )
        ))
        assertTrue(expr is CallExpression)
        val call = expr as CallExpression
        assertEquals("Fan", call.name)
        assertEquals(1, call.args.size)
        assertEquals(1, call.namedArgs.size)
    }

    @Test
    fun fromJson_index() {
        val expr = FloaterV2Expression.fromJson(mapOf(
            "op" to "index",
            "target" to mapOf("op" to "var", "name" to "fan"),
            "index" to mapOf("op" to "literal", "type" to "Int", "value" to 0)
        ))
        assertTrue(expr is IndexExpression)
        val index = expr as IndexExpression
        assertTrue(index.target is VarExpression)
        assertEquals(0, (index.index as LiteralExpression).value)
    }

    @Test
    fun fromJson_anchor() {
        val expr = FloaterV2Expression.fromJson(mapOf(
            "op" to "anchor",
            "target" to mapOf("op" to "index", "target" to mapOf("op" to "var", "name" to "fan")),
            "anchor" to "topLeft"
        ))
        assertTrue(expr is AnchorExpression)
        val anchor = expr as AnchorExpression
        assertEquals("topLeft", anchor.anchor)
        assertTrue(anchor.target is IndexExpression)
    }
}
