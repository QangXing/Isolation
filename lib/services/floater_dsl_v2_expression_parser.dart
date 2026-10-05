import '../models/floater_program_v2.dart';

/// Floater DSL v2 表达式解析器。
///
/// 在 v1 表达式解析器基础上扩展类型字面量：
/// - `56dp`、`100px`
/// - `260ms`、`90deg`
/// - `(100dp, 200dp)` 表示 Point
/// - `48dp x 48dp` 或 `(48dp, 48dp)` 表示 Size
/// - `#ff3366`、`#ff3366aa` 表示 Color
/// - 命名参数 `name: value`
class FloaterExpressionParser {
  static FloaterExpression parse(String source) {
    final tokens = _tokenize(source);
    final parser = _Parser(tokens);
    final expr = parser._parseExpression();
    if (!parser._isAtEnd) {
      throw _error(
        '表达式末尾存在未解析内容: ${parser._peek().lexeme}',
        parser._peek().line,
      );
    }
    return expr;
  }

  static FloaterParseError _error(String message, int line) {
    return FloaterParseError(message, line);
  }

  static List<_Token> _tokenize(String source) {
    final tokens = <_Token>[];
    final chars = source.split('');
    var i = 0;
    var line = 1;

    void skipWhitespace() {
      while (i < chars.length) {
        final c = chars[i];
        if (c == '\n') {
          line++;
          i++;
        } else if (c == ' ' || c == '\t' || c == '\r') {
          i++;
        } else if (c == '/' && i + 1 < chars.length && chars[i + 1] == '/') {
          // 单行注释
          while (i < chars.length && chars[i] != '\n') i++;
        } else {
          break;
        }
      }
    }

    bool isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
    bool isAlpha(String c) {
      final u = c.codeUnitAt(0);
      return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || u == 95;
    }

    while (i < chars.length) {
      skipWhitespace();
      if (i >= chars.length) break;

      final start = i;
      final c = chars[i];

      // 数字 + 单位
      if (isDigit(c) || (c == '.' && i + 1 < chars.length && isDigit(chars[i + 1]))) {
        final buffer = StringBuffer();
        while (i < chars.length && (isDigit(chars[i]) || chars[i] == '.')) {
          buffer.write(chars[i]);
          i++;
        }
        // 读取单位
        final unitBuffer = StringBuffer();
        while (i < chars.length && isAlpha(chars[i])) {
          unitBuffer.write(chars[i]);
          i++;
        }
        final unit = unitBuffer.toString();
        final literal = buffer.toString();
        switch (unit) {
          case 'dp':
            tokens.add(_Token(_TokenType.dpLiteral, '$literal$unit', line, literal));
          case 'px':
            tokens.add(_Token(_TokenType.pxLiteral, '$literal$unit', line, literal));
          case 'ms':
            tokens.add(_Token(_TokenType.durationLiteral, '$literal$unit', line, literal));
          case 'deg':
            tokens.add(_Token(_TokenType.angleLiteral, '$literal$unit', line, literal));
          default:
            if (unit.isNotEmpty) {
              throw _error('未知单位: $unit', line);
            }
            if (literal.contains('.')) {
              tokens.add(_Token(_TokenType.floatLiteral, literal, line, literal));
            } else {
              tokens.add(_Token(_TokenType.intLiteral, literal, line, literal));
            }
        }
        continue;
      }

      // 标识符或关键字
      if (isAlpha(c)) {
        final buffer = StringBuffer();
        while (i < chars.length && (isAlpha(chars[i]) || isDigit(chars[i]))) {
          buffer.write(chars[i]);
          i++;
        }
        final word = buffer.toString();
        switch (word) {
          case 'true':
            tokens.add(_Token(_TokenType.boolLiteral, word, line, true));
          case 'false':
            tokens.add(_Token(_TokenType.boolLiteral, word, line, false));
          default:
            tokens.add(_Token(_TokenType.identifier, word, line));
        }
        continue;
      }

      // 字符串
      if (c == '"' || c == "'") {
        final quote = c;
        i++;
        final buffer = StringBuffer();
        while (i < chars.length && chars[i] != quote) {
          if (chars[i] == '\\' && i + 1 < chars.length) {
            final next = chars[i + 1];
            if (next == 'n') buffer.write('\n');
            else if (next == 't') buffer.write('\t');
            else if (next == 'r') buffer.write('\r');
            else buffer.write(next);
            i += 2;
          } else {
            buffer.write(chars[i]);
            i++;
          }
        }
        if (i >= chars.length) throw _error('字符串未闭合', line);
        i++; // 跳过结束引号
        tokens.add(_Token(_TokenType.stringLiteral, buffer.toString(), line, buffer.toString()));
        continue;
      }

      // 颜色
      if (c == '#') {
        i++;
        final buffer = StringBuffer();
        while (i < chars.length && (isDigit(chars[i]) ||
            (chars[i].codeUnitAt(0) >= 65 && chars[i].codeUnitAt(0) <= 70) ||
            (chars[i].codeUnitAt(0) >= 97 && chars[i].codeUnitAt(0) <= 102))) {
          buffer.write(chars[i]);
          i++;
        }
        final hex = buffer.toString();
        if (hex.length != 6 && hex.length != 8) {
          throw _error('颜色格式错误，应为 #RRGGBB 或 #RRGGBBAA', line);
        }
        tokens.add(_Token(_TokenType.colorLiteral, '#$hex', line, hex));
        continue;
      }

      // 双字符运算符
      if (i + 1 < chars.length) {
        final two = chars[i] + chars[i + 1];
        if (two == '==' || two == '!=' || two == '>=' || two == '<=' || two == '->' || two == '..' || two == '||' || two == '&&') {
          tokens.add(_Token(_twoCharType(two)!, two, line));
          i += 2;
          continue;
        }
      }

      // 单字符
      switch (c) {
        case '(':
          tokens.add(_Token(_TokenType.leftParen, c, line));
        case ')':
          tokens.add(_Token(_TokenType.rightParen, c, line));
        case '{':
          tokens.add(_Token(_TokenType.leftBrace, c, line));
        case '}':
          tokens.add(_Token(_TokenType.rightBrace, c, line));
        case '[':
          tokens.add(_Token(_TokenType.leftBracket, c, line));
        case ']':
          tokens.add(_Token(_TokenType.rightBracket, c, line));
        case ',':
          tokens.add(_Token(_TokenType.comma, c, line));
        case ':':
          tokens.add(_Token(_TokenType.colon, c, line));
        case ';':
          tokens.add(_Token(_TokenType.semicolon, c, line));
        case '=':
          tokens.add(_Token(_TokenType.assign, c, line));
        case '+':
          tokens.add(_Token(_TokenType.plus, c, line));
        case '-':
          tokens.add(_Token(_TokenType.minus, c, line));
        case '*':
          tokens.add(_Token(_TokenType.star, c, line));
        case '/':
          tokens.add(_Token(_TokenType.slash, c, line));
        case '%':
          tokens.add(_Token(_TokenType.percent, c, line));
        case '>':
          tokens.add(_Token(_TokenType.greater, c, line));
        case '<':
          tokens.add(_Token(_TokenType.less, c, line));
        case '!':
          tokens.add(_Token(_TokenType.bang, c, line));
        case '.':
          tokens.add(_Token(_TokenType.dot, c, line));
        default:
          throw _error('未知字符: $c', line);
      }
      i++;
    }

    tokens.add(_Token(_TokenType.eof, '', line));
    return tokens;
  }

  static _TokenType? _twoCharType(String two) {
    switch (two) {
      case '==':
        return _TokenType.equalEqual;
      case '!=':
        return _TokenType.bangEqual;
      case '>=':
        return _TokenType.greaterEqual;
      case '<=':
        return _TokenType.lessEqual;
      case '->':
        return _TokenType.arrow;
      case '..':
        return _TokenType.dotDot;
      case '||':
        return _TokenType.pipePipe;
      case '&&':
        return _TokenType.andAnd;
      default:
        return null;
    }
  }
}

class FloaterParseError implements Exception {
  final String message;
  final int line;
  FloaterParseError(this.message, this.line);
  @override
  String toString() => '解析错误 (第 $line 行): $message';
}

enum _TokenType {
  identifier,
  intLiteral,
  floatLiteral,
  boolLiteral,
  stringLiteral,
  dpLiteral,
  pxLiteral,
  durationLiteral,
  angleLiteral,
  colorLiteral,
  leftParen,
  rightParen,
  leftBrace,
  rightBrace,
  leftBracket,
  rightBracket,
  comma,
  colon,
  semicolon,
  assign,
  plus,
  minus,
  star,
  slash,
  percent,
  greater,
  less,
  bang,
  dot,
  dotDot,
  equalEqual,
  bangEqual,
  greaterEqual,
  lessEqual,
  arrow,
  pipePipe,
  andAnd,
  eof,
}

class _Token {
  final _TokenType type;
  final String lexeme;
  final int line;
  final dynamic literal;

  const _Token(this.type, this.lexeme, this.line, [this.literal]);
}

class _Parser {
  final List<_Token> tokens;
  int _current = 0;

  _Parser(this.tokens);

  bool get _isAtEnd => _peek().type == _TokenType.eof;

  _Token _peek() => tokens[_current];

  _Token _previous() => tokens[_current - 1];

  _Token _advance() {
    if (!_isAtEnd) _current++;
    return _previous();
  }

  bool _check(_TokenType type) => _isAtEnd ? false : _peek().type == type;

  bool _match(List<_TokenType> types) {
    for (final type in types) {
      if (_check(type)) {
        _advance();
        return true;
      }
    }
    return false;
  }

  _Token _consume(_TokenType type, String message) {
    if (_check(type)) return _advance();
    throw FloaterParseError(message, _peek().line);
  }

  FloaterExpression _parseExpression() => _parseOr();

  FloaterExpression _parseOr() {
    var expr = _parseAnd();
    while (_match([_TokenType.pipePipe])) {
      final op = _previous().lexeme;
      final right = _parseAnd();
      expr = BinaryExpression(operator: op, left: expr, right: right);
    }
    return expr;
  }

  FloaterExpression _parseAnd() {
    var expr = _parseEquality();
    while (_match([_TokenType.andAnd])) {
      final op = _previous().lexeme;
      final right = _parseEquality();
      expr = BinaryExpression(operator: op, left: expr, right: right);
    }
    return expr;
  }

  FloaterExpression _parseEquality() {
    var expr = _parseComparison();
    while (_match([_TokenType.equalEqual, _TokenType.bangEqual])) {
      final op = _previous().lexeme;
      final right = _parseComparison();
      expr = BinaryExpression(operator: op, left: expr, right: right);
    }
    return expr;
  }

  FloaterExpression _parseComparison() {
    var expr = _parseTerm();
    while (_match([_TokenType.greater, _TokenType.greaterEqual, _TokenType.less, _TokenType.lessEqual])) {
      final op = _previous().lexeme;
      final right = _parseTerm();
      expr = BinaryExpression(operator: op, left: expr, right: right);
    }
    return expr;
  }

  FloaterExpression _parseTerm() {
    var expr = _parseFactor();
    while (_match([_TokenType.minus, _TokenType.plus])) {
      final op = _previous().lexeme;
      final right = _parseFactor();
      expr = BinaryExpression(operator: op, left: expr, right: right);
    }
    return expr;
  }

  FloaterExpression _parseFactor() {
    var expr = _parseUnary();
    while (_match([_TokenType.slash, _TokenType.star, _TokenType.percent])) {
      final op = _previous().lexeme;
      final right = _parseUnary();
      expr = BinaryExpression(operator: op, left: expr, right: right);
    }
    return expr;
  }

  FloaterExpression _parseUnary() {
    if (_match([_TokenType.bang, _TokenType.minus])) {
      final op = _previous().lexeme;
      final right = _parseUnary();
      return UnaryExpression(operator: op, right: right);
    }
    return _parsePostfix();
  }

  FloaterExpression _parsePostfix() {
    var expr = _parsePrimary();
    while (true) {
      if (_match([_TokenType.dot])) {
        final name = _consume(_TokenType.identifier, '属性访问需要名称').lexeme;
        expr = PropertyExpression(ballName: _extractIdentifierName(expr), property: name);
      } else if (_match([_TokenType.leftParen])) {
        // 函数调用
        final callName = _extractIdentifierName(expr);
        final args = <FloaterExpression>[];
        final namedArgs = <String, FloaterExpression>{};
        if (!_check(_TokenType.rightParen)) {
          do {
            if (_check(_TokenType.identifier) && _lookaheadNamedArg()) {
              final name = _advance().lexeme;
              _consume(_TokenType.colon, '命名参数后需要 :');
              namedArgs[name] = _parseExpression();
            } else {
              args.add(_parseExpression());
            }
          } while (_match([_TokenType.comma]));
        }
        _consume(_TokenType.rightParen, '函数调用缺少右括号');
        expr = CallExpression(name: callName, args: args, namedArgs: namedArgs);
      } else if (_match([_TokenType.leftBracket])) {
        // 索引访问，例如 fan[0]
        final indexExpr = _parseExpression();
        _consume(_TokenType.rightBracket, '索引缺少右括号');
        expr = CallExpression(
          name: 'index',
          args: [expr, indexExpr],
        );
      } else {
        break;
      }
    }
    return expr;
  }

  bool _lookaheadNamedArg() {
    // 当前是 identifier，下一个是 colon
    if (_current + 1 >= tokens.length) return false;
    return tokens[_current + 1].type == _TokenType.colon;
  }

  String _extractIdentifierName(FloaterExpression expr) {
    if (expr is VarExpression) return expr.name;
    if (expr is PropertyExpression) return '${expr.ballName}.${expr.property}';
    throw FloaterParseError('此处需要标识符', _peek().line);
  }

  FloaterExpression _parsePrimary() {
    if (_match([_TokenType.boolLiteral])) {
      final value = _previous().literal as bool;
      return LiteralExpression(
        value: FloaterValue(type: FloaterType.bool, value: value),
      );
    }
    if (_match([_TokenType.stringLiteral])) {
      return LiteralExpression(
        value: FloaterValue(type: FloaterType.string, value: _previous().literal),
      );
    }
    if (_match([_TokenType.intLiteral])) {
      final raw = _previous().literal as String;
      return LiteralExpression(
        value: FloaterValue(type: FloaterType.int, value: int.parse(raw)),
      );
    }
    if (_match([_TokenType.floatLiteral])) {
      final raw = _previous().literal as String;
      return LiteralExpression(
        value: FloaterValue(type: FloaterType.float, value: double.parse(raw)),
      );
    }
    if (_match([_TokenType.dpLiteral])) {
      final raw = _previous().literal as String;
      return LiteralExpression(
        value: FloaterValue(type: FloaterType.dp, value: double.parse(raw)),
      );
    }
    if (_match([_TokenType.pxLiteral])) {
      final raw = _previous().literal as String;
      return LiteralExpression(
        value: FloaterValue(type: FloaterType.px, value: double.parse(raw)),
      );
    }
    if (_match([_TokenType.durationLiteral])) {
      final raw = _previous().literal as String;
      return LiteralExpression(
        value: FloaterValue(type: FloaterType.duration, value: double.parse(raw)),
      );
    }
    if (_match([_TokenType.angleLiteral])) {
      final raw = _previous().literal as String;
      return LiteralExpression(
        value: FloaterValue(type: FloaterType.angle, value: double.parse(raw)),
      );
    }
    if (_match([_TokenType.colorLiteral])) {
      final raw = _previous().literal as String;
      return LiteralExpression(
        value: FloaterValue(type: FloaterType.color, value: raw),
      );
    }
    if (_match([_TokenType.identifier])) {
      return VarExpression(name: _previous().lexeme);
    }
    if (_match([_TokenType.leftParen])) {
      // 可能是 Point (x, y) 或普通括号表达式
      final first = _parseExpression();
      if (_match([_TokenType.comma])) {
        final second = _parseExpression();
        _consume(_TokenType.rightParen, '元组缺少右括号');
        return CallExpression(name: 'point', args: [first, second]);
      } else {
        _consume(_TokenType.rightParen, '括号不匹配');
        return first;
      }
    }
    throw FloaterParseError('未期望的 token: ${_peek().lexeme}', _peek().line);
  }
}
