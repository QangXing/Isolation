# Isolation 自动化宏插件

> 一款 Android 平台的跨应用自动化工具。把悬浮球变成可录制、可编程、可分享的宏触发器，让你在任意 App 中自动完成重复点击、滑动、等待、条件判断等操作。

---

## 功能概览

| 能力 | 说明 |
|------|------|
| **录制宏** | 在第三方 App 中点击目标位置，自动记录为步骤，支持节点信息与坐标双保险回放。 |
| **编程宏** | 使用类代码 DSL 直接编写宏，支持 `click`、`roll`、`print`、`find`、`if`、`for`、`find(loop)` 等指令。 |
| **图片/颜色识别** | `find(image=...)` 基于 OpenCV 模板匹配；`find(color=...)` 基于屏幕像素颜色，用于节点不可见的场景。 |
| **悬浮球触发** | 启用宏后，单击悬浮球即可执行；宏运行中三连击悬浮球强制停止。 |
| **导入/导出** | 宏保存为 `.isoplugin`（zip 包），可备份、分享或导入他人插件。 |
| **坐标调试** | 上传屏幕截图，点击任意位置获取坐标和颜色，一键生成 `click` 或 `find(color=...)` 代码。 |
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
| 打包格式 | `.isoplugin`（zip 压缩包） |

---

## 架构

```
┌─────────────────────────────────────────────────────────┐
│                      Flutter (Dart)                      │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────┐ │
│  │ HomeScreen │  │ManageScreen│  │  RecordingScreen   │ │
│  └────────────┘  └────────────┘  └────────────────────┘ │
│  ┌────────────────────┐  ┌────────────────────────────┐│
│  │ ProgramMacroScreen │  │ CoordinateDebugScreen      ││
│  └────────────────────┘  └────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────┐│
│  │        PluginProvider / MacroProgramParser          ││
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
│  │     Service        │  │                          │   │
│  └────────────────────┘  └──────────────────────────┘   │
│  ┌────────────────────┐  ┌──────────────────────────┐   │
│  │    MacroExecutor   │  │      ImageFinder         │   │
│  └────────────────────┘  └──────────────────────────┘   │
│  ┌───────────────────────────────────────────────────┐  │
│  │   ScreenCaptureHelper / TouchEffectOverlay        │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## 编程宏 DSL

在 **管理页 → 编程宏** 中编写，保存后可通过悬浮球执行。

```dsl
print("开始签到")

// 按屏幕颜色查找并点击
find(color=0xFF5000, tolerance=20) {
    click()
    wait(500)
}

// 按节点文字查找
find(text="签到") {
    click()
    roll(0, 300, 400)
    wait(500)
}

// 按图片模板查找
find(image="button_login.jpg", threshold=0.85, region=[100, 200, 900, 1200]) {
    click()
}

// 条件分支
if(find(color=0x00FF00, tolerance=25)) {
    click()
} else {
    print("今日无奖励")
}

// 固定次数循环
for(3) {
    roll(0, 300, 400)
    wait(500)
}

// 无限循环，三连击悬浮球停止
find(loop) {
    find(text="领取") { click() }
    wait(1000)
}

print("完成")
```

### 指令速查

| 指令 | 示例 | 说明 |
|------|------|------|
| `click` | `click(500, 800)` / `click()` | 坐标点击；无参时点击最近 `find`/`if` 命中的位置 |
| `roll` | `roll(dx, dy, duration)` | 以屏幕中心为起点派发滑动手势 |
| `wait` | `wait(ms)` | 等待指定毫秒 |
| `print` | `print("消息")` | 在悬浮球旁显示气泡消息 |
| `find` | `find(color=...)` / `find(text=...)` / `find(image=...)` | 颜色/文字/图片查找，命中后把坐标压栈 |
| `find(loop)` | `find(loop) { ... }` | 无限循环执行子块 |
| `if` | `if(find(...)) { ... } else { ... }` | 条件分支 |
| `back` / `home` / `recents` | `back()` 等 | 系统按键 |

---

## 主要文件

| 路径 | 说明 |
|------|------|
| `lib/main.dart` | 应用入口与底部导航 |
| `lib/screens/home_screen.dart` | 主页：插件列表与启用开关 |
| `lib/screens/manage_screen.dart` | 管理页：新建/导入/编程宏/坐标调试 |
| `lib/screens/recording_screen.dart` | 录制页：录制操作并编辑步骤 |
| `lib/screens/program_macro_screen.dart` | 编程宏编辑器 |
| `lib/screens/professional_editor_screen.dart` | 全屏代码编辑器（带行号） |
| `lib/screens/coordinate_debug_screen.dart` | 坐标与颜色调试工具 |
| `lib/services/macro_program_parser.dart` | DSL 解析与序列化 |
| `lib/models/macro.dart` | 宏数据模型 |
| `android/.../InputAccessibilityService.kt` | 辅助功能服务：录制 + 回放 |
| `android/.../FloatingBallService.kt` | 悬浮球服务与气泡显示 |
| `android/.../MacroExecutor.kt` | 宏执行引擎 |
| `android/.../ImageFinder.kt` | OpenCV 图片模板匹配 |
| `android/.../ScreenCaptureHelper.kt` | 屏幕截图与颜色查找 |
| `PROJECT_GUIDE.md` | 项目详细指南与实现状态 |

---

## 权限说明

| 权限 | 用途 |
|------|------|
| `SYSTEM_ALERT_WINDOW` | 显示悬浮球 |
| `BIND_ACCESSIBILITY_SERVICE` | 录制点击事件并回放手势 |
| `FOREGROUND_SERVICE` | 保持悬浮球后台运行 |
| 屏幕录制权限（运行时） | 颜色查找、图片模板匹配需要读取屏幕像素 |

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

1. 进入 **管理页** → **编程宏**。
2. 在代码编辑器中输入 DSL。
3. 点击 **校验** 检查语法。
4. 点击 **保存宏**。
5. 主页启用后，点击悬浮球执行。

### 导入图片模板

1. 在编程宏页面点击 **导入图片**。
2. 从相册选择图片，进入圆形裁剪框调整选区。
3. 裁剪后的图片自动加入当前插件的 `assets` 目录。
4. 在代码中使用 `find(image="文件名.jpg")` 引用。

---

## 插件包结构

```
xxx.isoplugin (zip)
├── manifest.json
├── icon.png
├── macro.json
└── assets/
    └── button_login.jpg
```

`manifest.json` 示例：

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
- 部分游戏、视频、WebView 内嵌内容的节点不可访问，建议改用 `find(color=...)` 或 `find(image=...)`。
- 颜色/图片识别依赖屏幕截图，请确保已授予屏幕录制权限。
- 坐标调试工具中的坐标基于设备屏幕像素；上传的截图最好是本机系统截屏，且未经过裁剪。
- Android 12+ 对后台启动 Activity 有限制，`launchApp` 步骤在应用未前台时可能失败。

---

## 迭代记录

详见 [PROJECT_GUIDE.md](PROJECT_GUIDE.md)，其中记录了：

- Bug 修复：辅助功能状态判定、悬浮球触摸反馈、气泡定位、图片匹配准确度、行号对齐、`print` 输出覆盖等。
- 功能实现：宏互斥启用、编程宏 DSL、录制页代码视图、图片/颜色查找、圆形裁剪框、坐标调试、悬浮球自定义图标等。
