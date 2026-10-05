package com.qangxing.isolation.floater

/**
 * Floater DSL v2 程序结构，对应 Dart 端 [FloaterProgramV2] 序列化后的 JSON。
 */
data class FloaterV2Program(
    val pluginId: String,
    val variables: List<FloaterV2Variable>,
    val balls: List<FloaterV2Ball>,
    val events: List<FloaterV2Event>
) {
    companion object {
        fun fromJson(json: Map<String, Any?>): FloaterV2Program {
            return FloaterV2Program(
                pluginId = json["pluginId"] as? String ?: "",
                variables = (json["variables"] as? List<*>)?.map {
                    FloaterV2Variable.fromJson(it as Map<String, Any?>)
                } ?: emptyList(),
                balls = (json["balls"] as? List<*>)?.map {
                    FloaterV2Ball.fromJson(it as Map<String, Any?>)
                } ?: emptyList(),
                events = (json["events"] as? List<*>)?.map {
                    FloaterV2Event.fromJson(it as Map<String, Any?>)
                } ?: emptyList()
            )
        }
    }
}

data class FloaterV2Variable(
    val name: String,
    val type: FloaterType,
    val value: FloaterValue,
    val mutable: Boolean
) {
    companion object {
        fun fromJson(json: Map<String, Any?>): FloaterV2Variable {
            return FloaterV2Variable(
                name = json["name"] as? String ?: "",
                type = (json["type"] as? Map<String, Any?>)?.get("kind") as? String ?: "Unknown".toFloaterType(),
                value = floaterValueFromJson(json["value"] as? Map<String, Any?> ?: emptyMap()),
                mutable = json["mutable"] as? Boolean ?: false
            )
        }
    }
}

data class FloaterV2Ball(
    val name: String,
    val role: String,
    val properties: Map<String, FloaterV2Property>,
    val eventHandlers: Map<String, List<FloaterV2Statement>>
) {
    companion object {
        fun fromJson(json: Map<String, Any?>): FloaterV2Ball {
            val properties = (json["properties"] as? Map<*, *>)?.map { (k, v) ->
                k as String to FloaterV2Property.fromJson(v as Map<String, Any?>)
            } ?: emptyMap()

            val eventHandlers = (json["eventHandlers"] as? Map<*, *>)?.map { (k, v) ->
                k as String to (v as List<*>).map {
                    FloaterV2Statement.fromJson(it as Map<String, Any?>)
                }
            } ?: emptyMap()

            return FloaterV2Ball(
                name = json["name"] as? String ?: "",
                role = json["role"] as? String ?: "Deputy",
                properties = properties,
                eventHandlers = eventHandlers
            )
        }
    }
}

data class FloaterV2Property(
    val declaredType: FloaterType,
    val expression: FloaterV2Expression,
    val line: Int
) {
    companion object {
        fun fromJson(json: Map<String, Any?>): FloaterV2Property {
            return FloaterV2Property(
                declaredType = (json["declaredType"] as? Map<String, Any?>)?.get("kind") as? String ?: "Unknown".toFloaterType(),
                expression = FloaterV2Expression.fromJson(json["expression"] as? Map<String, Any?> ?: emptyMap()),
                line = (json["line"] as? Number)?.toInt() ?: 0
            )
        }
    }
}

data class FloaterV2Event(
    val target: String,
    val event: String,
    val body: List<FloaterV2Statement>
) {
    companion object {
        fun fromJson(json: Map<String, Any?>): FloaterV2Event {
            return FloaterV2Event(
                target = json["target"] as? String ?: "",
                event = json["event"] as? String ?: "",
                body = (json["body"] as? List<*>)?.map {
                    FloaterV2Statement.fromJson(it as Map<String, Any?>)
                } ?: emptyList()
            )
        }
    }
}

/**
 * v2 语句 AST。
 */
sealed class FloaterV2Statement {
    companion object {
        fun fromJson(json: Map<String, Any?>): FloaterV2Statement {
            val type = json["type"] as? String ?: return UnknownStatement
            return when (type) {
                "assign" -> AssignStatement(
                    target = json["target"] as? String ?: "",
                    value = FloaterV2Expression.fromJson(json["value"] as Map<String, Any?>)
                )
                "setProperty" -> SetPropertyStatement(
                    ballName = json["ballName"] as? String ?: "",
                    property = json["property"] as? String ?: "",
                    value = FloaterV2Expression.fromJson(json["value"] as Map<String, Any?>)
                )
                "print" -> PrintStatement(
                    expression = FloaterV2Expression.fromJson(json["expression"] as Map<String, Any?>)
                )
                "wait" -> WaitStatement(
                    duration = FloaterV2Expression.fromJson(json["duration"] as Map<String, Any?>)
                )
                "if" -> IfStatement(
                    condition = FloaterV2Expression.fromJson(json["condition"] as Map<String, Any?>),
                    thenBody = (json["thenBody"] as? List<*>)?.map { fromJson(it as Map<String, Any?>) } ?: emptyList(),
                    elseBody = (json["elseBody"] as? List<*>)?.map { fromJson(it as Map<String, Any?>) }
                )
                "for" -> ForStatement(
                    variable = json["variable"] as? String ?: "",
                    from = FloaterV2Expression.fromJson(json["from"] as Map<String, Any?>),
                    to = FloaterV2Expression.fromJson(json["to"] as Map<String, Any?>),
                    body = (json["body"] as? List<*>)?.map { fromJson(it as Map<String, Any?>) } ?: emptyList()
                )
                else -> UnknownStatement
            }
        }
    }
}

object UnknownStatement : FloaterV2Statement()
data class AssignStatement(
    val target: String,
    val value: FloaterV2Expression
) : FloaterV2Statement()

data class SetPropertyStatement(
    val ballName: String,
    val property: String,
    val value: FloaterV2Expression
) : FloaterV2Statement()

data class PrintStatement(
    val expression: FloaterV2Expression
) : FloaterV2Statement()

data class WaitStatement(
    val duration: FloaterV2Expression
) : FloaterV2Statement()

data class IfStatement(
    val condition: FloaterV2Expression,
    val thenBody: List<FloaterV2Statement>,
    val elseBody: List<FloaterV2Statement>?
) : FloaterV2Statement()

data class ForStatement(
    val variable: String,
    val from: FloaterV2Expression,
    val to: FloaterV2Expression,
    val body: List<FloaterV2Statement>
) : FloaterV2Statement()

/**
 * v2 表达式 AST。
 */
sealed class FloaterV2Expression {
    companion object {
        fun fromJson(json: Map<String, Any?>): FloaterV2Expression {
            val op = json["op"] as? String ?: return LiteralExpression(FloaterValue.Unknown)
            return when (op) {
                "literal" -> LiteralExpression(floaterValueFromJson(json["value"] as? Map<String, Any?> ?: emptyMap()))
                "var" -> VarExpression(json["name"] as? String ?: "")
                "property" -> PropertyExpression(
                    ballName = json["ballName"] as? String ?: "",
                    property = json["property"] as? String ?: ""
                )
                "binary" -> BinaryExpression(
                    operator = json["operator"] as? String ?: "",
                    left = fromJson(json["left"] as Map<String, Any?>),
                    right = fromJson(json["right"] as Map<String, Any?>)
                )
                "unary" -> UnaryExpression(
                    operator = json["operator"] as? String ?: "",
                    right = fromJson(json["right"] as Map<String, Any?>)
                )
                "call" -> CallExpression(
                    name = json["name"] as? String ?: "",
                    args = (json["args"] as? List<*>)?.map { fromJson(it as Map<String, Any?>) } ?: emptyList(),
                    namedArgs = (json["namedArgs"] as? Map<*, *>)?.map { (k, v) ->
                        k as String to fromJson(v as Map<String, Any?>)
                    } ?: emptyMap()
                )
                else -> LiteralExpression(FloaterValue.Unknown)
            }
        }
    }
}

data class LiteralExpression(val value: FloaterValue) : FloaterV2Expression()
data class VarExpression(val name: String) : FloaterV2Expression()
data class PropertyExpression(val ballName: String, val property: String) : FloaterV2Expression()
data class BinaryExpression(
    val operator: String,
    val left: FloaterV2Expression,
    val right: FloaterV2Expression
) : FloaterV2Expression()

data class UnaryExpression(
    val operator: String,
    val right: FloaterV2Expression
) : FloaterV2Expression()

data class CallExpression(
    val name: String,
    val args: List<FloaterV2Expression>,
    val namedArgs: Map<String, FloaterV2Expression>
) : FloaterV2Expression()
