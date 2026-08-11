/// Isolation 宏 DSL 解析与序列化（v2）。
///
/// 采用“一个命令只做一件事”的设计：
/// - 查找：findText / findColor / findImage
/// - 等待命中：waitForText / waitForColor / waitForImage
/// - 颜色：colorAt / ifColorAt
/// - 条件：ifText / ifColor / ifImage / if
/// - 循环：for / loop
/// - 动作：click / swipe / input / wait / print / back / home / recents / launch
/// - 变量：let
///
/// 录制产生的 clickNode / clickPoint / swipe 等旧 step 仍会在 convertLegacySteps
/// 中转换为新 DSL 写法，但用户编写的旧 `find(...)` 语法不再兼容。
import 'macro_expression_parser.dart';

class MacroParseError implements Exception {
  final String message;
  final int line;
  MacroParseError(this.message, this.line);

  @override
  String toString() => '解析错误 (第 $line 行): $message';
}

class MacroProgramParser {
  /// 将 DSL 源码解析为步骤列表。
  static List<Map<String, dynamic>> parse(String source) {
    try {
      final lines = _preprocess(source);
      final parser = _BlockParser(lines);
      final steps = parser.parseBlock(stopOnCloseBrace: false);
      return steps.map(_normalizeStep).toList();
    } on MacroParseError {
      rethrow;
    } catch (e, s) {
      throw MacroParseError('解析失败: $e', 0);
    }
  }

  /// 递归规范化一个 step：把 positional$N 转为命名字段，递归处理 children/then/else。
  static Map<String, dynamic> _normalizeStep(Map<String, dynamic> step) {
    final type = step['type'] as String;
    final positional = <dynamic>[];
    for (final key in step.keys.toList()) {
      if (key.startsWith('positional\$')) {
        positional.add(step[key]);
        step.remove(key);
      }
    }

    void assign(List<String> names) {
      for (int i = 0; i < positional.length && i < names.length; i++) {
        step[names[i]] = positional[i];
      }
    }

    switch (type) {
      case 'click':
        if (positional.length >= 2) {
          step['x'] = positional[0];
          step['y'] = positional[1];
        }
        break;
      case 'swipe':
        if (positional.length == 5) {
          step['start'] = {'x': positional[0], 'y': positional[1]};
          step['end'] = {'x': positional[2], 'y': positional[3]};
          step['duration'] = positional[4];
        } else {
          assign(['dx', 'dy', 'duration']);
        }
        break;
      case 'swipeRel':
        assign(['fromX', 'fromY', 'dx', 'dy', 'duration']);
        break;
      case 'input':
        if (positional.isNotEmpty) step['text'] = positional[0];
        break;
      case 'print':
        if (positional.isNotEmpty) step['message'] = positional[0];
        break;
      case 'launch':
        if (positional.isNotEmpty) step['packageName'] = positional[0];
        break;
      case 'wait':
        if (positional.isNotEmpty) step['duration'] = positional[0];
        break;
      case 'loop':
        if (positional.isNotEmpty) step['name'] = positional[0];
        break;
      case 'breakLoop':
        if (positional.isNotEmpty) step['name'] = positional[0];
        break;
      case 'for':
        if (positional.isNotEmpty) {
          final first = positional[0];
          if (first is String && first.contains(';')) {
            final parts = first.split(';').map((s) => s.trim()).toList();
            if (parts.length != 3) {
              throw MacroParseError(
                  'for 循环需要 3 个分号分隔的部分，例如 for (int i = 0; i < 10; i = i + 1)', 0);
            }
            step['init'] = _parseCForInit(parts[0]);
            step['condition'] = ExpressionParser.parse(parts[1]).toJson();
            step['update'] = _parseCForUpdate(parts[2]);
          } else {
            step['count'] = first;
          }
        }
        break;
      case 'findText':
      case 'waitForText':
      case 'ifText':
        assign(['text']);
        break;
      case 'findColor':
      case 'waitForColor':
      case 'ifColor':
        assign(['color']);
        break;
      case 'findImage':
      case 'waitForImage':
      case 'ifImage':
        assign(['image']);
        break;
      case 'colorAt':
      case 'ifColorAt':
        assign(['x', 'y', 'color', 'tolerance']);
        break;
      case 'cornerRadius':
      case 'size':
        assign(['value']);
        break;
      case 'image':
      case 'audio':
      case 'include':
        assign(['path']);
        break;
      case 'floater':
        assign(['event']);
        break;
    }

    if (step['children'] is List) {
      step['children'] = (step['children'] as List)
          .map((e) => _normalizeStep(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    if (step['then'] is List) {
      step['then'] = (step['then'] as List)
          .map((e) => _normalizeStep(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    if (step['else'] is List) {
      step['else'] = (step['else'] as List)
          .map((e) => _normalizeStep(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    if (step['condition'] is Map) {
      final condMap = Map<String, dynamic>.from(step['condition'] as Map);
      if (condMap.containsKey('type')) {
        step['condition'] = _normalizeStep(condMap);
      }
    }
    return step;
  }

  /// 把步骤列表序列化为 DSL 源码。
  static String serialize(List<Map<String, dynamic>> steps,
      {String indent = ''}) {
    final buffer = StringBuffer();
    for (final step in steps) {
      _serializeStep(step, indent, buffer);
    }
    return buffer.toString();
  }

  /// 单步序列化为代码字符串。
  static String stepToCode(Map<String, dynamic> step) {
    final buffer = StringBuffer();
    _serializeStep(step, '', buffer);
    return buffer.toString().trimRight();
  }

  /// 把录制产生的旧 step 列表转成 DSL 代码。
  static String convertRecordedStepsToCode(
      List<Map<String, dynamic>> steps) {
    return serialize(steps);
  }

  /// 把录制产生的旧格式 step 列表转换成新的指令格式 step 列表。
  ///
  /// 支持：clickNode / clickPoint / swipe → findText+click / click(x,y) / swipe。
  /// 智能识别捕获的 color 字段会转换为 ifColorAt(...) 条件块。
  static List<Map<String, dynamic>> convertLegacySteps(
      List<Map<String, dynamic>> steps) {
    return steps.map(_convertLegacyStep).whereType<Map<String, dynamic>>().toList();
  }

  static Map<String, dynamic>? _convertLegacyStep(
      Map<String, dynamic> step) {
    final type = step['type'] as String?;
    final color = step['color'] as Map<String, dynamic>?;
    final delay = step['delay'];

    Map<String, dynamic>? result;
    switch (type) {
      case 'clickNode':
        final target = step['target'] as Map<String, dynamic>?;
        if (target != null) {
          final text = target['text'] as String?;
          final contentDescription = target['contentDescription'] as String?;
          final resourceId = target['resourceId'] as String?;

          if (text != null && text.isNotEmpty) {
            result = {
              'type': 'findText',
              'text': text,
              if (delay != null) 'delay': delay,
              'children': [
                {'type': 'click'},
              ],
            };
            break;
          }

          if (contentDescription != null && contentDescription.isNotEmpty) {
            result = {
              'type': 'findText',
              'text': contentDescription,
              if (delay != null) 'delay': delay,
              'children': [
                {'type': 'click'},
              ],
            };
            break;
          }

          if (resourceId != null && resourceId.isNotEmpty) {
            result = {
              'type': 'findText',
              'text': resourceId,
              if (delay != null) 'delay': delay,
              'children': [
                {'type': 'click'},
              ],
            };
            break;
          }

          final bounds = target['bounds'] as List?;
          if (bounds != null && bounds.length == 4) {
            final cx = ((bounds[0] as num) + (bounds[2] as num)) ~/ 2;
            final cy = ((bounds[1] as num) + (bounds[3] as num)) ~/ 2;
            result = {
              'type': 'click',
              'x': cx,
              'y': cy,
              if (delay != null) 'delay': delay,
            };
            break;
          }
        }
        result = Map<String, dynamic>.from(step);
        break;

      case 'clickPoint':
        final point = step['point'] as Map<String, dynamic>?;
        if (point != null) {
          result = {
            'type': 'click',
            'x': point['x'],
            'y': point['y'],
            if (delay != null) 'delay': delay,
          };
        } else {
          result = Map<String, dynamic>.from(step);
        }
        break;

      case 'swipe':
        final start = step['start'] as Map<String, dynamic>?;
        final end = step['end'] as Map<String, dynamic>?;
        final duration = step['duration'] ?? 300;
        if (start != null && end != null) {
          result = {
            'type': 'swipe',
            'start': start,
            'end': end,
            'duration': duration,
            if (delay != null) 'delay': delay,
          };
        } else {
          result = Map<String, dynamic>.from(step);
        }
        break;

      default:
        result = Map<String, dynamic>.from(step);
    }

    if (color != null && result != null) {
      result.remove('color');
      final cx = (color['x'] as num).toInt();
      final cy = (color['y'] as num).toInt();
      final c = (color['color'] as num).toInt();
      return {
        'type': 'ifColorAt',
        'x': cx,
        'y': cy,
        'color': c,
        'tolerance': 30,
        'then': [result],
      };
    }
    return result;
  }

  // ---------- 内部实现 ----------

  static Map<String, dynamic> _parseCForInit(String s) {
    final match = RegExp(
            r'^(int|double)\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.*)$')
        .firstMatch(s.trim());
    if (match == null) {
      throw MacroParseError('无法解析 for 初始化语句: $s', 0);
    }
    return {
      'type': 'var',
      'varType': match.group(1)!,
      'name': match.group(2)!,
      'value': ExpressionParser.parse(match.group(3)!.trim()).toJson(),
    };
  }

  static Map<String, dynamic> _parseCForUpdate(String s) {
    final match = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.*)$')
        .firstMatch(s.trim());
    if (match == null) {
      throw MacroParseError('无法解析 for 更新语句: $s', 0);
    }
    return {
      'type': 'assign',
      'name': match.group(1)!,
      'value': ExpressionParser.parse(match.group(2)!.trim()).toJson(),
    };
  }

  static List<_Line> _preprocess(String source) {
    final result = <_Line>[];
    final rawLines = source.split('\n');
    for (int idx = 0; idx < rawLines.length; idx++) {
      var line = rawLines[idx];
      if (line.trim().startsWith('#include')) {
        result.add(_Line(idx + 1, line.trim()));
        continue;
      }
      final commentIdx = _findCommentStart(line);
      if (commentIdx >= 0) {
        final commentText = line.substring(commentIdx).trim();
        // 保留注释，作为独立行以便反编译时恢复
        result.add(_Line(idx + 1, commentText));
        line = line.substring(0, commentIdx);
      }
      line = line.trim();
      if (line.isEmpty) continue;
      result.add(_Line(idx + 1, line));
    }
    return result;
  }

  static int _findCommentStart(String line) {
    bool inString = false;
    String? quote;
    for (int i = 0; i < line.length - 1; i++) {
      final c = line[i];
      if (inString) {
        if (c == quote) inString = false;
      } else if (c == '"' || c == "'") {
        inString = true;
        quote = c;
      } else if (c == '/' && line[i + 1] == '/') {
        return i;
      }
    }
    return -1;
  }

  static void _serializeStep(
      Map<String, dynamic> step, String indent, StringBuffer buffer) {
    final type = step['type'] as String;
    switch (type) {
      case 'click':
        _serializeClick(step, indent, buffer);
        break;
      case 'swipe':
        _serializeSwipe(step, indent, buffer);
        break;
      case 'swipeRel':
        _serializeSwipeRel(step, indent, buffer);
        break;
      case 'input':
        buffer.writeln('${indent}input(${_serializeArgValue(step['text'])})');
        break;
      case 'print':
        buffer.writeln('${indent}print(${_serializeArgValue(step['message'])})');
        break;
      case 'wait':
        buffer.writeln('${indent}wait(${_serializeArgValue(step['duration'])})');
        break;
      case 'launch':
        final packageName = step['packageName'];
        final timeout = step['timeout'];
        final assignTo = step['assignTo'] as String?;
        final args = <String>[
          _serializeArgValue(packageName),
          if (timeout != null) 'timeout=$timeout',
        ];
        if (assignTo != null) {
          buffer.writeln('${indent}$assignTo = launch(${args.join(', ')})');
        } else {
          buffer.writeln('${indent}launch(${args.join(', ')}) {');
          _serializeChildren(step['children'], indent, buffer);
          buffer.writeln('${indent}}');
        }
        break;
      case 'for':
        if (step['condition'] != null) {
          buffer.writeln(
              '${indent}for (${_serializeExprStep(step['init'])}; ${_serializeExprValue(step['condition'])}; ${_serializeExprStep(step['update'])}) {');
        } else {
          buffer.writeln('${indent}for(${step['count']}) {');
        }
        _serializeChildren(step['children'], indent, buffer);
        buffer.writeln('${indent}}');
        break;
      case 'findText':
      case 'waitForText':
      case 'ifText':
        _serializeFindLike(step, indent, buffer, type, ['text', 'timeout']);
        break;
      case 'findColor':
      case 'waitForColor':
      case 'ifColor':
        _serializeFindLike(step, indent, buffer, type,
            ['color', 'tolerance', 'step', 'region', 'timeout']);
        break;
      case 'findImage':
      case 'waitForImage':
      case 'ifImage':
        _serializeFindLike(step, indent, buffer, type,
            ['image', 'featureCount', 'featurePointThreshold', 'colorTolerance', 'region', 'timeout']);
        break;
      case 'colorAt':
        buffer.writeln(
            '${indent}colorAt(${_serializeExprValue(step['x'])}, ${_serializeExprValue(step['y'])})');
        break;
      case 'ifColorAt':
        _serializeIfColorAt(step, indent, buffer);
        break;
      case 'if':
        if (step['expression'] != null) {
          buffer.writeln(
              '${indent}if (${_serializeExprValue(step['expression'])}) {');
        } else {
          final condition = step['condition'] is Map
              ? Map<String, dynamic>.from(step['condition'] as Map)
              : <String, dynamic>{};
          final condCode = _stepToInlineCode(condition);
          buffer.writeln('${indent}if ($condCode) {');
        }
        _serializeChildren(step['then'], indent, buffer);
        final elseBranch = step['else'];
        if (elseBranch is List && elseBranch.isNotEmpty) {
          buffer.writeln('${indent}} else {');
          _serializeChildren(elseBranch, indent, buffer);
        }
        buffer.writeln('${indent}}');
        break;
      case 'loop':
        final name = step['name'];
        if (name != null) {
          buffer.writeln('${indent}loop(${_serializeArgValue(name)}) {');
        } else {
          buffer.writeln('${indent}loop {');
        }
        _serializeChildren(step['children'], indent, buffer);
        buffer.writeln('${indent}}');
        break;
      case 'breakLoop':
        final name = step['name'];
        if (name != null) {
          buffer.writeln('${indent}breakLoop(${_serializeArgValue(name)})');
        } else {
          buffer.writeln('${indent}breakLoop()');
        }
        break;
      case 'comment':
        buffer.writeln('${indent}// ${step['text']}');
        break;
      case 'let':
        buffer.writeln(
            '${indent}let ${step['name']} = ${_serializeExprValue(step['value'])}');
        break;
      case 'var':
        buffer.writeln(
            '${indent}${step['varType']} ${step['name']} = ${_serializeExprValue(step['value'])}');
        break;
      case 'assign':
        buffer.writeln(
            '${indent}${step['name']} = ${_serializeExprValue(step['value'])}');
        break;
      case 'back':
      case 'home':
      case 'recents':
        buffer.writeln('${indent}$type()');
        break;
      case 'cornerRadius':
      case 'size':
        buffer.writeln('${indent}$type(${_serializeArgValue(step['value'])})');
        break;
      case 'image':
      case 'audio':
        buffer.writeln('${indent}$type(${_serializeArgValue(step['path'])})');
        break;
      case 'include':
        buffer.writeln('${indent}#include <${step['displayName']}>');
        break;
      case 'floater':
        buffer.writeln('${indent}$type(${_serializeArgValue(step['event'])}) {');
        _serializeChildren(step['children'], indent, buffer);
        if (step['else'] is List) {
          buffer.writeln('${indent}} else {');
          _serializeChildren(step['else'], indent, buffer);
        }
        buffer.writeln('${indent}}');
        break;
      default:
        buffer.writeln('${indent}// 未知指令: $type');
    }
  }

  static void _serializeFindLike(
      Map<String, dynamic> step,
      String indent,
      StringBuffer buffer,
      String type,
      List<String> argNames) {
    String serializeArg(String name, dynamic value) {
      if (name == 'color') {
        final c = (value as num).toInt();
        return '0x${c.toRadixString(16).padLeft(6, '0').toUpperCase()}';
      }
      if (name == 'region' && value is List) {
        return 'region=[${value.join(', ')}]';
      }
      if (value is String) return _quoteString(value);
      return value.toString();
    }

    final primaryName = argNames.isNotEmpty ? argNames.first : null;
    final primaryValue = primaryName != null ? step[primaryName] : null;
    final pairs = <String>[];
    for (final name in argNames.skip(primaryName != null ? 1 : 0)) {
      final value = step[name];
      if (value == null) continue;
      pairs.add('$name=${serializeArg(name, value)}');
    }

    final args = <String>[
      if (primaryValue != null) serializeArg(primaryName!, primaryValue),
      ...pairs,
    ];

    final assignTo = step['assignTo'] as String?;
    final children = step['children'] as List?;
    final then = step['then'] as List?;
    final elseBranch = step['else'] as List?;

    if (assignTo != null) {
      buffer.writeln('${indent}$assignTo = $type(${args.join(', ')})');
      return;
    }

    if (then != null || elseBranch != null) {
      // ifText / ifColor / ifImage
      buffer.writeln('${indent}$type(${args.join(', ')}) {');
      _serializeChildren(then, indent, buffer);
      if (elseBranch is List && elseBranch.isNotEmpty) {
        buffer.writeln('${indent}} else {');
        _serializeChildren(elseBranch, indent, buffer);
      }
      buffer.writeln('${indent}}');
      return;
    }

    buffer.writeln('${indent}$type(${args.join(', ')}) {');
    _serializeChildren(children, indent, buffer);
    buffer.writeln('${indent}}');
  }

  static void _serializeIfColorAt(
      Map<String, dynamic> step, String indent, StringBuffer buffer) {
    final x = _serializeExprValue(step['x']);
    final y = _serializeExprValue(step['y']);
    final color = (step['color'] as num).toInt();
    final colorStr = '0x${color.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    final tolerance = step['tolerance'];
    final args = <String>[x, y, colorStr];
    if (tolerance != null) args.add('tolerance=$tolerance');
    buffer.writeln('${indent}ifColorAt(${args.join(', ')}) {');
    _serializeChildren(step['then'], indent, buffer);
    final elseBranch = step['else'];
    if (elseBranch is List && elseBranch.isNotEmpty) {
      buffer.writeln('${indent}} else {');
      _serializeChildren(elseBranch, indent, buffer);
    }
    buffer.writeln('${indent}}');
  }

  static void _serializeClick(
      Map<String, dynamic> step, String indent, StringBuffer buffer) {
    final x = step['x'];
    final y = step['y'];
    if (x != null && y != null) {
      final sx = _serializeExprValue(x);
      final sy = _serializeExprValue(y);
      buffer.writeln('${indent}click($sx, $sy)');
    } else {
      buffer.writeln('${indent}click()');
    }
  }

  static void _serializeSwipe(
      Map<String, dynamic> step, String indent, StringBuffer buffer) {
    final fromX = step['fromX'];
    final fromY = step['fromY'];
    if (fromX != null && fromY != null) {
      buffer.writeln(
          '${indent}swipe(fromX=${_serializeExprValue(fromX)}, fromY=${_serializeExprValue(fromY)}, dx=${_serializeExprValue(step['dx'])}, dy=${_serializeExprValue(step['dy'])}, duration=${_serializeExprValue(step['duration'])})');
    } else {
      final start = step['start'] as Map?;
      final end = step['end'] as Map?;
      if (start != null && end != null) {
        final sx = _serializeExprValue(start['x']);
        final sy = _serializeExprValue(start['y']);
        final ex = _serializeExprValue(end['x']);
        final ey = _serializeExprValue(end['y']);
        final dur = _serializeExprValue(step['duration']);
        buffer.writeln('${indent}swipe($sx, $sy, $ex, $ey, $dur)');
      } else {
        final dx = _serializeExprValue(step['dx']);
        final dy = _serializeExprValue(step['dy']);
        final dur = _serializeExprValue(step['duration']);
        buffer.writeln('${indent}swipe($dx, $dy, $dur)');
      }
    }
  }

  static void _serializeSwipeRel(
      Map<String, dynamic> step, String indent, StringBuffer buffer) {
    final fromX = _serializeExprValue(step['fromX']);
    final fromY = _serializeExprValue(step['fromY']);
    final dx = _serializeExprValue(step['dx']);
    final dy = _serializeExprValue(step['dy']);
    final dur = _serializeExprValue(step['duration']);
    buffer.writeln('${indent}swipeRel($fromX, $fromY, $dx, $dy, $dur)');
  }

  /// 把 var / assign 步骤 JSON 紧凑序列化为 for 头部子句。
  static String _serializeExprStep(dynamic step) {
    final map = step as Map<String, dynamic>;
    final type = map['type'] as String;
    if (type == 'var') {
      return '${map['varType']} ${map['name']} = ${_serializeExprValue(map['value'])}';
    }
    if (type == 'assign') {
      return '${map['name']} = ${_serializeExprValue(map['value'])}';
    }
    return '';
  }

  /// 把单个参数值序列化为字符串。
  static String _serializeArgValue(dynamic value) {
    if (value is String) return _quoteString(value);
    if (value is num || value is bool) return value.toString();
    return _serializeExprValue(value);
  }

  /// 把表达式 JSON 或 point map 序列化为字符串。
  static String _serializeExprValue(dynamic value) {
    if (value is Map) {
      final op = value['op'] as String?;
      switch (op) {
        case 'literal':
          return value['value'].toString();
        case 'var':
          return value['name'] as String;
        case 'unary':
          return '${value['operator']}${_serializeExprValue(value['right'])}';
        case 'binary':
          final left = _serializeExprValue(value['left']);
          final right = _serializeExprValue(value['right']);
          return '$left ${value['operator']} $right';
      }
      if (value.containsKey('x') && value.containsKey('y')) {
        final x = _serializeExprValue(value['x']);
        final y = _serializeExprValue(value['y']);
        return 'point($x, $y)';
      }
    }
    return value.toString();
  }

  /// 把一个 condition step（如 findText / findColor）序列化为内联字符串，用于 if(...)。
  static String _stepToInlineCode(Map<String, dynamic> step) {
    final type = step['type'] as String;
    switch (type) {
      case 'findText':
        return 'findText(${_quoteValue(step['text'])})';
      case 'findColor':
        final c = (step['color'] as num).toInt();
        return 'findColor(0x${c.toRadixString(16).padLeft(6, '0').toUpperCase()})';
      case 'findImage':
        return 'findImage(${_quoteValue(step['image'])})';
      case 'colorAt':
        return 'colorAt(${_serializeExprValue(step['x'])}, ${_serializeExprValue(step['y'])})';
      case 'launch':
        final packageName = step['packageName'];
        final timeout = step['timeout'];
        final args = <String>[
          _quoteValue(packageName),
          if (timeout != null) 'timeout=$timeout',
        ];
        return 'launch(${args.join(', ')})';
    }
    return '';
  }

  static void _serializeChildren(
      dynamic children, String indent, StringBuffer buffer) {
    if (children == null) return;
    final list = (children as List).cast<Map<String, dynamic>>();
    for (final child in list) {
      _serializeStep(child, '${indent}    ', buffer);
    }
  }

  static String _quoteString(String s) => '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  static String _quoteValue(dynamic v) {
    if (v is String) return _quoteString(v);
    return v.toString();
  }
}

class _Line {
  final int lineNumber;
  final String text;
  _Line(this.lineNumber, this.text);
}

class _BlockParser {
  final List<_Line> lines;
  int cursor = 0;
  _BlockParser(this.lines);

  List<Map<String, dynamic>> parseBlock({required bool stopOnCloseBrace}) {
    final result = <Map<String, dynamic>>[];
    while (cursor < lines.length) {
      final line = lines[cursor];
      final isElseClose = line.text.startsWith('}') && line.text.contains('else');
      if (line.text == '}' || isElseClose) {
        if (stopOnCloseBrace) {
          cursor++;
          return result;
        }
        cursor++;
        continue;
      }
      if (line.text == '{') {
        cursor++;
        continue;
      }
      if (line.text.startsWith('#include')) {
        final match = RegExp(r'^#include\s*<([^>]+)>$').firstMatch(line.text);
        cursor++;
        result.add({
          'type': 'include',
          'displayName': match?.group(1)?.trim() ?? '',
        });
        continue;
      }
      // 保留注释行
      if (line.text.startsWith('//')) {
        cursor++;
        result.add({'type': 'comment', 'text': line.text.substring(2).trim()});
        continue;
      }
      final step = _parseStatement();
      if (step != null) result.add(step);
    }
    return result;
  }

  Map<String, dynamic>? _parseStatement() {
    final line = lines[cursor];
    if (line.text.startsWith('}')) {
      cursor++;
      return null;
    }
    if (line.text == '{') {
      cursor++;
      return null;
    }

    // let 变量声明：let name = ...
    final letMatch = RegExp(r'^let\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.*)$')
        .firstMatch(line.text);
    if (letMatch != null) {
      final name = letMatch.group(1)!;
      final valueSource = letMatch.group(2)!.trim();
      cursor++;
      final callStep = _tryParseCallAssignment(valueSource);
      if (callStep != null) {
        callStep['assignTo'] = name;
        return callStep;
      }
      return {
        'type': 'let',
        'name': name,
        'value': ExpressionParser.parse(valueSource).toJson(),
      };
    }

    // 类型化变量声明：int score = 0 / point btn = point(100, 200)
    final declMatch = RegExp(
            r'^(int|double|point|color)\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.*)$')
        .firstMatch(line.text);
    if (declMatch != null) {
      final varType = declMatch.group(1)!;
      final name = declMatch.group(2)!;
      final valueSource = declMatch.group(3)!.trim();
      cursor++;
      return {
        'type': 'var',
        'varType': varType,
        'name': name,
        'value': ExpressionParser.parseVariableValue(varType, valueSource),
      };
    }

    // 赋值：score = score + 1
    final assignMatch = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.*)$')
        .firstMatch(line.text);
    if (assignMatch != null) {
      final name = assignMatch.group(1)!;
      final valueSource = assignMatch.group(2)!.trim();
      cursor++;
      final callStep = _tryParseCallAssignment(valueSource);
      if (callStep != null) {
        callStep['assignTo'] = name;
        return callStep;
      }
      return {
        'type': 'assign',
        'name': name,
        'value': ExpressionParser.parse(valueSource).toJson(),
      };
    }

    final match = RegExp(r'^(\w+)(?:\s*\((.*)\))?\s*(\{)?\s*$')
        .firstMatch(line.text);
    if (match == null) {
      throw MacroParseError('无法解析语句: ${line.text}', line.lineNumber);
    }
    final name = match.group(1)!;
    final argsStr = (match.group(2) ?? '').trim();
    final hasBraceInline = match.group(3) == '{';
    cursor++;

    final args = _parseArgs(argsStr);
    final step = <String, dynamic>{'type': name, ...args};

    // if / ifText / ifColor / ifImage / ifColorAt 统一处理 condition/else
    if (name == 'if') {
      final conditionCallMatch = RegExp(
              r'^(findText|findColor|findImage|colorAt|launch)\s*\(.*\)\s*$')
          .firstMatch(argsStr);
      if (conditionCallMatch == null) {
        step['expression'] = ExpressionParser.parse(argsStr).toJson();
        step.remove('condition');
      }
    }

    if (name == 'floater') {
      if (hasBraceInline) {
        step['children'] = parseBlock(stopOnCloseBrace: true);
      } else if (cursor < lines.length && lines[cursor].text == '{') {
        cursor++;
        step['children'] = parseBlock(stopOnCloseBrace: true);
      }
      final closeLineIndex = cursor - 1;
      if (closeLineIndex >= 0) {
        final closeLineText = lines[closeLineIndex].text;
        if (closeLineText.startsWith('}') && closeLineText.contains('else')) {
          step['else'] = parseBlock(stopOnCloseBrace: true);
        }
      }
      if (!step.containsKey('else') && cursor < lines.length) {
        final nextLine = lines[cursor];
        if (nextLine.text.startsWith('else')) {
          cursor++;
          if (cursor < lines.length && lines[cursor].text == '{') {
            cursor++;
          }
          step['else'] = parseBlock(stopOnCloseBrace: true);
        }
      }
      return MacroProgramParser._normalizeStep(step);
    }

    if (hasBraceInline) {
      final children = parseBlock(stopOnCloseBrace: true);
      step['children'] = children;
    } else if (cursor < lines.length && lines[cursor].text == '{') {
      cursor++;
      final children = parseBlock(stopOnCloseBrace: true);
      step['children'] = children;
    }

    if (name == 'if' || name.startsWith('if')) {
      final closeLineIndex = cursor - 1;
      if (closeLineIndex >= 0) {
        final closeLineText = lines[closeLineIndex].text;
        if (closeLineText.startsWith('}') && closeLineText.contains('else')) {
          final elseChildren = parseBlock(stopOnCloseBrace: true);
          step['else'] = elseChildren;
        }
      }

      if (!step.containsKey('else') && cursor < lines.length) {
        final nextLine = lines[cursor];
        if (nextLine.text == 'else {' ||
            nextLine.text == 'else' ||
            nextLine.text.startsWith('else ')) {
          cursor++;
          if (cursor < lines.length && lines[cursor].text == '{') {
            cursor++;
          }
          final elseChildren = parseBlock(stopOnCloseBrace: true);
          step['else'] = elseChildren;
        }
      }

      if (step.containsKey('children') && !step.containsKey('then')) {
        step['then'] = step.remove('children');
      }
    }

    return step;
  }

  static final _assignableCommands = {
    'findText',
    'findColor',
    'findImage',
    'waitForText',
    'waitForColor',
    'waitForImage',
    'colorAt',
    'launch',
  };

  Map<String, dynamic>? _tryParseCallAssignment(String valueSource) {
    final callMatch = RegExp(r'^(\w+)\s*\((.*)\)\s*$').firstMatch(valueSource);
    if (callMatch == null) return null;
    final funcName = callMatch.group(1)!;
    if (!_assignableCommands.contains(funcName)) return null;
    final argsStr = callMatch.group(2)!;
    final args = _parseArgs(argsStr);
    return MacroProgramParser._normalizeStep({'type': funcName, ...args});
  }

  Map<String, dynamic> _parseArgs(String argsStr) {
    final result = <String, dynamic>{};
    if (argsStr.isEmpty) return result;

    // 先尝试匹配嵌套函数调用（如 if(findText("领取"))）
    final funcMatch = RegExp(r'^(\w+)\s*\((.*)\)$').firstMatch(argsStr);
    if (funcMatch != null) {
      final funcName = funcMatch.group(1)!;
      final funcArgs = _parseArgs(funcMatch.group(2)!);
      result['condition'] = {'type': funcName, ...funcArgs};
      return result;
    }

    final parts = _splitArgs(argsStr);
    int positionalIndex = 0;
    for (final part in parts) {
      final namedMatch = RegExp(r'^(\w+)\s*=\s*(.*)$').firstMatch(part);
      if (namedMatch != null) {
        final key = namedMatch.group(1)!;
        final value = _parseValue(namedMatch.group(2)!);
        result[key] = value;
      } else {
        result['positional\$$positionalIndex'] = _parseExpressionOrValue(part);
        positionalIndex++;
      }
    }
    return result;
  }

  List<String> _splitArgs(String argsStr) {
    final result = <String>[];
    int depth = 0;
    int start = 0;
    bool inString = false;
    String? quoteChar;
    for (int i = 0; i < argsStr.length; i++) {
      final c = argsStr[i];
      if (inString) {
        if (c == quoteChar) inString = false;
      } else if (c == '"' || c == "'") {
        inString = true;
        quoteChar = c;
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      } else if (c == ',' && depth == 0) {
        result.add(argsStr.substring(start, i).trim());
        start = i + 1;
      }
    }
    if (start < argsStr.length) {
      result.add(argsStr.substring(start).trim());
    }
    return result.where((s) => s.isNotEmpty).toList();
  }

  dynamic _parseValue(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      return s.substring(1, s.length - 1).replaceAll('\\"', '"').replaceAll('\\\\', '\\');
    }
    if (s.startsWith("'") && s.endsWith("'") && s.length >= 2) {
      return s.substring(1, s.length - 1);
    }
    if (s.startsWith('[') && s.endsWith(']') && s.length >= 2) {
      final inner = s.substring(1, s.length - 1);
      final parts = _splitArgs(inner);
      return parts.map(_parseExpressionOrValue).toList();
    }
    if (s.startsWith('(') && s.endsWith(')') && s.length >= 2) {
      final inner = s.substring(1, s.length - 1);
      final parts = _splitArgs(inner);
      if (parts.length == 2) {
        return {
          'x': _parseExpressionOrValue(parts[0]),
          'y': _parseExpressionOrValue(parts[1]),
        };
      }
    }
    if (s.startsWith('0x') || s.startsWith('0X')) {
      final hex = int.tryParse(s.substring(2), radix: 16);
      if (hex != null) return hex;
    }
    if (s.startsWith('#')) {
      final hex = int.tryParse(s.substring(1), radix: 16);
      if (hex != null) return hex;
    }
    final asInt = int.tryParse(s);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(s);
    if (asDouble != null) return asDouble;
    if (s == 'true') return true;
    if (s == 'false') return false;
    if (RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(s)) {
      return {'op': 'var', 'name': s};
    }
    return s;
  }

  bool _looksLikeExpression(String s) {
    if (RegExp(r'[\+\-\*/%<>=!&|]').hasMatch(s)) return true;
    return !RegExp(r'^-?(\d+(\.\d+)?|[a-zA-Z_][a-zA-Z0-9_]*)$').hasMatch(s);
  }

  dynamic _parseExpressionOrValue(String part) {
    final value = _parseValue(part);
    if (value is String && _looksLikeExpression(part)) {
      try {
        return ExpressionParser.parse(part).toJson();
      } catch (_) {}
    }
    return value;
  }
}
