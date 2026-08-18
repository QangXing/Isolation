# Isolation 编程球（floaterPlugin）指令规范

> 本文档说明“编程球”插件使用的指令、多球结构、事件触发与 `#include` 引用。宏指令（点击、查找、循环等）请参见 [DSL_SPEC.md](./DSL_SPEC.md)。

---

## 1. 编程球是什么

编程球是一种特殊的插件类型（`floaterPlugin`），用于：

- 自定义一个或多个悬浮球的外观（圆角、大小、图片）。
- 监听悬浮球相关事件（单击、双击、三连击、长按等）。
- 在事件触发时执行指定动作（启动宏、关闭宏、启动应用、打印日志等）。

一个编程球插件启用后即可独立生效，也可以被多个宏脚本通过 `#include` 引用。

---

## 2. 多球结构

一个 `floater.dsl` 文件可以声明多个球：

- **主球** `main`：必须且只能有一个。
- **副球** `deputy`：可选，可声明多个。

```dsl
ball(main, "mainBall") {
    size(64)
    cornerRadius(16)
    image("main.png")
    location("mainBall", 100, 200)
    status(show, "mainBall")

    singleClick(Launch_macro)
}

ball(deputy, "helper") {
    size(48)
    cornerRadius(24)
    image("helper.png")
    location("helper", 0, 0)
    status(hide, "helper")
}

// 全局流程
mainX = found("mainBall", x)
mainY = found("mainBall", y)
location("helper", mainX + 80, mainY)
status(show, "helper")
```

---

## 3. 球声明 `ball(role, "name")`

| 参数 | 类型 | 说明 |
|---|---|---|
| `role` | 关键字 | `main` 表示主球，`deputy` 表示副球。 |
| `"name"` | 字符串 | 球的唯一标识名，同一文件内不可重复。后续 `location`、`status`、`found` 均通过该名称引用。 |

- 一个 `floater.dsl` 必须且只能有一个 `main`。
- 每个球的形态、位置、显隐、事件监听均在自己的块内声明。
- 球内未声明的形态参数，统一沿用**系统默认悬浮球参数**。

---

## 4. 球内形态声明

### 4.1 size

```dsl
size(64)
```

设置悬浮球宽高尺寸，参数为 dp 单位的整数。未声明时使用系统默认悬浮球大小。

### 4.2 cornerRadius

```dsl
cornerRadius(16)
```

设置悬浮球圆角半径，参数为 dp 单位的整数。未声明时使用系统默认悬浮球圆角。

### 4.3 image

```dsl
image("main.png")
```

设置悬浮球显示的图片。图片文件应位于插件包 `assets/` 目录下，通过文件名引用。未声明时使用系统默认悬浮球图标。

### 4.4 location（起始位置）

```dsl
location("mainBall", 100, 200)
```

- 第一个参数为球的 `name`。
- 后两个参数为 x、y 坐标，支持纯数字、变量或表达式。
- 坐标系为屏幕像素坐标，原点为屏幕左上角。
- **该指令仅在球创建时作为起始位置确认一次**，运行时若要持续刷新位置，请在事件块或全局流程中通过循环调用 `location("name", x, y)`。
- 未声明时，主球使用系统默认悬浮球位置，副球默认位置为 `(0, 0)`。

### 4.5 status

```dsl
status(show, "mainBall")
status(hide, "helper")
```

- `status(show, "name")`：显示球。
- `status(hide, "name")`：隐藏球。
- 未声明时，主球默认显示，副球默认隐藏。

---

## 5. 全局指令

### 5.1 location

```dsl
location("helper", x + 20, y)
```

动态改变指定球的位置，坐标支持变量与表达式。常用于循环内实时刷新球的位置。

### 5.2 status

```dsl
status(show, "helper")
status(hide, "helper")
```

动态显示或隐藏指定球。

### 5.3 found

```dsl
x = found("mainBall", x)
y = found("mainBall", y)
location("helper", found("mainBall", x) + 100, found("mainBall", y))
```

- `found("name", x)`：获取名为 `name` 的球的当前 x 坐标。
- `found("name", y)`：获取名为 `name` 的球的当前 y 坐标。
- 第二个参数只能是字面量 `x` 或 `y`。
- 返回值可赋值给变量，也可直接用于表达式。

---

## 6. 事件触发指令

每个球内可以声明以下触发指令，用于响应用户与悬浮球的交互：

| 指令 | 触发条件 |
|---|---|
| `singleClick` | 单击悬浮球 |
| `doubleClick` | 快速双击悬浮球 |
| `tripleClick` | 快速三连击悬浮球 |
| `longPress` | 长按悬浮球 |

### 6.1 直接触发动作

使用内置动作名作为参数：

```dsl
singleClick(Launch_macro)
doubleClick(Turn_off_macros)
```

| 动作 | 说明 |
|---|---|
| `Launch_macro` | 启动当前已启用的宏 |
| `Turn_off_macros` | 强制停止当前正在运行的宏 |

### 6.2 触发自定义代码块

通过 `{}` 块编写多步指令：

```dsl
singleClick {
    launch("com.example.app", timeout=3000) {
    }
}

doubleClick {
    print("双击触发")
}

tripleClick(Turn_off_macros)

longPress {
    print("长按主球")
}
```

块内支持以下指令：

- `launch("包名", timeout=毫秒)`：启动指定应用。
- `print("信息")`：在悬浮球附近显示气泡提示。
- `location("name", x, y)`：移动球位置。
- `status(show|hide, "name")`：显示/隐藏球。
- `image("xxx.png")`：临时切换当前球图片（如支持）。
- `audio("xxx.mp3")`：播放音效（如支持）。
- `for` / `if` / `else`：流程控制，支持循环刷新与条件分支。

---

## 7. 旧 `floater("...")` 事件监听

为兼容旧脚本，仍支持 `floater("事件名") { ... }` 写法：

```dsl
floater("click") {
    image("click.png")
    audio("click.mp3")
    print("点击于 " + clickX + ", " + clickY)
} else {
    print("点击执行失败")
}
```

该写法用于监听某个宏指令或悬浮球交互事件的执行结果，块内会注入事件相关变量。`singleClick` 等新的交互触发指令不注入 `clickX`/`clickY`。

### 7.1 事件注入变量

| 事件 | 注入变量 | 说明 |
|---|---|---|
| `click` | `clickX`、`clickY` | 点击发生时的屏幕坐标 |
| `swipe` / `swipeRel` | `swipeFromX`、`swipeFromY`、`swipeToX`、`swipeToY` | 滑动的起点与终点坐标 |
| `findText` / `waitForText` | `foundText` | 命中目标的文字内容 |
| `findColor` / `waitForColor` / `findImage` / `waitForImage` | `foundX`、`foundY` | 命中目标在屏幕上的坐标 |
| `input` | `inputText` | 本次输入的文字内容 |
| `launch` | `packageName` | 启动的应用包名 |

---

## 8. 插件引用 `#include`

```dsl
#include <插件显示名称>
```

引用一个 `floaterPlugin` 插件。被引用插件的 `floater.dsl` 中的悬浮球配置和事件处理器会进入当前宏脚本的执行上下文。

- `<...>` 内填写插件的显示名称，即 `manifest.json` 中的 `name` 字段。
- 一个宏脚本中可以包含多条 `#include` 指令。
- 插件自身独立管理图片、音频等资源。

---

## 9. 完整示例

```dsl
ball(main, "mainBall") {
    size(64)
    cornerRadius(16)
    image("main.png")
    location("mainBall", 100, 200)
    status(show, "mainBall")

    singleClick(Launch_macro)

    doubleClick {
        launch("com.example.app", timeout=3000) {
        }
    }

    tripleClick(Turn_off_macros)

    longPress {
        print("长按主球")
    }
}

ball(deputy, "helper") {
    size(48)
    cornerRadius(24)
    image("helper.png")
    location("helper", 0, 0)
    status(hide, "helper")
}

// 副球显示在主球右侧
mainX = found("mainBall", x)
mainY = found("mainBall", y)
location("helper", mainX + 80, mainY)
status(show, "helper")
```

---

## 10. 编程球包格式

```
my_floater/
├── manifest.json
├── floater.dsl
└── assets/
    ├── main.png
    ├── helper.png
    └── click.mp3
```

### 10.1 manifest.json

```json
{
  "id": "com.example.isolation.floater.my",
  "type": "floaterPlugin",
  "name": "我的悬浮球",
  "version": "1.0.0",
  "description": "示例悬浮球插件",
  "author": "user",
  "iconName": "favorite"
}
```

### 10.2 floater.dsl

插件核心脚本，包含多球声明、形态配置与事件触发逻辑。

---

## 11. 默认参数继承链

每个球的最终形态按以下优先级确定：

```
球内声明 > 系统默认悬浮球参数
```

- 未声明 `size` → 使用系统默认悬浮球 `size`。
- 未声明 `cornerRadius` → 使用系统默认悬浮球 `cornerRadius`。
- 未声明 `image` → 使用系统默认悬浮球图标。
- 未声明 `location` → 主球使用系统默认悬浮球位置，副球为 `(0, 0)`。
- 未声明 `status` → 主球默认显示，副球默认隐藏。

---

## 12. 与宏指令的关系

- 编程球本身不直接执行“点击屏幕”“查找颜色”等操作，它通过事件触发响应用户交互。
- 宏脚本中的基础动作指令（`click`、`findText`、`loop` 等）详见 [DSL_SPEC.md](./DSL_SPEC.md)。
- `Launch_macro` 会启动当前已启用的宏；`Turn_off_macros` 会强制停止当前运行中的宏。

---

## 13. 三角函数

表达式中支持 `sin`、`cos`、`tan` 函数，参数为弧度值，返回双精度浮点数。

```dsl
angle = 0.0
for (int i = 0; i < 360; i = i + 1) {
    rad = angle * 3.1415926 / 180.0
    x = 500 + cos(rad) * 200
    y = 500 + sin(rad) * 200
    location("helper", x, y)
    angle = angle + 1.0
}
```

三角函数同时适用于宏脚本和编程球表达式。

---

## 14. 启用球时刷新悬浮球状态

每次启用编程球插件时，系统会：

1. 重新加载并应用当前默认悬浮球配置（大小、圆角、图标、位置）。
2. 清空旧的插件球注册表。
3. 按最新 `floater.dsl` 重新创建所有球，未声明的参数回退到默认悬浮球参数。
4. 执行全局流程步骤，触发初始 `location` / `status` 等动态设置。

这样可以确保修改默认悬浮球设置或更换球文件后，启用插件时看到的是最新状态。
