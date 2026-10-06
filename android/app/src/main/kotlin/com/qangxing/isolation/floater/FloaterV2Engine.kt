package com.qangxing.isolation.floater

import android.animation.ValueAnimator
import android.graphics.Point
import android.os.Handler
import android.os.Looper
import android.util.Size
import android.view.animation.OvershootInterpolator
import com.qangxing.isolation.FloatingBallService
import kotlin.math.roundToInt

/**
 * Floater DSL v2 执行引擎。
 *
 * 负责解析 v2 程序、创建球、绑定事件、执行语句。
 */
class FloaterV2Engine(
    private val service: FloatingBallService
) {
    private var program: FloaterV2Program? = null
    private val variables = mutableMapOf<String, FloaterValue>()
    private val uiHandler = Handler(Looper.getMainLooper())

    /**
     * 加载并初始化 v2 程序。
     */
    fun load(programJson: Map<String, Any?>) {
        unload()
        val parsed = FloaterV2Program.fromJson(programJson)
        program = parsed

        // 初始化变量
        variables.clear()
        parsed.variables.forEach { variables[it.name] = it.value }

        // 创建球
        parsed.balls.forEach { ball ->
            createBallFromDeclaration(ball)
        }

        // 绑定事件
        parsed.events.forEach { event ->
            bindEvent(event)
        }

        // 绑定球内事件处理器
        parsed.balls.forEach { ball ->
            ball.eventHandlers.forEach { (eventName, body) ->
                service.setPluginBallEventHandler(ball.name, eventName) {
                    executeStatements(body)
                }
            }
        }
    }

    /**
     * 卸载当前程序。
     */
    fun unload() {
        program?.balls?.forEach { ball ->
            service.removePluginBall(ball.name)
        }
        program = null
        variables.clear()
    }

    private fun createBallFromDeclaration(ball: FloaterV2Ball) {
        val props = ball.properties
        val sizeValue = props["size"]?.let { evaluateExpression(it.expression) }
        val sizeDp = when (sizeValue) {
            is FloaterValue.Dp -> sizeValue.value.toInt()
            is FloaterValue.IntVal -> sizeValue.value
            is FloaterValue.Size -> {
                val pxSize = sizeValue.toDpSize(service)
                pxSize.width
            }
            else -> 56
        }

        val radiusValue = props["radius"]?.let { evaluateExpression(it.expression) }
        val radiusDp = when (radiusValue) {
            is FloaterValue.Dp -> radiusValue.value.toInt()
            is FloaterValue.IntVal -> radiusValue.value
            else -> sizeDp / 2
        }

        val positionValue = props["position"]?.let { evaluateExpression(it.expression) }
        val positionPx = when (positionValue) {
            is FloaterValue.Point -> positionValue.toScreenPixels(service)
            else -> Point(100 * service.resources.displayMetrics.density.roundToInt(),
                300 * service.resources.displayMetrics.density.roundToInt())
        }

        val visible = (props["visible"]?.let { evaluateExpression(it.expression) } as? FloaterValue.Bool)?.value ?: true
        val draggable = (props["draggable"]?.let { evaluateExpression(it.expression) } as? FloaterValue.Bool)?.value ?: false
        val image = (props["image"]?.let { evaluateExpression(it.expression) } as? FloaterValue.Str)?.value
        val opacity = (props["opacity"]?.let { evaluateExpression(it.expression) } as? FloaterValue.FloatVal)?.value?.toFloat() ?: 1f

        service.createOrUpdatePluginBall(
            name = ball.name,
            role = ball.role,
            sizeDp = sizeDp,
            cornerRadiusDp = radiusDp,
            imagePath = image,
            initialX = positionPx.x,
            initialY = positionPx.y,
            visible = visible,
            draggable = draggable,
            opacity = opacity
        )
    }

    private fun bindEvent(event: FloaterV2Event) {
        val targetName = event.target
        val eventName = event.event
        service.setPluginBallEventHandler(targetName, eventName) {
            executeStatements(event.body)
        }
    }

    /**
     * 执行语句列表。
     */
    fun executeStatements(statements: List<FloaterV2Statement>) {
        statements.forEach { executeStatement(it) }
    }

    private fun executeStatement(statement: FloaterV2Statement) {
        when (statement) {
            is AssignStatement -> {
                variables[statement.target] = evaluateExpression(statement.value)
            }
            is SetPropertyStatement -> {
                val value = evaluateExpression(statement.value)
                applyBallProperty(statement.ballName, statement.property, value)
            }
            is PrintStatement -> {
                val value = evaluateExpression(statement.expression)
                service.showBubble(valueToString(value))
            }
            is WaitStatement -> {
                val duration = evaluateExpression(statement.duration)
                val ms = when (duration) {
                    is FloaterValue.Duration -> duration.toLong()
                    is FloaterValue.IntVal -> duration.value.toLong()
                    else -> 0L
                }
                if (ms > 0) {
                    Thread.sleep(ms)
                }
            }
            is IfStatement -> {
                val condition = evaluateExpression(statement.condition)
                if (condition.toBoolean()) {
                    executeStatements(statement.thenBody)
                } else if (statement.elseBody != null) {
                    executeStatements(statement.elseBody)
                }
            }
            is ForStatement -> {
                val from = evaluateExpression(statement.from).toInt()
                val to = evaluateExpression(statement.to).toInt()
                for (i in from..to) {
                    variables[statement.variable] = FloaterValue.IntVal(i)
                    executeStatements(statement.body)
                }
            }
            is AnimateStatement -> executeAnimate(statement)
            else -> {}
        }
    }

    private fun executeAnimate(statement: AnimateStatement) {
        val durationValue = evaluateExpression(statement.duration)
        val durationMs = when (durationValue) {
            is FloaterValue.Duration -> durationValue.toLong()
            is FloaterValue.IntVal -> durationValue.value.toLong()
            else -> 0L
        }
        if (durationMs <= 0) return

        val interpolator = easingToInterpolator(statement.easing)
        val destinations = resolveAnimationDestinations(statement.destination, statement.targets.size)
        if (destinations.isEmpty()) return

        val latch = java.util.concurrent.CountDownLatch(if (statement.await) statement.targets.size else 0)
        for ((i, target) in statement.targets.withIndex()) {
            val dest = destinations.getOrNull(i % destinations.size) ?: continue
            val params = service.getPluginBallParams(target) ?: continue
            val fromX = (params["x"] as? Number)?.toInt() ?: 0
            val fromY = (params["y"] as? Number)?.toInt() ?: 0
            service.animatePluginBallPosition(
                name = target,
                fromX = fromX,
                fromY = fromY,
                toX = dest.x,
                toY = dest.y,
                durationMs = durationMs,
                interpolator = interpolator,
                onEnd = { latch.countDown() }
            )
        }
        if (statement.await) {
            latch.await()
        }
    }

    /**
     * 解析动画目标位置列表。
     * - 单个 Point：所有目标移动到同一点。
     * - fan[].topLeft 等几何展开：返回与目标数量相等的 Point 列表。
     */
    private fun resolveAnimationDestinations(destination: FloaterV2Expression, targetCount: Int): List<Point> {
        // 处理 fan[].anchor / ring[].anchor / grid[].anchor
        if (destination is AnchorExpression && destination.target is IndexExpression && destination.target.index == null) {
            val geometry = evaluateExpression(destination.target.target)
            val anchor = destination.anchor
            val size = resolveAnchorSize(destination.target)
            return when (geometry) {
                is FloaterValue.Fan -> (0 until geometry.count.value.coerceAtMost(targetCount))
                    .map { applyAnchorOffset(geometry.slotCenterPx(service, it), anchor, size) }
                is FloaterValue.Ring -> (0 until geometry.count.value.coerceAtMost(targetCount))
                    .map { applyAnchorOffset(geometry.slotCenterPx(service, it), anchor, size) }
                is FloaterValue.Grid -> (0 until geometry.count.value.coerceAtMost(targetCount))
                    .map { applyAnchorOffset(geometry.slotCenterPx(service, it), anchor, size) }
                else -> emptyList()
            }
        }
        val value = evaluateExpression(destination)
        if (value is FloaterValue.Point) {
            return listOf(value.toScreenPixels(service))
        }
        return emptyList()
    }

    private fun easingToInterpolator(easing: String): android.animation.TimeInterpolator {
        return when (easing) {
            "accelerate" -> android.view.animation.AccelerateInterpolator()
            "decelerate" -> android.view.animation.DecelerateInterpolator()
            "overshoot" -> OvershootInterpolator()
            "bounce" -> android.view.animation.BounceInterpolator()
            else -> android.view.animation.LinearInterpolator()
        }
    }

    private fun applyBallProperty(ballName: String, property: String, value: FloaterValue) {
        when (property) {
            "position" -> {
                if (value is FloaterValue.Point) {
                    val px = value.toScreenPixels(service)
                    service.updatePluginBallPosition(ballName, px.x, px.y)
                }
            }
            "visible" -> {
                if (value is FloaterValue.Bool) {
                    service.setPluginBallVisible(ballName, value.value)
                }
            }
            "opacity" -> {
                if (value is FloaterValue.FloatVal) {
                    service.updatePluginBallOpacity(ballName, value.value.toFloat())
                }
            }
            "size" -> {
                val dp = when (value) {
                    is FloaterValue.Dp -> value.value.toInt()
                    is FloaterValue.IntVal -> value.value
                    else -> null
                }
                if (dp != null) {
                    service.updatePluginBallSize(ballName, dp)
                }
            }
            else -> {}
        }
    }

    /**
     * 计算表达式。
     */
    fun evaluateExpression(expr: FloaterV2Expression): FloaterValue {
        return when (expr) {
            is LiteralExpression -> expr.value
            is VarExpression -> resolveVariable(expr.name)
            is PropertyExpression -> readBallProperty(expr.ballName, expr.property)
            is BinaryExpression -> evaluateBinary(expr)
            is UnaryExpression -> evaluateUnary(expr)
            is CallExpression -> evaluateCall(expr)
            is IndexExpression -> evaluateIndex(expr)
            is AnchorExpression -> evaluateAnchor(expr)
        }
    }

    private fun resolveVariable(name: String): FloaterValue {
        val stored = variables[name]
        if (stored != null && stored !is FloaterValue.Unknown) {
            return stored
        }
        // 变量值可能是延迟表达式（如 Fan(...) 构造函数），首次访问时求值
        val variable = program?.variables?.find { it.name == name }
        val rawValue = variable?.rawValue
        if (rawValue?.containsKey("op") == true) {
            val value = evaluateExpression(FloaterV2Expression.fromJson(rawValue))
            variables[name] = value
            return value
        }
        return stored ?: FloaterValue.Unknown
    }

    private fun evaluateIndex(expr: IndexExpression): FloaterValue {
        val target = evaluateExpression(expr.target)
        val index = expr.index?.let { evaluateExpression(it).toInt() }
        return when (target) {
            is FloaterValue.Fan -> {
                if (index == null) target else target.slotCenterPx(service, index).toFloaterPoint()
            }
            is FloaterValue.Ring -> {
                if (index == null) target else target.slotCenterPx(service, index).toFloaterPoint()
            }
            is FloaterValue.Grid -> {
                if (index == null) target else target.slotCenterPx(service, index).toFloaterPoint()
            }
            else -> FloaterValue.Unknown
        }
    }

    private fun evaluateAnchor(expr: AnchorExpression): FloaterValue {
        val target = expr.target
        // 球属性访问优先：target 是 VarExpression 且对应球存在
        if (target is VarExpression && service.getPluginBallParams(target.name) != null) {
            return readBallProperty(target.name, expr.anchor)
        }
        // 几何对象的锚点访问
        val targetValue = evaluateExpression(target)
        val size = resolveAnchorSize(target)
        return when (targetValue) {
            is FloaterValue.Fan -> {
                // fan[] 整体访问在 animate 中批量处理；单个 slot 已被 IndexExpression 求值成 Point
                if (expr.target is IndexExpression && expr.target.index != null) {
                    val center = targetValue.slotCenterPx(service, expr.target.index.let { evaluateExpression(it).toInt() })
                    applyAnchorOffset(center, expr.anchor, size).toFloaterPoint()
                } else FloaterValue.Unknown
            }
            is FloaterValue.Point -> applyAnchorOffset(targetValue.toScreenPixels(service), expr.anchor, size).toFloaterPoint()
            else -> FloaterValue.Unknown
        }
    }

    /** 根据上下文（如 IndexExpression 对应的球）推断用于 anchor 偏移的尺寸。 */
    private fun resolveAnchorSize(target: FloaterV2Expression): android.util.Size? {
        if (target is IndexExpression) {
            // fan[] 场景下无法从表达式推断单个球尺寸，返回 null 让 applyAnchorOffset 使用中心
            return null
        }
        return null
    }

    private fun applyAnchorOffset(center: Point, anchor: String, size: android.util.Size?): Point {
        val halfW = (size?.width ?: 0) / 2
        val halfH = (size?.height ?: 0) / 2
        return when (anchor) {
            "topLeft" -> Point(center.x - halfW, center.y - halfH)
            "topRight" -> Point(center.x + halfW, center.y - halfH)
            "bottomLeft" -> Point(center.x - halfW, center.y + halfH)
            "bottomRight" -> Point(center.x + halfW, center.y + halfH)
            "center" -> center
            else -> center
        }
    }

    private fun Point.toFloaterPoint(): FloaterValue.Point =
        FloaterValue.Point(FloaterValue.Px(x.toDouble()), FloaterValue.Px(y.toDouble()))

    private fun readBallProperty(ballName: String, property: String): FloaterValue {
        val params = service.getPluginBallParams(ballName) ?: return FloaterValue.Unknown
        val x = (params["x"] as? Number)?.toInt() ?: 0
        val y = (params["y"] as? Number)?.toInt() ?: 0
        val width = (params["width"] as? Number)?.toInt() ?: 0
        val height = (params["height"] as? Number)?.toInt() ?: 0
        val visible = params["visible"] as? Boolean ?: false
        return when (property) {
            "x" -> FloaterValue.Px(x.toDouble())
            "y" -> FloaterValue.Px(y.toDouble())
            "width" -> FloaterValue.Px(width.toDouble())
            "height" -> FloaterValue.Px(height.toDouble())
            "topLeft" -> FloaterValue.Point(
                FloaterValue.Px(x.toDouble()),
                FloaterValue.Px(y.toDouble())
            )
            "center" -> FloaterValue.Point(
                FloaterValue.Px((x + width / 2).toDouble()),
                FloaterValue.Px((y + height / 2).toDouble())
            )
            "bottomRight" -> FloaterValue.Point(
                FloaterValue.Px((x + width).toDouble()),
                FloaterValue.Px((y + height).toDouble())
            )
            "size" -> FloaterValue.Size(
                FloaterValue.Px(width.toDouble()),
                FloaterValue.Px(height.toDouble())
            )
            "visible" -> FloaterValue.Bool(visible)
            else -> FloaterValue.Unknown
        }
    }

    private fun evaluateBinary(expr: BinaryExpression): FloaterValue {
        val left = evaluateExpression(expr.left)
        val right = evaluateExpression(expr.right)
        return when (expr.operator) {
            "+", "-", "*", "/", "%" -> evaluateArithmetic(left, right, expr.operator)
            ">", "<", ">=", "<=", "==", "!=" -> evaluateComparison(left, right, expr.operator)
            "&&", "||" -> evaluateLogic(left, right, expr.operator)
            else -> FloaterValue.Unknown
        }
    }

    private fun evaluateArithmetic(left: FloaterValue, right: FloaterValue, op: String): FloaterValue {
        val l = left.toDouble()
        val r = right.toDouble()
        if (l == null || r == null) return FloaterValue.Unknown
        val result = when (op) {
            "+" -> l + r
            "-" -> l - r
            "*" -> l * r
            "/" -> if (r != 0.0) l / r else 0.0
            "%" -> if (r != 0.0) l % r else 0.0
            else -> 0.0
        }
        // 保持单位：Dp + Dp -> Dp；Dp * Float -> Dp
        return if (left is FloaterValue.Dp || right is FloaterValue.Dp) {
            FloaterValue.Dp(result)
        } else if (left is FloaterValue.Px || right is FloaterValue.Px) {
            FloaterValue.Px(result)
        } else if (left is FloaterValue.FloatVal || right is FloaterValue.FloatVal) {
            FloaterValue.FloatVal(result)
        } else {
            FloaterValue.IntVal(result.roundToInt())
        }
    }

    private fun evaluateComparison(left: FloaterValue, right: FloaterValue, op: String): FloaterValue.Bool {
        val l = left.toDouble() ?: return FloaterValue.Bool(false)
        val r = right.toDouble() ?: return FloaterValue.Bool(false)
        val result = when (op) {
            ">" -> l > r
            "<" -> l < r
            ">=" -> l >= r
            "<=" -> l <= r
            "==" -> l == r
            "!=" -> l != r
            else -> false
        }
        return FloaterValue.Bool(result)
    }

    private fun evaluateLogic(left: FloaterValue, right: FloaterValue, op: String): FloaterValue.Bool {
        val l = left.toBoolean()
        val r = right.toBoolean()
        return FloaterValue.Bool(
            when (op) {
                "&&" -> l && r
                "||" -> l || r
                else -> false
            }
        )
    }

    private fun evaluateUnary(expr: UnaryExpression): FloaterValue {
        val right = evaluateExpression(expr.right)
        return when (expr.operator) {
            "-" -> {
                val v = right.toDouble() ?: return FloaterValue.Unknown
                when (right) {
                    is FloaterValue.Dp -> FloaterValue.Dp(-v)
                    is FloaterValue.Px -> FloaterValue.Px(-v)
                    is FloaterValue.FloatVal -> FloaterValue.FloatVal(-v)
                    else -> FloaterValue.IntVal(-v.roundToInt())
                }
            }
            "!" -> FloaterValue.Bool(!right.toBoolean())
            else -> FloaterValue.Unknown
        }
    }

    private fun evaluateCall(expr: CallExpression): FloaterValue {
        val args = expr.args.map { evaluateExpression(it) }
        return when (expr.name) {
            "point" -> {
                if (args.size >= 2) FloaterValue.Point(args[0], args[1]) else FloaterValue.Unknown
            }
            "size" -> {
                if (args.size >= 2) FloaterValue.Size(args[0], args[1]) else FloaterValue.Unknown
            }
            "screen" -> {
                val screen = service.getScreenUsableSize()
                when (args.firstOrNull()?.let { (it as? FloaterValue.Str)?.value }) {
                    "width" -> FloaterValue.Px(screen.width.toDouble())
                    "height" -> FloaterValue.Px(screen.height.toDouble())
                    "centerX" -> FloaterValue.Px((screen.width / 2).toDouble())
                    "centerY" -> FloaterValue.Px((screen.height / 2).toDouble())
                    else -> FloaterValue.Unknown
                }
            }
            "px" -> {
                val dp = args.firstOrNull() as? FloaterValue.Dp ?: return FloaterValue.Unknown
                FloaterValue.Px(dp.toPx(service).toDouble())
            }
            "dp" -> {
                val px = args.firstOrNull() as? FloaterValue.Px ?: return FloaterValue.Unknown
                FloaterValue.Dp(px.value / service.resources.displayMetrics.density)
            }
            "min" -> {
                if (args.size >= 2) {
                    val a = args[0].toDouble() ?: return FloaterValue.Unknown
                    val b = args[1].toDouble() ?: return FloaterValue.Unknown
                    FloaterValue.FloatVal(kotlin.math.min(a, b))
                } else FloaterValue.Unknown
            }
            "max" -> {
                if (args.size >= 2) {
                    val a = args[0].toDouble() ?: return FloaterValue.Unknown
                    val b = args[1].toDouble() ?: return FloaterValue.Unknown
                    FloaterValue.FloatVal(kotlin.math.max(a, b))
                } else FloaterValue.Unknown
            }
            "index" -> {
                // fan[0] 已由 evaluateIndex 处理
                FloaterValue.Unknown
            }
            "Fan" -> buildFan(args, expr.namedArgs)
            "Ring" -> buildRing(args, expr.namedArgs)
            "Grid" -> buildGrid(args, expr.namedArgs)
            "screen" -> {
                val key = args.firstOrNull()?.let { (it as? FloaterValue.Str)?.value }
                    ?: expr.namedArgs["of"]?.let { (evaluateExpression(it) as? FloaterValue.Str)?.value }
                val screen = service.getScreenUsableSize()
                when (key) {
                    "size" -> FloaterValue.Size(
                        FloaterValue.Px(screen.width.toDouble()),
                        FloaterValue.Px(screen.height.toDouble())
                    )
                    "center" -> FloaterValue.Point(
                        FloaterValue.Px((screen.width / 2).toDouble()),
                        FloaterValue.Px((screen.height / 2).toDouble())
                    )
                    "width" -> FloaterValue.Px(screen.width.toDouble())
                    "height" -> FloaterValue.Px(screen.height.toDouble())
                    "centerX" -> FloaterValue.Px((screen.width / 2).toDouble())
                    "centerY" -> FloaterValue.Px((screen.height / 2).toDouble())
                    else -> FloaterValue.Unknown
                }
            }
            else -> FloaterValue.Unknown
        }
    }

    private fun buildFan(args: List<FloaterValue>, namedArgs: Map<String, FloaterV2Expression>): FloaterValue.Fan {
        val center = argValue(namedArgs, args, 0, "center") as? FloaterValue.Point
            ?: FloaterValue.Point(FloaterValue.Px(0.0), FloaterValue.Px(0.0))
        val radius = argValue(namedArgs, args, 1, "radius") as? FloaterValue.Dp ?: FloaterValue.Dp(0.0)
        val startAngle = argValue(namedArgs, args, 2, "startAngle") as? FloaterValue.Angle ?: FloaterValue.Angle(0.0)
        val sweep = argValue(namedArgs, args, 3, "sweep") as? FloaterValue.Angle ?: FloaterValue.Angle(0.0)
        val count = argValue(namedArgs, args, 4, "count") as? FloaterValue.IntVal ?: FloaterValue.IntVal(0)
        return FloaterValue.Fan(center, radius, startAngle, sweep, count)
    }

    private fun buildRing(args: List<FloaterValue>, namedArgs: Map<String, FloaterV2Expression>): FloaterValue.Ring {
        val center = argValue(namedArgs, args, 0, "center") as? FloaterValue.Point
            ?: FloaterValue.Point(FloaterValue.Px(0.0), FloaterValue.Px(0.0))
        val radius = argValue(namedArgs, args, 1, "radius") as? FloaterValue.Dp ?: FloaterValue.Dp(0.0)
        val count = argValue(namedArgs, args, 2, "count") as? FloaterValue.IntVal ?: FloaterValue.IntVal(0)
        return FloaterValue.Ring(center, radius, count)
    }

    private fun buildGrid(args: List<FloaterValue>, namedArgs: Map<String, FloaterV2Expression>): FloaterValue.Grid {
        val origin = argValue(namedArgs, args, 0, "origin") as? FloaterValue.Point
            ?: FloaterValue.Point(FloaterValue.Px(0.0), FloaterValue.Px(0.0))
        val columns = argValue(namedArgs, args, 1, "columns") as? FloaterValue.IntVal ?: FloaterValue.IntVal(1)
        val spacing = argValue(namedArgs, args, 2, "spacing") as? FloaterValue.Dp ?: FloaterValue.Dp(0.0)
        return FloaterValue.Grid(origin, columns, spacing)
    }

    private fun argValue(
        namedArgs: Map<String, FloaterV2Expression>,
        positional: List<FloaterValue>,
        index: Int,
        name: String
    ): FloaterValue? {
        namedArgs[name]?.let { return evaluateExpression(it) }
        if (index < positional.size) return positional[index]
        return null
    }

    private fun valueToString(value: FloaterValue): String = when (value) {
        is FloaterValue.Dp -> "${value.value}dp"
        is FloaterValue.Px -> "${value.value}px"
        is FloaterValue.IntVal -> value.value.toString()
        is FloaterValue.FloatVal -> value.value.toString()
        is FloaterValue.Bool -> value.value.toString()
        is FloaterValue.Str -> value.value
        is FloaterValue.Duration -> "${value.valueMs}ms"
        is FloaterValue.Angle -> "${value.valueDeg}deg"
        is FloaterValue.Point -> "(${valueToString(value.x)}, ${valueToString(value.y)})"
        is FloaterValue.Size -> "(${valueToString(value.width)} x ${valueToString(value.height)})"
        is FloaterValue.Color -> "#${Integer.toHexString(value.argb)}"
        is FloaterValue.Fan -> "Fan(count=${value.count.value})"
        is FloaterValue.Ring -> "Ring(count=${value.count.value})"
        is FloaterValue.Grid -> "Grid(cols=${value.columns.value})"
        is FloaterValue.Unknown -> "unknown"
    }

    // 扩展函数：FloaterValue 转数值/布尔
    private fun FloaterValue.toDouble(): Double? = when (this) {
        is FloaterValue.Dp -> value
        is FloaterValue.Px -> value
        is FloaterValue.IntVal -> value.toDouble()
        is FloaterValue.FloatVal -> value
        is FloaterValue.Duration -> valueMs
        is FloaterValue.Angle -> valueDeg
        is FloaterValue.Fan, is FloaterValue.Ring, is FloaterValue.Grid -> null
        else -> null
    }

    private fun FloaterValue.toInt(): Int = toDouble()?.roundToInt() ?: 0

    private fun FloaterValue.toBoolean(): Boolean = when (this) {
        is FloaterValue.Bool -> value
        is FloaterValue.IntVal -> value != 0
        is FloaterValue.FloatVal -> value != 0.0
        else -> false
    }

    private fun Int.dpToPx(context: android.content.Context): Int =
        (this * context.resources.displayMetrics.density).roundToInt()
}
