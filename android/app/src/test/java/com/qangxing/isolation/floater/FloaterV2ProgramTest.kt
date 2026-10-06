package com.qangxing.isolation.floater

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FloaterV2ProgramTest {

    @Test
    fun fromJson_programWithStatesAndTransitions() {
        val json = mapOf(
            "dslVersion" to 2,
            "pluginId" to "fan-menu-v2",
            "variables" to listOf<Map<String, Any?>>(
                mapOf(
                    "name" to "offset",
                    "type" to mapOf("kind" to "Int"),
                    "value" to mapOf("type" to "Int", "value" to 10),
                    "mutable" to false,
                    "local" to false
                )
            ),
            "balls" to listOf(
                mapOf(
                    "name" to "mainBall",
                    "role" to "Main",
                    "properties" to mapOf<String, Any?>(
                        "size" to mapOf("expression" to mapOf("op" to "literal", "type" to "Dp", "value" to 56))
                    ),
                    "eventHandlers" to mapOf<String, Any?>()
                )
            ),
            "events" to listOf<Map<String, Any?>>(),
            "states" to listOf(
                mapOf(
                    "name" to "collapsed",
                    "body" to listOf(
                        mapOf(
                            "type" to "multiSetProperty",
                            "ballNames" to listOf("sub1", "sub2"),
                            "property" to "visible",
                            "value" to mapOf("op" to "literal", "type" to "Bool", "value" to false)
                        )
                    ),
                    "localVariables" to listOf<String>()
                ),
                mapOf(
                    "name" to "expanded",
                    "body" to listOf(
                        mapOf(
                            "type" to "let",
                            "name" to "fan",
                            "typeInfo" to mapOf("kind" to "Fan"),
                            "value" to mapOf("op" to "call", "name" to "Fan", "args" to listOf<Any?>())
                        ),
                        mapOf(
                            "type" to "animate",
                            "targets" to listOf("sub1", "sub2"),
                            "destination" to mapOf("op" to "anchor", "target" to mapOf("op" to "index", "target" to mapOf("op" to "var", "name" to "fan")), "anchor" to "topLeft"),
                            "duration" to mapOf("op" to "literal", "type" to "Duration", "value" to 260),
                            "easing" to "overshoot",
                            "await" to true
                        )
                    ),
                    "localVariables" to listOf("fan")
                )
            ),
            "transitions" to listOf(
                mapOf("from" to "collapsed", "to" to "expanded", "ballName" to "mainBall", "event" to "click")
            )
        )

        val program = FloaterV2Program.fromJson(json)
        assertEquals("fan-menu-v2", program.pluginId)
        assertEquals(1, program.variables.size)
        assertEquals("offset", program.variables[0].name)
        assertFalse(program.variables[0].mutable)

        assertEquals(1, program.balls.size)
        assertEquals("mainBall", program.balls[0].name)

        assertEquals(2, program.states.size)
        assertEquals("expanded", program.states[1].name)
        assertTrue(program.states[1].body.any { it is AnimateStatement })
        val animate = program.states[1].body.filterIsInstance<AnimateStatement>().first()
        assertTrue(animate.await)
        assertEquals("overshoot", animate.easing)

        assertEquals(1, program.transitions.size)
        assertEquals("collapsed", program.transitions[0].from)
        assertEquals("expanded", program.transitions[0].to)
    }
}
