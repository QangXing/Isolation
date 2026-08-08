# 宏 DSL 扩展：roll 绝对坐标、变量与表达式

## 目标

扩展《Isolation》宏 DSL，支持更灵活的手势与逻辑：

1. `roll` 支持绝对起始/结束坐标。
2. 引入强类型变量（`int`、`double`、`point`、`color`）与四则运算。
3. `if` 支持数字比较表达式；`for` 支持 C 风格三语句循环。

## 非目标

- 不支持函数定义、闭包、数组/列表变量、字符串运算。
- `point` / `color` 不参与算术运算，仅作为参数传递。
- 不实现完整的短路求值或位运算。

## 1. roll 扩展

### 语法

```dsl
// 相对滑动（保留）
roll(dx, dy, duration)

// 绝对坐标滑动（新增）
roll(startX, startY, endX, endY, duration)
```

### 解析规则

`_BlockParser._parseArgs` 按位置参数数量区分：

- 3 个位置参数 → `dx`、`dy`、`duration`
- 5 个位置参数 → `startX`、`startY`、`endX`、`endY`、`duration`

解析后 step 结构：

```json
// 相对
{"type": "roll", "dx": 0, "dy": 300, "duration": 500}

// 绝对
{"type": "roll", "start": {"x": 100, "y": 200}, "end": {"x": 100, "y": 800}, "duration": 500}
```

### 序列化

`_serializeStep` 中 `case 'roll'`：

- 若 `step['start']` 与 `step['end']` 均为 Map，输出 `roll(startX, startY, endX, endY, duration)`。
- 否则输出 `roll(dx, dy, duration)`。

旧 `swipe` 兼容转换：已有 `start`/`end` 的 swipe 在 `_convertLegacyStep` 中不再转换为 `dx/dy`，而是保留 `start`/`end`。

### 执行器

`MacroExecutor.executeRollStep`：

- 有 `start`/`end` 时直接 `dispatchSwipe(startX, startY, endX, endY, duration)`。
- 否则保持现有逻辑：从屏幕中心出发按 `dx`、`dy` 滑动。

## 2. 变量系统

### 语法

```dsl
int score = 0
score = score + 1

double ratio = 0.5
ratio = ratio * 2

point btn = point(100, 200)
click(btn)

color target = color(0xFF0000)
if (find(color=target)) {
    click()
}
```

### 类型

| 类型 | 字面量/构造 | 支持运算 | 用途 |
|------|------------|----------|------|
| `int` | `0`、`-5`、`0xFF0000` | `+ - * /`、比较 | 计数、分数 |
| `double` | `0.5`、`-1.2` | `+ - * /`、比较 | 比例、时间计算 |
| `point` | `point(x, y)` | 无 | `click`、`roll` 参数 |
| `color` | `color(0xFF0000)` | `==`、`!=` | `find(color=...)` 参数 |

### 作用域

全局作用域：变量一旦声明，在整个宏执行期间有效。find/if/for 块内声明的变量在块结束后仍然可用。

### 执行器变量表

Kotlin 端使用 `Map<String, Variable>`：

```kotlin
sealed class Variable {
    data class Number(val value: Double) : Variable()
    data class Point(val x: Int, val y: Int) : Variable()
    data class Color(val value: Int) : Variable()
}
```

`int` 以 `Double` 存储，使用时按需转 `Int`；比较使用浮点比较。

## 3. 表达式

### 支持的表达式

- 数字字面量、变量名
- 二元算术：`+ - * /`
- 二元比较：`> < >= <= == !=`
- 逻辑组合：`&&`、`||`、`!`（基础级别）
- 括号分组

### 优先级

从高到低：

1. `()`
2. `!`
3. `* /`
4. `+ -`
5. `> < >= <=`
6. `== !=`
7. `&&`
8. `||`

### 解析

Dart 端新增轻量级表达式解析器：

- 输入：字符串（如 `"score + 1 > 5"`）
- 输出：AST 节点（`BinaryOp`、`UnaryOp`、`Literal`、`VariableRef`）

由于表达式只出现在变量值、if 条件、for 语句中，可以先用 shunting-yard 算法转 RPN，再生成 step 中的表达式树；也可以直接手写递归下降。本设计采用递归下降，代码量可控且便于报错。

### 序列化

表达式 AST 序列化为中缀字符串，保持可读性。

## 4. if 扩展

### 语法

```dsl
// 原有 find 条件
if (find(text="签到")) {
    click()
}

// 新增数字比较
if (score > 5) {
    click()
}

// 组合条件
if (find(color=0xFF0000) && score < 3) {
    click()
}
```

### 解析

- 若参数以 `find(...)` 开头，保持原有逻辑，生成 `condition` 字段。
- 否则作为表达式解析，生成 `expression` 字段。

step 结构：

```json
{"type": "if", "expression": <AST>, "then": [...], "else": [...]}
```

### 执行器

`executeIfStep`：

- 若存在 `expression`，求值为布尔值。
- 若存在 `condition`，保持原有 `evaluateConditionWithCoord` 逻辑。
- 命中/为真时执行 `then`，否则执行 `else`。

## 5. for 扩展

### 语法

```dsl
// 原有计数循环
for (10) {
    roll(0, 300, 400)
}

// 新增 C 风格循环
for (int i = 0; i < 10; i = i + 1) {
    roll(0, 300, 400)
}
```

### 解析

- 若参数是单个表达式/数字 → 计数循环，字段 `count`。
- 若参数包含两个分号 `;` → C 风格，字段 `init`、`condition`、`update`。

step 结构：

```json
{"type": "for", "init": <var-step>, "condition": <AST>, "update": <assign-step>, "children": [...]}
```

### 执行器

`executeForStep`：

- 存在 `condition` 时：先执行 `init`，然后 `while (condition 为真) { executeSteps(children); update; }`。
- 否则保持现有计数循环。

## 6. 语法高亮

在 `MacroSyntaxHighlighter._keywords` 中新增：

- `int`
- `double`
- `point`
- `color`
- `var`（预留）
- `true`、`false`（已存在）

## 7. 测试计划

### Dart 侧

- `MacroProgramParser` 解析/序列化 roll 绝对坐标。
- 变量声明解析。
- 表达式解析与序列化。
- if/for 扩展语法解析。

### Kotlin 侧

- `ColorParser` 已覆盖颜色解析。
- 新增表达式求值器单元测试。
- `MacroExecutor` 中变量表、C 风格 for、if 表达式等逻辑测试（依赖 Android 的部分用 instrumentation 测试覆盖）。

## 8. 风险与回退

- 表达式解析错误需要给出清晰行号，避免宏编辑加载时崩溃。
- 新语法需保持向后兼容：旧的 `roll(dx, dy, duration)`、`for(10)`、`if(find(...))` 必须继续工作。
- 全局作用域意味着块内变量会泄漏到外部，需在文档中明确说明。
