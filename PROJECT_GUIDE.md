# Isolation 项目指南

> 本文档整合了 Isolation 项目的原始设计介绍、当前已知问题分析与下一步改进方案，作为后续开发的统一参考。

---

## 一、项目介绍

### 1.1 项目目标

Isolation 是一款 Android 平台的**跨应用自动化宏插件应用**，将原本功能单一的悬浮球小键盘改造为可录制、可回放、可导入导出的自动化触发器。

核心目标：

- 用户能在任意 App 中录制一系列点击操作。
- 录制结果保存为 `.isoplugin` 宏插件，可导入 / 导出 / 分享。
- 启用宏后，点击悬浮球即可在目标 App 中自动执行该宏。
- 优先使用 Accessibility 节点信息回放，节点不可见时回退到屏幕坐标。

### 1.2 技术栈

| 层 | 技术 |
|----|------|
| UI 层 | Flutter（Dart） |
| 原生层 | Kotlin（Android） |
| 通信 | MethodChannel `com.example.isolation` |
| 状态管理 | provider |
| 持久化 | shared_preferences + 应用私有目录文件 |
| 打包 | `.isoplugin`（zip 压缩包） |

### 1.3 现有架构

```
┌─────────────────────────────────────────────────┐
│                  Flutter (Dart)                  │
│  ┌────────────┐ ┌────────────┐ ┌─────────────┐  │
│  │ HomeScreen │ │ManageScreen│ │ AboutScreen │  │
│  └────────────┘ └────────────┘ └─────────────┘  │
│  ┌──────────────────────────────────────────┐   │
│  │ RecordingScreen  MacroSettingsScreen     │   │
│  └──────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────┐   │
│  │       PluginProvider (ChangeNotifier)    │   │
│  └──────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────┐   │
│  │     NativeChannel  ←→  MethodChannel     │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────┘
                          │
┌─────────────────────────┴───────────────────────┐
│                Kotlin (Android)                  │
│  ┌──────────────┐  ┌──────────────────────────┐ │
│  │ MainActivity │  │  InputAccessibilityService│ │
│  └──────────────┘  └──────────────────────────┘ │
│  ┌──────────────────┐  ┌────────────────────┐   │
│  │ FloatingBallService│  │   MacroExecutor    │   │
│  └──────────────────┘  └────────────────────┘   │
│  ┌──────────────────────────────────────────┐   │
│  │       ScreenCaptureHelper / Keyboard     │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### 1.4 数据模型

**MacroStep**：单个宏步骤，关键字段：

| 类型 | 说明 | 关键字段 |
|------|------|----------|
| `clickNode` | 按节点信息点击 | `target { resourceId, text, className, bounds }` |
| `clickPoint` | 按坐标点击 | `point { x, y }` |
| `swipe` | 滑动 | `start, end, duration` |
| `wait` | 等待 | `duration` |
| `back` / `home` / `recents` | 系统按键 | - |
| `launchApp` | 打开指定 App | `packageName` |
| `inputText` | 向焦点输入框注入文字 | `text` |

**MacroSettings**：宏全局设置，包含 `smartRecognition`（智能识别）、`loopCount`（循环次数，0 表示无限）。

**MacroPlugin（manifest.json）**：

```json
{
  "id": "com.example.isolation.macro.xxx",
  "name": "宏名称",
  "version": "1.0.0",
  "actions": [{ "type": "macro", "label": "运行", "macroFile": "macro.json" }]
}
```

### 1.5 录制与回放流程

**录制流程**：

1. Flutter 调用 `NativeChannel.startRecording()`。
2. `InputAccessibilityService` 进入录制状态。
3. 监听 `AccessibilityEvent.TYPE_VIEW_CLICKED`，过滤本应用包名事件。
4. 对每个有效点击提取 `resourceId`、`text`、`className`、`bounds`，生成 `MacroStep`。
5. Flutter 调用 `stopRecording()` 获取步骤列表。

**回放流程**：

1. Flutter 调用 `executeMacro` 并传入步骤数组。
2. `MacroExecutor` 按顺序执行：
   - `clickNode`：优先按 `resourceId` 匹配，其次 `text` / `contentDescription`，最后 `className + bounds`，未找到则回退坐标点击。
   - `clickPoint`：使用 `GestureDescription` 派发点击。
   - 每步前等待 `delay` 毫秒。
3. 三连击悬浮球可强制停止循环。

### 1.6 主要文件清单

| 路径 | 说明 |
|------|------|
| `lib/main.dart` | 应用入口与底部导航 |
| `lib/screens/home_screen.dart` | 主页：插件列表 |
| `lib/screens/manage_screen.dart` | 管理页：新建 / 导入 / 编辑宏 |
| `lib/screens/recording_screen.dart` | 录制页：录制 + 编辑步骤 |
| `lib/screens/macro_settings_screen.dart` | 宏设置页 |
| `lib/screens/about_screen.dart` | 说明页 |
| `lib/providers/plugin_provider.dart` | 状态管理 |
| `lib/services/native_channel.dart` | Flutter ↔ 原生通道 |
| `lib/services/plugin_manager.dart` | 插件管理（导入 / 删除 / 持久化） |
| `lib/models/macro.dart` | 宏数据模型 |
| `lib/models/plugin.dart` | 插件数据模型 |
| `android/.../MainActivity.kt` | 原生入口、MethodChannel 处理 |
| `android/.../InputAccessibilityService.kt` | 辅助功能服务（录制 + 回放） |
| `android/.../FloatingBallService.kt` | 悬浮球服务 |
| `android/.../MacroExecutor.kt` | 宏执行引擎 |
| `android/.../ScreenCaptureHelper.kt` | 屏幕截图（颜色识别） |

### 1.7 权限

- **悬浮窗权限**（SYSTEM_ALERT_WINDOW）：显示悬浮球。
- **辅助功能权限**（BIND_ACCESSIBILITY_SERVICE）：录制点击事件并回放宏。
- **前台服务权限**：保持悬浮球后台运行。
- **屏幕录制权限**：智能识别模式下读取像素颜色。

---

## 二、当前存在的问题

### 2.1 Bug 1：已开启辅助功能仍提示未开启

**现象**：用户已经在系统设置中授予了辅助功能权限，但使用时仍然提示"请先开启辅助功能权限"。

**根因分析**：

- `InputAccessibilityService.isEnabled(context)` 通过读取 `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES` 判断服务是否在系统设置中启用，返回 `true`。
- 但 `InputAccessibilityService.executeMacro()` 等静态方法内部判断的是 `instance`（即 `onServiceConnected` 中赋值的运行时实例），而**不是** `isEnabled`。
- 当服务在系统设置中已启用、但 `onServiceConnected` 尚未回调（例如系统重启服务、应用重装、服务被回收后未触发事件）时，`instance` 仍为 `null`。
- 静态方法此时仅依据 `instance == null` 就弹出"请先开启辅助功能权限"，造成误导。

**位置**：`android/app/src/main/kotlin/com/example/isolation/InputAccessibilityService.kt` 的 `startRecording` / `stopRecording` / `executeMacro` / `dispatchClick` 等静态方法。

### 2.2 Bug 2：其他应用中点击悬浮球无反应

**现象**：悬浮球显示正常，但在其他 App 中点击悬浮球没有任何反馈。

**根因分析**：

- `FloatingBallService.runEnabledMacro()` 内部调用 `InputAccessibilityService.executeMacro()`，当 `instance == null` 时仅弹 `Toast`，没有触发气泡（`showBubble`）反馈，用户看不到。
- 同时由于 Bug 1 的存在，即使辅助功能已开启，也会因 `instance == null` 提前 return，宏根本没被调度执行。
- 此外，`FloatingBallService` 中 `ball.setOnOnTouchListener` 直接消费了所有 touch 事件并返回 `true`，长按监听被吞掉（次要问题）。
- `notifyFloatingBallClick` 与 `runEnabledMacro` 调用顺序导致单次点击也走"三连击停止"的计数逻辑，体验上不够直观。

**位置**：`android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt`、`InputAccessibilityService.kt`。

### 2.3 Bug 3：文字气泡显示位置错误

**现象**：执行宏时弹出的状态气泡位置不在悬浮球附近，有时甚至看不到。

**根因分析**：

- `showBubble()` 中使用 `ballParams.x + floatingView?.width + 16` 作为气泡 x 坐标，但 `floatingView?.width` 在首次显示时常为 0（未完成布局测量）。
- 当悬浮球位于屏幕右半屏时，气泡会超出屏幕右侧被裁剪。
- 气泡 y 坐标直接取 `ballParams.y`，未做边界裁剪，悬浮球贴近上下边缘时气泡会被遮挡。

**位置**：`FloatingBallService.kt` 的 `showBubble()` 方法。

---

### 2.4 Bug 4：`find(image=...)` / `if(image=...)` 图片匹配不准确

**现象**：编程宏使用 `find(image="...")` 或 `if(image="...")` 判断屏幕上的图片时，经常找不到目标或位置偏差较大。

**根因分析**：

- 早期实现只做单一尺度的 OpenCV 模板匹配，当目标 App 的 UI 缩放、字体大小、分辨率与模板不一致时，匹配分数低于阈值。
- 没有颜色校验，灰度匹配在颜色相近但形状不同的区域容易误命中。
- 没有降噪处理，屏幕截图中的压缩噪点会拉低匹配分数。

**修复方向**：

- 多尺度匹配：模板在 0.8x ~ 1.2x 范围内逐步缩放，取最优匹配。
- 高斯模糊：匹配前对模板和屏幕截图做 3x3 模糊，降低噪点影响。
- 颜色通道匹配：灰度匹配分数不足时，在 RGB 空间再做一次跨尺度匹配，取最高分为准。

**位置**：`android/app/src/main/kotlin/com/example/isolation/ImageFinder.kt`。

### 2.5 Bug 5：图片裁剪框无法移动/缩放

**现象**：导入图片作为模板时，裁剪框是固定矩形，不能拖动、放大或缩小。

**根因分析**：原 `ImageCropScreen` 只展示一个静态矩形遮罩，没有手势处理。

**修复方向**：改为圆形裁剪框，支持 `GestureDetector.onScaleUpdate` 拖动与捏合缩放，右下角同时提供单指缩放手柄；裁剪结果保持 1:1 正圆，最长边不超过 320px。

**位置**：`lib/screens/image_crop_screen.dart`。

### 2.6 Bug 6：专业编程区行号不对齐

**现象**：`ProfessionalEditorScreen` 左侧行号与右侧代码行的垂直位置不一致，代码换行后错位更明显。

**根因分析**：行号高度按固定单倍行高计算，没有考虑自动换行导致的实际行高变化。

**修复方向**：使用 `TextPainter.computeLineMetrics()` 动态计算每一逻辑行的视觉高度，同步滚动控制器，使行号与代码行一一对应。

**位置**：`lib/screens/professional_editor_screen.dart`。

### 2.7 Bug 7：悬浮球固定提示语覆盖 `print` 输出

**现象**：宏执行时悬浮球先弹出“开始执行宏”“宏运行中”等固定气泡，随后被“执行第 N 步”等框架状态覆盖，导致宏内 `print("...")` 的内容一闪而过或根本看不到。

**根因分析**：`MacroExecutor` 每执行一步都 `postStatus("执行第 N 步: ...")`，与 `print` 共用同一个 `onMacroStatus` 通道；`FloatingBallService` 对所有状态都弹气泡，print 消息被框架状态快速替换。

**修复方向**：

- 将 `print` 与框架生命周期状态分离，`MacroExecutorListener` 新增 `onMacroPrint(message)`。
- `print` 指令只触发 `onMacroPrint`。
- `FloatingBallService` 只在 `onMacroPrint` 时显示气泡，框架状态不再占用水泡。
- 录制停止时自动在宏首尾插入 `print("开始")` / `print("完成")`，替代原来的固定提示语。
- 修复 `showBubble` 水平方向未裁剪导致的越屏/遮挡问题。

**位置**：`FloatingBallService.kt`、`MacroExecutor.kt`、`RecordingScreen.dart`。

---

## 三、改进建议

### 3.1 改进 1：宏互斥启用

**需求**：所有宏插件只能开启一个；启用任意一个时，其余宏插件强制关闭。

**实现思路**：

- 在 `PluginManager.setEnabled(id, enabled)` 中，当 `enabled == true` 且该插件是宏插件时，遍历所有其他宏插件，将它们的 `enabled` 置为 `false`。
- `PluginProvider.setEnabled()` 调用底层后，同步刷新 UI 状态。
- 主页 / 管理页的开关 UI 自动反映互斥效果。

**改动文件**：`lib/services/plugin_manager.dart`、`lib/providers/plugin_provider.dart`。

### 3.2 改进 2：可视化编程宏

**需求**：将录制宏的机制改为可视化编程模式，在管理页提供"编程宏"入口，支持内置指令：

| 指令 | 含义 | 示例 |
|------|------|------|
| `click` | 点击（坐标或目标） | `click(500, 800)` / `click(text="签到")` |
| `roll` | 滚动 | `roll(0, 300, 500)` |
| `print` | 显示悬浮文字 | `print("开始签到")` |
| `for` | 循环 | `for(5) { click(...); print(...) }` |
| `find` | 寻找元素 | `find(text="领取") { click(...) }` |
| `if` | 条件分支 | `if(find(text="领")) { click(...) } else { print("无") }` |

**实现思路**：

- 新增指令类型枚举：`click` / `roll` / `print` / `for` / `find` / `if`。
- 新增 `ProgramMacroScreen`：代码编辑器 + 指令面板。
- 在 `ManageScreen` 添加"编程宏"按钮，与"新建宏"并列。
- 实现 DSL 解析器：`lib/services/macro_program_parser.dart`，将代码字符串解析为步骤树（支持嵌套块）。
- 原生 `MacroExecutor` 扩展：支持 `roll`（手势滑动）、`print`（通过 listener 回调到 `FloatingBallService.showBubble`）、`for`（循环块）、`find`（节点查找 + 子块执行）、`if`（条件判断）。
- 步骤数据结构改为支持 `children` 嵌套（树形结构）。

**改动文件**：

- 新增：`lib/screens/program_macro_screen.dart`、`lib/services/macro_program_parser.dart`、`lib/models/macro_instruction.dart`
- 修改：`lib/screens/manage_screen.dart`、`lib/models/macro.dart`、`lib/providers/plugin_provider.dart`、`android/.../MacroExecutor.kt`、`android/.../FloatingBallService.kt`

### 3.3 改进 3：录制区域显示为可编辑代码

**需求**：录制宏时，录制好的区域不再只显示步骤列表，而是显示为编程代码；用户可手动修改代码后保存。

**实现思路**：

- 在 `RecordingScreen` 的编辑器区域，把已录制的步骤渲染为 DSL 代码文本（`click(...)` / `roll(...)` 等）。
- 提供可编辑 `TextField`，用户能直接修改代码。
- 保存时调用 `MacroProgramParser` 将代码解析为步骤树，再走原有 `saveMacroPlugin` 流程。
- 同时保留"步骤卡片视图"和"代码视图"两种切换。

**改动文件**：`lib/screens/recording_screen.dart`、`lib/services/macro_program_parser.dart`。

---

## 四、验收清单

### Bug 修复验收

- [x] 已开启辅助功能后，点击悬浮球不再误报"未开启辅助功能权限"。
- [x] 在第三方 App 中点击悬浮球能触发宏执行，并在悬浮球附近显示状态气泡。
- [x] 气泡显示位置紧邻悬浮球，靠近屏幕边缘时自动避开裁剪。

### 改进验收

- [x] 主页启用一个宏后，其他宏自动关闭。
- [x] 管理页提供"编程宏"入口，可创建基于代码的宏。
- [x] 编程宏支持 `click` / `roll` / `print` / `for` / `find` / `if` 指令。
- [x] 编程宏保存后可被悬浮球执行。
- [x] 录制页编辑器支持代码视图，可手动修改并保存。
- [x] 代码视图与步骤卡片视图可互相切换。

---

## 五、实现状态

> 本节记录上述所有 Bug 修复与改进的实际落地情况，便于回归验证与后续维护。

### 5.1 Bug 1 修复：辅助功能就绪状态三态判定

**改动文件**：[InputAccessibilityService.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/InputAccessibilityService.kt)

- 新增 `readinessState(context)`：返回 `0`（就绪）/ `1`（系统设置未启用）/ `2`（已启用但实例未连上）。
- 新增 `notifyNotReady(context)`：根据状态码显示更准确的 Toast，避免误报"未开启辅助功能"。
- `startRecording` / `stopRecording` / `executeMacro` / `dispatchClick` 均改为通过 `notifyNotReady` 守卫，仅在 `state == 0` 时继续执行。
- 新增 `onUnbind` 清理 `instance`，避免服务解绑后残留旧实例。

### 5.2 Bug 2 修复：悬浮球触摸反馈与单击/长按区分

**改动文件**：[FloatingBallService.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt)

- 引入 `CLICK_SLOP_PX` / `LONG_CLICK_TIMEOUT_MS` 常量，使用 `Handler.postDelayed` 实现 600ms 长按判定，替代易被吞掉的 `setOnLongClickListener`。
- `ACTION_DOWN` 时记录起点并启动长按定时器；`ACTION_MOVE` 超出 slop 立即取消长按；`ACTION_UP` 在 slop 内且未触发长按则视为单击。
- 单击时先调用 `MacroExecutor.notifyFloatingBallClick`（三连击停止计数），再调用 `runEnabledMacro`，所有状态（未启用宏 / 辅助功能未就绪 / 开始执行）均通过 `showBubble` 给出反馈。
- 新增 `ACTION_CANCEL` 处理，避免拖动中断时定时器泄漏。

### 5.3 Bug 3 修复：气泡定位算法重写

**改动文件**：[FloatingBallService.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt)

- 引入 `BALL_SIZE_DP` / `BUBBLE_GAP_DP` 常量，使用 `resources.displayMetrics.density` 转 px。
- `showBubble()` 在定位前先调用 `View.measure()` 触发测量，拿到 `measuredWidth` / `measuredHeight`。
- 横向：默认放悬浮球右侧，若右侧空间不足则自动切到左侧。
- 纵向：以悬浮球中心为基准居中对齐，靠近上下边缘时做 `clamp`，避免被裁剪。
- 新增 `clampToScreen()` 限制悬浮球本身被拖出屏幕，保证后续气泡定位计算始终有效。

### 5.4 改进 1：宏互斥启用

**改动文件**：[plugin_manager.dart](file:///workspace/Isolation/lib/services/plugin_manager.dart)

- 在 `setEnabled(id, enabled)` 中，当 `enabled == true` 且目标插件含 `macro` 类型 action 时，遍历其他所有宏插件并强制 `enabled = false`。
- 通过 `savePlugins()` 持久化互斥结果，主页 / 管理页的开关会随 `PluginProvider` 通知自动刷新。

### 5.5 改进 2：可视化编程宏

**新增文件**：

- [macro_program_parser.dart](file:///workspace/Isolation/lib/services/macro_program_parser.dart)：DSL 解析与序列化器。
- [program_macro_screen.dart](file:///workspace/Isolation/lib/screens/program_macro_screen.dart)：编程宏编辑页（代码编辑器 + 指令面板 + 校验 + 保存）。

**改动文件**：

- [manage_screen.dart](file:///workspace/Isolation/lib/screens/manage_screen.dart)：在"新建宏"与"导入"之间新增"编程宏"按钮；宏卡片右侧新增 `Icons.code_rounded` 图标按钮可一键跳转编辑为编程宏。
- [MacroExecutor.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt)：重构为递归 `executeSteps` / `executeStep`，新增 `executeClickStep` / `executeRollStep` / `executeForStep` / `executeFindStep` / `executeIfStep` / `evaluateCondition`；新增 `dispatchSwipe`、`screenCenter`。保留对 `clickNode` / `clickPoint` / `swipe` / `launchApp` / `inputText` 的兼容。

**DSL 语法示例**：

```
print("开始签到")
// 颜色查找命中后点击该位置
find(color=0xFF5000, tolerance=20) {
    click()
    wait(500)
}
// 节点文字查找命中后点击该位置
find(text="签到") {
    click()
    roll(0, 300, 400)
    wait(500)
}
for(3) {
    roll(0, 300, 400)
    wait(500)
}
if(find(color=0x00FF00)) {
    click()
} else {
    print("今日无奖励")
}
```

**支持指令总览**：

| 指令 | 形式 | 说明 |
|------|------|------|
| `click` | `click(x, y)` 或 `click()` | 坐标点击；无参时点击最近 `find` 命中的坐标 |
| `roll` | `roll(dx, dy, duration)` | 以屏幕中心为起点派发手势滑动 |
| `print` | `print("消息")` | 通过 `MacroExecutorListener` 回调到悬浮球气泡 |
| `wait` | `wait(ms)` | 睡眠等待 |
| `for` | `for(n) { ... }` | 循环块 |
| `find` | `find(color=0xRRGGBB, tolerance=20) { ... }` 或 `find(text="..." ) { ... }` | 颜色或节点查找，命中时把坐标压栈并执行子块 |
| `if` | `if(find(...)) { ... } else { ... }` | 条件分支；条件命中时坐标同样压栈，then 块内可 `click()` |
| `back` / `home` / `recents` | `back()` 等 | 系统按键 |

> **关于 click 语义**：`click` 仅支持坐标点击（`click(x, y)`）或在 `find` / `if(find)` 块内点击命中位置（`click()`）。
> 不再提供 `click(text="...")` 形式 —— 文字/颜色查找统一交给 `find`，避免依赖屏幕文字识别（OCR）。
> 旧录制产生的 `clickNode` 在序列化时会自动转为 `find(target) { click() }` 形式，兼容存量宏。

### 5.6 改进 3：录制页代码视图

**改动文件**：[recording_screen.dart](file:///workspace/Isolation/lib/screens/recording_screen.dart)

- 新增 `_codeView` 开关与 `_codeController`。
- AppBar 新增切换按钮：`Icons.code_rounded` 切到代码视图，`Icons.list_rounded` 切回步骤卡片视图。
- 切换前调用 `_syncCodeFromSteps` / `_syncStepsFromCode` 双向同步。
- "返回录制"按钮与 `_showSaveDialog` 保存逻辑均增加 `if (_codeView) _syncStepsFromCode();` 守卫，确保手动编辑的代码不会丢失。
- 代码视图使用深色背景（`0xFF1E1E1E`）+ 等宽字体，与 `ProgramMacroScreen` 风格一致。

### 5.7 兼容性说明

- 旧录制产生的 `clickNode` / `clickPoint` / `swipe` 步骤仍可被 `MacroExecutor` 执行（`clickNode` 走节点查找 + 坐标回退；`clickPoint` 直接坐标点击）。
- `MacroProgramParser.serialize` 在序列化旧类型时自动转为新 DSL 写法：
  - `swipe` → `roll(dx, dy, duration)`
  - `clickNode(text="...")` → `find(text="...") { click() }`（保留语义且符合新规范）
  - `clickNode` 仅有 `bounds` 时 → `click(cx, cy)`（直接转坐标）
  - `clickPoint` → `click(x, y)`
- 旧 `.isoplugin` 包导入后仍可用，进入"编程宏"编辑页时会自动序列化为代码形式。

### 5.8 颜色查找实现（v2）

针对"`click(text=...)` 依赖节点信息、在 WebView/游戏/Canvas 场景失效"的问题，DSL 语义已收敛：

- `click` 只接受坐标；文本/颜色查找统一交给 `find`。
- `find(color=0xRRGGBB, tolerance=20)` 通过 [ScreenCaptureHelper.findColor](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/ScreenCaptureHelper.kt) 全屏扫描像素（默认步长 4，可在性能与精度间权衡）。
- 命中坐标通过 `MacroExecutor.foundCoordinates` 栈传递给子块，`click()` 无参时取栈顶点击；`if(find(...))` 命中时同样压栈。
- 颜色查找需要屏幕录制权限，未授权时 `find` 会 postStatus 提示并跳过。

### 5.9 坐标调试页（v2）

**新增文件**：[coordinate_debug_screen.dart](file:///workspace/Isolation/lib/screens/coordinate_debug_screen.dart)

**入口位置**：[manage_screen.dart](file:///workspace/Isolation/lib/screens/manage_screen.dart) 工具栏下方独立卡片"坐标调试"。

**用途**：用户从相册选一张屏幕截图作为背景，在图片上点击任意位置，获取该点的坐标与像素颜色，并一键复制为 `click(x, y)` 或 `find(color=0xRRGGBB, tolerance=20) { click() }` 代码片段。

**核心机制**：

- 用 `file_picker` 选图，`image` 包（`pubspec.yaml` 新增 `image: ^4.2.0`）解码得到像素 buffer。
- 用 `LayoutBuilder` 计算 `BoxFit.contain` 下图片的实际显示矩形（含 letterbox 偏移）。
- 点击位置 → Flutter widget 坐标 → 减去 letterbox 偏移 → 按 `image.width / displayWidth` 缩放 → 得到图片像素坐标。
- **坐标系等价**：图片像素坐标 = Android 屏幕像素坐标。前提是用户上传的截图来自该设备的系统截屏（未裁剪）。
- 取色：`image.getPixel(imgX, imgY)` 直接读 R/G/B，组合为 `0xRRGGBB`。
- 预编码：选图时一次性 `img.encodeJpg` 缓存为 `Uint8List`，避免每帧重新编码。

**交互**：

| 操作 | 效果 |
|------|------|
| 点击图片 | 在该位置打点，记录 `(x, y, color)` |
| 点击图片上的点 | 弹出底部菜单：复制 `click(x,y)` / 复制 `find(color=)` 代码 / 删除 |
| 列表项 `touch_app` 按钮 | 复制 `click(x, y)` |
| 列表项 `colorize` 按钮 | 复制 `find(color=0xRRGGBB, tolerance=20) { click() }` |
| 顶部"清空"按钮 | 清除所有采点 |
| 顶部"选择截图"按钮 | 重新选图 |

**坐标系提示**（页内常驻）：

> 坐标 = 图片像素坐标 = Android 屏幕像素
> 原点：左上角 (0,0)  ·  单位：像素(px)

### 5.10 UI 设计规范（v2）

全应用统一的视觉与交互规范，新增/修改页面必须遵守。

#### 颜色

| 用途 | 颜色 | 说明 |
|------|------|------|
| 主背景 | `Colors.white` | 全局 scaffoldBackgroundColor |
| 主文本 | `Colors.black.withValues(alpha: 0.85)` | 标题、列表项名称 |
| 次文本 | `Colors.black.withValues(alpha: 0.6)` / `Colors.grey.withValues(alpha: 0.7)` | 描述、辅助说明 |
| 主按钮填充 | `Colors.black87` | "保存宏"、"选择截图"、权限检查按钮 |
| 主按钮文字 | `Colors.white` | 与主按钮填充对比 |
| 次按钮填充 | `Colors.black.withValues(alpha: 0.05)` | "校验"、"返回录制" |
| 危险操作 | `Colors.redAccent` + `Colors.red.withValues(alpha: 0.08)` 背景 | 删除按钮 |
| 强调色 | `Colors.redAccent` | 录制按钮、错误 SnackBar |
| 警告色 | `Colors.orangeAccent` | 未授权提示 |

#### 字号

| 用途 | 字号 | 字重 |
|------|------|------|
| 页面大标题 | 28 | w300 |
| AppBar 标题 | 默认 | w500 |
| 卡片标题 | 16 | w600 |
| 列表项主标题 | 15 | w600 / w500 |
| 正文 | 13-14 | normal |
| 辅助文字 | 11-12 | normal |
| 代码字面量 | 12-14 | monospace |

#### 间距

| 用途 | 数值 |
|------|------|
| 页面水平边距 | 20 |
| 卡片间距 | 12-14 |
| 卡片内边距 | 16（GlassCard 默认） |
| 按钮水平间距（同一 Row） | 12 |
| 图标按钮水平间距 | 6 |
| 底部安全区下方留白 | 24 |

#### 圆角

| 元素 | 圆角 |
|------|------|
| GlassCard | 20（默认） |
| 主按钮 | 16 |
| 次按钮 / Chip | 12 |
| 图标按钮 | 10 |
| 弹窗 | 20 |

#### 控件样式规范

**主按钮**（"保存宏"、"选择截图"等）：
```dart
Container(
  padding: EdgeInsets.symmetric(vertical: 14, horizontal: 28),
  decoration: BoxDecoration(
    color: Colors.black87,
    borderRadius: BorderRadius.circular(16),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(..., color: Colors.white, size: 18),
      SizedBox(width: 8),
      Text(..., style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: w600)),
    ],
  ),
)
```

**次按钮**（"校验"、"返回录制"等）：同主按钮，但 `color: Colors.black.withValues(alpha: 0.05)`，文字 `Colors.black87`。

**图标按钮**（卡片右侧操作）：固定 8 padding + 10 圆角，[manage_screen.dart#L283-L322](file:///workspace/Isolation/lib/screens/manage_screen.dart#L283-L322) 的 `_IconAction`。

**GlassCard 内按钮组**：用 `Row + Expanded + SizedBox(width: 12)` 实现，统一高度 48。

**FilledButton / ElevatedButton / OutlinedButton**：**禁止使用** Material 3 默认按钮，全部用自定义 Container + GestureDetector 风格，确保视觉一致。

#### 页面结构

| 页面类型 | 结构 |
|----------|------|
| 主 tab 页（主页/管理/说明） | `CustomScrollView` + `SliverToBoxAdapter` 标题 + `SliverPadding` 内容 |
| 子页面（录制/编辑/设置/调试） | `Scaffold` + `AppBar`（白底，无阴影）+ `Column`（内容 + 底部按钮栏） |
| 底部按钮栏 | `Container(margin: EdgeInsets.fromLTRB(20, 0, 20, 24))` + `SafeArea(top: false)` |

#### 已修正的不一致

| 问题 | 修正 |
|------|------|
| 管理页顶部按钮高度不齐 | 用 `_ActionTile` 统一高度 48 |
| 管理页插件卡片右侧按钮无间距 | 用 `_IconAction` 统一 `margin: left 6` |
| 说明页两个权限按钮各占一整行 | 合并到一张 GlassCard 内，`Row + Expanded` 等宽 |
| 坐标调试页用 `FilledButton.icon`（蓝色调） | 改为黑色填充圆角按钮，与其他页一致 |
| 管理页"坐标调试"按钮独占一行但样式同主操作 | 用 `_ActionTile(full: true)` 显式标记为辅助操作 |

### 5.11 悬浮球二次检查与修正（v2）

对 [FloatingBallService.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt) 做了一次完整 review，发现并修复了 6 个问题。

| 严重度 | 问题 | 修正 |
|--------|------|------|
| 🔴 严重 | 单击时无条件调用 `notifyFloatingBallClick` 累加计数，宏未运行也会被三连击触发"已强制停止" Toast，宏运行时单击会立即累加计数导致刚启动就被停止 | 抽出 `onBallSingleClick()`：宏运行中才走三连击逻辑，宏未运行时直接走 `runEnabledMacro`，互不干扰 |
| 🟡 中 | 宏运行中再次单击会被 `MacroExecutor.execute` 的 `if (running) return` 静默吞掉，用户无反馈 | `onBallSingleClick` 中通过 `MacroExecutor.isRunning()` 显式判断，未触发停止时显示气泡"宏运行中，三连击停止" |
| 🟡 中 | `notifyFloatingBallClick` 返回 `void`，调用方无法区分"仅计数"与"触发停止" | 改为返回 `Boolean`，触发停止返回 `true`，调用方据此决定是否还要弹气泡 |
| 🟡 中 | `MacroExecutor.running` 是 `private`，companion `isRunning()` 无法读取 | 改为 `@Volatile internal var running`，新增 `isRunning()` 和 `stopActive()` 静态方法 |
| 🟡 中 | 长按阈值 600ms 偏长，用户容易误判为单击失败就抬手 | 缩短到 `LONG_CLICK_TIMEOUT_MS = 400L`（接近 Android 标准 longPressTimeout 500ms 但更灵敏） |
| 🟡 中 | 气泡用 `android.R.drawable.dialog_holo_light_frame` 背景，是 Holo 时代旧样式，与简洁白色风格不符 | 改用 `GradientDrawable` 自绘：圆角 12dp、白色 95% 透明、1px 灰边 |
| 🟢 低 | `FLAG_LAYOUT_NO_LIMITS` 让悬浮球可被拖到状态栏/导航栏下被遮挡 | 去掉该 flag，让 WindowManager 自动限制在应用可见区域 |
| 🟢 低 | `screenSize()` 用 `getRealMetrics`（含系统 UI）做 clamp，与去 flag 后的可见区域不一致 | 改用 `getMetrics`（不含状态栏/导航栏），clamp 更准确 |
| 🟢 低 | 初始位置 `(100, 300)` 在小屏上可能超出可见区域 | `showFloatingBall` 中设置完 params 后立即调 `clampToScreen(params)` |
| 🟢 低 | `onDestroy` 只清理 `longClickRunnable`，未清理 `bubbleHideRunnable`，可能内存泄漏 | 同时 `removeCallbacks(bubbleHideRunnable)` |
| 🟢 低 | 服务销毁时若有宏在运行不会停止，造成线程泄漏 | 新增 `MacroExecutor.stopActive()`，`onDestroy` 中调用 |

**核心改进：单击/三连击逻辑分离**

修正前的逻辑：
```
单击 → notifyFloatingBallClick() 计数+1 → runEnabledMacro() 启动宏
连续单击 3 次 → 第 3 次启动宏 + 触发"已强制停止" Toast → 宏刚启动就被停
宏未运行时三连击 → 弹"已强制停止循环" Toast → 用户困惑
```

修正后的逻辑：
```
单击 → onBallSingleClick()
       ├─ MacroExecutor.isRunning() == true
       │    → notifyFloatingBallClick() 计数+1
       │    → 达 3 次：stop + Toast"已强制停止循环"
       │    → 未达 3 次：气泡"宏运行中，三连击停止"
       └─ MacroExecutor.isRunning() == false
            → runEnabledMacro()
            → 检查辅助功能 → 检查已启用宏 → 启动执行
```

**触摸状态机保留**：长按 400ms → 打开 MainActivity；拖动 > 12px → 取消长按 + 取消单击；ACTION_CANCEL 同 ACTION_UP 但不触发任何动作。

### 5.12 管理页新增"显示悬浮球"开关（v2）

**需求**：用户希望有一个独立的入口控制悬浮球显示/隐藏，而不是仅由启用宏间接控制。

**实现**：

- [plugin_provider.dart](file:///workspace/Isolation/lib/providers/plugin_provider.dart) 新增：
  - `_floatingBallVisible` 状态 + `floatingBallVisible` getter
  - `setFloatingBallVisible(bool)`：持久化到 `SharedPreferences`（key：`floating_ball_visible`），并调用 `NativeChannel.start/stopFloatingBall()`
  - `load()` 启动时读取开关状态并恢复悬浮球
  - `_startFloatingBallIfReady()`：只有悬浮窗 + 辅助功能权限都具备时才启动
- [manage_screen.dart](file:///workspace/Isolation/lib/screens/manage_screen.dart) 新增：
  - 顶部按钮区下方插入 `_FloatingBallToggle` 卡片
  - 卡片左侧显示图标，中间"显示悬浮球"+状态文字，右侧 Switch
  - 点击整行或 Switch 都会触发
  - 开启时若权限不足弹出确认对话框，引导用户去授权

**与其他功能的关系**：

| 操作 | 悬浮球行为 | 开关状态 |
|------|------------|----------|
| 启用宏且开关关闭 | 自动打开悬浮球并把开关置为开启 | 变为 on |
| 启用宏且开关开启 | 重新启动悬浮球服务 | 保持 on |
| 禁用宏 | 不关闭悬浮球 | 保持原状态 |
| 手动关闭开关 | 立即隐藏悬浮球 | 变为 off |
| 手动打开开关 | 检查权限后启动悬浮球 | 变为 on |
| App 重启 | 读取 SharedPreferences，恢复开关状态 | 按持久化值 |

---

### 5.13 悬浮球权限解耦与宏执行触摸动画

**问题 1**：授予悬浮窗权限并打开"显示悬浮球"开关后，悬浮球仍未显示。

**根因**：`_startFloatingBallIfReady()` 与管理页的权限检查同时要求悬浮窗权限和辅助功能权限，导致仅授予悬浮窗权限时无法启动悬浮球。

**修复**：

- [plugin_provider.dart](file:///workspace/Isolation/lib/providers/plugin_provider.dart) 的 `_startFloatingBallIfReady()` 仅检查悬浮窗权限；辅助功能权限只在宏执行/启用宏时要求。
- [manage_screen.dart](file:///workspace/Isolation/lib/screens/manage_screen.dart) 的开关弹窗仅提示并引导用户授予悬浮窗权限。
- [FloatingBallService.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt) 的 `onStartCommand` 增加 `intent == null` 兜底：系统以 `START_STICKY` 重启服务时，只要权限已授予就自动重新显示悬浮球。
- `showFloatingBall()` 中对 `windowManager.addView()` 增加 `try-catch`，失败时通过 `Toast` 提示具体错误，避免静默失败。

**问题 2**：宏执行时缺少视觉反馈，用户无法感知当前点击/滑动的位置。

**实现**：

- 新增 [TouchEffect.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/TouchEffect.kt) 定义点击/滑动动画数据模型。
- 新增 [TouchEffectOverlay.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/TouchEffectOverlay.kt) 全屏透明硬件加速覆盖层，使用 `Handler` 驱动 16ms 帧动画，约 450–550ms 内完成扩散/淡出后自动移除。
- [FloatingBallService.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt) 提供静态方法 `showClickAnimation` / `showSwipeAnimation`，通过单例引用把效果投递到主线程的覆盖层；服务未运行时调用不会崩溃。
- [MacroExecutor.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt) 在 `dispatchClick` 与 `dispatchSwipe` 中分别调用上述动画方法，因此 `click`、`roll` 以及旧版 `clickPoint` / `swipe` / `clickNode` 回退手势都会显示反馈。

---

### 5.14 坐标调试页：新增采样点导致图片上移、标记错位

**问题**：`coordinate_debug_screen.dart` 中，图片显示区使用 `Expanded` 占据剩余空间，而底部采样列表仅在 `_points.isNotEmpty` 时才显示。点击第一个点后，采样列表突然出现并挤占了 `Expanded` 的高度，导致图片重新布局、已采集点的 `displayX/displayY` 与实际显示位置不一致。

**修复**：

- 将 `_buildPointsList()` 从 `Column` 的底部子节点改为 `Stack` 上的底部浮层（`Positioned(left:0, right:0, bottom:0)`）。
- 采样列表使用白色半透明背景 + 顶部圆角 + 上阴影，不再挤压图片显示区。
- 图片 `LayoutBuilder` 的约束高度始终不变，因此 `_imageDisplayOffset` 和已采集点标记位置保持稳定。

---

### 5.15 智能识别（局部像素颜色）修复

**问题 1**：`InputAccessibilityService` 收到 `TYPE_VIEW_CLICKED` 事件后才调用 `ScreenCaptureHelper.captureColor`，此时页面可能已经跳转，采集到的颜色是“点击后”的状态，导致执行时 `waitForColorMatch` 永远等不到目标颜色，宏卡住或错误点击。

**问题 2**：每次读取颜色都调用 `acquireLatestImage`，不仅慢，而且拿到的帧进一步滞后。

**修复**：

- [ScreenCaptureHelper.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/ScreenCaptureHelper.kt) 重构：
  - 新增后台 `HandlerThread` 持续监听 `ImageReader.OnImageAvailableListener`。
  - 把最新一帧像素数据复制到 `latestBuffer` 并加锁缓存。
  - `captureColor` / `findColor` 优先从缓存读取，命中更快、更接近真实“当前”画面；未命中时 fallback 到 `acquireLatestImage`。
  - `release()` 中停止后台线程并清空缓存。
- [MacroExecutor.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt) 的 `waitForColorMatch`：
  - 容差 `tolerance` 改为从步骤参数读取，默认由 20 放宽到 30，减少轻微色差导致的等待失败。

**仍存在的限制**：

- 智能识别目前仅对点击步骤生效，滑动（`roll`）步骤录制时不会附带颜色信息。
- 录制时仍依赖 Accessibility 点击事件，采集的颜色是事件触发时的最近帧，不能完全等同于“点击前”一帧；对于极快跳转的页面仍可能偏差。

---

### 5.16 编程宏图片查找 `find(image=...)`

**需求**：在 `find(color=...)` / `find(text=...)` 之外，新增图片模板匹配能力，用于目标没有稳定文字/颜色、但有固定图标的场景。

**实现**：

- 指令语法：
  ```dsl
  find(image="button_login.jpg", threshold=0.85, region=[100, 200, 900, 1200]) {
      click()
  }
  ```
- [ImageFinder.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/ImageFinder.kt) 使用 OpenCV `TM_CCOEFF_NORMED` 在灰度图上做模板匹配，返回命中区域中心坐标。
- [ScreenCaptureHelper.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/ScreenCaptureHelper.kt) 通过后台线程持续缓存最新帧，匹配时直接从缓存读取，无需反复 `acquireLatestImage`。
- [MacroExecutor.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt) 在 `executeFindStep` 中新增 `image` 分支，命中后把中心坐标压入坐标栈。
- 插件资源目录通过 `NativeChannel.executeMacro` 的 `assetsDir` 参数传递到执行引擎，模板图片从 `<pluginDir>/<pluginId>/assets/` 加载。
- [ProgramMacroScreen](file:///workspace/Isolation/lib/screens/program_macro_screen.dart) 新增：
  - 工具栏 `导入图片` 按钮。
  - 已导入图片资源列表（水平滚动），点击即可插入 `find(image="...") { click() }`。
  - 长按资源可删除。
- [ImageCropScreen](file:///workspace/Isolation/lib/screens/image_crop_screen.dart) 提供手动矩形裁剪：用户拖动/缩放裁剪框，输出图片最长边不超过 320px。
- [PluginProvider](file:///workspace/Isolation/lib/providers/plugin_provider.dart) 新增 `importMacroAsset` / `listMacroAssets` / `deleteMacroAsset`，并在 `saveMacroPlugin` 编辑现有插件时备份并恢复 `assets` 目录，避免覆盖式保存丢失图片。
- [MacroProgramParser](file:///workspace/Isolation/lib/services/macro_program_parser.dart) 支持 `image` / `threshold` / `region` 参数的序列化，以及 `region=[...]` 列表字面量的解析。

**导出/导入**：

- `exportMacroPlugin` 递归打包整个插件目录，assets 中的图片会随 `.isoplugin` 一起导出。
- `PluginManager.importPlugin` 解压时会保留 assets 子目录，因此导入后图片资源可用。

---

### 5.17 悬浮球自定义图标

**需求**：允许用户把悬浮球的默认图标替换为自己选择的图片。

**实现**：

- 管理页 [manage_screen.dart](file:///workspace/Isolation/lib/screens/manage_screen.dart) 的 `_FloatingBallToggle` 中新增“悬浮球图标”入口：
  - 显示当前图标预览（自定义图片或默认图标）。
  - 点击弹出底部菜单：`从相册选择` / `恢复默认`。
  - 从相册选择后进入 [ImageCropScreen](file:///workspace/Isolation/lib/screens/image_crop_screen.dart)，使用 `aspectRatio: 1.0` 强制正方形裁剪，输出最长边 128px。
  - 裁剪后的图片复制到应用文档目录 `floating_ball_icon.png`。
- [NativeChannel](file:///workspace/Isolation/lib/services/native_channel.dart) 新增 `setFloatingBallIcon` / `getFloatingBallIcon`。
- [MainActivity.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/MainActivity.kt) 处理这两个通道调用，转发给 [FloatingBallService](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt)。
- [FloatingBallService.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt)：
  - 使用 `SharedPreferences` 持久化自定义图标路径。
  - 新增 `applyCustomIconOrDefault` / `applyCustomIcon` / `applyDefaultIcon`。
  - `showFloatingBall()` 初始化时应用保存的图标；`setCustomIcon()` 被调用时若服务正在运行则立即刷新。

---

### 5.18 宏执行触摸动画与手势稳定性

**问题**：用户反馈宏执行时点击/滑动动画不显示，且点击、滚动指令偶尔失灵。

**根因**：之前动画只在 [FloatingBallService](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt) 中绘制，若用户未开启悬浮球或未授予悬浮窗权限，动画不会显示；容易误判为指令未执行。

**修复**：

- 动画层迁移到 [InputAccessibilityService](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/InputAccessibilityService.kt)：
  - 使用 `TYPE_ACCESSIBILITY_OVERLAY`（API 26+）添加全屏透明覆盖层，不依赖悬浮窗权限。
  - 宏执行时自动创建动画层，执行结束/异常后 1 秒自动移除。
  - [MacroExecutor](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt) 中 `dispatchClick` / `dispatchSwipe` 改为调用 `InputAccessibilityService.showClickAnimation` / `showSwipeAnimation`。
- [TouchEffectOverlay](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/TouchEffectOverlay.kt)：
  - 白色动画增加黑色阴影/轮廓，提升在浅色背景下的可见性。
  - 修复 attach 前入队的效果可能不刷新的问题。
- [MacroExecutor](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt)：
  - `stopRequested` 加 `@Volatile`。
  - listener 机制从单 listener 改为多 listener，[FloatingBallService](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt) 与 [InputAccessibilityService](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/InputAccessibilityService.kt) 可同时接收状态。
- [accessibility_service_config.xml](file:///workspace/Isolation/android/app/src/main/res/xml/accessibility_service_config.xml)：
  - 增加 `android:canPerformGestures="true"`，明确声明手势执行能力。

---

### 5.19 图片识别、圆形裁剪、行号对齐、DSL 循环与悬浮球 print 输出

本轮改动对应两次连续迭代：

- 第一次：提升图片匹配准确度、圆形可交互裁剪框、修复行号对齐、移除旧智能识别设置、DSL 支持 `find(loop)` 无限循环。
- 第二次：悬浮球删除固定提示语、录制默认插入 `print`、修复 `print` 在悬浮球附近的显示。

#### 5.19.1 图片模板匹配增强

**改动文件**：[ImageFinder.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/ImageFinder.kt)

- 新增 `matchMultiScale`：模板在 `[minScale, maxScale]`（默认 0.8 ~ 1.2）范围内按 `scaleStep`（默认 0.1）逐步缩放，使用 `TM_CCOEFF_NORMED` 灰度匹配。
- 新增 `matchMultiScaleColor`：在 BGR 三通道分别做跨尺度模板匹配，再取三通道平均相关度。
- 匹配前可选 3x3 高斯模糊降噪，默认开启。
- 执行流程：先灰度多尺度匹配；若分数不足阈值且 `useColor=true`，再跑颜色匹配；最终取两者最高分为命中结果。
- 命中坐标会加上 `region` 搜索区域偏移，返回屏幕绝对坐标。

#### 5.19.2 圆形裁剪框

**改动文件**：[ImageCropScreen.dart](file:///workspace/Isolation/lib/screens/image_crop_screen.dart)

- 裁剪框从矩形改为正圆形，始终维持宽高比 1.0。
- 支持手势：
  - `onScaleUpdate`：单指拖动改变圆心、双指捏合缩放直径。
  - 右下角缩放手柄：单指拖动调整直径。
- 圆心/直径限制在图片显示区域内，不会越界。
- 输出时按像素比例映射回原图，再裁剪为正方形；若最长边超过 `maxOutputSize`（默认 320），用立方插值缩放。

#### 5.19.3 专业编程区行号对齐

**改动文件**：[ProfessionalEditorScreen.dart](file:///workspace/Isolation/lib/screens/professional_editor_screen.dart)

- 用 `TextPainter.computeLineMetrics()` 根据 `TextField` 实际可用宽度，逐行计算每逻辑行对应的视觉行高。
- 左侧行号 gutter 的每个数字容器高度与右侧对应逻辑行高度完全一致，自动换行不再错位。
- 编辑/滚动时两个 `ScrollController` 同步 offset。

#### 5.19.4 移除旧智能识别设置与 `find(loop)` 无限循环

**改动文件**：

- [ProgramMacroScreen.dart](file:///workspace/Isolation/lib/screens/program_macro_screen.dart)
- [MacroProgramParser.dart](file:///workspace/Isolation/lib/services/macro_program_parser.dart)
- [MacroExecutor.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt)
- [MacroSettings / StepColor](file:///workspace/Isolation/lib/models/macro.dart)（简化，保留字段仅用于旧数据反序列化兼容）

- 删除 `ProgramMacroScreen` 中的智能识别开关、循环次数、无限循环开关。
- 循环统一使用 `for(n) { ... }`。
- 新增 `find(loop) { ... }` 表示无限循环：
  - DSL 解析器识别 `loop` 参数为 `true` 的步骤。
  - `MacroExecutor.executeFindStep` 中 `loop == true` 时 `while (!stopRequested)` 持续执行子块。
- 内部颜色判断通过 `if(find(color=0xRRGGBB, tolerance=20)) { ... }` 完成，不再依赖全局智能识别开关。
- 示例模板更新为：
  ```dsl
  print("开始")
  find(loop) {
      find(text="签到") { click() }
      wait(1000)
  }
  print("完成")
  ```

#### 5.19.5 悬浮球固定提示语删除与 `print` 输出修复

**改动文件**：

- [FloatingBallService.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt)
- [MacroExecutor.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt)
- [RecordingScreen.dart](file:///workspace/Isolation/lib/screens/recording_screen.dart)

- 删除 `FloatingBallService` 中“开始执行宏”“宏运行中，三连击停止”“未启用宏”等固定气泡提示；未就绪/未启用等关键错误改用 `Toast`。
- `MacroExecutorListener` 新增 `onMacroPrint(message)`；`print` 指令不再走 `onMacroStatus`，避免被步骤状态覆盖。
- `FloatingBallService` 仅在 `onMacroPrint` 时显示气泡，框架生命周期状态不再显示。
- `MacroExecutor.executeStep` 移除每步的 `postStatus("执行第 N 步: $type")`，print 内容可在气泡中持续显示。
- `showBubble` 修复：
  - 水平方向做 `[0, screen.x - bubbleW]` 裁剪。
  - 增加 `FLAG_LAYOUT_NO_LIMITS`。
  - 气泡最大宽度限制为屏幕宽度的 70%。
  - 增加 `ellipsize = END` 与 `maxLines = 4`。
- `RecordingScreen`：
  - 删除智能识别、循环次数、无限循环设置面板。
  - 录制停止后自动在步骤列表首尾插入 `print("开始")` 与 `print("完成")`。
  - 保存时统一使用 `const MacroSettings()`。

---

## 六、关键路径与依赖

```
[MD 文档]   ← 第一步（已完成）
    │
    ▼
[Bug1 修复] → [Bug2 修复] → [Bug3 修复]   ← 第二步（原生层，已完成）
    │
    ▼
[改进1：宏互斥]                              ← 第三步（Flutter 状态层，已完成）
    │
    ▼
[改进2：编程宏 DSL + 编辑器 + 原生执行]      ← 第四步（端到端，已完成）
    │
    ▼
[改进3：录制页代码视图]                      ← 第五步（Flutter UI 层，已完成）
    │
    ▼
[图片识别/裁剪/行号/循环/print]              ← 第六步（已完成）
```

---

## 七、备注

- 本文档整合自 `README.md` 与 `docs/superpowers/specs/2026-07-17-isolation-macro-design.md`，并加入了新一轮迭代的 Bug 分析与改进建议。
- 第五节"实现状态"对应所有需求项的实际落地说明，可作为代码走查入口。
- 后续如需调整范围，请直接修改本文件。
