/// 可视化编程宏的 DSL 解析与序列化。
///
/// 支持指令：
/// - `click(x, y)` / `click(text="签到")` / `click(resourceId="...")`
/// - `roll(dx, dy, duration)`
/// - `print("text")`
/// - `wait(ms)`
/// - `for(n) { ... }`
/// - `find(text="x") { ... }`
/// - `if(find(text="x")) { ... } else { ... }`
/// - `back()` / `home()` / `recents()`
///
/// 也兼容录制产生的 `clickNode` / `clickPoint` / `swipe` 等旧类型，
/// 序列化时自动转为新的 DSL 写法。
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
    final lines = _preprocess(source);
    final parser = _BlockParser(lines);
    final steps = parser.parseBlock(stopOnCloseBrace: false);
    return steps.map(_normalizeStep).toList();
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
      case 'roll':
        assign(['dx', 'dy', 'duration']);
        break;
      case 'print':
        if (positional.isNotEmpty) step['message'] = positional[0].toString();
        break;
      case 'wait':
        if (positional.isNotEmpty) step['duration'] = positional[0];
        break;
      case 'for':
        if (positional.isNotEmpty) step['count'] = positional[0];
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
      step['condition'] =
          _normalizeStep(Map<String, dynamic>.from(step['condition'] as Map));
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

  // ---------- 内部实现 ----------

  static List<_Line> _preprocess(String source) {
    final result = <_Line>[];
    final rawLines = source.split('\n');
    for (int idx = 0; idx < rawLines.length; idx++) {
      var line = rawLines[idx];
      // Strip // comments (but only when not inside a string - 简化处理)
      final commentIdx = _findCommentStart(line);
      if (commentIdx >= 0) {
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
      case 'roll':
        buffer.writeln(
            '$indent roll(${step['dx']}, ${step['dy']}, ${step['duration']})');
        break;
      case 'print':
        buffer.writeln(
            '$indent print(${_quoteString(step['message'].toString())})');
        break;
      case 'wait':
        buffer.writeln('$indent wait(${step['duration']})');
        break;
      case 'back':
      case 'home':
      case 'recents':
        buffer.writeln('$indent $type()');
        break;
      case 'for':
        buffer.writeln('$indent for(${step['count']}) {');
        _serializeChildren(step['children'], indent, buffer);
        buffer.writeln('$indent }');
        break;
      case 'find':
        final argStr = _serializeFindArgs(step);
        buffer.writeln('$indent find($argStr) {');
        _serializeChildren(step['children'], indent, buffer);
        buffer.writeln('$indent }');
        break;
      case 'if':
        final condition =
            Map<String, dynamic>.from(step['condition'] as Map);
        final condArgStr = _serializeFindArgs(condition);
        buffer.writeln(
            '$indent if(find($condArgStr)) {');
        _serializeChildren(step['then'], indent, buffer);
        if (step['else'] != null && (step['else'] as List).isNotEmpty) {
          buffer.writeln('$indent } else {');
          _serializeChildren(step['else'], indent, buffer);
        }
        buffer.writeln('$indent }');
        break;
      // 兼容旧类型
      case 'clickNode':
        _serializeLegacyClickNode(step, indent, buffer);
        break;
      case 'clickPoint':
        final point = step['point'] as Map;
        buffer.writeln('$indent click(${point['x']}, ${point['y']})');
        break;
      case 'swipe':
        final start = step['start'] as Map?;
        final end = step['end'] as Map?;
        final duration = step['duration'] ?? 300;
        if (start != null && end != null) {
          final dx = (end['x'] as num) - (start['x'] as num);
          final dy = (end['y'] as num) - (start['y'] as num);
          buffer.writeln('$indent roll($dx, $dy, $duration)');
        }
        break;
      case 'launchApp':
        buffer.writeln(
            '$indent // launchApp(${step['packageName']}) — 请手动转换为对应操作');
        break;
      case 'inputText':
        buffer.writeln(
            '$indent // inputText(${_quoteString(step['text'].toString())}) — 暂不支持');
        break;
      default:
        buffer.writeln('$indent // 未知指令: $type');
    }
  }

  /// click 只支持两种形式：`click(x, y)` 或 `click()`（在 find 块内取栈顶坐标）。
  /// 旧 click(text=...) 形式已废弃，由 _serializeLegacyClickNode 转为 find+click()。
  static void _serializeClick(
      Map<String, dynamic> step, String indent, StringBuffer buffer) {
    final x = step['x'];
    final y = step['y'];
    if (x != null && y != null) {
      buffer.writeln('$indent click($x, $y)');
    } else {
      buffer.writeln('$indent click()');
    }
  }

  /// 把 find 的参数序列化为字符串。支持 color / tolerance / text / resourceId 等。
  static String _serializeFindArgs(Map<String, dynamic> step) {
    final pairs = <String>[];
    final color = step['color'];
    if (color != null) {
      // 颜色统一输出 0xRRGGBB 十六进制
      final c = (color as num).toInt();
      pairs.add('color=0x${c.toRadixString(16).padLeft(6, '0').toUpperCase()}');
    }
    final tolerance = step['tolerance'];
    if (tolerance != null) pairs.add('tolerance=$tolerance');
    final target = step['target'] as Map?;
    if (target != null) {
      target!.forEach((k, v) {
        pairs.add('$k=${_quoteValue(v)}');
      });
    }
    return pairs.join(', ');
  }

  /// 旧 clickNode 序列化为 find(target) { click() } 形式，符合新语义。
  static void _serializeLegacyClickNode(
      Map<String, dynamic> step, String indent, StringBuffer buffer) {
    final target = step['target'] as Map?;
    if (target == null) return;
    final text = target!['text'];
    final cd = target['contentDescription'];
    final resourceId = target['resourceId'];
    final pairs = <String>[];
    if (text != null && (text as String).isNotEmpty) {
      pairs.add('text=${_quoteString(text)}');
    } else if (cd != null && (cd as String).isNotEmpty) {
      pairs.add('contentDescription=${_quoteString(cd)}');
    } else if (resourceId != null && (resourceId as String).isNotEmpty) {
      pairs.add('resourceId=${_quoteString(resourceId)}');
    }
    if (pairs.isNotEmpty) {
      buffer.writeln('$indent find(${pairs.join(', ')}) {');
      buffer.writeln('$indent    click()');
      buffer.writeln('$indent }');
      return;
    }
    // 兜底：用 bounds 中心坐标直接 click(x, y)
    final bounds = target['bounds'] as List?;
    if (bounds != null && bounds.length == 4) {
      final cx = ((bounds[0] as num) + (bounds[2] as num)) ~/ 2;
      final cy = ((bounds[1] as num) + (bounds[3] as num)) ~/ 2;
      buffer.writeln('$indent click($cx, $cy)');
    }
  }

  static void _serializeChildren(
      dynamic children, String indent, StringBuffer buffer) {
    if (children == null) return;
    final list = (children as List).cast<Map<String, dynamic>>();
    for (final child in list) {
      _serializeStep(child, '$indent    ', buffer);
    }
  }

  static String _serializeTarget(dynamic target) {
    if (target == null) return '';
    final map = Map<String, dynamic>.from(target as Map);
    final pairs = <String>[];
    map.forEach((k, v) {
      pairs.add('$k=${_quoteValue(v)}');
    });
    return pairs.join(', ');
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

  /// 解析一个块。当 stopOnCloseBrace=true 时，遇到 `}` 停止。
  List<Map<String, dynamic>> parseBlock({required bool stopOnCloseBrace}) {
    final result = <Map<String, dynamic>>[];
    while (cursor < lines.length) {
      final line = lines[cursor];
      if (line.text == '}') {
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
      final step = _parseStatement();
      if (step != null) result.add(step);
    }
    return result;
  }

  Map<String, dynamic>? _parseStatement() {
    final line = lines[cursor];
    // 形如: name(args) {       或     name(args)        或     name()
    // 也可能是: } else {
    if (line.text.startsWith('}')) {
      // skip
      cursor++;
      return null;
    }
    if (line.text == '{') {
      cursor++;
      return null;
    }

    final match = RegExp(r'^(\w+)\s*\((.*)\)\s*(\{)?\s*$')
        .firstMatch(line.text);
    if (match == null) {
      throw MacroParseError('无法解析语句: ${line.text}', line.lineNumber);
    }
    final name = match.group(1)!;
    final argsStr = match.group(2)!.trim();
    final hasBraceInline = match.group(3) == '{';
    cursor++;

    final args = _parseArgs(argsStr);
    final step = <String, dynamic>{'type': name, ...args};

    // 处理块
    if (hasBraceInline) {
      // 块开始就在当前行
      final children = parseBlock(stopOnCloseBrace: true);
      step['children'] = children;
    } else if (cursor < lines.length && lines[cursor].text == '{') {
      cursor++;
      final children = parseBlock(stopOnCloseBrace: true);
      step['children'] = children;
    }

    // 处理 if 的 else 子句
    if (name == 'if' && cursor < lines.length) {
      final nextLine = lines[cursor];
      if (nextLine.text.startsWith('} else') ||
          nextLine.text == '} else {' ||
          nextLine.text.startsWith('} else{')) {
        cursor++;
        // 检查 { 是否在下一行
        final elseHasBrace = nextLine.text.contains('{');
        if (!elseHasBrace && cursor < lines.length && lines[cursor].text == '{') {
          cursor++;
        }
        final elseChildren = parseBlock(stopOnCloseBrace: true);
        step['else'] = elseChildren;
        // 把 condition 单独提出来，把 children 改名 then
        step['then'] = step.remove('children');
      }
    }

    // 对于 if 语句，规范化字段名
    if (name == 'if') {
      if (step.containsKey('children') && !step.containsKey('then')) {
        step['then'] = step.remove('children');
      }
    }

    return step;
  }

  Map<String, dynamic> _parseArgs(String argsStr) {
    final result = <String, dynamic>{};
    if (argsStr.isEmpty) return result;

    // 1) 先尝试匹配嵌套函数调用（如 find(text="领取")）
    final funcMatch = RegExp(r'^(\w+)\s*\((.*)\)$').firstMatch(argsStr);
    if (funcMatch != null) {
      final funcName = funcMatch.group(1)!;
      final funcArgs = _parseArgs(funcMatch.group(2)!);
      result['condition'] = {'type': funcName, ...funcArgs};
      return result;
    }

    // 2) 解析参数列表
    final parts = _splitArgs(argsStr);
    int positionalIndex = 0;
    for (final part in parts) {
      final namedMatch = RegExp(r'^(\w+)\s*=\s*(.*)$').firstMatch(part);
      if (namedMatch != null) {
        final key = namedMatch.group(1)!;
        final value = _parseValue(namedMatch.group(2)!);
        // 处理 target 子字段：text="..." / resourceId="..." / contentDescription="..."
        if (const ['text', 'resourceId', 'contentDescription', 'className']
            .contains(key)) {
          final target =
              Map<String, dynamic>.from(result['target'] as Map? ?? {});
          target[key] = value;
          result['target'] = target;
        } else {
          result[key] = value;
        }
      } else {
        // 位置参数：交给调用方按 type 解释
        result['positional\$$positionalIndex'] = _parseValue(part);
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
    // 十六进制颜色字面量：0xFF0000 / 0XFF0000 / #FF0000
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
    return s;
  }
}
