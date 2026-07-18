# Isolation 自动化宏插件设计文档

## 背景与目标

现有内置插件“悬浮球小键盘”功能单一、使用场景有限。本项目决定改为**跨应用自动化宏插件**，让悬浮球成为一个可录制、可回放、可导入导出的自动化触发器。

目标：
- 用户能在任意 App 中录制一系列点击操作。
- 录制结果保存为 `.isoplugin` 宏插件，可导入/导出/分享。
- 启用宏后，点击悬浮球即可在目标 App 中自动执行该宏。
- 优先使用 Accessibility 节点信息回放，节点不可见时回退到屏幕坐标。

## 范围

本设计覆盖：
- 宏数据结构（步骤类型、字段）。
- 原生层录制与回放引擎（Kotlin AccessibilityService / WindowManager）。
- Flutter 层的录制 UI、步骤编辑器、插件管理集成。
- 插件包格式扩展。

**MVP 范围**：仅实现 `clickNode`（节点点击）的录制与回放，其他步骤类型（`clickPoint`、`swipe`、`wait`、`back`、`home`、`launchApp`、`inputText`）保留接口，后续迭代实现。

## 现有架构利用

- **Flutter 插件系统**：复用 `Plugin` / `PluginAction` 模型，新增 `type: "macro"`。
- **悬浮球服务 `FloatingBallService`**：改为“运行当前启用宏”。
- **辅助功能服务 `InputAccessibilityService`**：扩展录制监听与回放能力。
- **MethodChannel `com.example.isolation/native`**：新增 `startRecording`、`stopRecording`、`executeMacro` 等方法。

## 数据模型

### MacroStep

```json
{
  "type": "clickNode",
  "delay": 500,
  "target": {
    "resourceId": "com.example.app:id/btn_sign",
    "text": "签到",
    "className": "android.widget.Button",
    "bounds": [100, 200, 300, 400]
  }
}
```

步骤类型：

| 类型 | 说明 | 关键字段 |
|------|------|----------|
| `clickNode` | 按节点信息点击 | `target` |
| `clickPoint` | 按坐标点击 | `point: {x, y}` |
| `swipe` | 滑动 | `start: {x, y}`, `end: {x, y}`, `duration` |
| `wait` | 等待 | `duration` |
| `back` | 返回键 | - |
| `home` | Home 键 | - |
| `recents` | 最近任务键 | - |
| `launchApp` | 打开指定 App | `packageName` |
| `inputText` | 向焦点输入框注入文字 | `text` |

### MacroPlugin

`manifest.json` 示例：

```json
{
  "id": "com.example.isolation.builtin.daily-checkin",
  "name": "每日签到宏",
  "version": "1.0.0",
  "description": "打开目标 App 后自动点击签到按钮",
  "author": "isolation",
  "actions": [
    {
      "type": "macro",
      "label": "运行签到宏",
      "macroFile": "macro.json"
    }
  ]
}
```

插件包结构：

```
xxx.isoplugin （zip）
├── manifest.json
├── icon.png
└── macro.json
```

## 原生层设计

### 录制流程

1. Flutter 调用 `NativeChannel.startRecording()`。
2. `InputAccessibilityService` 进入录制状态。
3. 监听 `AccessibilityEvent.TYPE_VIEW_CLICKED`。
4. 过滤掉本应用包名（`com.example.isolation`）的事件，避免记录悬浮控制窗的点击。
5. 对每个有效点击，提取 `resourceId`、`text`、`className`、`bounds`，生成 `MacroStep`。
6. 记录事件时间戳，计算与上一步的 `delay`。
7. Flutter 调用 `NativeChannel.stopRecording()`，服务返回步骤列表。

### 回放流程

1. Flutter 调用 `executeMacro` 并传入步骤数组。
2. 引擎按顺序执行：
   - `clickNode`：从 `rootInActiveWindow` 查找匹配节点。
     - 优先匹配 `resourceId`。
     - 其次匹配 `text` 或 `contentDescription`。
     - 最后匹配 `className + bounds` 重叠。
     - 未找到则使用 `bounds` 中心坐标执行 `clickPoint`。
   - `clickPoint`：使用 `GestureDescription` 派发单点点击。
   - 每步前等待 `delay` 毫秒。
3. 执行失败某一步时，记录失败原因并继续（可配置）。

### 悬浮球行为变更

- 单击悬浮球：运行当前唯一启用的宏插件。
- 若未启用宏插件：提示“请先启用一个宏”。
- 长按悬浮球：打开宏选择面板（MVP 可省略，只做单击运行）。

## Flutter 层设计

### 页面调整

底部导航保持 **主页 / 管理 / 说明**。

- **主页**：展示插件列表，每个插件卡片显示启用开关；启用宏插件后卡片显示“运行”按钮（也可通过悬浮球触发）。
- **管理页**：
  - 保留“从文件导入插件”。
  - 新增“新建宏”按钮。
  - 列出所有宏插件，支持编辑/删除/导出。
- **新建宏 / 录制页**：
  - 顶部显示录制状态（录制中 / 暂停 / 完成）。
  - 显示半透明悬浮控制条：开始、暂停、完成、取消。
  - 录制完成后进入步骤编辑器：步骤列表、删除、重排、手动添加坐标点击（MVP 可只支持删除）。
  - 保存时生成 `.isoplugin` 压缩包并存入应用私有目录。

### MethodChannel 扩展

新增方法：

```dart
static Future<List<Map<String, dynamic>>> startRecording() async
static Future<List<Map<String, dynamic>>> stopRecording() async
static Future<bool> executeMacro(List<Map<String, dynamic>> steps) async
static Future<bool> dispatchClick(int x, int y) async
```

### 状态管理

- `PluginProvider` 增加当前录制状态、当前运行宏状态。
- 录制得到的步骤在保存前驻留内存，不进入插件列表。

## 插件格式兼容

- 旧插件（`type != "macro"`）继续兼容。
- 内置插件从“悬浮球键盘”替换为“示例签到宏”。

## 权限与限制

- 需要 **悬浮窗权限**（SYSTEM_ALERT_WINDOW）。
- 需要 **无障碍服务权限**（BIND_ACCESSIBILITY_SERVICE）。
- Android 12+ 对后台启动 Activity 有限制，`launchApp` 步骤在执行时若应用不在前台可能失败。
- 部分游戏、视频、WebView 内嵌内容的节点不可访问，回退到坐标后稳定性下降。

## 非目标

- 不实现图像识别 / OCR。
- 不实现云端宏同步。
- 不实现条件判断、循环等复杂脚本（保持步骤线性）。

## 验收标准

- [ ] 能在第三方 App 中录制 3 次连续点击并保存为宏插件。
- [ ] 启用宏后，点击悬浮球可在同一界面自动执行这 3 次点击。
- [ ] 节点变化后（如按钮文字不变但位置偏移）仍能正确点击。
- [ ] 录制的宏可通过 `.isoplugin` 文件导入/导出。
- [ ] UI 保持白色简洁风格、毛玻璃圆角方块、底部三栏导航。
