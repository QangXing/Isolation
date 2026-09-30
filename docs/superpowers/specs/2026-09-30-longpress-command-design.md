# 新增 longPressAt 长按指令设计

## 背景

宏脚本目前的基础动作只有 `click`（单击）与 `swipe`（滑动），缺少"长按"操作。部分场景（图标整理、删除二次确认、长按唤起快捷面板等）需要按住屏幕某个位置并保持一段时间。

## 英文命名设计

### 候选方案对比

| 候选名 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| `longPress` | 语义最直白，与中文"长按"一一对应 | 与悬浮球"长按事件"关键字**冲突**：`macro_program_parser.dart` 的 `longPress` 分支会把第一个位置参数提取为 `action`（`step['action'] = keyword(0)`），坐标参数会被丢弃，解析歧义无法消除 | ✗ 不可用 |
| `longClick` | Android 有 `ACTION_CLICK_LONG` 先例，无冲突 | 与现有动作命名体系不一致（现有为 `click` / `swipe` / `colorAt`，没有 Click 后缀风格）；"Click" 语义上偏单击 | ✗ 不采用 |
| `press` | 简短 | 语义模糊（无法表达"长按"），且与未来可能的"短按/按下"指令冲突 | ✗ 不采用 |
| `longPressAt` | 见下方决策理由 | 名称稍长 | ✓ **采用** |

### 决策理由

1. **避开 `longPress` 冲突**：悬浮球 DSL 已用 `longPress` 表示"长按悬浮球事件"（见 `BALL_SPEC.md` §6、parser 的 `singleClick / doubleClick / tripleClick / longPress` normalize 分支）。同一关键字若同时表示"屏幕长按动作"，解析与语法高亮都无法区分上下文。
2. **遵循现有 "`At`" 后缀约定**：`colorAt(x, y)` / `ifColorAt(x, y, ...)` 已用 `At` 表示"作用于指定屏幕坐标"，`longPressAt` 沿用同一模式，命名自解释：`longPress` + `At` = "在指定坐标长按"。
3. **动作指令统一为小驼峰**：`click`、`swipe`、`swipeRel`、`launch` 均为小驼峰，`longPressAt` 符合规范。

## DSL 语法设计

### 语法规则（EBNF 风格）

```
longPressAt   ::= 'longPressAt' '(' [ args ] ')'

args          ::= expr ',' expr [ ',' expr ]        // 位置参数
                | expr ',' expr ',' 'duration=' expr  // 命名参数
                | 'duration=' expr ')'               // 非法，见错误处理

expr          ::= 数字 | 变量 | 算术/逻辑表达式
```

### 三种合法调用形式

| 形式 | 参数个数 | 含义 |
|---|---|---|
| `longPressAt()` | 0 | 在 `find` / `waitFor` 块内长按最近命中坐标 |
| `longPressAt(x, y)` | 2 | 在指定坐标长按，`duration` 取默认值 `800` |
| `longPressAt(x, y, duration)` / `longPressAt(x, y, duration=1000)` | 3 | 在指定坐标长按指定毫秒数 |

### 示例

```dsl
longPressAt(500, 800)                  // 在 (500, 800) 长按，使用默认时长 800ms
longPressAt(500, 800, 1500)            // 在 (500, 800) 长按 1500ms
longPressAt(x, y, duration=1000)       // 坐标与时长均支持变量/表达式/命名参数
longPressAt(btnX, btnY, 2000)          // 变量坐标 + 位置参数时长

findText("应用图标") {
    longPressAt()                      // 块内无参：长按命中坐标
}
```

### 错误处理

| 场景 | 行为 |
|---|---|
| 只传 1 个参数（如 `longPressAt(500)`） | 非法形式，解析时抛出 `MacroParseError` 提示"longPressAt 需要 0、2 或 3 个参数" |
| 无参形式出现在 `find` / `waitFor` 块外 | 与 `click()` 一致：输出错误日志"缺少坐标且不在 find 块内"，返回失败 |
| `duration < 0` | 运行时按 `0` 处理（退化为极短按压），不报错 |

### 解析与序列化规则

- 解析（`_normalizeStep`）：`case 'longPressAt': assign(['x', 'y', 'duration'])`，与 `swipeRel` 同构。
- 序列化（`_serializeStep`）：输出 `longPressAt(x, y)` 或 `longPressAt(x, y, duration)`；坐标/时长若为表达式则按现有 `_serializeExprValue` 还原。
- 关键字注册：`_keywords` 添加 `longPressAt`，语法高亮生效。

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
