import '../models/floater_program_v2.dart';
import 'floater_dsl_v2_expression_parser.dart';

/// Floater DSL v2 顶层解析器。
///
/// 将 v2 DSL 源码解析为 [FloaterProgramV2]。
class FloaterDslV2Parser {
  static FloaterProgramV2 parse(String source) {
    final lines = _preprocess(source);
    final parser = _BlockParser(lines);
    return parser.parseProgram();
  }

  /// 预处理：删除空行、合并续行（目前不支持 \\ 续行）。
  static List<_Line> _preprocess(String source) {
    final result = <_Line>[];
    final rawLines = source.split('\n');
    for (int i = 0; i < rawLines.length; i++) {
      final text = rawLines[i];
      final trimmed = text.replaceAll('\t', '    ');
      if (trimmed.trim().isEmpty) continue;
      if (trimmed.trim().startsWith('//')) continue;
      result.add(_Line(text: trimmed, originalLine: i + 1));
    }
    return result;
  }
}

class _Line {
  final String text;
  final int originalLine;
  _Line({required this.text, required this.originalLine});
}

class _BlockParser {
  final List<_Line> lines;
  final Set<String> _ballNames = {};
  int _index = 0;

  _BlockParser(this.lines);

  bool get _isAtEnd => _index >= lines.length;

  _Line _peek() => lines[_index];

  _Line _advance() => lines[_index++];

  int _indentOf(String line) {
    var count = 0;
    for (final c in line.codeUnits) {
      if (c == 32) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  String _trimIndent(String line) => line.trimLeft();

  FloaterProgramV2 parseProgram() {
    final variables = <FloaterVariable>[];
    final balls = <FloaterBallV2>[];
    final events = <FloaterEvent>[];
    String pluginId = '';

    while (!_isAtEnd) {
      final line = _peek();
      final trimmed = line.text.trim();

      if (trimmed.startsWith('floater')) {
        pluginId = _parseFloaterHeader(trimmed);
        _advance();
        final block = _parseBlock(parentIndent: _indentOf(line.text));
        for (final item in block) {
          if (item is FloaterVariable) variables.add(item);
          else if (item is FloaterBallV2) balls.add(item);
          else if (item is FloaterEvent) events.add(item);
        }
      } else {
        throw _error('顶层只能出现 floater 声明', line.originalLine);
      }
    }

    return FloaterProgramV2(
      pluginId: pluginId,
      variables: variables,
      balls: balls,
      events: events,
    );
  }

  String _parseFloaterHeader(String line) {
    final reg = RegExp(r'^floater\s+"([^"]+)"\s*\{');
    final match = reg.firstMatch(line);
    if (match == null) {
      throw _error('floater 声明格式错误，应为 floater "id" {', 0);
    }
    return match.group(1)!;
  }

  List<dynamic> _parseBlock({required int parentIndent}) {
    final items = <dynamic>[];

    // 跳过 floater { 这一行本身
    while (!_isAtEnd) {
      final line = _peek();
      final indent = _indentOf(line.text);
      if (indent <= parentIndent) {
        // 块结束
        if (line.text.trim() == '}') {
          _advance();
        }
        break;
      }
      _advance();

      final trimmed = _trimIndent(line.text);

      if (trimmed.startsWith('val ') || trimmed.startsWith('var ')) {
        items.add(_parseVariable(trimmed, line.originalLine));
      } else if (trimmed.startsWith('ball ')) {
        items.add(_parseBall(trimmed, line.originalLine, indent));
      } else if (trimmed.startsWith('on ')) {
        items.add(_parseEvent(trimmed, line.originalLine, indent));
      } else if (trimmed.startsWith('state ')) {
        // 阶段 3 暂不实现
        throw _error('state 语法在阶段 1 尚未支持', line.originalLine);
      } else if (trimmed.startsWith('transition ')) {
        // 阶段 3 暂不实现
        throw _error('transition 语法在阶段 1 尚未支持', line.originalLine);
      } else {
        throw _error('未知顶层语句: $trimmed', line.originalLine);
      }
    }

    return items;
  }

  FloaterVariable _parseVariable(String line, int lineNo) {
    final reg = RegExp(r'^(val|var)\s+(\w+)\s*:\s*(\w+)\s*=\s*(.+)\s*$');
    final match = reg.firstMatch(line);
    if (match == null) {
      throw _error('变量声明格式错误，应为 val/var name: Type = expr', lineNo);
    }
    final mutable = match.group(1) == 'var';
    final name = match.group(2)!;
    final typeName = match.group(3)!;
    final exprStr = match.group(4)!;
    final expr = FloaterExpressionParser.parse(exprStr, ballNames: _ballNames);
    return FloaterVariable(
      name: name,
      type: FloaterType.fromName(typeName),
      value: _inferLiteralValue(expr),
      mutable: mutable,
    );
  }

  FloaterBallV2 _parseBall(String line, int lineNo, int parentIndent) {
    final reg = RegExp(r'^ball\s+(\w+(?:\.\.\d+)?)\s*:\s*(\w+)\s*\{');
    final match = reg.firstMatch(line);
    if (match == null) {
      throw _error('球声明格式错误，应为 ball name: Role { ... }', lineNo);
    }
    final nameSpec = match.group(1)!;
    final role = match.group(2)!;

    // 处理批量声明 sub1..4
    final rangeMatch = RegExp(r'^(\w+)(\.\.(\d+))$').firstMatch(nameSpec);
    if (rangeMatch != null) {
      final end = int.parse(rangeMatch.group(3)!);
      if (end < 1) throw _error('批量声明结束序号必须 >=1', lineNo);
      // 批量声明返回第一个球，外部需要展开。这里为了简化，先不支持批量。
      throw _error('批量声明 (sub1..4) 在阶段 1 暂不实现', lineNo);
    }

    _ballNames.add(nameSpec);

    final properties = <String, FloaterProperty>{};
    final eventHandlers = <String, List<FloaterStatement>>{};

    while (!_isAtEnd) {
      final childLine = _peek();
      final childIndent = _indentOf(childLine.text);
      if (childIndent <= parentIndent) {
        if (childLine.text.trim() == '}') _advance();
        break;
      }
      _advance();
      final childTrimmed = _trimIndent(childLine.text);

      if (childTrimmed.startsWith('on ')) {
        final event = _parseEventInBall(childTrimmed, childLine.originalLine, childIndent);
        eventHandlers[event.event] = event.body;
      } else if (childTrimmed.contains('=')) {
        final prop = _parseProperty(childTrimmed, childLine.originalLine);
        properties[prop.key] = prop.value;
      } else {
        throw _error('球体内未知语句: $childTrimmed', childLine.originalLine);
      }
    }

    return FloaterBallV2(
      name: nameSpec,
      role: role,
      properties: properties,
      eventHandlers: eventHandlers,
    );
  }

  FloaterEvent _parseEvent(String line, int lineNo, int parentIndent) {
    final reg = RegExp(r'^on\s+([\w.]+)\.(\w+)\s*\{');
    final match = reg.firstMatch(line);
    if (match == null) {
      throw _error('事件声明格式错误，应为 on ballName.event { ... }', lineNo);
    }
    final target = match.group(1)!;
    final event = match.group(2)!;
    final body = _parseStatementBlock(parentIndent);
    return FloaterEvent(target: target, event: event, body: body);
  }

  FloaterEvent _parseEventInBall(String line, int lineNo, int parentIndent) {
    final reg = RegExp(r'^on\s+(\w+)\s*\{');
    final match = reg.firstMatch(line);
    if (match == null) {
      throw _error('球内事件格式错误，应为 on event { ... }', lineNo);
    }
    final event = match.group(1)!;
    final body = _parseStatementBlock(parentIndent);
    return FloaterEvent(target: '', event: event, body: body);
  }

  List<FloaterStatement> _parseStatementBlock(int parentIndent) {
    final statements = <FloaterStatement>[];
    while (!_isAtEnd) {
      final line = _peek();
      final indent = _indentOf(line.text);
      if (indent <= parentIndent) {
        if (line.text.trim() == '}') _advance();
        break;
      }
      final stmt = _parseStatementLine(line);
      statements.add(stmt);
    }
    return statements;
  }

  FloaterStatement _parseStatementLine(_Line line) {
    final trimmed = _trimIndent(line.text);
    _advance();

    if (trimmed.startsWith('print ')) {
      final exprStr = trimmed.substring(6).trim();
      return PrintStatement(expression: FloaterExpressionParser.parse(exprStr, ballNames: _ballNames));
    }

    if (trimmed.startsWith('wait ')) {
      final exprStr = trimmed.substring(5).trim();
      return WaitStatement(duration: FloaterExpressionParser.parse(exprStr, ballNames: _ballNames));
    }

    if (trimmed.startsWith('animate ') || trimmed.startsWith('await animate ')) {
      return _parseAnimate(trimmed, line.originalLine);
    }

    if (trimmed.startsWith('if ')) {
      return _parseIf(trimmed, line.originalLine, _indentOf(line.text));
    }

    if (trimmed.startsWith('for ')) {
      return _parseFor(trimmed, line.originalLine, _indentOf(line.text));
    }

    // 赋值语句：name = expr 或 ballName.prop = expr
    final assignReg = RegExp(r'^(\w+(?:\.\w+)*)\s*=\s*(.+)\s*$');
    final match = assignReg.firstMatch(trimmed);
    if (match != null) {
      final left = match.group(1)!;
      final exprStr = match.group(2)!;
      final expr = FloaterExpressionParser.parse(exprStr, ballNames: _ballNames);
      if (left.contains('.')) {
        final parts = left.split('.');
        if (parts.length != 2) {
          throw _error('赋值左侧只支持 varName 或 ballName.prop', line.originalLine);
        }
        return SetPropertyStatement(
          ballName: parts[0],
          property: parts[1],
          value: expr,
        );
      }
      return AssignStatement(target: left, value: expr);
    }

    throw _error('未知语句: $trimmed', line.originalLine);
  }

  FloaterStatement _parseAnimate(String line, int lineNo) {
    final reg = RegExp(r'^(await\s+)?animate\s+(.+?)\s+to\s+(.+?)\s+duration\s+(.+?)(?:\s+easing\s+(\w+))?\s*$');
    final match = reg.firstMatch(line);
    if (match == null) {
      throw _error(
        'animate 格式错误，应为 animate [targets] to destination duration 260ms [easing overshoot]',
        lineNo,
      );
    }
    final await = match.group(1) != null;
    final targetStr = match.group(2)!;
    final destStr = match.group(3)!;
    final durationStr = match.group(4)!;
    final easing = match.group(5) ?? 'linear';
    final targets = _parseAnimateTargets(targetStr);
    if (targets.isEmpty) {
      throw _error('animate 目标不能为空', lineNo);
    }
    final destination = FloaterExpressionParser.parse(destStr, ballNames: _ballNames);
    final duration = FloaterExpressionParser.parse(durationStr, ballNames: _ballNames);
    return AnimateStatement(
      targets: targets,
      destination: destination,
      duration: duration,
      easing: easing,
      await: await,
    );
  }

  List<String> _parseAnimateTargets(String targetStr) {
    final trimmed = targetStr.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      final inner = trimmed.substring(1, trimmed.length - 1);
      return inner.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return [trimmed];
  }

  FloaterStatement _parseIf(String line, int lineNo, int parentIndent) {
    final reg = RegExp(r'^if\s*\((.*?)\)\s*\{');
    final match = reg.firstMatch(line);
    if (match == null) {
      throw _error('if 格式错误，应为 if (expr) { ... }', lineNo);
    }
    final condStr = match.group(1)!;
    final condition = FloaterExpressionParser.parse(condStr, ballNames: _ballNames);
    final thenBody = _parseStatementBlock(parentIndent);

    List<FloaterStatement>? elseBody;
    if (!_isAtEnd) {
      final nextTrimmed = _peek().text.trim();
      if (nextTrimmed == 'else {' || nextTrimmed.startsWith('else ')) {
        _advance();
        elseBody = _parseStatementBlock(parentIndent);
      }
    }

    return IfStatement(condition: condition, thenBody: thenBody, elseBody: elseBody);
  }

  FloaterStatement _parseFor(String line, int lineNo, int parentIndent) {
    final reg = RegExp(r'^for\s+\((\w+)\s+in\s+(.+?)\)\s*\{');
    final match = reg.firstMatch(line);
    if (match == null) {
      throw _error('for 格式错误，应为 for (i in 0..3) { ... }', lineNo);
    }
    final varName = match.group(1)!;
    final rangeStr = match.group(2)!;
    // 简化：只支持 a..b
    final rangeMatch = RegExp(r'^(\d+)\.\.(\d+)$').firstMatch(rangeStr);
    if (rangeMatch == null) {
      throw _error('for 目前只支持整数范围，例如 0..3', lineNo);
    }
    final from = int.parse(rangeMatch.group(1)!);
    final to = int.parse(rangeMatch.group(2)!);
    final body = _parseStatementBlock(parentIndent);
    return ForStatement(
      variable: varName,
      from: LiteralExpression(value: FloaterValue(type: FloaterType.int, value: from)),
      to: LiteralExpression(value: FloaterValue(type: FloaterType.int, value: to)),
      body: body,
    );
  }

  _PropEntry _parseProperty(String line, int lineNo) {
    final reg = RegExp(r'^(\w+)\s*=\s*(.+)\s*$');
    final match = reg.firstMatch(line);
    if (match == null) {
      throw _error('属性格式错误，应为 key = value', lineNo);
    }
    final key = match.group(1)!;
    final exprStr = match.group(2)!;
    final expr = FloaterExpressionParser.parse(exprStr, ballNames: _ballNames);
    final declaredType = _guessPropertyType(key, expr);
    return _PropEntry(
      key,
      FloaterProperty(declaredType: declaredType, expression: expr, line: lineNo),
    );
  }

  /// 根据属性名和表达式猜测声明类型。
  FloaterType _guessPropertyType(String key, FloaterExpression expr) {
    if (key == "size") return FloaterType.size;
    if (key == "position") return FloaterType.point;
    if (key == "radius") return FloaterType.dp;
    if (expr is LiteralExpression) return expr.value.type;
    return FloaterType.unknown;
  }

  /// 从表达式推断字面量值。变量初始化只支持字面量表达式。
  FloaterValue _inferLiteralValue(FloaterExpression expr) {
    if (expr is LiteralExpression) return expr.value;
    if (expr is VarExpression) {
      return FloaterValue(type: FloaterType.unknown, value: expr.name);
    }
    return FloaterValue(type: FloaterType.unknown, value: expr.toJson());
  }

  FloaterParseError _error(String message, int line) {
    return FloaterParseError(message, line);
  }
}

class _PropEntry {
  final String key;
  final FloaterProperty value;
  _PropEntry(this.key, this.value);
}
