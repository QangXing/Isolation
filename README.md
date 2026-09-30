# Isolation 自动化宏插件

> 一款 Android 平台的跨应用自动化工具。把悬浮球变成可录制、可编程、可分享的宏触发器，让你在任意 App 中自动完成重复点击、长按、滑动、等待、条件判断等操作；配合"编程球"可自定义悬浮球外观、手势与事件响应，并支持定时启动宏。

---

## 功能概览

| 能力 | 说明 |
|------|------|
| **录制宏** | 在第三方 App 中点击目标位置，自动记录为步骤，支持节点信息与坐标双保险回放。 |
| **编程宏 DSL** | 类代码 DSL 编写宏，支持 `click`、`longPressAt`、`swipe`、`launch`、`findText`、`findColor`、`findImage`、`if`、`for`、`loop`、变量与表达式等指令。 |
| **图片/颜色识别** | `findImage(...)` 基于特征点匹配；`findColor(...)` 基于屏幕像素颜色，用于节点不可见的场景。 |
| **编程球（floaterPlugin）** | 自定义一个或多个悬浮球：圆角、大小、图片、位置、显隐；监听单击/双击/三连击/长按等手势并触发动作；副球可跟随主球移动。 |
| **宏事件监听** | `floater("事件名") { ... }` 监听宏指令执行结果（click、longPressAt、swipe、findText 等），块内注入事件变量，可响应式执行动作或播放音效。 |
| **定时启动宏** | 在宏设置中开启后，每天固定时间自动执行指定宏；基于 AlarmManager 精确触发，App 退到后台甚至进程被回收也能到点执行，并支持开机自启。 |
| **悬浮球触发** | 单击/双击/长按悬浮球执行对应动作；宏运行中三连击悬浮球强制停止。 |
| **导入/导出** | 宏保存为 `.isoplugin`（zip 包），编程球保存为 `floaterPlugin` 包，可备份、分享或导入。 |
| **坐标调试** | 上传屏幕截图，点击任意位置获取坐标和颜色，一键生成 `click` 或 `findColor(...)` 代码。 |
| **自定义悬浮球图标** | 支持从相册选择图片替换默认悬浮球图标。 |

---

## 技术栈

| 层 | 技术 |
|----|------|
| UI 层 | Flutter 3.x（Dart 3） |
| 原生层 | Kotlin（Android） |
| 通信 | MethodChannel `com.example.isolation/native` |
| 状态管理 | `provider` |
| 持久化 | `shared_preferences` + 应用私有目录 |
| 图像处理 | OpenCV（Android）、`image` 包（Flutter） |
| 定时任务 | AlarmManager（精确）+ 开机广播 |
| 打包格式 | `.isoplugin`（zip 压缩包）、`floaterPlugin` 包 |

---

## 架构

```
┌─────────────────────────────────────────────────────────┐
│                      Flutter (Dart)                      │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────┐ │
│  │ HomeScreen │  │ManageScreen│  │  RecordingScreen   │ │
│  └────────────┘  └────────────┘  └────────────────────┘ │
│  ┌────────────────────┐  ┌────────────────────────────┐│
│  │ ProgramMacroScreen │  │    FloaterEditorScreen     ││
│  └────────────────────┘  └────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────┐│
│  │  PluginProvider / MacroProgramParser / MacroSettings ││
│  └─────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────┐│
│  │              NativeChannel ← MethodChannel          ││
│  └─────────────────────────────────────────────────────┘│
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────┴─────────────────────────────┐
│                      Kotlin (Android)                    │
│  ┌────────────────────┐  ┌──────────────────────────┐   │
│  │ InputAccessibility │  │    FloatingBallService   │   │
│  │     Service        │  │    / FloaterRegistry     │   │
│  └────────────────────┘  └──────────────────────────┘   │
│  ┌────────────────────┐  ┌──────────────────────────┐   │
│  │    MacroExecutor   │  │ MacroScheduler / Receiver│   │
│  └────────────────────┘  └──────────────────────────┘   │
│  ┌───────────────────────────────────────────────────┐  │
│  │   ScreenCaptureHelper / TouchEffectOverlay        │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## 编程宏 DSL

在 **主页 → 编程宏** 中编写，保存后可通过悬浮球或定时任务执行。

```dsl
print("开始签到")

// 按文字查找并点击
findText("签到") {
    click()
    wait(500)
}

// 按图片模板查找
findImage("button_login.jpg", featureCount=12) { click() }

// 长按指定坐标（默认 800ms，可自定义时长）
longPressAt(500, 800, 1500)

// 条件分支
ifText("同意") {
    click()
} else {
    print("未找到")
}

// 变量与表达式
let count = 0
for (3) {
    swipe(0, 300, 400)
    count = count + 1
}

// 等待目标出现后执行一次
waitForText("加载完成", timeout=5000) { click() }

// 无限循环，三连击悬浮球停止
loop {
    findText("领取") { click() }
    wait(1000)
}

// 启动应用并判断结果
ok = launch("com.example.app", timeout=3000)
if (ok) { click(500, 800) }

print("完成")
```

### 指令速查

| 指令 | 示例 | 说明 |
|------|------|------|
| `click` | `click(500, 800)` / `click()` | 坐标点击；无参时点击最近 `find`/`if` 命中的位置 |
| `longPressAt` | `longPressAt(500, 800, 1500)` / `longPressAt()` | 坐标长按；`duration` 默认 800ms，无参时长按最近命中位置 |
| `swipe` | `swipe(dx, dy, duration)` / `swipe(x1,y1,x2,y2,duration)` | 从屏幕中心相对滑动 / 从起点滑到终点 |
| `swipeRel` | `swipeRel(x, y, dx, dy, duration)` | 从指定起点按相对偏移滑动 |
| `input` | `input("文字")` | 在已聚焦输入框输入文字 |
| `wait` | `wait(ms)` | 等待指定毫秒 |
| `print` | `print("消息")` | 在悬浮球旁显示气泡消息 |
| `back` / `home` / `recents` | `back()` 等 | 系统按键 |
| `launch` | `launch("包名", timeout=3000)` | 启动应用，可用 `ok = launch(...)` 接收结果 |
| `findText` / `findColor` / `findImage` | `findText("签到") { click() }` | 查找目标，命中后把坐标压栈供块内 `click()` 使用 |
| `waitForText` / `waitForColor` / `waitForImage` | `waitForText("加载完成") { click() }` | 等待目标出现后执行一次，支持 `timeout` |
| `if` / `ifText` / `ifColor` / `ifImage` / `ifColorAt` | `ifText("同意") { ... } else { ... }` | 条件分支 |
| `colorAt` | `c = colorAt(500, 800)` | 读取指定坐标的颜色值 |
| `loop` / `breakLoop` | `loop("name") { ... }` / `breakLoop("name")` | 无限循环 / 终止指定循环 |
| `for` | `for(3) { ... }` / `for(int i=0; i<10; i=i+1)` | 固定次数 / C 风格循环 |
| `let` / `int` / `double` / `point` / `color` | `let count = 0` | 变量声明，支持表达式与命令结果赋值 |

> 坐标、颜色、时间等数值均支持纯数字、变量或表达式，例如 `click(x + 10, y - 20)`。

### 宏事件监听

`floater("事件名") { ... } else { ... }` 监听宏指令的执行结果，块内自动注入事件变量：

```dsl
floater("longPressAt") {
    print("长按于 " + longPressX + ", " + longPressY + "，时长 " + longPressDuration)
} else {
    print("长按执行失败")
}
```

支持事件：`click`、`longPressAt`、`swipe` / `swipeRel`、`findText` / `waitForText`、`findColor` / `findImage` / `waitFor*`、`input`、`launch`，详见 [docs/DSL_SPEC.md](docs/DSL_SPEC.md#13-事件监听)。

### 编程球（floaterPlugin）

编程球 DSL 声明一个或多个悬浮球（主球 `main` / 副球 `deputy`），并为每个球配置外观、位置、显隐与手势事件：

```dsl
ball(main, "mainBall") {
    size(64)
    cornerRadius(16)
    image("main.png")
    singleClick(Launch_macro)
    longPress(Turn_off_macros)
}

ball(deputy, "helper") {
    size(48)
    location("helper", 0, 0)
    status(hide, "helper")
}

follow("mainBall", 80, 0)   // 副球跟随主球
```

支持：`cornerRadius` / `size` / `image` / `audio`、`location` / `status` / `found`、`singleClick` / `doubleClick` / `tripleClick` / `longPress`、`Launch_macro` / `Turn_off_macros`、`toggle` / `follow`、`#include <插件名>` 引用。详见 [docs/BALL_SPEC.md](docs/BALL_SPEC.md)。

### 定时启动宏

在 **宏设置** 页开启「定时启动宏」并选择每日时间（`HH:mm`）后：

- 到点自动执行该宏（需已开启辅助功能），与手动点击悬浮球走同一条执行链路。
- 基于 `AlarmManager` 精确触发，App 退到后台、进程被回收仍可执行。
- 支持开机自启；关闭开关或删除宏后定时任务自动取消。

---

## 主要文件

| 路径 | 说明 |
|------|------|
| `lib/main.dart` | 应用入口与底部导航 |
| `lib/screens/home_screen.dart` | 主页：编程宏 / 编程球双 Tab 列表与启用开关 |
| `lib/screens/manage_screen.dart` | 管理页：新建/导入/编程宏/坐标调试 |
| `lib/screens/recording_screen.dart` | 录制页：录制操作并编辑步骤 |
| `lib/screens/program_macro_screen.dart` | 编程宏编辑器 |
| `lib/screens/professional_editor_screen.dart` | 全屏代码编辑器（带行号） |
| `lib/screens/floater_editor_screen.dart` | 编程球（floaterPlugin）编辑器 |
| `lib/screens/macro_settings_screen.dart` | 宏设置页（含定时启动宏） |
| `lib/screens/coordinate_debug_screen.dart` | 坐标与颜色调试工具 |
| `lib/services/macro_program_parser.dart` | DSL 解析与序列化 |
| `lib/models/macro.dart` | 宏数据模型 |
| `android/.../InputAccessibilityService.kt` | 辅助功能服务：录制 + 回放 |
| `android/.../FloatingBallService.kt` | 悬浮球服务与气泡显示 |
| `android/.../MacroExecutor.kt` | 宏执行引擎（含 longPressAt / 事件变量注入） |
| `android/.../FloaterRegistry.kt` | 多球（编程球）注册与管理 |
| `android/.../MacroScheduler.kt` / `MacroScheduleReceiver.kt` | 定时启动宏：AlarmManager 调度与接收 |
| `android/.../ImageFinder.kt` | OpenCV 图片特征点匹配 |
| `android/.../ScreenCaptureHelper.kt` | 屏幕截图与颜色查找 |
| `docs/DSL_SPEC.md` | 宏 DSL 完整语法规范 |
| `docs/BALL_SPEC.md` | 编程球指令规范 |
| `PROJECT_GUIDE.md` | 项目详细指南与实现状态 |

---

## 权限说明

| 权限 | 用途 |
|------|------|
| `SYSTEM_ALERT_WINDOW` | 显示悬浮球 |
| `BIND_ACCESSIBILITY_SERVICE` | 录制点击事件并回放手势 |
| `FOREGROUND_SERVICE`（含 special use） | 保持悬浮球后台运行 |
| 屏幕录制权限（运行时） | 颜色查找、图片模板匹配需要读取屏幕像素 |
| `SCHEDULE_EXACT_ALARM` | 定时启动宏的精确触发 |
| `RECEIVE_BOOT_COMPLETED` | 开机后恢复定时任务 |
| 存储权限（运行时） | 导入/导出插件包与图片模板 |

---

## 使用流程

### 录制一个宏

1. 打开应用，进入 **管理页** → **新建宏**。
2. 点击 **开始录制**，返回目标 App。
3. 在目标 App 中执行需要自动化的点击操作。
4. 返回本应用，点击 **完成**。
5. 检查/编辑生成的步骤，点击 **保存为宏插件**。
6. 在主页启用该宏，点击悬浮球即可回放。

### 编写一个编程宏

1. 进入 **主页 → 编程宏**（或管理页 → 编程宏）。
2. 在代码编辑器中输入 DSL。
3. 点击 **校验** 检查语法。
4. 点击 **保存宏**。
5. 主页启用后，点击悬浮球执行。

### 编辑编程球

1. 进入 **主页 → 编程球** → **新建编程球**。
2. 在 `floater.dsl` 中声明球的外观与事件（见上文编程球示例）。
3. 导入图片/音频资源到 `assets` 目录。
4. 保存并在主页启用；编程球插件可被宏脚本通过 `#include <插件名>` 引用。

### 设置定时启动宏

1. 打开某个宏的 **宏设置**。
2. 开启 **定时启动宏** 开关，选择每日执行时间。
3. 保存设置；到点将自动执行该宏（需保持辅助功能开启）。

### 导入图片模板

1. 在编程宏页面点击 **导入图片**。
2. 从相册选择图片，进入圆形裁剪框调整选区。
3. 裁剪后的图片自动加入当前插件的 `assets` 目录。
4. 在代码中使用 `findImage("文件名.jpg")` 引用。

---

## 插件包结构

宏插件：

```
xxx.isoplugin (zip)
├── manifest.json
├── icon.png
├── macro.json
└── assets/
    └── button_login.jpg
```

编程球插件（floaterPlugin）：

```
my_floater/
├── manifest.json          # type 固定为 "floaterPlugin"
├── floater.dsl
└── assets/
    ├── default.png
    ├── click.png
    └── click.mp3
```

`manifest.json` 示例（宏插件）：

```json
{
  "id": "com.example.isolation.macro.daily-checkin",
  "name": "每日签到宏",
  "version": "1.0.0",
  "description": "打开目标 App 后自动点击签到按钮",
  "author": "isolation",
  "actions": [
    {
      "type": "macro",
      "label": "运行",
      "macroFile": "macro.json"
    }
  ]
}
```

---

## 注意事项

- 同一时间只能启用一个宏插件；启用新宏会自动禁用其他宏。
- 部分游戏、视频、WebView 内嵌内容的节点不可访问，建议改用 `findColor(...)` 或 `findImage(...)`。
- 颜色/图片识别依赖屏幕截图，请确保已授予屏幕录制权限。
- 定时启动宏需要辅助功能处于开启状态；Android 12+ 需授予"闹钟和提醒"（精确闹钟）权限。
- 坐标调试工具中的坐标基于设备屏幕像素；上传的截图最好是本机系统截屏，且未经过裁剪。
- Android 12+ 对后台启动 Activity 有限制，`launch` 步骤在应用未前台时可能失败。
- 长按指令默认时长 800ms，若目标应用判定更严可增大 `duration`。

---

## 迭代记录

详见 [PROJECT_GUIDE.md](PROJECT_GUIDE.md)，其中记录了：

- Bug 修复：辅助功能状态判定、悬浮球触摸反馈、气泡定位、图片匹配准确度、行号对齐、`print` 输出覆盖等。
- 功能实现：宏互斥启用、编程宏 DSL、变量与表达式、录制页代码视图、图片/颜色查找、圆形裁剪框、坐标调试、自定义悬浮球图标、编程球（多球）、宏事件监听、`longPressAt` 长按指令、定时启动宏等。
