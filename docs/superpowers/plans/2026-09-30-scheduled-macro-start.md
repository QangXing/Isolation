# 定时启动宏 设计文档

> 需求：在「宏设置」页新增一个设置项，让指定宏可以在每天固定时间自动开始执行。
> 本文档只做设计，不涉及代码落地。

---

## 一、需求描述

用户希望在宏设置页新增「定时启动宏」开关：

- 开启后选择一个每日触发时间（时:分）。
- 保存设置后，即使 App 退到后台、甚至进程被系统回收，到点也要自动执行该宏。
- 到点执行时与手动点击悬浮球执行走同一条执行链路（辅助功能服务 + MacroExecutor），不要求悬浮球处于显示状态。
- 关闭开关或删除宏后，定时任务同步取消。

### 交互暂定

| 控件 | 位置 | 行为 |
|------|------|------|
| 开关「定时启动宏」 | 「宏设置」页一张新卡片内 | 打开后展开时间选择 |
| 时间选择 | 同一卡片内，显示 `HH:mm` | 点击弹出 `showTimePicker` |
| 副标题提示 | 卡片副标题 | 「到每天设定时间自动执行该宏（需已开启辅助功能）」 |

## 二、现状梳理

### 2.1 宏设置链路（Flutter 侧）

1. [macro_settings_screen.dart](file:///workspace/lib/screens/macro_settings_screen.dart) 是宏设置页，设置项以卡片形式通过 `_buildSwitchCard` / `_buildNumberCard` 渲染，点「保存设置」统一走 `_save()`。
2. [plugin_provider.dart](file:///workspace/lib/providers/plugin_provider.dart#L419-L487) 的 `updateMacroMetadata()` 把 `MacroSettings` 写回 `<pluginDir>/<pluginId>/macro.json` 的 `settings` 字段，并在该宏是当前启用宏时同步写 `enabled_macro.json`。
3. [macro.dart](file:///workspace/lib/models/macro.dart#L1-L57) 的 `MacroSettings` 是设置的数据模型，含 `toJson / fromJson / copyWith`，新增字段需三处同步修改。

### 2.2 宏执行链路（原生侧）

1. 手动触发入口是 [FloatingBallService.runEnabledMacro()](file:///workspace/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt#L1229-L1252)：读 `filesDir/enabled_macro.json` → 校验辅助功能就绪 → `InputAccessibilityService.executeMacro(settings, steps)`。
2. [InputAccessibilityService.executeMacro](file:///workspace/android/app/src/main/kotlin/com/example/isolation/InputAccessibilityService.kt#L76-L83) 是原生层的统一执行入口；触摸动画覆盖层、多 listener 都在该服务内部，**执行宏不依赖悬浮球服务存活**。
3. `MacroExecutor` 已有 `findPluginDirectoryByName()` 通过 `File(service.filesDir, "plugins/$id")` 访问插件目录（路径与 Flutter 侧 `getApplicationDocumentsDirectory()/plugins` 一致），可直接复用来定位定时宏的 `macro.json`。

### 2.3 现状结论

- 定时执行的「触发」环节是全新能力：当前没有任何定时机制（无 AlarmManager / WorkManager / 广播接收器）。
- 定时执行的「执行」环节可直接复用：`InputAccessibilityService.executeMacro()`。
- 数据模型扩展成本低：`MacroSettings` 加字段，其余跟随既有序列化逻辑。

## 三、方案设计

### 3.1 总体架构

```
┌───────────────────────────── Flutter ─────────────────────────────┐
│ 宏设置页(新增定时卡片) → updateMacroMetadata → macro.json.settings  │
│      │ 保存时同步调用 NativeChannel.setMacroSchedule(...)          │
└──────┼────────────────────────────────────────────────────────────┘
       ▼
┌───────────────────────────── 原生 (Android) ──────────────────────┐
│ MainActivity.setMethodCallHandler → MacroScheduler.schedule(...)   │
│      │                                                            │
│      ├─ AlarmManager.setExactAndAllowWhileIdle(RTC_WAKEUP, ...)   │
│      │   + PendingIntent → MacroScheduleReceiver                   │
│      │                                                            │
│      └─ 到点唤醒 → MacroScheduleReceiver.onReceive                 │
│            └─ 读自身配置的 pluginId/macroFile → 加载 macro.json     │
│                 └─ 校验辅助功能就绪 → InputAccessibilityService     │
│                     .executeMacro(...)                             │
│      └─ 执行完成后 `MacroScheduler.scheduleNext(...)` 排明天同一时 │
│        间（每日重复）                                             │
└───────────────────────────────────────────────────────────────────┘
```

**方案选型：AlarmManager（精确）而非 WorkManager。**

| 方案 | 精确到分钟 | 进程被杀仍触发 | 备注 |
|------|-----------|---------------|------|
| WorkManager | ✗（15 分钟粒度，不保证准点） | ✓ | 不适合「定时」语义 |
| AlarmManager（setExactAndAllowWhileIdle） | ✓ | ✓（广播接收器常驻注册） | 需处理 Android 12+ 精确闹钟权限 |

### 3.2 数据模型（lib/models/macro.dart）

在 `MacroSettings` 上新增 3 个字段（默认值保证旧数据反序列化兼容）：

```dart
/// 定时启动宏开关
final bool scheduleEnabled;

/// 触发小时（0-23）
final int scheduleHour;

/// 触发分钟（0-59）
final int scheduleMinute;
```

- 默认：`scheduleEnabled: false, scheduleHour: 8, scheduleMinute: 0`。
- `toJson`：仅 scheduleEnabled 打开时才写 `scheduleHour/ScheduleMinute`（或全部照写均可，字段极小，全部写入更简单）。
- `fromJson`：缺省读默认值，旧宏文件不受影响。
- `copyWith`：同步新增 3 个参数。

v1 只支持「每天同一时间」；周几重复留到后续版本（见"未来扩展"）。

### 3.3 UI（lib/screens/macro_settings_screen.dart）

在「无限循环」卡片之后新增一张卡片，复用 `GlassCard`：

```
[定时启动宏]
[开关]  到每天设定时间自动执行该宏（需已开启辅助功能）
        [08:00 ▾]   ← 仅开关打开时显示；点击弹 showTimePicker
```

- 开关状态绑定 `_settings!.scheduleEnabled`，onChanged 时 `copyWith(scheduleEnabled: value)`。
- 时间文本绑定 `scheduleHour:scheduleMinute`，点击 `showTimePicker(context, initialTime: TimeOfDay(...))` 后 `copyWith(scheduleHour, scheduleMinute)`。
- 保存流程无需改动 `_save()`：时间/开关已并入 `_settings`，`updateMacroMetadata` 自然写入 macro.json。

### 3.4 定时注册/取消

#### Flutter 侧（lib/services/native_channel.dart + lib/providers/plugin_provider.dart）

新增两个通道方法：

```dart
/// 注册每日定时；enabled=false 或 hour/minute 变化时先取消旧的再注册
static Future<bool> setMacroSchedule({
  required String pluginId,
  required String macroFile,
  required bool enabled,
  required int hour,
  required int minute,
});

/// 取消某宏的定时
static Future<bool> clearMacroSchedule(String pluginId);
```

调用时机（均放在 `updateMacroMetadata` 保存成功后）：

- 保存时若 `plugin.enabled == true`：调用 `setMacroSchedule`，参数取自 `_settings` 与当前宏的 `macroFile`。
- 若宏被禁用 / 删除：调用 `clearMacroSchedule`。
- 导出/导入不影响定时：定时与插件目录绑定，重装后自然失效（可接受）。

> 为什么只在「启用宏」时注册：当前产品形态是宏互斥启用，只有启用中的宏才会被定时触发，与 `enabled_macro.json` 的语义一致。若未来想支持"定时未启用宏"，把条件去掉即可，原生侧不感知。

#### 原生侧（新增 2 个文件）

**`MacroScheduler.kt`** —— 定时注册/取消/读取配置的辅助类：

```kotlin
object MacroScheduler {
    // 通过 FlutterSharedPreferences 里的 isolation_plugins 定位插件目录（复用现有 findPluginDirectoryByName 思路）
    // schedule(pluginId, macroFile, hour, minute)
    //   → 计算下一个触发时间戳（今天若已过则明天）
    //   → AlarmManager.setExactAndAllowWhileIdle(RTC_WAKEUP, triggerAt, pendingIntent)
    //   → 把配置写入 SharedPreferences("isolation_schedules", JSON)
    // cancel(pluginId)
    //   → AlaramManager.cancel + 从 prefs 删除
    // scheduleNext(context, intent)  → 执行完成后排明天同一时间
    // loadScheduledConfigs(context)  → 供 BootReceiver 重启后重注册
}
```

**`MacroScheduleReceiver.kt`** —— 广播接收器（`android:exported="false"`，manifest 静态注册）：

```kotlin
class MacroScheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context, intent) {
        // 1. MacroExecutor.isRunning() ? 跳过本次（下次自动补）
        // 2. 从 intent extras 读 pluginId / macroFile
        // 3. 加载 <filesDir>/plugins/<pluginId>/<macroFile> → MacroData
        // 4. InputAccessibilityService.readinessState(context) == 0 才执行，
        //    否则 Toast 提示"辅助功能未开启，定时宏已跳过"
        // 5. InputAccessibilityService.executeMacro(context, settings, steps, assetsDir)
        // 6. MacroScheduler.scheduleNext(...) 排明天同一时间（每日重复）
        // 7. goAsync() 结束前做完整处理（AlarmManager receiver 有 10s 限制，
        //    executeMacro 内部是异步线程，直接返回即可，无需 goAsync 阻塞）
    }
}
```

关键点：

- **PendingIntent extras 携带 pluginId/macroFile**，触发时不再依赖 `enabled_macro.json`，保证"定时的是设置时指定的那个宏"。
- 执行走 `InputAccessibilityService.executeMacro`，与悬浮球链路一致，自动获得触摸动画与多 listener。
- 若到点发现该宏已被删除（文件不存在），静默跳过并不再续排。

#### 权限与注册（AndroidManifest.xml）

```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<receiver
    android:name=".MacroScheduleReceiver"
    android:exported="false" />

<receiver
    android:name=".BootReceiver"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED" />
    </intent-filter>
</receiver>
```

- `SCHEDULE_EXACT_ALARM`：Android 12+ 需要用户在系统设置授予（`canScheduleExactAlarms()`）；未授予时回退 `setAndAllowWhileIdle`（非精确，晚几分钟也算达标）。若想免授权可直接用 `USE_EXACT_ALARM`，但其受 Play 政策限制，本地分发型 App 可按需二选一，设计上先采用 `SCHEDULE_EXACT_ALARM`。
- Android 12 及以下 `setExactAndAllowWhileIdle` 无需权限。
- `BootReceiver`：重启后遍历 `isolation_schedules` 里的配置，重新注册所有定时（AlarmManager 的 RTC 闹钟重启后不会自动恢复）。

### 3.5 原生通道（MainActivity.kt）

在 `setMethodCallHandler` 新增两个分支：

```kotlin
"setMacroSchedule" -> {
    val pluginId = call.argument<String>("pluginId")
    val macroFile = call.argument<String>("macroFile")
    val enabled = call.argument<Boolean>("enabled") ?: false
    val hour = call.argument<Int>("hour") ?: 0
    val minute = call.argument<Int>("minute") ?: 0
    if (enabled) MacroScheduler.schedule(this, pluginId, macroFile, hour, minute)
    else MacroScheduler.cancel(this, pluginId)
    result.success(true)
}
"clearMacroSchedule" -> {
    val pluginId = call.argument<String>("pluginId")
    MacroScheduler.cancel(this, pluginId)
    result.success(true)
}
```

## 四、边界情况与注意事项

| 场景 | 处理 |
|------|------|
| 到点宏已在运行 | `MacroExecutor.isRunning()` 为真则跳过本次（不重复排队），下一周期正常触发 |
| 到点辅助功能未开启/未就绪 | Toast 提示并跳过；不续排（避免到点反复弹）——或选择续排，设计上先选"不续排 + 提示" |
| 进程被系统回收 | AlarmManager 闹钟与静态注册的 receiver 不受进程死亡影响，照常触发 |
| 系统重启 | BootReceiver 从 prefs 恢复全部定时并重新注册 |
| 宏被删除/插件目录缺失 | 加载失败静默跳过，不再续排 |
| 定时宏被禁用/取消勾选 | `clearMacroSchedule` 取消 PendingIntent |
| 时间修改 | 保存时先 `cancel` 再 `schedule`（天然覆盖） |
| 时区/夏令时变化 | AlarmManager RTC 闹钟按时间戳触发，时区变化由系统调整；本设计不额外处理（可选后续监听 `ACTION_TIME_CHANGED` 重注册） |
| 屏幕锁定/息屏 | `setExactAndAllowWhileIdle` 可唤醒执行，但完整 UI 操作类宏在锁屏下可能不生效；作为已知限制写入卡片副标题或说明页 |

## 五、改动文件清单

| 文件 | 改动 |
|------|------|
| `lib/models/macro.dart` | `MacroSettings` 新增 3 字段 + fromJson/toJson/copyWith |
| `lib/screens/macro_settings_screen.dart` | 新增「定时启动宏」卡片（开关 + 时间选择） |
| `lib/services/native_channel.dart` | 新增 `setMacroSchedule` / `clearMacroSchedule` |
| `lib/providers/plugin_provider.dart` | `updateMacroMetadata` 保存成功后同步注册/取消定时；禁用/删除宏时取消 |
| `android/.../MainActivity.kt` | 新增 2 个通道分支 |
| `android/.../AndroidManifest.xml` | 新增权限 + 2 个 receiver 声明 |
| `android/.../MacroScheduler.kt` | **新增**：AlarmManager 注册/取消/续排/持久化 |
| `android/.../MacroScheduleReceiver.kt` | **新增**：到点加载宏并执行 |
| `android/.../BootReceiver.kt` | **新增**：开机恢复定时 |
| `test/.../macro_settings` 相关测试 | 补充 MacroSettings 新字段序列化测试 |

## 六、验收标准

- [ ] 宏设置页出现「定时启动宏」开关，打开后可选择时间，保存后重启 App 配置仍在。
- [ ] 到设定时间，宏自动执行（悬浮球无需显示），行为与手动点击执行一致（含触摸动画、print 气泡）。
- [ ] 到点后自动排明天同一时间，连续多天可重复触发。
- [ ] 关闭开关 / 禁用宏 / 删除宏后，不再触发。
- [ ] 杀死 App 进程后到点仍能触发。
- [ ] 重启设备后定时恢复（需先校验精确闹钟权限集成创建问题预留的说明位）。

## 七、未来扩展（不在本期范围）

- 按周几重复（周一~周日位掩码）。
- 单次/自定义重复（N 天一次）。
- 定时前 5 分钟通知提醒，可一键取消本次。
- 定时执行失败（辅助功能未开）时异步通知兜底，而非仅 Toast。
- 锁屏时自动解锁后执行（涉及 KeyguardManager，复杂度高，单独评估）。