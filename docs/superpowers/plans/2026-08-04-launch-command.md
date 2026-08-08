# launch 应用启动指令实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Isolation 宏 DSL 中新增 `launch(packageName, timeout?)` 指令，支持启动其他应用并可选等待目标应用窗口出现。

**Architecture:** 在 Dart 解析器中将 `launch(...)` 解析为 `type: 'launch'` 的步骤；在 Kotlin 执行器中通过 `startActivity` 启动目标应用，若指定 timeout 则轮询 Accessibility 根节点包名直到命中或超时。

**Tech Stack:** Flutter / Dart, Kotlin, Android AccessibilityService, GitHub Actions

---

### Task 1: Parser 支持 launch 指令

**Files:**
- Modify: `lib/services/macro_program_parser.dart:9-10`
- Modify: `lib/services/macro_program_parser.dart:57-118`
- Modify: `lib/services/macro_program_parser.dart:200-280`（序列化分支，需先查看）

- [ ] **Step 1: 在 DSL 命令注释中添加 launch**

```dart
/// - 动作：click / swipe / input / wait / print / back / home / recents / launch
/// - 变量：let
```

- [ ] **Step 2: 在 _normalizeStep 中添加 launch 分支**

```dart
case 'launch':
  if (positional.isNotEmpty) step['packageName'] = positional[0];
  break;
```

放在 `case 'wait':` 之后即可。

- [ ] **Step 3: 在序列化分支中添加 launch**

在 `_serializeStep` 的 switch 中，找到 `case 'wait'` 附近，添加：

```dart
case 'launch':
  final packageName = step['packageName'];
  final timeout = step['timeout'];
  final args = <String>[
    if (packageName != null) _serializeArg('packageName', packageName),
    if (timeout != null) _serializeArg('timeout', timeout),
  ];
  _writeLine(buffer, indent, 'launch($args)');
  _serializeBody(step, indent, buffer);
  break;
```

> 注意：`_serializeArg` 函数名需以实际解析器中的辅助函数为准；若不存在，直接拼字符串 `"$name=$value"`。

- [ ] **Step 4: Commit**

```bash
git add lib/services/macro_program_parser.dart
git commit -m "feat(parser): 支持 launch 指令解析与序列化"
```

---

### Task 2: 语法高亮添加 launch 关键字

**Files:**
- Modify: `lib/services/macro_syntax_highlighter.dart`

- [ ] **Step 1: 在关键字集合中添加 launch**

```dart
const Set<String> commandKeywords = {
  'click', 'swipe', 'input', 'wait', 'print',
  'back', 'home', 'recents',
  'findText', 'findColor', 'findImage',
  'waitForText', 'waitForColor', 'waitForImage',
  'loop', 'colorAt',
  'if', 'ifText', 'ifColor', 'ifImage', 'ifColorAt',
  'for', 'let', 'else',
  'launch', // 新增
};
```

- [ ] **Step 2: Commit**

```bash
git add lib/services/macro_syntax_highlighter.dart
git commit -m "feat(highlighter): 将 launch 加入关键字高亮"
```

---

### Task 3: Kotlin 执行器实现 launch

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt`

- [ ] **Step 1: 在 executeStep 的 when 分支中注册 launch**

```kotlin
// 系统键
"back" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
"home" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
"recents" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_RECENTS)

// 新增：启动应用
"launch" -> executeLaunchStep(step)
```

- [ ] **Step 2: 新增 executeLaunchStep 方法**

```kotlin
private fun executeLaunchStep(step: Map<String, Any>): Boolean {
    val packageName = step["packageName"] as? String ?: return false
    val timeout = evaluateNumber(step["timeout"])?.toLong() ?: 0L

    val intent = service.packageManager.getLaunchIntentForPackage(packageName)
    if (intent == null) {
        postStatus("launch: 无法启动 $packageName")
        return false
    }

    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    service.startActivity(intent)

    if (timeout <= 0) return true

    val start = SystemClock.elapsedRealtime()
    while (SystemClock.elapsedRealtime() - start < timeout) {
        if (stopRequested) return false
        val root = service.rootInActiveWindow
        if (root != null && root.packageName?.toString() == packageName) {
            return true
        }
        Thread.sleep(200)
    }
    return false
}
```

- [ ] **Step 3: 让 launch 可以参与 let / if 求值**

在 `executeLetStep` 与 `executeAssignStep` 中，若 `value` 是 Map 且包含 `"type": "launch"`，需要直接执行并返回布尔变量。

更简洁的做法：在 `ExpressionEvaluator.evaluate` 中支持对 `launch` step 的求值。但为了避免过度改动，可在 `executeLetStep` 中特判：

```kotlin
private fun executeLetStep(step: Map<String, Any>) {
    val name = step["name"] as? String ?: return
    val value = step["value"] as? Map<String, Any> ?: return
    val type = value["type"] as? String

    val result = if (type == "launch") {
        val success = executeLaunchStep(value)
        Variable.Number(if (success) 1 else 0)
    } else {
        ExpressionEvaluator.evaluate(value, variables) ?: return
    }
    variables[name] = result
}
```

同时把 `executeIfStep` 中对条件 step 的处理也改为识别 `launch` 类型：

```kotlin
private fun executeIfStep(step: Map<String, Any>) {
    val condition = step["condition"] as? Map<String, Any>
    val conditionType = condition?.get("type") as? String
    val matched = when (conditionType) {
        "launch" -> executeLaunchStep(condition)
        else -> condition != null && evaluateCondition(condition)
    }
    // ... 后续 then/else 逻辑不变
}
```

> 需要先读取 `executeIfStep` 现有实现，保持原有结构。

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt
git commit -m "feat(executor): 实现 launch 应用启动与等待指令"
```

---

### Task 4: 编辑器快捷插入 chips 添加 launch

**Files:**
- Modify: `lib/screens/program_macro_screen.dart`

- [ ] **Step 1: 在快捷插入列表中添加 launch chip**

```dart
Chip(
  label: const Text('launch'),
  onPressed: () => _insertCode('launch("com.example.app", timeout=3000) {\n    \n}'),
),
```

- [ ] **Step 2: Commit**

```bash
git add lib/screens/program_macro_screen.dart
git commit -m "feat(editor): 快捷插入添加 launch 模板"
```

---

### Task 5: 更新 DSL_SPEC.md

**Files:**
- Modify: `docs/DSL_SPEC.md`

- [ ] **Step 1: 在“基础动作指令”表格中添加 launch 行**

```markdown
| `launch("包名", timeout=3000)` | 启动其他应用，超时返回 0/1 | `launch("com.example.app", timeout=3000)` |
```

- [ ] **Step 2: 在文档末尾新增“启动应用”小节**

```markdown
## 10. 启动应用

```dsl
launch("com.example.app")
launch("com.example.app", timeout=3000)
let ok = launch("com.example.app", timeout=3000)
if (launch("com.example.app", timeout=3000)) {
    click(500, 800)
}
```

- `packageName`：目标应用包名，必填。
- `timeout`：最长等待毫秒数，默认 `0`（不等待）。
- 返回值：`1` 表示目标应用窗口已出现，`0` 表示超时或启动失败。
```

- [ ] **Step 3: Commit**

```bash
git add docs/DSL_SPEC.md
git commit -m "docs: DSL_SPEC 新增 launch 指令说明"
```

---

### Task 6: 新增 Parser 测试

**Files:**
- Modify: `test/services/macro_program_parser_test.dart`

- [ ] **Step 1: 添加 launch round-trip 测试**

```dart
test('launch command round-trip', () {
  const code = '''
launch("com.example.app", timeout=3000) {
    click(500, 800)
}
'''.trim();
  final parsed = MacroProgramParser.parse(code);
  expect(parsed.length, 1);
  expect(parsed.first['type'], 'launch');
  expect(parsed.first['packageName'], 'com.example.app');
  expect(parsed.first['timeout'], 3000);
  expect(parsed.first['children'], isA<List>());
  final serialized = MacroProgramParser.serialize(parsed).trim();
  expect(serialized, code);
});
```

- [ ] **Step 2: Commit**

```bash
git add test/services/macro_program_parser_test.dart
git commit -m "test(parser): 添加 launch 指令 round-trip 测试"
```

---

## Self-Review

1. **Spec coverage:**
   - DSL 语法 → Task 1 + Task 5
   - 执行语义 → Task 3
   - 返回值 → Task 3
   - 编辑器支持 → Task 4
   - 测试 → Task 6
   - 无遗漏

2. **Placeholder scan：** 无 TBD、TODO 或模糊描述，所有步骤包含具体代码。

3. **Type consistency：**
   - Dart 端字段名为 `packageName`、`timeout`
   - Kotlin 端读取相同字段名
   - 返回值统一用 `Boolean` 表示，存入变量时转换为 `Variable.Number(1/0)`
