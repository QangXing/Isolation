# Floater DSL v2 设计文档

## 1. 背景

当前 v1 DSL 是松散命令式的：

```dsl
ball(main, "mainBall") { size(56); cornerRadius(28) }
location("mainBall", 100, 300)
```

主要问题：
- **类型不明确**：`size(56)` 是 dp，`location(..., 100, 300)` 是 px，用户极易混淆。
- **命令式步骤难管理**：位置、可见性、事件、动画散落在全局步骤中。
- **缺少内置几何/动画抽象**：扇形、环形等布局需要手写三角函数。
- **状态管理靠全局变量**：`expanded`、`animating` 等需要自己维护。

v2 目标：声明式、强类型、内置布局/动画原语、状态机驱动。

---

## 2. 总体结构

```dsl
floater "plugin-id" {
    // 插件级常量/变量
    val debug: Bool = false

    // 球声明
    ball mainBall: Main { ... }
    ball sub1..4: Deputy { ... }

    // 状态机（阶段 3）
    state collapsed { ... }
    state expanded { ... }
    transition collapsed -> expanded on mainBall.click

    // 事件（兼容阶段 1/2）
    on mainBall.click { ... }
    on sub1.click { ... }
}
```

---

## 3. 类型系统（阶段 1）

### 3.1 基本类型

| 类型 | 字面量示例 | 说明 |
|---|---|---|
| `Dp` | `56dp` | 密度无关像素，引擎按屏幕密度转 px |
| `Px` | `100px` | 真实像素 |
| `Int` | `42` | 整数 |
| `Float` | `3.14` | 浮点数 |
| `Bool` | `true` / `false` | 布尔 |
| `String` | `"hello"` | 字符串 |
| `Duration` | `260ms` | 毫秒 |
| `Angle` | `90deg` | 角度 |
| `Point` | `(100dp, 200dp)` | 坐标点，分量类型必须一致 |
| `Size` | `48dp x 48dp` 或 `(48dp, 48dp)` | 尺寸 |
| `Color` | `#ff3366` / `#ff3366aa` | 颜色 |

### 3.2 类型转换

- `Dp` 与 `Px` 之间不允许隐式转换，必须显式调用 `px(56dp)` 或 `dp(100px)`。
- 数值类型 `Int`/`Float` 可自动提升。

### 3.3 变量声明

```dsl
val mainSize: Dp = 56dp      // 常量，不可重新赋值
var expanded: Bool = false   // 变量，可重新赋值
```

---

## 4. 球声明（阶段 1）

### 4.1 语法

```dsl
ball <name>: <role> {
    size = <Size>
    radius = <Dp>
    position = <Point>
    anchor = <Anchor>        // topLeft | center | topRight | ...
    visible = <Bool>
    draggable = <Bool>
    image = <String>?
    opacity = <Float>
}
```

### 4.2 role

- `Main`：主球，默认显示，可拖拽。
- `Deputy`：副球，通常默认隐藏。
- 未来可扩展 `Badge`、`Anchor` 等。

### 4.3 批量声明

```dsl
ball sub1..4: Deputy {
    size = 48dp
    radius = 24dp
    visible = false
}
```

展开为 `sub1`、`sub2`、`sub3`、`sub4` 四个相同属性的球。

### 4.4 示例

```dsl
floater "fan-menu" {
    ball mainBall: Main {
        size = 56dp
        radius = 28dp
        position = (100dp, 300dp)
        visible = true
        draggable = true
        anchor = topLeft
    }

    ball sub1..4: Deputy {
        size = 48dp
        radius = 24dp
        visible = false
        anchor = topLeft
    }
}
```

---

## 5. 表达式与运算符

### 5.1 支持运算符

- 算术：`+` `-` `*` `/` `%`
- 比较：`>` `<` `>=` `<=` `==` `!=`
- 逻辑：`&&` `||` `!`

### 5.2 类型检查

- `Dp + Dp -> Dp`
- `Dp * Float -> Dp`
- `Dp + Int` 非法（必须显式转换）
- `Point + Point` 非法；`Point + Size` 非法；通过 `point.offset(dx, dy)` 方法移动。

### 5.3 内置函数

| 函数 | 签名 | 说明 |
|---|---|---|
| `screen.size` | `() -> Size` | 屏幕可用区域尺寸 |
| `screen.center` | `() -> Point` | 屏幕中心点 |
| `screen.quadrant(of: Point)` | `() -> Quadrant` | 判断点所在象限 |
| `px(dp: Dp)` | `() -> Px` | dp 转 px |
| `dp(px: Px)` | `() -> Dp` | px 转 dp |
| `min(a, b)` | `() -> T` | 最小值 |
| `max(a, b)` | `() -> T` | 最大值 |

---

## 6. 坐标与锚点

### 6.1 锚点

每个球有一个 `anchor` 属性，决定 `position` 语义：

- `topLeft`：`position` 是球左上角坐标（默认）
- `center`：`position` 是球中心坐标
- `topRight`、`bottomLeft`、`bottomRight` 等

### 6.2 属性访问

```dsl
mainBall.topLeft      // Point
mainBall.center       // Point
mainBall.bottomRight  // Point
mainBall.size         // Size
mainBall.width        // Dp
mainBall.height       // Dp
mainBall.x            // 当前 anchor 对应的 x 坐标
mainBall.y            // 当前 anchor 对应的 y 坐标
```

---

## 7. 动画（阶段 2）

### 7.1 基本动画

```dsl
animate sub1 to (200dp, 300dp) duration 260ms easing overshoot
```

### 7.2 多球同步动画

```dsl
animate [sub1, sub2, sub3, sub4] to fan[].topLeft duration 260ms easing overshoot
```

### 7.3 复合动画

```dsl
animate mainBall {
    position to (200dp, 300dp)
    scale to 1.08
    duration 150ms
}
```

### 7.4 await

```dsl
await animate sub1 to (200dp, 300dp) duration 260ms
```

### 7.5 缓动

`linear`、`accelerate`、`decelerate`、`overshoot`、`bounce`

---

## 8. 内置几何布局（阶段 2）

### 8.1 Fan（扇形）

```dsl
val fan = Fan(
    center: mainBall.center,
    radius: 140dp,
    startAngle: 0deg,
    sweep: 90deg,
    count: 4
)

sub1.position = fan[0].topLeft
sub2.position = fan[1].topLeft
```

### 8.2 Ring（环形）

```dsl
val ring = Ring(center: mainBall.center, radius: 120dp, count: 6)
```

### 8.3 Grid（网格）

```dsl
val grid = Grid(origin: (100dp, 100dp), columns: 3, spacing: 16dp)
```

---

## 9. 状态机（阶段 3）

```dsl
state collapsed {
    sub1..4.visible = false
}

state expanded {
    let fan = Fan(center: mainBall.center, radius: 140dp, startAngle: 0deg, sweep: 90deg, count: 4)
    sub1..4.position = mainBall.topLeft
    sub1..4.visible = true
    await animate [sub1..4] to fan[].topLeft duration 260ms easing overshoot
}

transition collapsed -> expanded on mainBall.click
transition expanded -> collapsed on mainBall.click
```

---

## 10. 事件

```dsl
on mainBall.click { ... }
on mainBall.doubleClick { ... }
on mainBall.tripleClick { ... }
on mainBall.longPress { ... }
on sub1.click { print("功能 1") }
```

---

## 11. 阶段计划

### 阶段 1：类型系统 + 声明式球声明

- [ ] 重写 Floater AST 模型
- [ ] 重写 Floater Parser（支持类型、ball 声明、val/var、表达式）
- [ ] Kotlin 执行引擎支持类型系统、属性声明式求值
- [ ] 旧 DSL 兼容层（可选，但建议保留一段时间）
- [ ] 更新 fan-menu 示例

### 阶段 2：动画 + 内置几何

- [ ] 新动画调度器（支持多球同步、await）
- [ ] Fan / Ring / Grid 几何对象
- [ ] `animate`、`await animate` 语法

### 阶段 3：状态机

- [ ] `state` / `transition` 语法与执行
- [ ] 移除旧全局变量写法

---

## 12. 兼容性

- v2 parser 和 v1 parser 并存。
- `manifest.json` 中可增加 `"dslVersion": 2` 字段标识新语法；未指定时默认使用 v1，便于平滑迁移。
- 编辑器根据 `dslVersion` 切换语法高亮和补全。

---

## 13. 阶段 1 示例：类型 + 声明式球

```dsl
floater "fan-menu-v2" {
    ball mainBall: Main {
        size = 56dp
        radius = 28dp
        position = (100dp, 300dp)
        visible = true
        draggable = true
        anchor = topLeft
    }

    ball sub1..4: Deputy {
        size = 48dp
        radius = 24dp
        visible = false
        anchor = topLeft
    }

    on mainBall.click {
        print(mainBall.center.x)
        print(mainBall.center.y)
    }
}
```
