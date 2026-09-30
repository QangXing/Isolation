# 新增 longPressAt 长按指令设计

## 背景

宏脚本目前的基础动作只有 `click`（单击）与 `swipe`（滑动），缺少"长按"操作。部分场景（图标整理、删除二次确认、长按唤起快捷面板等）需要按住屏幕某个位置并保持一段时间。

## 命名：为什么用 `longPressAt`

`longPress` 已被悬浮球 DSL 的"长按事件"关键字占用（见 `BALL_SPEC.md` 事件触发指令、`macro_program_parser.dart` 中 `singleClick / doubleClick / tripleClick / longPress` 的 `normalize` 分支），若直接复用会造成解析歧义：

- 该分支会把第一个位置参数当作 action 关键字提取（`step['action'] = keyword(0)`），坐标参数会丢失。
- 同一关键字在不同上下文含义不同，解析与高亮都难以区分。

因此新指令命名为 **`longPressAt`**：

- 与 `colorAt` / `ifColorAt` 的 "`At`" 后缀约定一致，表示"作用于指定屏幕坐标"。
- 与悬浮球事件 `longPress` 在语义与拼写上明确区分，互不干扰。

## DSL 语法

```dsl
longPressAt(500, 800)                  // 在 (500, 800) 长按，使用默认时长
longPressAt(500, 800, 1500)            // 在 (500, 800) 长按 1500ms
longPressAt(x, y, duration=1000)       // 坐标与时长均支持变量/表达式/命名参数
```

在 `find` / `waitFor` 块内，支持无参形式长按最近命中的坐标（与 `click()` 行为一致）：

```dsl
findText("应用图标") {
    longPressAt()
}
```

## 参数说明

| 参数 | 位置 | 类型 | 默认值 | 说明 |
|---|---|---|---|---|
| `x` | 第 1 位 | 数字/变量/表达式 | 必填* | 屏幕像素横坐标，原点为屏幕左上角 |
| `y` | 第 2 位 | 数字/变量/表达式 | 必填* | 屏幕像素纵坐标 |
| `duration` | 第 3 位，可命名 | 数字/变量/表达式 | `800` | 按压保持时长（毫秒），须大于目标应用的长按判定阈值 |

\* 使用无参形式 `longPressAt()` 时 `x`/`y` 不填，取当前查找块命中的坐标；若不在查找块内且无坐标，输出错误日志并返回失败（与 `click()` 一致）。

默认时长取 `800ms`：Android 系统长按阈值（`ViewConfiguration.getLongPressTimeout()`）约为 `500ms`，`800ms` 可稳定触发绝大多数应用的长按判定，同时避免过长的无意义按压。

## 执行语义（Android 侧）

1. 解析并计算 `x`、`y`、`duration`（支持表达式与变量）。
2. 构造单笔 `GestureDescription.StrokeDescription(path, 0, duration)`：
   - `path` 从 `(x, y)` 到 `(x + 0.5, y + 0.5)`，加入极短位移，避免部分系统将单点手势优化掉（与 `dispatchClick` 相同做法）。
   - `duration` 即按压保持时长。
3. 通过 `service.dispatchGesture(...)` 派发，阻塞等待结果。
4. 返回布尔值：派发成功为 `true`，失败为 `false`。

与 `click` 相同，该指令为纯动作指令，不参与变量赋值与条件判断。

## 实现要点

- 建议将 `dispatchClick(x, y)` 抽取为通用的 `dispatchGesture(x, y, durationMs)`，`click` 传 `80`，`longPressAt` 传用户时长，避免重复代码。

## 影响文件

| 文件 | 改动 |
|---|---|
| `lib/services/macro_program_parser.dart` | `_normalizeStep` 新增 `case 'longPressAt': assign(['x', 'y', 'duration'])`；`_serializeStep` 新增序列化分支 |
| `lib/services/macro_syntax_highlighter.dart` | `_keywords` 添加 `longPressAt` |
| `android/.../MacroExecutor.kt` | `executeStep` 的 when 分支新增 `"longPressAt" -> executeLongPressStep(step)`；实现 `executeLongPressStep`（支持无参取查找坐标），并抽取 `dispatchGesture` |
| `docs/DSL_SPEC.md` | §2 基础动作指令表格新增 `longPressAt(x, y, duration)` 行 |
| `test/services/macro_program_parser_test.dart` | 新增 `longPressAt` 解析与 round-trip 序列化测试 |

## 权限

无需额外权限，长按通过无障碍手势派发实现，与现有 `click` / `swipe` 一致。
