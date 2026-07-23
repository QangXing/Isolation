package com.example.isolation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExpressionEvaluatorTest {

    @Test
    fun evaluate_arithmeticAndComparison_scorePlusOneGreaterThanFive_returnsTrue() {
        val expr = mapOf(
            "op" to "binary",
            "operator" to ">",
            "left" to mapOf(
                "op" to "binary",
                "operator" to "+",
                "left" to mapOf("op" to "var", "name" to "score"),
                "right" to mapOf("op" to "literal", "value" to 1)
            ),
            "right" to mapOf("op" to "literal", "value" to 5)
        )
        val variables = mapOf("score" to Variable.Number(3.0))

        val result = ExpressionEvaluator.evaluate(expr, variables)

        assertEquals(Variable.Number(1.0), result)
        assertTrue(ExpressionEvaluator.toBoolean(result))
    }

    @Test
    fun evaluate_arithmeticAndComparison_scorePlusOneGreaterThanFiveWithLowScore_returnsFalse() {
        val expr = mapOf(
            "op" to "binary",
            "operator" to ">",
            "left" to mapOf(
                "op" to "binary",
                "operator" to "+",
                "left" to mapOf("op" to "var", "name" to "score"),
                "right" to mapOf("op" to "literal", "value" to 1)
            ),
            "right" to mapOf("op" to "literal", "value" to 5)
        )
        val variables = mapOf("score" to Variable.Number(2.0))

        val result = ExpressionEvaluator.evaluate(expr, variables)

        assertEquals(Variable.Number(0.0), result)
        assertFalse(ExpressionEvaluator.toBoolean(result))
    }

    @Test
    fun evaluate_colorEquality_sameColors_returnsTrue() {
        val expr = mapOf(
            "op" to "binary",
            "operator" to "==",
            "left" to mapOf("op" to "var", "name" to "colorA"),
            "right" to mapOf("op" to "var", "name" to "colorB")
        )
        val variables = mapOf(
            "colorA" to Variable.Color(0xFF0000),
            "colorB" to Variable.Color(0xFF0000)
        )

        val result = ExpressionEvaluator.evaluate(expr, variables)

        assertEquals(Variable.Number(1.0), result)
        assertTrue(ExpressionEvaluator.toBoolean(result))
    }

    @Test
    fun evaluate_colorEquality_differentColors_returnsFalse() {
        val expr = mapOf(
            "op" to "binary",
            "operator" to "==",
            "left" to mapOf("op" to "var", "name" to "colorA"),
            "right" to mapOf("op" to "var", "name" to "colorB")
        )
        val variables = mapOf(
            "colorA" to Variable.Color(0xFF0000),
            "colorB" to Variable.Color(0x00FF00)
        )

        val result = ExpressionEvaluator.evaluate(expr, variables)

        assertEquals(Variable.Number(0.0), result)
        assertFalse(ExpressionEvaluator.toBoolean(result))
    }

    @Test
    fun evaluate_colorInequality_differentColors_returnsTrue() {
        val expr = mapOf(
            "op" to "binary",
            "operator" to "!=",
            "left" to mapOf("op" to "var", "name" to "colorA"),
            "right" to mapOf("op" to "var", "name" to "colorB")
        )
        val variables = mapOf(
            "colorA" to Variable.Color(0xFF0000),
            "colorB" to Variable.Color(0x00FF00)
        )

        val result = ExpressionEvaluator.evaluate(expr, variables)

        assertEquals(Variable.Number(1.0), result)
        assertTrue(ExpressionEvaluator.toBoolean(result))
    }

    @Test
    fun evaluate_logicalAnd_bothTrue_returnsTrue() {
        val expr = mapOf(
            "op" to "binary",
            "operator" to "&&",
            "left" to mapOf("op" to "literal", "value" to 1),
            "right" to mapOf("op" to "literal", "value" to 2)
        )

        val result = ExpressionEvaluator.evaluate(expr, emptyMap())

        assertEquals(Variable.Number(1.0), result)
        assertTrue(ExpressionEvaluator.toBoolean(result))
    }

    @Test
    fun evaluate_logicalAnd_oneFalse_returnsFalse() {
        val expr = mapOf(
            "op" to "binary",
            "operator" to "&&",
            "left" to mapOf("op" to "literal", "value" to 1),
            "right" to mapOf("op" to "literal", "value" to 0)
        )

        val result = ExpressionEvaluator.evaluate(expr, emptyMap())

        assertEquals(Variable.Number(0.0), result)
        assertFalse(ExpressionEvaluator.toBoolean(result))
    }

    @Test
    fun evaluate_logicalOr_oneTrue_returnsTrue() {
        val expr = mapOf(
            "op" to "binary",
            "operator" to "||",
            "left" to mapOf("op" to "literal", "value" to 0),
            "right" to mapOf("op" to "literal", "value" to 1)
        )

        val result = ExpressionEvaluator.evaluate(expr, emptyMap())

        assertEquals(Variable.Number(1.0), result)
        assertTrue(ExpressionEvaluator.toBoolean(result))
    }

    @Test
    fun evaluate_logicalOr_bothFalse_returnsFalse() {
        val expr = mapOf(
            "op" to "binary",
            "operator" to "||",
            "left" to mapOf("op" to "literal", "value" to 0),
            "right" to mapOf("op" to "literal", "value" to 0)
        )

        val result = ExpressionEvaluator.evaluate(expr, emptyMap())

        assertEquals(Variable.Number(0.0), result)
        assertFalse(ExpressionEvaluator.toBoolean(result))
    }

    @Test
    fun evaluate_logicalNot_true_returnsFalse() {
        val expr = mapOf(
            "op" to "unary",
            "operator" to "!",
            "right" to mapOf("op" to "literal", "value" to 1)
        )

        val result = ExpressionEvaluator.evaluate(expr, emptyMap())

        assertEquals(Variable.Number(0.0), result)
        assertFalse(ExpressionEvaluator.toBoolean(result))
    }

    @Test
    fun evaluate_unaryNegation_number_returnsNegated() {
        val expr = mapOf(
            "op" to "unary",
            "operator" to "-",
            "right" to mapOf("op" to "literal", "value" to 5)
        )

        val result = ExpressionEvaluator.evaluate(expr, emptyMap())

        assertEquals(Variable.Number(-5.0), result)
    }

    @Test
    fun evaluate_unknownVariable_returnsNull() {
        val expr = mapOf("op" to "var", "name" to "missing")

        val result = ExpressionEvaluator.evaluate(expr, emptyMap())

        assertNull(result)
    }
}
