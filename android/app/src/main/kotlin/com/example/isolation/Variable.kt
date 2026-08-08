package com.example.isolation

sealed class Variable {
    data class Number(val value: Double) : Variable()
    data class Point(val x: Int, val y: Int) : Variable()
    data class Color(val value: Int) : Variable()
}
