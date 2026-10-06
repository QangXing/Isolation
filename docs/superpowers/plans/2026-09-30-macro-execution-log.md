# 宏执行日志 设计文档

> 需求：在「宏设置」页新增一块执行日志，展示该宏每次运行时产生的**调试模式文本**（`onMacroStatus`）与 **print 打印内容**（`onMacroPrint`），供用户排查宏执行过程。
> 本文档只做设计，不涉及代码落地。

---

## 一、需求描述

- 宏每次执行时，把产生的日志**持久化保存**，按宏（pluginId）隔离。
- 在「宏设置」页新增「执行日志」区块：
  - 展示该宏最近 N 条执行日志，每条包含**时间**、**类型**（print / 状态）与**内容**。
  - 提供「清空日志」按钮。
- 日志默认记录：
  - **print 内容**：无条件记录（`onMacroPrint`）。
  - **调试模式文本**：仅当该宏开启「调试模式」时记录每次执行的步骤状态（`onMacroStatus`，如「执行第 N 步: click」「findColor: 未命中」等）。
  - **执行生命周期**：始终记录「开始执行 / 任务完成 / 任务已停止 / 宏已停止 / 任务异常」等关键状态，让日志有上下文锚点。

### 交互暂定

| 控件 | 位置 | 行为 |
|------|------|------|
| 「执行日志」卡片（可展开/收起） | 「宏设置」页底部，定时卡片之后 | 默认收起，展示最近日志摘要 |
| 单条日志 | 卡片内列表 | 时间 + 内容，print 与状态用不同图标/颜色区分 |
| 「清空日志」按钮 | 卡片右上角 | 二次确认后清空该宏全部日志 |
| 自动刷新 | 进入页面时 | 读取持久化日志并展示 |

## 二、现状梳理

### 2.1 消息产生链路（原生侧）

[Java
MacroExecutor.kt](file:///workspace/android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt) 是唯一产生执行消息的地方：

- `postStatus(message)` → 遍历 `MacroExecutorListener.onMacroStatus(message)`。
  - 生命周期：开始执行 / 任务完成 / 任务已停止 / 宏已停止 / 任务异常（[execute](file:///workspace/android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt#L156-L170)）。
  - 调试模式：`executeStep` 中 `if (debugMode) postStatus("执行第 N 步: $type")`（[L199-L203](file:///workspace/android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt#L199-L203)），以及各指令内部 `postStatus("findColor: 未命中")` 等（`debugMode` 开关在 `execute()` 从 `settings["debugMode"]` 读取）。
- `postPrint(message)` → 遍历 `MacroExecutorListener.onMacroPrint(message)`，仅 `print` 指令触发（[executePrintStep](file:///workspace/android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt#L331-L345)）。

监听者目前有两个：[FloatingBallService](file:///workspace/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt#L1254-L1274)（气泡/Toast）与 [InputAccessibilityService](file:///workspace/android/app/src/main/kotlin/com/example/isolation/InputAccessibilityService.kt#L299-L304)（动画层）。多 listener 模型已支持新增监听者。

### 2.2 宏标识（pluginId）现状

**问题**：原生执行入口 `InputAccessibilityService.executeMacro(context, settings, steps, assetsDir)`（[L76-L85](file:///workspace/android/app/src/main/kotlin/com/example/isolation/InputAccessibilityService.kt#L76-L85)）以及 Flutter 通道 `executeMacro` **都没有携带 pluginId**。

- [FloatingBallService.runEnabledMacro](file:///workspace/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt#L1229-L1252) 从 `enabled_macro.json` 加载，调用时不带 id。
- [MainActivity.kt#L229-L242](file:///workspace/android/app/src/main/kotlin/com/example/isolation/MainActivity.kt#L229-L242) 通道转发同样不带 id。
- [MacroScheduleReceiver.kt#L63](file:///workspace/android/app/src/main/kotlin/com/example/isolation/MacroScheduleReceiver.kt#L63)（定时触发，上一期功能）**有** pluginId。

日志按宏隔离，必须把 pluginId 贯穿到执行入口。

### 2.3 结论

- 消息来源单一（MacroExecutor），新增一个 `MacroLogStore` 监听者即可捕获全部 print 与状态。
- 需要扩展执行链路参数携带 pluginId（Flutter 通道 + `InputAccessibilityService.executeMacro` + `MacroExecutor.execute`）。
- 日志持久化在原生侧（文件），Flutter 宏设置页通过通道读取/清空。

## 三、方案设计

### 3.1 总体架构

```
┌───────────────────────────── 原生 (Android) ────────────────────────┐
│ MacroExecutor(Listener)                                              │
│   ├─ postStatus(msg) ──→ onMacroStatus  ──→ FloatingBallService      │
│   ├─ postPrint(msg)  ──→ onMacroPrint   ──→ InputAccessibilityService │
│   └─ 新增: MacroLogStore.onMacroStatus/onMacroPrint（兼容默认实现）    │
│               │ 写入文件日志（按 pluginId 分文件，时间戳 + 类型 + 内容）│
│               │ 带上限（默认 300 条/宏，环形覆盖）                     │
└───────────────┬──────────────────────────────────────────────────────┘
                │ MethodChannel
                ▼
┌───────────────────────────── Flutter ───────────────────────────────┐
│ macro_settings_screen.dart 「执行日志」区块                            │
│   ├─ getMacroLogs(pluginId) → List<LogEntry>                         │
│   └─ clearMacroLogs(pluginId)                                        │
└──────────────────────────────────────────────────────────────────────┘
```

### 3.2 数据模型（原生侧，新增 MacroLogStore.kt）

```kotlin
data class MacroLogEntry(
    val timeMillis: Long,   // 记录时间（System.currentTimeMillis）
    val type: String,       // "print" 或 "status"
    val message: String,
)
```

持久化格式（`<filesDir>/macro_logs/<pluginId>.json`）：

```json
[
  { "timeMillis": 1730000000000, "type": "status", "message": "开始执行" },
  { "timeMillis": 1730000001000, "type": "print",  "message": "签到成功" },
  { "timeMillis": 1730000002000, "type": "status", "message": "任务完成" }
]
```

- 单文件顺序数组，**新增追尾写**，超上限时从头部裁剪（简单实现：数组长度超限后全量重写前 N 条）。
- 默认 `MAX_LOG_ENTRIES = 300`（写死常量，后续可改设置）。
- 清空 = 删除该宏对应文件。

### 3.3 消息捕获规则（MacroLogStore 作为 listener）

| 消息来源 | 记录条件 | 记录 type |
|----------|----------|-----------|
| `onMacroPrint(msg)` | 始终 | `print` |
| `onMacroStatus(msg)` 生命周期（开始执行 / 任务完成 / 任务已停止 / 宏已停止 / 以「任务异常」开头）| 始终（提供上下文锚点） | `status` |
| `onMacroStatus(msg)` 其它（调试模式步骤 / find 结果等）| **仅当宏开启调试模式** | `status` |

> 关键点：`MacroExecutor` 内部已把 `debugMode` 的存在作为是否发步骤状态的条件，但 `onMacroStatus` 回调本身不区分「调试文本」与「生命周期」。方案：在 `MacroExecutor.executeStat` 生命周期消息上打上统一 marker 前缀，或让 `MacroLogStore` 持有「当前宏是否调试模式」状态（由 execute 时传入），按固定关键词集合判定生命周期。
>
> 采用**后者**（store 保存 debugMode 标志，按关键词集合识别生命周期消息），改动最小、不侵入现有 `postStatus` 文案。

为此 `MacroExecutor.execute()` 需在开始线程前通知 store 会话开始：

```kotlin
MacroLogStore.onSessionStart(pluginId, debugMode = settings["debugMode"] as? Boolean ?: false)
```

### 3.4 原生改动

#### A. 新增 `MacroLogStore.kt`

```kotlin
object MacroLogStore : MacroExecutorListener {
    // 会话期间记录当前 pluginId 与 debugMode
    fun onSessionStart(pluginId: String?, debugMode: Boolean)

    // MacroExecutorListener
    override fun onMacroStatus(message: String)
    override fun onMacroPrint(message: String)

    fun getLogs(context: Context, pluginId: String): List<MacroLogEntry>
    fun clearLogs(context: Context, pluginId: String)
}
```

- `onSessionStart` 重置会话字段（pluginId 为 null 时不记录，兼容旧调用路径）。
- 在 `postStatus` / `postPrint` 路径上自动调用（store 已注册为 listener，无需改 MacroExecutor 的 post 逻辑；只需在 execute 开头调一次 `onSessionStart`）。
- 生命周期关键词集合：`开始执行`、`任务完成`、`任务已停止`、`宏已停止`、前缀 `任务异常`。

#### B. `executeMacro` 链路携带 pluginId

- `InputAccessibilityService.executeMacro(context, settings, steps, assetsDir, pluginId: String? = null)`，内部 `executeMacroInternal(..., pluginId)` 传给 `MacroExecutor.execute(settings, steps, ...)`（execute 增加 `pluginId` 参数）。
- `MainActivity.executeMacro` 分支透传通道 `pluginId` 参数（兼容 null）。
- `FloatingBallService.runEnabledMacro`：传入当前启用宏的 id（需在 loadEnabledMacro 处同步读出 id，或从 FlutterSharedPreferences 的 isolation_plugins 解析启用宏 id——复用 `findPluginDirectoryByName` 同款做法）。
- `MacroScheduleReceiver`：已持有 pluginId，直接传入。
- `MacroExecutor.execute(settings, steps, pluginId: String? = null)`：开头 `MacroLogStore.onSessionStart(pluginId, debugMode)`。

#### C. `MacroExecutor` 注册 listener

`executeMacroInternal` 已有 `MacroExecutor.addListener(this)`（InputAccessibilityService 实例）。新增 `MacroLogStore` 在进程侧注册一次即可（例如第一次调用 `onSessionStart` 时懒注册）。

### 3.5 Flutter 改动

#### A. `lib/services/native_channel.dart`

```dart
/// 读取某宏的执行日志（时间升序，最多 N 条）
static Future<List<Map<String, dynamic>>> getMacroLogs(String pluginId);

/// 清空某宏的执行日志
static Future<bool> clearMacroLogs(String pluginId);
```

#### B. `lib/providers/plugin_provider.dart`

- `Future<List<MacroLogEntry>> loadMacroLogs(String pluginId)`：包装通道读取并映射为模型。
- `Future<void> clearMacroLogs(String pluginId)`：调用通道清空。

#### C. `lib/models/macro_log.dart`（新增）

```dart
class MacroLogEntry {
  final DateTime time;
  final String type;    // 'print' | 'status'
  final String message;
}
```

#### D. `lib/screens/macro_settings_screen.dart`

在「定时启动宏」卡片下方新增「执行日志」卡片：

```
[执行日志]                    [清空]
[16:30:01] 📄 print   签到成功
[16:30:00] ℹ️ status  执行第 1 步: click
[16:29:59] ℹ️ status  开始执行
```

- 进入页面时异步 `loadMacroLogs(pluginId)`；空数据时显示「暂无日志」。
- print 用 `Icons.chat_bubble_rounded`，status 用 `Icons.info_outline_rounded`，颜色区分。
- 时间格式化 `HH:mm:ss`；日志条带类型颜色 `Colors.black.withValues(alpha: 0.6)` 等，符合 v2 UI 规范。
- 卡片可展开/收起（默认展开，最多显示 50 条，超出显示「仅展示最近 50 条」提示——**或**直接展示全部 300 条，量级可接受，先展示最近 100 条）。
- 「清空」按钮：红色文字 + 二次确认对话框，成功后 `setState` 刷新为空。

## 四、边界情况与注意事项

| 场景 | 处理 |
|------|------|
| 未开启调试模式 | 只记录 print 与生命周期，不记录每步状态 |
| 旧调用路径（未传 pluginId）| pluginId 为 null 时不记录，保证向前兼容 |
| 日志文件损坏 / 不存在 | `getMacroLogs` 返回空列表，不抛异常 |
| 文件无限增长 | 单文件上限 300 条，超出裁剪 |
| 定时执行 / 悬浮球执行 / 通道执行 | 三条路径都携带 pluginId，均可记录 |
| 宏被删除 | 不主动清理日志文件（保留可接受）；「清空日志」可手动删除。若需自动清理，可挂在 deletePlugin 后（可选） |
| 卸载重装 | 日志随应用私有目录删除，无需处理 |
| 并发写 | 日志写入发生在 mainHandler 线程（postStatus/postPrint 已 post 主线程），单线程写文件，无需加锁 |

## 五、改动文件清单

| 文件 | 改动 |
|------|------|
| `android/.../MacroLogStore.kt` | **新增**：日志捕获、持久化、查询、清空 |
| `android/.../MacroExecutor.kt` | `execute()` 增加 `pluginId` 参数；开头调用 `MacroLogStore.onSessionStart` |
| `android/.../InputAccessibilityService.kt` | `executeMacro` / `executeMacroInternal` 透传 `pluginId` |
| `android/.../MainActivity.kt` | `executeMacro` 通道读取并转发 `pluginId`；新增 `getMacroLogs` / `clearMacroLogs` 通道分支 |
| `android/.../FloatingBallService.kt` | `runEnabledMacro` 解析并传入当前启用宏 id |
| `android/.../MacroScheduleReceiver.kt` | 已有 pluginId，直接传入 |
| `lib/services/native_channel.dart` | 新增 `getMacroLogs` / `clearMacroLogs` |
| `lib/providers/plugin_provider.dart` | 新增 `loadMacroLogs` / `clearMacroLogs` |
| `lib/models/macro_log.dart` | **新增**：`MacroLogEntry` 模型 |
| `lib/screens/macro_settings_screen.dart` | 新增「执行日志」卡片（列表 + 清空） |
| `test/models/macro_settings_test.dart` | 补充 `MacroLogEntry` 序列化测试（如适用） |

## 六、验收标准

- [ ] 未开调试模式执行宏：日志记录全部 print 内容与开始/完成等生命周期状态。
- [ ] 开启调试模式执行宏：额外记录「执行第 N 步」「find 命中/未命中」等每步状态。
- [ ] 「宏设置」页「执行日志」卡片展示最近日志，print 与状态视觉可区分。
- [ ] 定时触发、悬浮球点击、通道执行三种方式产生的日志均归属正确宏。
- [ ] 重启 App 后日志仍在；「清空日志」后列表为空。
- [ ] 日志超过 300 条时按最早时间裁剪，不无限增长。

## 七、未来扩展（不在本期范围）

- 日志搜索 / 按类型过滤。
- 每条日志可复制到剪贴板，或一键导出全部日志为 txt。
- 日志保留条数作为宏设置项（滑杆）。
- 每次执行生成会话分组（本次执行 vs 上次执行），按会话折叠展示。