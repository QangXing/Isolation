# Isolation 多球 DSL 总设计

> 本文档确定 `floaterPlugin`（编程球）的下一代 DSL 总结构：一个球文件可声明多个悬浮球（1 个主球 + N 个副球），每个球独立声明形态、位置、显隐状态，并支持运行时坐标获取。
>
> 本设计替代 [BALL_SPEC.md](./BALL_SPEC.md) 中“单球全局配置”的旧写法，后续实现与解析器均以此为准。

---

## 1. 设计目标

1. **多球共存**：一个 `floater.dsl` 可以声明一个主球和多个副球，分别对应不同功能入口。
2. **每个球独立配置**：大小、圆角、图片、位置、显隐等形态参数都在各自的 `ball(...)` 块内声明，互不干扰。
3. **缺省回退**：球内未显式声明的形态参数，统一沿用 **系统默认悬浮球参数**。
4. **运行时可控**：支持动态显示/隐藏、移动位置，并能读取球的当前坐标。
5. **不再依赖 `#include`**：球文件启用后即可独立生效。

---

## 2. 文件总体结构

```dsl
// ── 1. 主球声明（必须且唯一） ──
ball(main, "mainBall") {
    size(64)
    cornerRadius(16)
    image("main.png")
    location("mainBall", 100, 200)
    status(show, "mainBall")

    floater("click") {
        image("click.png")
        audio("click.mp3")
        print("主球被点击：" + clickX + ", " + clickY)
    }
}

// ── 2. 副球声明（可选，可多个） ──
ball(deputy, "helper") {
    size(48)
    cornerRadius(24)
    image("helper.png")
    location("helper", x, y)
    status(hide, "helper")
}

// ── 3. 全局流程 / 变量 ──
x = found("mainBall", x) + 50
y = found("mainBall", y)
status(show, "helper")
location("helper", x, y)
```

### 结构说明

| 区域 | 说明 |
|---|---|
| 主球声明 | `ball(main, "name") { ... }`，一个文件必须有且只有一个。 |
| 副球声明 | `ball(deputy, "name") { ... }`，可选，可多个。 |
| 全局流程 | 在球块之外，可以使用 `status`、`location`、`found` 等指令编排多球交互。 |

---

## 3. 球声明 `ball(role, "name")`

### 语法

```dsl
ball(main, "mainBall") { ... }
ball(deputy, "helper") { ... }
```

### 参数

| 参数 | 类型 | 说明 |
|---|---|---|
| `role` | 关键字 | `main` 表示主球，`deputy` 表示副球。 |
| `"name"` | 字符串 | 球的唯一标识名，同一文件内不可重复。后续 `location`、`status`、`found` 均通过该名称引用。 |

### 约束

- 一个 `floater.dsl` 必须且只能有一个 `main`。
- `deputy` 可以有零个或多个。
- 每个球的形态、位置、显隐均在自己的块内声明。

---

## 4. 球内形态声明

每个球块内部可以独立声明以下参数：

### 4.1 大小 `size`

```dsl
ball(main, "mainBall") {
    size(64)
}
```

- 参数为 dp 单位的整数。
- 未声明时使用系统默认悬浮球大小。

### 4.2 圆角 `cornerRadius`

```dsl
ball(main, "mainBall") {
    cornerRadius(16)
}
```

- 参数为 dp 单位的整数。
- 未声明时使用系统默认悬浮球圆角。

### 4.3 图片 `image`

```dsl
ball(main, "mainBall") {
    image("main.png")
}
```

- 参数为图片文件名，图片放在插件包 `assets/` 目录下。
- 未声明时使用系统默认悬浮球图标。

### 4.4 位置 `location`

```dsl
ball(deputy, "helper") {
    location("helper", 100, 200)
}
```

- 第一个参数为球的 `name`（通常与所在块名称一致，也可以指向其他球）。
- 后两个参数为 x、y 坐标，支持纯数字、变量或表达式。
- 坐标系为屏幕像素坐标，原点为屏幕左上角。
- 未声明时，主球使用系统默认悬浮球位置，副球默认位置为 `(0, 0)`。

### 4.5 显隐状态 `status`

```dsl
ball(deputy, "helper") {
    status(hide, "helper")
}
```

- `status(show, "name")`：显示球。
- `status(hide, "name")`：隐藏球。
- 未声明时，主球默认显示，副球默认隐藏。

---

## 5. 球内事件监听

```dsl
ball(main, "mainBall") {
    size(64)
    cornerRadius(16)
    image("main.png")
    location("mainBall", 100, 200)

    floater("click") {
        image("click.png")
        audio("click.mp3")
        print("点击于 " + clickX + ", " + clickY)
    } else {
        print("点击执行失败")
    }

    floater("findText") {
        print("找到文字：" + foundText)
    }
}
```

- `floater("事件名") { ... }` 用于监听宏指令或悬浮球交互事件的执行结果。
- 块内自动注入事件相关变量（如 `clickX`、`clickY`、`foundText` 等）。
- 事件变量作用域仍限定在当前 `floater` 块内。

---

## 6. 全局指令

球声明块之外，可以使用以下指令控制任意球：

### 6.1 `location`

```dsl
location("helper", x + 20, y)
```

- 动态改变指定球的位置。
- 坐标支持变量和表达式。

### 6.2 `status`

```dsl
status(show, "helper")
status(hide, "helper")
```

- 动态显示或隐藏指定球。

### 6.3 `found`

```dsl
x = found("mainBall", x)
y = found("mainBall", y)
```

- `found("name", x)`：获取名为 `name` 的球的当前 x 坐标。
- `found("name", y)`：获取名为 `name` 的球的当前 y 坐标。
- 第二个参数只能是字面量 `x` 或 `y`，用于指定读取的轴。
- 返回值可赋值给变量，也可直接用于表达式：

```dsl
location("helper", found("mainBall", x) + 100, found("mainBall", y))
```

---

## 7. 变量与表达式

### 7.1 变量赋值

```dsl
offset = 120
x = found("mainBall", x)
y = found("mainBall", y)
```

### 7.2 表达式

支持基本算术运算：

```dsl
location("helper", x + offset, y * 2 - 50)
```

### 7.3 变量作用域

- 当前设计采用**文件全局作用域**：在球块内外定义的变量均可相互访问。
- 后续如需块级作用域，可在实现阶段扩展。

---

## 8. 主球与副球的语义差异

| 特性 | 主球 `main` | 副球 `deputy` |
|---|---|---|
| 数量 | 必须 1 个 | 0 个或多个 |
| 默认显隐 | 若未声明 `status`，默认显示 | 若未声明 `status`，默认隐藏 |
| 默认位置 | 若未声明 `location`，使用系统默认悬浮球位置 | 若未声明 `location`，默认 `(0, 0)` |
| 生命周期 | 与插件生命周期绑定 | 由 `status` 控制显隐 |
| 事件监听 | 推荐放置主要事件 | 可放置辅助事件或仅作为视觉辅助 |

---

## 9. 完整示例

```dsl
// 主球：主要交互入口
ball(main, "primary") {
    size(64)
    cornerRadius(16)
    image("primary.png")
    location("primary", 100, 400)
    status(show, "primary")

    floater("click") {
        image("primary_click.png")
        audio("click.mp3")
        print("主球点击：" + clickX + ", " + clickY)
    }

    floater("findText") {
        print("找到文字：" + foundText)
    }
}

// 副球：跟随主球的辅助按钮
ball(deputy, "secondary") {
    size(48)
    cornerRadius(24)
    image("secondary.png")
    location("secondary", 0, 0)
    status(hide, "secondary")
}

// 全局流程：当主球移动后，让副球显示在主球右侧
mainX = found("primary", x)
mainY = found("primary", y)
location("secondary", mainX + 80, mainY)
status(show, "secondary")
```

---

## 10. 与旧 BALL_SPEC 的差异

| 旧写法 | 新写法 | 说明 |
|---|---|---|
| 全局 `size/cornerRadius/image` 直接生效 | 形态参数移到每个 `ball(...)` 块内 | 每个球独立配置 |
| 单球，无名称 | `ball(main, "name")` / `ball(deputy, "name")` | 多球，按名称引用 |
| `#include <球名称>` | 不需要 | 球文件启用后自动生效 |
| 无 `location` / `status` / `found` | 新增 | 用于多球位置与显隐控制 |
| `floater("...") { ... }` | 保留，放在 `ball(...)` 块内 | 语义不变 |

---

## 11. 默认参数继承链

每个球的最终形态按以下优先级确定：

```
球内声明 > 系统默认悬浮球参数
```

- 球内未声明 `size` → 使用系统默认悬浮球 `size`。
- 球内未声明 `cornerRadius` → 使用系统默认悬浮球 `cornerRadius`。
- 球内未声明 `image` → 使用系统默认悬浮球图标。
- 球内未声明 `location` → 主球使用系统默认悬浮球位置，副球为 `(0, 0)`。
- 球内未声明 `status` → 主球默认显示，副球默认隐藏。

---

## 12. 后续实现要点

1. **解析器扩展**
   - 识别 `ball(role, "name") { ... }` 块。
   - 在块内解析 `size`、`cornerRadius`、`image`、`location`、`status`。
   - 在块外解析 `location`、`status`、`found`。
   - `found("name", axis)` 需要 runtime 从悬浮球服务读取坐标。

2. **运行时模型**
   - 每个球对应一个 `FloaterInstance`，持有 `name`、`role`、`x`、`y`、`visible`、`config`。
   - 主球缺失或文件未声明任何球时，按旧逻辑退化为一个默认主球。

3. **Native 通道**
   - 增加按名称创建/更新/移动/显隐悬浮球的 API。
   - 增加按名称读取悬浮球当前坐标的 API。

4. **包格式**
   - `assets/` 目录仍用于存放图片与音频资源。
   - 每个球通过文件名引用自己的资源。
