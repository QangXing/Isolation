package com.example.isolation

import org.junit.Assert.assertEquals
import org.junit.Test

class ColorParserTest {

    @Test
    fun parseColor_number_returnsIntValue() {
        assertEquals(0xFF0000, ColorParser.parseColor(16711680))
    }

    @Test
    fun parseColor_hexWithHash_returnsIntValue() {
        assertEquals(0xFF0000, ColorParser.parseColor("#FF0000"))
    }

    @Test
    fun parseColor_hexWith0xPrefix_returnsIntValue() {
        assertEquals(0x00FF00, ColorParser.parseColor("0x00FF00"))
    }

    @Test
    fun parseColor_plainHex6_returnsIntValue() {
        assertEquals(0x0000FF, ColorParser.parseColor("0000FF"))
    }

    @Test
    fun parseColor_plainHex8_returnsIntValue() {
        assertEquals(0xFF0000FF.toInt(), ColorParser.parseColor("FF0000FF"))
    }

    @Test
    fun parseColor_invalidString_returnsZero() {
        assertEquals(0, ColorParser.parseColor("not-a-color"))
    }

    @Test
    fun parseColor_unsupportedType_returnsZero() {
        assertEquals(0, ColorParser.parseColor(listOf<Any>()))
    }
}
