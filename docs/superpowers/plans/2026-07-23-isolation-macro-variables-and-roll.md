> **I'm using the writing-plans skill to create the implementation plan.**

# 宏 DSL 扩展：roll 绝对坐标、变量与表达式

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 扩展 Isolation 宏 DSL，支持 roll 绝对坐标、int/double/point/color 变量、四则运算与比较表达式，以及 C 风格 for 循环。

**Architecture:** Dart 侧负责 DSL 解析与序列化（新增表达式 AST），Kotlin 侧负责运行期变量表维护、表达式求值与扩展指令执行。保持现有 find/if 语义向后兼容。

**Tech Stack:** Flutter/Dart（解析器、UI），Kotlin（执行器、表达式求值），JUnit/Dart test。

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `lib/services/macro_program_parser.dart` | 扩展 DSL 解析与序列化：roll 绝对坐标、变量声明/赋值、表达式、if/for 扩展 |
| `lib/services/macro_expression_parser.dart` | 新增：表达式 AST 与递归下降解析器 |
| `lib/services/macro_syntax_highlighter.dart` | 新增关键字高亮：int、double、point、color |
| `test/services/macro_program_parser_test.dart` | 扩展：roll、变量、if/for round-trip 测试 |
| `test/services/macro_expression_parser_test.dart` | 新增：表达式解析/序列化测试 |
| `android/app/src/main/kotlin/com/example/isolation/Variable.kt` | 新增：变量密封类 |
| `android/app/src/main/kotlin/com/example/isolation/ExpressionEvaluator.kt` | 新增：表达式 AST 求值器 |
| `android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt` | 扩展：roll 绝对坐标、变量、赋值、C 风格 for、if 表达式求值 |
| `android/app/src/test/java/com/example/isolation/ExpressionEvaluatorTest.kt` | 新增：表达式求值单元测试 |
| `lib/screens/program_macro_screen.dart` | 更新模板示例（可选） |
| `lib/screens/instruction_manual_screen.dart` | 更新语法说明（可选） |

---

## Task 1: Dart 表达式 AST 与解析器

**Files:**
- Create: `lib/services/macro_expression_parser.dart`
- Test: `test/services/macro_expression_parser_test.dart`

### Step 1: 定义 AST 节点

创建 `lib/services/macro_expression_parser.dart`，写入 AST 定义与解析器骨架：

```dart
sealed class Expr {
  Map<String, dynamic> toJson();
}

class LiteralExpr extends Expr {
  final dynamic value;
  LiteralExpr(this.value);
  @override
  Map<String, dynamic> toJson() => {'op': 'literal', 'value': value};
}

class VarExpr extends Expr {
  final String name;
  VarExpr(this.name);
  @override
  Map<String, dynamic> toJson() => {'op': 'var', 'name': name};
}

class UnaryExpr extends Expr {
  final String operator;
  final Expr right;
  UnaryExpr(this.operator, this.right);
  @override
  Map<String, dynamic> toJson() => {
        'op': 'unary',
        'operator': operator,
        'right': right.toJson(),
      };
}

class BinaryExpr extends Expr {
  final String operator;
  final Expr left;
  final Expr right;
  BinaryExpr(this.operator, this.left, this.right);
  @override
  Map<String, dynamic> toJson() => {
        'op': 'binary',
        'operator': operator,
        'left': left.toJson(),
        'right': right.toJson(),
      };
}
```

### Step 2: 编写失败测试

创建 `test/services/macro_expression_parser_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:isolation/services/macro_expression_parser.dart';

void main() {
  test('parses simple comparison', () {
    final expr = ExpressionParser.parse('score + 1 > 5');
    expect(expr.toJson(), {
      'op': 'binary',
      'operator': '>',
      'left': {
        'op': 'binary',
        'operator': '+',
        'left': {'op': 'var', 'name': 'score'},
        'right': {'op': 'literal', 'value': 1},
      },
      'right': {'op': 'literal', 'value': 5},
    });
  });
}
```

Run: `flutter test test/services/macro_expression_parser_test.dart`

Expected: FAIL — `ExpressionParser` not found.

### Step 3: 实现 ExpressionParser

在 `lib/services/macro_expression_parser.dart` 中实现递归下降解析器：

```dart
class ExpressionParser {
  static Expr parse(String source) {
    final tokens = _tokenize(source);
    final parser = _Parser(tokens);
    return parser.parseExpression();
  }

  static List<String> _tokenize(String source) {
    final regExp = RegExp(
      r'\b\d+\.?\d*\b|' // number
      r'0x[0-9a-fA-F]+|' // hex
      r'[a-zA-Z_][a-zA-Z0-9_]*|' // identifier
      r'&&|\|\||>=|<=|==|!=|[+\-*/()<>!]',
    );
    return regExp.allMatches(source.replaceAll(' ', ''))
        .map((m) => m.group(0)!)
        .toList();
  }
}

class _Parser {
  final List<String> tokens;
  int pos = 0;
  _Parser(this.tokens);

  Expr parseExpression() => _parseOr();

  Expr _parseOr() {
    var left = _parseAnd();
    while (_match('||')) {
      left = BinaryExpr('||', left, _parseAnd());
    }
    return left;
  }

  Expr _parseAnd() {
    var left = _parseEquality();
    while (_match('&&')) {
      left = BinaryExpr('&&', left, _parseEquality());
    }
    return left;
  }

  Expr _parseEquality() {
    var left = _parseRelational();
    while (true) {
      if (_match('==')) {
        left = BinaryExpr('==', left, _parseRelational());
      } else if (_match('!=')) {
        left = BinaryExpr('!=', left, _parseRelational());
      } else {
        break;
      }
    }
    return left;
  }

  Expr _parseRelational() {
    var left = _parseAdditive();
    while (true) {
      if (_match('>=')) {
        left = BinaryExpr('>=', left, _parseAdditive());
      } else if (_match('<=')) {
        left = BinaryExpr('<=', left, _parseAdditive());
      } else if (_match('>')) {
        left = BinaryExpr('>', left, _parseAdditive());
      } else if (_match('<')) {
        left = BinaryExpr('<', left, _parseAdditive());
      } else {
        break;
      }
    }
    return left;
  }

  Expr _parseAdditive() {
    var left = _parseMultiplicative();
    while (true) {
      if (_match('+')) {
        left = BinaryExpr('+', left, _parseMultiplicative());
      } else if (_match('-')) {
        left = BinaryExpr('-', left, _parseMultiplicative());
      } else {
        break;
      }
    }
    return left;
  }

  Expr _parseMultiplicative() {
    var left = _parseUnary();
    while (true) {
      if (_match('*')) {
        left = BinaryExpr('*', left, _parseUnary());
      } else if (_match('/')) {
        left = BinaryExpr('/', left, _parseUnary());
      } else {
        break;
      }
    }
    return left;
  }

  Expr _parseUnary() {
    if (_match('!')) return UnaryExpr('!', _parseUnary());
    if (_match('-')) return UnaryExpr('-', _parseUnary());
    return _parsePrimary();
  }

  Expr _parsePrimary() {
    if (_match('(')) {
      final expr = parseExpression();
      _expect(')');
      return expr;
    }
    final token = _current;
    if (token == null) throw Exception('Unexpected end of expression');
    if (_isNumber(token)) {
      _advance();
      return LiteralExpr(_parseNumber(token));
    }
    if (_isIdentifier(token)) {
      _advance();
      return VarExpr(token);
    }
    throw Exception('Unexpected token: $token');
  }

  bool _match(String expected) {
    if (_current == expected) {
      _advance();
      return true;
    }
    return false;
  }

  void _expect(String expected) {
    if (_current != expected) {
      throw Exception('Expected $expected but found $_current');
    }
    _advance();
  }

  String? get _current => pos < tokens.length ? tokens[pos] : null;
  void _advance() => pos++;

  static bool _isNumber(String s) => RegExp(r'^\d+\.?\d*$').hasMatch(s);
  static bool _isIdentifier(String s) => RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(s);
  static dynamic _parseNumber(String s) => s.contains('.') ? double.parse(s) : int.parse(s);
}
```

### Step 4: 实现表达式序列化

在同一文件中添加：

```dart
String serializeExpr(Expr expr) {
  final json = expr.toJson();
  return _serializeJson(json);
}

String _serializeJson(Map<String, dynamic> json) {
  switch (json['op']) {
    case 'literal':
      return json['value'].toString();
    case 'var':
      return json['name'] as String;
    case 'unary':
      return '(${json['operator']}${_serializeJson(json['right'] as Map<String, dynamic>)})';
    case 'binary':
      final left = _serializeJson(json['left'] as Map<String, dynamic>);
      final right = _serializeJson(json['right'] as Map<String, dynamic>);
      return '($left ${json['operator']} $right)';
    default:
      return '';
  }
}
```

### Step 5: 运行测试

Run: `flutter test test/services/macro_expression_parser_test.dart`

Expected: PASS.

Add more tests for `&&`, `||`, parentheses, hex literals, variables.

### Step 6: Commit

```bash
git add lib/services/macro_expression_parser.dart test/services/macro_expression_parser_test.dart
git commit -m "feat: add expression parser with AST and serializer"
```

---

## Task 2: Dart 解析/序列化 roll 绝对坐标

**Files:**
- Modify: `lib/services/macro_program_parser.dart`
- Test: `test/services/macro_program_parser_test.dart`

### Step 1: 编写失败测试

在 `test/services/macro_program_parser_test.dart` 添加：

```dart
test('roll absolute coordinates round-trip', () {
  const code = 'roll(100, 200, 100, 800, 500)';
  final parsed = MacroProgramParser.parse(code);
  expect(parsed.length, 1);
  expect(parsed.first['type'], 'roll');
  expect(parsed.first['start'], {'x': 100, 'y': 200});
  expect(parsed.first['end'], {'x': 100, 'y': 800});
  expect(parsed.first['duration'], 500);
  final serialized = MacroProgramParser.serialize(parsed);
  expect(serialized.trim(), code);
});
```

Run: `flutter test test/services/macro_program_parser_test.dart`

Expected: FAIL — 5 参数 roll 未被识别。

### Step 2: 修改 `_normalizeStep` 中的 roll 处理

在 `lib/services/macro_program_parser.dart` 中找到 `case 'roll'`：

```dart
case 'roll':
  final positional = <dynamic>[];
  for (int i = 0;; i++) {
    final key = 'positional\$$i';
    if (!step.containsKey(key)) break;
    positional.add(step[key]);
    step.remove(key);
  }
  if (positional.length == 3) {
    step['dx'] = positional[0];
    step['dy'] = positional[1];
    step['duration'] = positional[2];
  } else if (positional.length == 5) {
    step['start'] = {'x': positional[0], 'y': positional[1]};
    step['end'] = {'x': positional[2], 'y': positional[3]};
    step['duration'] = positional[4];
  }
  break;
```

### Step 3: 修改 `_serializeStep` 中的 roll 序列化

替换 `case 'roll'`：

```dart
case 'roll':
  final start = step['start'] as Map?;
  final end = step['end'] as Map?;
  if (start != null && end != null) {
    buffer.writeln(
      '$indent roll(${start['x']}, ${start['y']}, ${end['x']}, ${end['y']}, ${step['duration']})',
    );
  } else {
    buffer.writeln(
      '$indent roll(${step['dx']}, ${step['dy']}, ${step['duration']})',
    );
  }
  break;
```

### Step 4: 运行测试

Run: `flutter test test/services/macro_program_parser_test.dart`

Expected: PASS.

### Step 5: Commit

```bash
git add lib/services/macro_program_parser.dart test/services/macro_program_parser_test.dart
git commit -m "feat: support absolute coordinates in roll"
```

---

## Task 3: Dart 变量声明与赋值解析/序列化

**Files:**
- Modify: `lib/services/macro_program_parser.dart`
- Modify: `lib/services/macro_expression_parser.dart`（可能需要导出 `parseValue`）
- Test: `test/services/macro_program_parser_test.dart`

### Step 1: 识别变量声明与赋值语句

当前 `_parseStatement` 使用正则 `^(

+)` 只匹配函数调用。需要新增两个正则：

```dart
// 变量声明：int score = 0
final varDeclMatch = RegExp(r'^(int|double|point|color)\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)$')
    .firstMatch(line.text);
if (varDeclMatch != null) {
  final varType = varDeclMatch.group(1)!;
  final name = varDeclMatch.group(2)!;
  final valueStr = varDeclMatch.group(3)!;
  cursor++;
  return {
    'type': 'var',
    'varType': varType,
    'name': name,
    'value': _parseVariableValue(varType, valueStr),
  };
}

// 赋值：score = score + 1
final assignMatch = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)$')
    .firstMatch(line.text);
if (assignMatch != null) {
  final name = assignMatch.group(1)!;
  final valueStr = assignMatch.group(2)!;
  cursor++;
  return {
    'type': 'assign',
    'name': name,
    'value': ExpressionParser.parse(valueStr).toJson(),
  };
}
```

### Step 2: 解析 point/color 构造

在 `lib/services/macro_expression_parser.dart` 中添加辅助函数：

```dart
class ExpressionParser {
  // ... existing parse method

  static dynamic parseVariableValue(String varType, String source) {
    source = source.trim();
    if (varType == 'point') {
      final match = RegExp(r'^point\s*\(([^)]+)\)$').firstMatch(source);
      if (match == null) throw Exception('Invalid point value: $source');
      final parts = match.group(1)!.split(',').map((s) => parse(s.trim()).toJson()).toList();
      return {'x': parts[0], 'y': parts[1]};
    }
    if (varType == 'color') {
      final match = RegExp(r'^color\s*\(([^)]+)\)$').firstMatch(source);
      if (match == null) throw Exception('Invalid color value: $source');
      return parse(match.group(1)!.trim()).toJson();
    }
    // int / double
    return parse(source).toJson();
  }
}
```

### Step 3: 修改 `_parseValue` 支持变量引用

在 `macro_program_parser.dart` 中：

```dart
dynamic _parseValue(String s) {
  s = s.trim();
  if (s.isEmpty) return null;
  // ... existing string/list/hex/int/double/bool handling
  if (RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(s)) {
    return {'op': 'var', 'name': s};
  }
  return s;
}
```

### Step 4: 序列化 var/assign

在 `_serializeStep` 中添加：

```dart
case 'var':
  final varType = step['varType'];
  final name = step['name'];
  final value = _serializeExprValue(step['value']);
  buffer.writeln('$indent $varType $name = $value');
  break;
case 'assign':
  buffer.writeln('$indent ${step['name']} = ${_serializeExprValue(step['value'])}');
  break;
```

并添加辅助函数：

```dart
String _serializeExprValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    final op = value['op'] as String?;
    if (op == 'literal') return value['value'].toString();
    if (op == 'var') return value['name'] as String;
    if (op == 'binary') {
      final left = _serializeExprValue(value['left']);
      final right = _serializeExprValue(value['right']);
      return '($left ${value['operator']} $right)';
    }
    if (op == 'unary') {
      return '(${value['operator']}${_serializeExprValue(value['right'])})';
    }
  }
  if (value is Map) {
    // point value: {'x': ..., 'y': ...}
    if (value.containsKey('x') && value.containsKey('y')) {
      return 'point(${_serializeExprValue(value['x'])}, ${_serializeExprValue(value['y'])})';
    }
  }
  return value.toString();
}
```

### Step 5: 测试

添加测试：

```dart
test('variable declaration and assignment round-trip', () {
  const code = '''
int score = 0
score = score + 1
point btn = point(100, 200)
'''.trim();
  final parsed = MacroProgramParser.parse(code);
  expect(parsed.length, 3);
  expect(parsed[0]['type'], 'var');
  expect(parsed[0]['name'], 'score');
  expect(parsed[1]['type'], 'assign');
  expect(parsed[2]['varType'], 'point');
  final serialized = MacroProgramParser.serialize(parsed).trim();
  expect(serialized, code);
});
```

Run: `flutter test test/services/macro_program_parser_test.dart`

Expected: PASS.

### Step 6: Commit

```bash
git add lib/services/macro_program_parser.dart lib/services/macro_expression_parser.dart test/services/macro_program_parser_test.dart
git commit -m "feat: parse and serialize variable declarations and assignments"
```

---

## Task 4: Dart if/for 扩展解析/序列化

**Files:**
- Modify: `lib/services/macro_program_parser.dart`
- Test: `test/services/macro_program_parser_test.dart`

### Step 1: if 支持表达式条件

在 `_parseStatement` 处理 `if` 时：

```dart
if (name == 'if') {
  // 若 argsStr 是 find(...) 则保持原有 condition 解析
  final findMatch = RegExp(r'^find\s*\((.*)\)$').firstMatch(argsStr);
  if (findMatch != null) {
    step['condition'] = {
      'type': 'find',
      ..._parseArgs(findMatch.group(1)!),
    };
  } else {
    step['expression'] = ExpressionParser.parse(argsStr).toJson();
  }
}
```

### Step 2: for 支持 C 风格

在 `_normalizeStep` 的 `case 'for'` 中：

```dart
case 'for':
  if (positional.isNotEmpty) {
    final first = positional[0];
    if (first is String && first.contains(';')) {
      final parts = first.split(';').map((s) => s.trim()).toList();
      if (parts.length == 3) {
        step['init'] = _parseCForInit(parts[0]);
        step['condition'] = ExpressionParser.parse(parts[1]).toJson();
        step['update'] = _parseCForUpdate(parts[2]);
      }
    } else {
      step['count'] = first;
    }
  }
  break;
```

添加辅助函数：

```dart
Map<String, dynamic> _parseCForInit(String s) {
  final match = RegExp(r'^(int|double)\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)$')
      .firstMatch(s);
  if (match == null) throw Exception('Invalid for-init: $s');
  return {
    'type': 'var',
    'varType': match.group(1),
    'name': match.group(2),
    'value': ExpressionParser.parse(match.group(3)!).toJson(),
  };
}

Map<String, dynamic> _parseCForUpdate(String s) {
  final match = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)$')
      .firstMatch(s);
  if (match == null) throw Exception('Invalid for-update: $s');
  return {
    'type': 'assign',
    'name': match.group(1),
    'value': ExpressionParser.parse(match.group(2)!).toJson(),
  };
}
```

### Step 3: 序列化 if/for 扩展

在 `_serializeStep` 中修改 `case 'if'`：

```dart
case 'if':
  final expression = step['expression'];
  if (expression != null) {
    buffer.writeln('$indent if (${_serializeExprValue(expression)}) {');
  } else {
    final condition = step['condition'] is Map
        ? Map<String, dynamic>.from(step['condition'] as Map)
        : <String, dynamic>{};
    final condArgStr = _serializeFindArgs(condition);
    buffer.writeln('$indent if(find($condArgStr)) {');
  }
  _serializeChildren(step['then'], indent, buffer);
  final elseBranch = step['else'];
  if (elseBranch is List && elseBranch.isNotEmpty) {
    buffer.writeln('$indent } else {');
    _serializeChildren(elseBranch, indent, buffer);
  }
  buffer.writeln('$indent }');
  break;
```

修改 `case 'for'`：

```dart
case 'for':
  if (step.containsKey('condition')) {
    final init = _serializeExprStep(step['init']);
    final cond = _serializeExprValue(step['condition']);
    final update = _serializeExprStep(step['update']);
    buffer.writeln('$indent for ($init; $cond; $update) {');
  } else {
    buffer.writeln('$indent for(${step['count']}) {');
  }
  _serializeChildren(step['children'], indent, buffer);
  buffer.writeln('$indent }');
  break;
```

添加辅助函数：

```dart
String _serializeExprStep(dynamic step) {
  if (step is! Map<String, dynamic>) return '';
  final type = step['type'];
  if (type == 'var') {
    return '${step['varType']} ${step['name']} = ${_serializeExprValue(step['value'])}';
  }
  if (type == 'assign') {
    return '${step['name']} = ${_serializeExprValue(step['value'])}';
  }
  return '';
}
```

### Step 4: 测试

添加测试：

```dart
test('if with expression condition round-trip', () {
  const code = '''
if (score > 5) {
    click()
}
'''.trim();
  final parsed = MacroProgramParser.parse(code);
  expect(parsed.first['type'], 'if');
  expect(parsed.first.containsKey('expression'), isTrue);
  final serialized = MacroProgramParser.serialize(parsed).trim();
  expect(serialized, code);
});

test('c-style for round-trip', () {
  const code = '''
for (int i = 0; i < 3; i = i + 1) {
    roll(0, 300, 400)
}
'''.trim();
  final parsed = MacroProgramParser.parse(code);
  expect(parsed.first['type'], 'for');
  expect(parsed.first.containsKey('condition'), isTrue);
  final serialized = MacroProgramParser.serialize(parsed).trim();
  expect(serialized, code);
});
```

Run: `flutter test test/services/macro_program_parser_test.dart`

Expected: PASS.

### Step 5: Commit

```bash
git add lib/services/macro_program_parser.dart test/services/macro_program_parser_test.dart
git commit -m "feat: extend if/for with expressions and c-style loops"
```

---

## Task 5: Kotlin Variable 与 ExpressionEvaluator

**Files:**
- Create: `android/app/src/main/kotlin/com/example/isolation/Variable.kt`
- Create: `android/app/src/main/kotlin/com/example/isolation/ExpressionEvaluator.kt`
- Test: `android/app/src/test/java/com/example/isolation/ExpressionEvaluatorTest.kt`

### Step 1: 创建 Variable 密封类

`Variable.kt`：

```kotlin
package com.example.isolation

sealed class Variable {
    data class Number(val value: Double) : Variable()
    data class Point(val x: Int, val y: Int) : Variable()
    data class Color(val value: Int) : Variable()
}
```

### Step 2: 创建 ExpressionEvaluator

`ExpressionEvaluator.kt`：

```kotlin
package com.example.isolation

object ExpressionEvaluator {
    fun evaluate(expr: Map<String, Any>?, variables: Map<String, Variable>): Variable? {
        if (expr == null) return null
        return when (expr["op"] as? String) {
            "literal" -> {
                val value = expr["value"]
                when (value) {
                    is Number -> Variable.Number(value.toDouble())
                    is String -> Variable.Number(value.toDoubleOrNull() ?: 0.0)
                    else -> null
                }
            }
            "var" -> variables[expr["name"] as? String]
            "unary" -> evaluateUnary(expr, variables)
            "binary" -> evaluateBinary(expr, variables)
            else -> null
        }
    }

    private fun evaluateUnary(
        expr: Map<String, Any>,
        variables: Map<String, Variable>
    ): Variable? {
        val op = expr["operator"] as? String ?: return null
        val right = evaluate(expr["right"] as? Map<String, Any>, variables) ?: return null
        if (right !is Variable.Number) return null
        return when (op) {
            "-" -> Variable.Number(-right.value)
            "!" -> Variable.Number(if (right.value == 0.0) 1.0 else 0.0)
            else -> null
        }
    }

    private fun evaluateBinary(
        expr: Map<String, Any>,
        variables: Map<String, Variable>
    ): Variable? {
        val op = expr["operator"] as? String ?: return null
        val left = evaluate(expr["left"] as? Map<String, Any>, variables) ?: return null
        val right = evaluate(expr["right"] as? Map<String, Any>, variables) ?: return null

        if (op in setOf("+", "-", "*", "/")) {
            if (left !is Variable.Number || right !is Variable.Number) return null
            return when (op) {
                "+" -> Variable.Number(left.value + right.value)
                "-" -> Variable.Number(left.value - right.value)
                "*" -> Variable.Number(left.value * right.value)
                "/" -> Variable.Number(if (right.value != 0.0) left.value / right.value else 0.0)
                else -> null
            }
        }

        if (op in setOf(">", "<", ">=", "<=", "==", "!=")) {
            val result = when {
                left is Variable.Number && right is Variable.Number -> compareNumbers(op, left.value, right.value)
                left is Variable.Color && right is Variable.Color -> compareColors(op, left.value, right.value)
                else -> false
            }
            return Variable.Number(if (result) 1.0 else 0.0)
        }

        if (op in setOf("&&", "||")) {
            val l = (left as? Variable.Number)?.value != 0.0
            val r = (right as? Variable.Number)?.value != 0.0
            val result = if (op == "&&") l && r else l || r
            return Variable.Number(if (result) 1.0 else 0.0)
        }

        return null
    }

    private fun compareNumbers(op: String, a: Double, b: Double): Boolean = when (op) {
        ">" -> a > b
        "<" -> a < b
        ">=" -> a >= b
        "<=" -> a <= b
        "==" -> a == b
        "!=" -> a != b
        else -> false
    }

    private fun compareColors(op: String, a: Int, b: Int): Boolean = when (op) {
        "==" -> a == b
        "!=" -> a != b
        else -> false
    }

    fun toBoolean(variable: Variable?): Boolean {
        return (variable as? Variable.Number)?.value != 0.0
    }
}
```

### Step 3: 编写单元测试

`ExpressionEvaluatorTest.kt`：

```kotlin
package com.example.isolation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExpressionEvaluatorTest {
    @Test
    fun arithmeticAndComparison() {
        val expr = mapOf(
            "op" to "binary",
            "operator" to ">",
            "left" to mapOf(
                "op" to "binary",
                "operator" to "+",
                "left" to mapOf("op" to "var", "name" to "score"),
                "right" to mapOf("op" to "literal", "value" to 1)
            ),
            "right" to mapOf("op" to "literal", "value" to 5)
        )
        val vars = mapOf("score" to Variable.Number(3.0))
        val result = ExpressionEvaluator.evaluate(expr, vars)
        assertTrue(ExpressionEvaluator.toBoolean(result))
    }

    @Test
    fun colorEquality() {
        val expr = mapOf(
            "op" to "binary",
            "operator" to "==",
            "left" to mapOf("op" to "var", "name" to "c1"),
            "right" to mapOf("op" to "var", "name" to "c2")
        )
        val vars = mapOf(
            "c1" to Variable.Color(0xFF0000),
            "c2" to Variable.Color(0xFF0000)
        )
        assertTrue(ExpressionEvaluator.toBoolean(ExpressionEvaluator.evaluate(expr, vars)))
    }
}
```

Run: `gradle testDebugUnitTest --tests "com.example.isolation.ExpressionEvaluatorTest"`（若 gradle wrapper 可用）或本地 Android Studio 运行。

Expected: PASS.

### Step 4: Commit

```bash
git add android/app/src/main/kotlin/com/example/isolation/Variable.kt \
  android/app/src/main/kotlin/com/example/isolation/ExpressionEvaluator.kt \
  android/app/src/test/java/com/example/isolation/ExpressionEvaluatorTest.kt
git commit -m "feat: add Variable sealed class and ExpressionEvaluator"
```

---

## Task 6: Kotlin MacroExecutor 扩展

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt`
- Test: 手动验证或 instrumentation 测试

### Step 1: 添加变量表

在 `MacroExecutor` 中添加：

```kotlin
private val variables = mutableMapOf<String, Variable>()
```

### Step 2: 处理 var/assign 步骤

在 `executeStep` 的 when 中添加：

```kotlin
"var" -> executeVarStep(step)
"assign" -> executeAssignStep(step)
```

实现：

```kotlin
private fun executeVarStep(step: Map<String, Any>) {
    val name = step["name"] as? String ?: return
    val varType = step["varType"] as? String ?: return
    val valueExpr = step["value"] as? Map<String, Any>
    val value = ExpressionEvaluator.evaluate(valueExpr, variables) ?: return
    variables[name] = when (varType) {
        "int", "double" -> value
        "point" -> {
            val xExpr = valueExpr?.get("x") as? Map<String, Any>
            val yExpr = valueExpr?.get("y") as? Map<String, Any>
            val x = (ExpressionEvaluator.evaluate(xExpr, variables) as? Variable.Number)?.value?.toInt() ?: 0
            val y = (ExpressionEvaluator.evaluate(yExpr, variables) as? Variable.Number)?.value?.toInt() ?: 0
            Variable.Point(x, y)
        }
        "color" -> {
            val c = (value as? Variable.Number)?.value?.toInt() ?: 0
            Variable.Color(c)
        }
        else -> value
    }
}

private fun executeAssignStep(step: Map<String, Any>) {
    val name = step["name"] as? String ?: return
    val valueExpr = step["value"] as? Map<String, Any>
    val value = ExpressionEvaluator.evaluate(valueExpr, variables) ?: return
    variables[name] = value
}
```

### Step 3: 扩展 roll 支持绝对坐标

修改 `executeRollStep`：

```kotlin
private fun executeRollStep(step: Map<String, Any>) {
    val start = step["start"] as? Map<*, *>
    val end = step["end"] as? Map<*, *>
    val duration = (step["duration"] as? Number)?.toLong() ?: 400L

    if (start != null && end != null) {
        val sx = evaluateCoordinate(start["x"]) ?: return
        val sy = evaluateCoordinate(start["y"]) ?: return
        val ex = evaluateCoordinate(end["x"]) ?: return
        val ey = evaluateCoordinate(end["y"]) ?: return
        dispatchSwipe(sx.toFloat(), sy.toFloat(), ex.toFloat(), ey.toFloat(), duration)
        return
    }

    val dx = evaluateCoordinate(step["dx"]) ?: 0
    val dy = evaluateCoordinate(step["dy"]) ?: 0
    val (cx, cy) = screenCenter()
    dispatchSwipe(cx.toFloat(), cy.toFloat(), (cx + dx).toFloat(), (cy + dy).toFloat(), duration)
}

private fun evaluateCoordinate(value: Any?): Int? {
    return when (value) {
        is Number -> value.toInt()
        is Map<*, *> -> {
            val result = ExpressionEvaluator.evaluate(value as Map<String, Any>, variables)
            (result as? Variable.Number)?.value?.toInt()
        }
        else -> null
    }
}
```

### Step 4: 扩展 click 支持 point 变量

修改 `executeClickStep`：

```kotlin
private fun executeClickStep(step: Map<String, Any>) {
    val x = evaluateCoordinate(step["x"])
    val y = evaluateCoordinate(step["y"])
    if (x != null && y != null) {
        dispatchClick(x, y)
        return
    }
    // 无坐标参数：在 find 块内点击最近命中的坐标
    val coord = foundCoordinates.firstOrNull()
    if (coord != null) {
        dispatchClick(coord.first, coord.second)
    } else {
        postStatus("click: 缺少坐标且不在 find 块内")
    }
}
```

### Step 5: 扩展 if 支持表达式

修改 `executeIfStep`：

```kotlin
private fun executeIfStep(step: Map<String, Any>) {
    val expression = step["expression"] as? Map<String, Any>
    val condition = step["condition"] as? Map<String, Any>
    val then = (step["then"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: emptyList()
    val elseBranch = (step["else"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: emptyList()

    val matched = if (expression != null) {
        val result = ExpressionEvaluator.evaluate(expression, variables)
        ExpressionEvaluator.toBoolean(result)
    } else {
        evaluateConditionWithCoord(condition) != null
    }

    if (matched) {
        val coord = evaluateConditionWithCoord(condition)
        if (coord != null) {
            foundCoordinates.addFirst(coord)
            try {
                executeSteps(then)
            } finally {
                foundCoordinates.removeFirstOrNull()
            }
        } else {
            executeSteps(then)
        }
    } else {
        executeSteps(elseBranch)
    }
}
```

注意：当 `expression` 与 `condition` 同时存在时优先 expression；现有逻辑保持 condition 会压栈坐标。

### Step 6: 扩展 for 支持 C 风格

修改 `executeForStep`：

```kotlin
private fun executeForStep(step: Map<String, Any>) {
    val conditionExpr = step["condition"] as? Map<String, Any>
    if (conditionExpr != null) {
        val init = step["init"] as? Map<String, Any>
        val update = step["update"] as? Map<String, Any>
        val children = (step["children"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: return
        if (init != null) executeVarStep(init)
        while (!stopRequested) {
            val result = ExpressionEvaluator.evaluate(conditionExpr, variables)
            if (!ExpressionEvaluator.toBoolean(result)) break
            executeSteps(children)
            if (update != null) executeAssignStep(update)
        }
        return
    }

    // 原有计数循环
    val count = (step["count"] as? Number)?.toInt() ?: 1
    val children = (step["children"] as? List<*>)?.mapNotNull { it as? Map<String, Any> } ?: return
    for (i in 1..count) {
        if (stopRequested) break
        if (debugMode) postStatus("循环 $i/$count")
        executeSteps(children)
    }
}
```

### Step 7: 在宏结束时清理变量表

在 `execute` 的 finally 中清空变量：

```kotlin
} finally {
    running = false
    activeExecutor = null
    debugMode = false
    variables.clear()
}
```

### Step 8: Commit

```bash
git add android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt \
  android/app/src/main/kotlin/com/example/isolation/ExpressionEvaluator.kt \
  android/app/src/main/kotlin/com/example/isolation/Variable.kt
git commit -m "feat: extend MacroExecutor with variables, expressions, absolute roll and c-style for"
```

---

## Task 7: 语法高亮与文档更新

**Files:**
- Modify: `lib/services/macro_syntax_highlighter.dart`
- Modify: `lib/screens/program_macro_screen.dart`（可选）
- Modify: `lib/screens/instruction_manual_screen.dart`（可选）

### Step 1: 新增关键字

在 `MacroSyntaxHighlighter._keywords` 中添加：

```dart
static const List<String> _keywords = [
  'find', 'if', 'else', 'for', 'while', 'print', 'wait',
  'click', 'roll', 'swipe', 'input', 'back', 'home', 'recent',
  'true', 'false',
  'int', 'double', 'point', 'color', 'var',
];
```

### Step 2: 更新模板示例

在 `program_macro_screen.dart` 的 `_template` 中追加：

```dsl
// 变量与表达式
int score = 0
score = score + 1

point btn = point(100, 200)
click(btn)

for (int i = 0; i < 3; i = i + 1) {
    roll(100, 200, 100, 800, 500)
}

if (score > 0) {
    print("得分大于零")
}
```

### Step 3: Commit

```bash
git add lib/services/macro_syntax_highlighter.dart lib/screens/program_macro_screen.dart
git commit -m "feat: highlight new keywords and update macro template"
```

---

## Task 8: 集成测试与回归验证

### Step 1: Dart 全量测试

Run: `flutter test`

Expected: 所有测试 PASS，包括新加的表达式、roll、变量、if/for 测试。

### Step 2: Kotlin 全量测试

Run: `./gradlew testDebugUnitTest`（本地有 Android SDK 时）

Expected: `ColorParserTest` 与 `ExpressionEvaluatorTest` PASS。

### Step 3: 手动构建 APK

Run: `flutter build apk --release`

Expected: 构建成功，输出 `build/app/outputs/flutter-apk/app-release.apk`。

### Step 4: Commit 任何修复

若测试中发现问题，按需要修复并提交。

---

## Spec 覆盖检查

| Spec 章节 | 对应 Task |
|-----------|----------|
| 1. roll 绝对坐标 | Task 2, Task 6 Step 3 |
| 2. 变量系统 | Task 3, Task 5, Task 6 Step 2 |
| 3. 表达式 | Task 1, Task 5, Task 6 Step 2/5 |
| 4. if 扩展 | Task 4, Task 6 Step 5 |
| 5. for 扩展 | Task 4, Task 6 Step 6 |
| 6. 语法高亮 | Task 7 |
| 7. 测试计划 | Task 1, 2, 3, 4, 5, 8 |

无占位符，所有步骤均包含具体代码与命令。
