package com.example.isolation

object ExpressionEvaluator {

    fun evaluate(expr: Map<String, Any>?, variables: Map<String, Variable>): Variable? {
        if (expr == null) return null
        return when (expr["op"]) {
            "literal" -> {
                val value = expr["value"] as? Number ?: return null
                Variable.Number(value.toDouble())
            }
            "var" -> {
                val name = expr["name"] as? String ?: return null
                variables[name]
            }
            "unary" -> {
                val operator = expr["operator"] as? String ?: return null
                val rightExpr = expr["right"] as? Map<String, Any> ?: return null
                val right = evaluate(rightExpr, variables) ?: return null
                evaluateUnary(operator, right)
            }
            "binary" -> {
                val operator = expr["operator"] as? String ?: return null
                val leftExpr = expr["left"] as? Map<String, Any> ?: return null
                val rightExpr = expr["right"] as? Map<String, Any> ?: return null
                val left = evaluate(leftExpr, variables) ?: return null
                val right = evaluate(rightExpr, variables) ?: return null
                evaluateBinary(operator, left, right)
            }
            else -> null
        }
    }

    fun toBoolean(variable: Variable?): Boolean {
        return when (variable) {
            is Variable.Number -> variable.value != 0.0
            else -> false
        }
    }

    private fun evaluateUnary(operator: String, right: Variable): Variable? {
        return when (operator) {
            "!" -> Variable.Number(if (toBoolean(right)) 0.0 else 1.0)
            "-" -> {
                if (right !is Variable.Number) return null
                Variable.Number(-right.value)
            }
            else -> null
        }
    }

    private fun evaluateBinary(operator: String, left: Variable, right: Variable): Variable? {
        return when (operator) {
            "+", "-", "*", "/" -> evaluateArithmetic(operator, left, right)
            ">", "<", ">=", "<=" -> evaluateComparison(operator, left, right)
            "==", "!=" -> evaluateEquality(operator, left, right)
            "&&", "||" -> evaluateLogical(operator, left, right)
            else -> null
        }
    }

    private fun evaluateArithmetic(operator: String, left: Variable, right: Variable): Variable? {
        if (left !is Variable.Number || right !is Variable.Number) return null
        val l = left.value
        val r = right.value
        val result = when (operator) {
            "+" -> l + r
            "-" -> l - r
            "*" -> l * r
            "/" -> if (r == 0.0) return null else l / r
            else -> return null
        }
        return Variable.Number(result)
    }

    private fun evaluateComparison(operator: String, left: Variable, right: Variable): Variable? {
        if (left !is Variable.Number || right !is Variable.Number) return null
        val l = left.value
        val r = right.value
        val result = when (operator) {
            ">" -> l > r
            "<" -> l < r
            ">=" -> l >= r
            "<=" -> l <= r
            else -> return null
        }
        return Variable.Number(if (result) 1.0 else 0.0)
    }

    private fun evaluateEquality(operator: String, left: Variable, right: Variable): Variable? {
        val result = when {
            left is Variable.Number && right is Variable.Number -> left.value == right.value
            left is Variable.Color && right is Variable.Color -> left.value == right.value
            else -> false
        }
        val equal = if (operator == "==") result else !result
        return Variable.Number(if (equal) 1.0 else 0.0)
    }

    private fun evaluateLogical(operator: String, left: Variable, right: Variable): Variable? {
        val l = toBoolean(left)
        val r = toBoolean(right)
        val result = when (operator) {
            "&&" -> l && r
            "||" -> l || r
            else -> return null
        }
        return Variable.Number(if (result) 1.0 else 0.0)
    }
}
