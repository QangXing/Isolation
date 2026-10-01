# 仓库 Bug 排查报告

> 排查日期：2026-09-30
> 范围：宏执行引擎、定时调度、日志系统、DSL 解析器、Flutter 数据层、辅助功能服务、悬浮球服务

## 状态说明

| 编号 | 严重度 | 问题 | 状态 |
| --- | --- | --- | --- |
| #0 | 高 | 表达式求值除零错误 | ✅ 已修复 |
| #1 | 高 | 定时宏"每日触发"静默失效 | ✅ 已修复 |
| #2 | 高 | 无 body 的 `waitForX` 不等待直接返回失败 | ✅ 已修复 |
| #3 | 高 | `executeMacro` 假成功 | ✅ 已修复 |
| #4 | 中 | 宏运行状态 UI 永远显示"未运行" | ✅ 已修复 |
| #5 | 中 | floater 事件处理器无限递归风险 | ✅ 已修复 |
| #6 | 中 | 无宏运行时三连击仍弹提示 | ✅ 已修复 |
| #7 | 低 | `setEnabled` 的 `firstWhere` 无 `orElse` 崩溃风险 | ⏳ 待处理 |
| #8 | 低 | audio 播放不随宏停止 | ⏳ 待处理 |
| #9 | 低 | 解析器转义引号切分错误 | ⏳ 待处理 |
| #10 | 低 | find 块内无参 click 的事件变量为 0 | ⏳ 待处理 |
| #11 | 低 | `execute()` 并发竞态 | ⏳ 待处理 |

---

## #0 表达式求值除零错误（已修复）

- **位置**：`ExpressionEvaluator.kt` 除法运算
- **问题**：`l / r` 在 `r == 0.0` 时产生 `Infinity/NaN`，可能污染变量与循环条件。
- **修复**：除数为零时返回 `null`，表达式求值失败。

## #1 定时宏"每日触发"静默失效（已修复）

- **位置**：`MacroScheduleReceiver.onReceive`
- **问题**：
  - 辅助功能未开启（state=1）或服务未连上（state=2）时直接 `return`，没有续排明天的闹钟，定时从此永久失效。
  - `executeMacro` 返回 `false` 时同样不续排。
- **修复**：除"宏文件缺失（配置被清除）"外，其余路径一律调用 `MacroScheduler.scheduleNext` 续排次日同一时间。

## #2 无 body 的 `waitForX` 不等待（已修复）

- **位置**：`MacroExecutor.executeWaitForStep`
- **问题**：`(step["children"] as? List<*>) ... ?: return false`，缺 `children` 键时立即返回，连轮询都没有。`waitForText("加载完成")` 这类不带代码块的写法会被直接跳过，与"等待命中"语义不符。
- **修复**：`children` 允许为空，无 body 时仍轮询直到命中或超时。

## #3 `executeMacro` 假成功（已修复）

- **位置**：`InputAccessibilityService.executeMacro` / `MacroExecutor.execute`
- **问题**：内部 `MacroExecutor.execute` 在已有宏运行时是静默 void 返回，但外层 `executeMacro` 仍返回 `true`，调用方误以为宏已启动。
- **修复**：`execute` 改为返回 `Boolean`（是否真正启动），`executeMacroInternal` / `executeMacro` 透传真实结果。

## #4 宏运行状态 UI 永远显示"未运行"（已修复）

- **位置**：`PluginProvider.runMacroPlugin`
- **问题**：`NativeChannel.executeMacro` 只负责启动线程、立即返回，`_runningMacroId` 随即被清空，`isRunningMacro` 实际恒为 `false`。
- **修复**：新增原生 `isMacroRunning` 方法；Dart 侧启动成功后后台轮询原生执行状态，宏结束后才清除"运行中"标记。

## #5 floater 事件处理器无限递归风险（已修复）

- **位置**：`MacroExecutor.runFloaterHandlers`
- **问题**：`floater(click) { click() }` 这类 handler 内再次触发同事件指令会无限递归直至栈溢出。
- **修复**：增加事件处理器嵌套深度上限（16 层），超限时忽略并输出状态提示。

## #6 无宏运行时三连击仍弹提示（已修复）

- **位置**：`MacroExecutor.notifyFloatingBallClick`
- **问题**：`activeExecutor == null`（无宏运行）时仍显示"已强制停止循环"。
- **修复**：仅当确有宏在运行时才停止并弹 toast。

---

## 待处理问题

### #7 `setEnabled` 崩溃风险（低）

- **位置**：`PluginProvider.setEnabled`（第 172 行）及 `_writeEnabledMacro`（第 1011 行）
- **问题**：`_plugins.firstWhere((p) => p.id == id)` 无 `orElse`，id 不存在时抛 `StateError` 崩溃。
- **建议**：补充 `orElse` 兜底。

### #8 audio 播放不随宏停止（低）

- **位置**：`MacroExecutor.playAudio`
- **问题**：`MediaPlayer` 无引用跟踪，宏停止后音频继续播放；多次播放会叠加。
- **建议**：维护播放器列表，宏结束时统一释放。

### #9 解析器转义引号切分错误（低）

- **位置**：`macro_program_parser.dart` `_splitArgs`
- **问题**：未处理字符串内的 `\"`，`"a\"b,c"` 会被错误切分。
- **建议**：字符串内遇到 `\` 时跳过下一个字符。

### #10 find 块内无参 click 的事件变量为 0（低）

- **位置**：`MacroExecutor.setEventVariables`
- **问题**：`click()` 实际点击的是 find 命中坐标，但注入的 `clickX/clickY` 是 0。
- **建议**：无显式坐标时取 `foundCoordinates.firstOrNull()`。

### #11 `execute()` 并发竞态（低）

- **位置**：`MacroExecutor.execute`
- **问题**：`if (running || activeExecutor != null) return` 非原子，并发调用可能双双通过检查。
- **建议**：对启动检查加锁或使用原子标记。
