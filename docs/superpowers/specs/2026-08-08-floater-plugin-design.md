# Floater Plugin / 编程球 设计文档

> 目标：让悬浮球可配置、可插件化，并能在宏执行过程中根据事件改变悬浮球外观/播放音频。

---

## 1. 概述

引入 **编程球（floaterPlugin）** 这一新插件类型。它本质上是一份 DSL 源码，里面用指令声明悬浮球的默认参数和事件监听。普通编程宏通过 `#include <显示名称>` 引用它；未引用时则使用 App 级的**默认悬浮球配置**。

新增 DSL 指令：

- `#include <名称>`：加载某个 floaterPlugin。
- `cornerRadius(dp)`：设置悬浮球圆角。
- `size(dp)`：设置悬浮球尺寸。
- `image("path")` / `image = "path"`：设置悬浮球图片。
- `audio("path")` / `audio = "path"`：播放音频。
- `floater("事件") { ... }`：注册事件监听块。

---

## 2. 默认悬浮球配置

### 2.1 位置

在设置页（`ManageScreen`）新增入口“默认悬浮球”。

### 2.2 可配置项

| 字段 | 类型 | 范围 | 默认值 |
|---|---|---|---|
| `cornerRadius` | int | 0 ~ 28 dp | 28 |
| `size` | int | 40 ~ 80 dp | 56 |
| `imagePath` | String? | jpg / png / gif | null |

### 2.3 存储

使用 `SharedPreferences`，key 为 `default_floater_config` 的 JSON 字符串。

### 2.4 生效逻辑

`FloatingBallService.showFloatingBall()` 时：

1. 若当前宏没有 `#include` 任何 floaterPlugin，读取默认配置。
2. 若 `#include` 了 floaterPlugin，先应用默认配置，再应用 floaterPlugin 中声明的参数（后者覆盖前者）。

---

## 3. floaterPlugin 插件包

### 3.1 包类型

`manifest.json` 中 `type` 字段为 `"floaterPlugin"`。

### 3.2 目录结构

```
plugins/
  com.example.isolation.floater.xxx/
    manifest.json
    floater.dsl          # 编程球 DSL 源码
    assets/
      default.png
      click.png
      click.mp3
```

### 3.3 manifest.json 示例

```json
{
  "id": "com.example.isolation.floater.happy",
  "type": "floaterPlugin",
  "name": "开心球",
  "version": "1.0.0",
  "description": "点击时变开心的悬浮球",
  "author": "user",
  "iconName": "favorite"
}
```

### 3.4 floater.dsl 示例

```dsl
cornerRadius(16)
size(56)
image("default.png")

floater("click") {
    image("click.png")
    audio("click.mp3")
    print("点击于 " + clickX + ", " + clickY)
} else {
    print("点击执行失败")
}

floater("swipe") {
    image("swipe.png")
}

floater("findText") {
    print("找到文字：" + foundText)
} else {
    print("未找到文字")
}
```

### 3.5 创建流程

1. 主界面“编程球”区域点击“新建编程球”。
2. 进入简化版编辑器，默认填充完整模板（覆盖常见事件，并预置调试 `print` 以便查看可用变量）：
   ```dsl
   cornerRadius(16)
   size(56)
   image("default.png")

   floater("click") {
       image("click.png")
       audio("click.mp3")
       print("点击于 " + clickX + ", " + clickY)
   } else {
       print("点击执行失败")
   }

   floater("swipe") {
       print("从 " + swipeFromX + "," + swipeFromY + " 滑到 " + swipeToX + "," + swipeToY)
   }

   floater("findText") {
       print("找到文字：" + foundText)
   } else {
       print("未找到文字")
   }
   ```
3. 用户只需修改数值（圆角、大小、图片名、音频名、print 内容）。
4. 保存时只校验 floaterPlugin 相关指令，生成 manifest + floater.dsl + assets。

### 3.6 设置页与资源导入

floaterPlugin 的设置页包含：

- 名称
- 简介
- **资源管理按钮**：进入资源导入页，可导入 jpg/png/gif 图片和 mp3 音频到插件 `assets/` 目录。

资源导入页与现有编程宏的“导入图片”功能复用同一套文件选择与裁剪逻辑。

不提供宏设置中的循环次数、特征点等参数。

---

## 4. #include 机制

### 4.1 语法

```dsl
#include <开心球>
```

尖括号内为 floaterPlugin 的 `name`（displayName）。

### 4.2 解析

解析为步骤：

```json
{ "type": "include", "displayName": "开心球" }
```

`#include` 只允许出现在顶层。

### 4.3 执行

`MacroExecutor` 遇到 `include` 步骤时：

1. 在已安装插件中按 `name` 查找 floaterPlugin。
2. 若找不到，记录警告并继续。
3. 若找到，解析其 `floater.dsl`。
4. 执行其中的 `cornerRadius` / `size` / `image` 步骤，更新悬浮球外观。
5. 注册其中的 `floater("事件") { ... }` 监听块。

---

## 5. floater 事件监听

### 5.1 语法

```dsl
floater("click") {
    image("click.png")
    audio("click.mp3")
    print("点击于 " + clickX + ", " + clickY)
} else {
    print("点击执行失败")
}
```

`else` 分支可选。当对应指令执行失败时执行 `else` 块。

### 5.2 支持的事件

| 事件 | 触发时机 | 注入变量 | 失败条件 |
|---|---|---|---|
| `click` | 执行 `click` 指令时 | `clickX`, `clickY` | 无有效坐标且不在 find 块内 |
| `swipe` | 执行 `swipe` / `swipeRel` 时 | `swipeFromX`, `swipeFromY`, `swipeToX`, `swipeToY` | 参数无效导致无法滑动 |
| `input` | 执行 `input` 时 | `inputText` | 未找到输入焦点 |
| `findText` | `findText` 命中时 | `foundText` | 未找到文字 |
| `findColor` | `findColor` 命中时 | `foundX`, `foundY` | 未找到颜色 |
| `findImage` | `findImage` 命中时 | `foundX`, `foundY` | 未找到图片 |
| `launch` | `launch` 执行后 | `packageName` | 启动失败 |
| `waitForText` | `waitForText` 命中时 | `foundText` | 超时未命中 |
| `waitForColor` | `waitForColor` 命中时 | `foundX`, `foundY` | 超时未命中 |
| `waitForImage` | `waitForImage` 命中时 | `foundX`, `foundY` | 超时未命中 |

### 5.3 执行时机

事件监听块在对应指令执行**之后**运行。若指令执行失败且存在 `else` 分支，则执行 `else` 块。

### 5.4 块内特殊语义

- `image("path")` 或 `image = "path"`：切换悬浮球图片。
- `audio("path")` 或 `audio = "path"`：播放音频。
- 其他命令按常规执行。

---

## 6. 新增/扩展的 DSL 指令

### 6.1 cornerRadius

```dsl
cornerRadius(16)
```

参数：圆角 dp 值。

### 6.2 size

```dsl
size(56)
```

参数：边长 dp 值。

### 6.3 image

```dsl
image("default.png")
```

参数：assets 下的图片文件名。支持 jpg、png、gif。

### 6.4 audio

```dsl
audio("click.mp3")
```

参数：assets 下的音频文件名。

### 6.5 include

```dsl
#include <开心球>
```

按 displayName 引入 floaterPlugin。

---

## 7. Android 侧实现

### 7.1 FloatingBallService

- 新增 `applyFloaterConfig(cornerRadius, size, imagePath)` 方法。
- 图片路径优先解析为插件 assets 目录；若未找到则回退到默认配置。
- GIF 使用 `android.widget.ImageView` + `pl.droidsonroids.gif:android-gif-drawable` 或系统 `AnimatedImageDrawable`。

### 7.2 音频播放

- 使用 `MediaPlayer` 播放 assets 中的音频文件。
- 若音频文件不存在，静默跳过。

### 7.3 MacroExecutor 通信

- 新增 `FloaterRegistry` 维护当前注册的事件监听块。
- 执行任何指令后，检查是否有对应事件的 floater 块，有则执行。
- `image` / `audio` / `cornerRadius` / `size` 步骤通过 `FloatingBallService` 接口应用。

---

## 8. Flutter 侧实现

### 8.1 文件变更

| 文件 | 改动 |
|---|---|
| `lib/models/plugin.dart` | 识别 `type: "floaterPlugin"`；Plugin 模型无需大改。 |
| `lib/providers/plugin_provider.dart` | 新增保存/加载 floaterPlugin 方法；区分 macro 与 floater 的保存逻辑。 |
| `lib/screens/home_screen.dart` 或主列表 | “编程宏”下方新增“编程球”分隔区。 |
| `lib/screens/floater_editor_screen.dart` | 新建简化编辑器，用于创建/编辑 floaterPlugin。 |
| `lib/screens/floater_settings_screen.dart` | 名称、简介和资源管理入口。 |
| `lib/screens/floater_assets_screen.dart` | 编程球资源导入页（图片+音频）。 |
| `lib/screens/program_macro_screen.dart` | 指令提示条增加 `#include` 和 `floater`。 |
| `lib/services/macro_program_parser.dart` | 解析 `#include`、`cornerRadius`、`size`、`image`、`audio`、`floater`。 |
| `lib/services/macro_syntax_highlighter.dart` | 高亮新关键字。 |
| `docs/DSL_SPEC.md` | 补充新指令和包格式说明。 |

### 8.2 主界面分区

主界面插件列表分两段：

```
编程宏
[宏卡片] [宏卡片]

编程球
[球卡片] [球卡片]
```

用不同标题字体/颜色区分。

---

## 9. DSL_SPEC.md 更新要点

新增章节：

- `#include` 指令
- `floater` 事件监听
- `cornerRadius` / `size` / `image` / `audio` 指令
- 事件注入变量表
- floaterPlugin 包格式

---

## 10. 边界与限制

- 一个宏可 `#include` 多个 floaterPlugin，后加载的覆盖先加载的同名参数。
- `floater` 块内不支持嵌套 `floater`。
- 默认悬浮球配置仅在未 `#include` 时完全生效；`#include` 后仅作为被覆盖的基线。
- 音频播放为异步触发，不阻塞宏执行。

---

## 11. 验收标准

- [ ] 默认悬浮球可在设置页修改圆角、大小、图片。
- [ ] 新建编程球时自动生成带 `cornerRadius`/`size`/`image`/`floater` 的模板。
- [ ] 编程宏中 `#include <名称>` 能正确加载 floaterPlugin 并应用配置。
- [ ] `floater("click") { image("..."); audio("..."); print(...) }` 在 click 执行后触发。
- [ ] 事件变量（如 `clickX`）可在 floater 块内使用。
- [ ] DSL_SPEC.md 更新新指令说明。
