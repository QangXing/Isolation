# Isolation 编程球（floaterPlugin）指令规范

> 本文档专门说明“编程球”插件使用的指令与事件，包括悬浮球外观配置、事件监听、`#include` 引用等内容。宏指令（点击、查找、循环等）请参见 [DSL_SPEC.md](./DSL_SPEC.md)。

---

## 1. 编程球是什么

编程球是一种特殊的插件类型（`floaterPlugin`），用于：

- 自定义悬浮球的外观（圆角、大小、图片）。
- 监听悬浮球相关事件（点击、滑动、长按、查找结果等）。
- 在事件触发时执行指定动作（更换图片、播放音效、打印日志等）。

一个编程球插件可以被多个宏脚本通过 `#include` 引用，从而统一悬浮球行为。

---

## 2. 悬浮球配置指令

这些指令用于设置当前上下文中的悬浮球外观。

### 2.1 cornerRadius

```dsl
cornerRadius(16)
```

设置悬浮球的圆角半径，参数为 dp 单位的整数。

### 2.2 size

```dsl
size(56)
```

设置悬浮球的宽高尺寸，参数为 dp 单位的整数。

### 2.3 image

```dsl
image("default.png")
```

设置悬浮球显示的图片。图片文件应位于 `floaterPlugin` 包目录下的 `assets/` 文件夹中，宏脚本通过文件名引用。

### 2.4 audio

```dsl
audio("ding.mp3")
```

播放指定音效。音频文件同样应位于 `assets/` 文件夹中，仅在事件触发时播放。

---

## 3. 事件监听

### 3.1 floater

```dsl
floater("click") {
    image("click.png")
    audio("click.mp3")
    print("点击于 " + clickX + ", " + clickY)
} else {
    print("点击执行失败")
}
```

`floater("事件名") { ... }` 用于监听某个宏指令或悬浮球交互事件的执行结果：

- 当对应事件成功执行后，运行主块内的指令。
- 可选的 `else { ... }` 块在对应事件执行失败时运行。
- 块内会自动注入与该事件相关的变量，可用于 `print`、条件判断或其他指令参数。

### 3.2 事件注入变量

| 事件 | 注入变量 | 说明 |
|---|---|---|
| `click` | `clickX`、`clickY` | 点击发生时的屏幕坐标 |
| `swipe` / `swipeRel` | `swipeFromX`、`swipeFromY`、`swipeToX`、`swipeToY` | 滑动的起点与终点坐标 |
| `findText` / `waitForText` | `foundText` | 命中目标的文字内容 |
| `findColor` / `waitForColor` / `findImage` / `waitForImage` | `foundX`、`foundY` | 命中目标在屏幕上的坐标 |
| `input` | `inputText` | 本次输入的文字内容 |
| `launch` | `packageName` | 启动的应用包名 |
| `singleClick` / `doubleClick` / `tripleClick` / `longPress` | 无 | 悬浮球本身的多击/长按事件 |

这些变量仅在当前 `floater` 块内有效，离开块后不再保证其值。

---

## 4. 插件引用

### 4.1 #include

```dsl
#include <插件显示名称>
```

引用一个 `floaterPlugin` 插件。被引用插件的 `floater.dsl` 中的悬浮球配置和事件处理器会进入当前宏脚本的执行上下文。

- `<...>` 内填写插件的显示名称，即 `manifest.json` 中的 `name` 字段。
- 一个宏脚本中可以包含多条 `#include` 指令。
- 插件自身独立管理图片、音频等资源。

---

## 5. 完整示例

```dsl
cornerRadius(16)
size(56)
image("default.png")

// 悬浮球被点击时切换图片并播放音效
floater("click") {
    image("click.png")
    audio("click.mp3")
    print("点击于 " + clickX + ", " + clickY)
}

// 找到目标文字后给出视觉/听觉反馈
floater("findText") {
    image("found.png")
    audio("found.mp3")
    print("找到文字：" + foundText)
}

// 滑动后打印起止坐标
floater("swipe") {
    print("从 " + swipeFromX + "," + swipeFromY + " 滑到 " + swipeToX + "," + swipeToY)
}
```

---

## 6. 编程球包格式

一个完整的 `floaterPlugin` 包目录结构如下：

```
my_floater/
├── manifest.json
├── floater.dsl
└── assets/
    ├── default.png
    ├── click.png
    └── click.mp3
```

### 6.1 manifest.json

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

### 6.2 floater.dsl

插件核心脚本，包含悬浮球配置与事件监听逻辑，参见上文完整示例。

---

## 7. 与宏指令的关系

- 编程球本身不直接执行“点击屏幕”“查找颜色”等操作，它通过事件监听响应宏指令的执行结果。
- 宏脚本中的基础动作指令（`click`、`findText`、`loop` 等）详见 [DSL_SPEC.md](./DSL_SPEC.md)。
