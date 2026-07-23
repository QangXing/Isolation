/// Dart 风格表达式 AST 与解析器。
///
/// 支持的操作符（按优先级从低到高）：
/// - `||`
/// - `&&`
/// - `==` / `!=`
/// - `>` / `<` / `>=` / `<=`
/// - `+` / `-`
/// - `*` / `/`
/// - 一元 `!` / `-`
/// - 括号、数字、十六进制 `0x...`、标识符
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

class ExpressionParser {
  /// 将表达式源码解析为 AST。
  static Expr parse(String source) {
    final tokens = _tokenize(source);
    final parser = _Parser(tokens);
    final expr = parser.parseExpression();
    if (!parser._isAtEnd) {
      throw _ParseError('Unexpected token: ${parser._current.text}');
    }
    return expr;
  }

  /// 解析变量声明右侧的值。
  ///
  /// - `point`: `point(x, y)` -> `{'x': expr-json, 'y': expr-json}`
  /// - `color`: `color(0xFF0000)` -> expr-json
  /// - `int` / `double`: 直接按表达式解析并返回 JSON
  static dynamic parseVariableValue(String varType, String source) {
    final s = source.trim();
    if (varType == 'point') {
      final match = RegExp(r'^point\s*\(\s*(.+)\s*,\s*(.+)\s*\)$').firstMatch(s);
      if (match != null) {
        return {
          'x': parse(match.group(1)!.trim()).toJson(),
          'y': parse(match.group(2)!.trim()).toJson(),
        };
      }
      throw _ParseError('Invalid point value: $s');
    }
    if (varType == 'color') {
      final match = RegExp(r'^color\s*\((.+)\)$').firstMatch(s);
      if (match != null) {
        return parse(match.group(1)!.trim()).toJson();
      }
      throw _ParseError('Invalid color value: $s');
    }
    return parse(s).toJson();
  }

  static List<_Token> _tokenize(String source) {
    final tokens = <_Token>[];
    int pos = 0;
    while (pos < source.length) {
      final c = source[pos];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        pos++;
        continue;
      }
      if (c == '(') {
        tokens.add(_Token(_TokenType.lparen, '('));
        pos++;
        continue;
      }
      if (c == ')') {
        tokens.add(_Token(_TokenType.rparen, ')'));
        pos++;
        continue;
      }
      if (_isDigit(c) || c == '.') {
        final start = pos;
        // 十六进制
        if (c == '0' && pos + 1 < source.length &&
            (source[pos + 1] == 'x' || source[pos + 1] == 'X')) {
          pos += 2;
          while (pos < source.length && _isHexDigit(source[pos])) {
            pos++;
          }
          final hexStr = source.substring(start + 2, pos);
          final value = int.parse(hexStr, radix: 16);
          tokens.add(_Token(_TokenType.number, source.substring(start, pos),
              value: value));
          continue;
        }
        bool hasDot = false;
        while (pos < source.length &&
            (_isDigit(source[pos]) || source[pos] == '.')) {
          if (source[pos] == '.') {
            if (hasDot) break;
            hasDot = true;
          }
          pos++;
        }
        final text = source.substring(start, pos);
        final value = hasDot ? double.parse(text) : int.parse(text);
        tokens.add(_Token(_TokenType.number, text, value: value));
        continue;
      }
      if (_isIdentifierStart(c)) {
        final start = pos;
        while (pos < source.length && _isIdentifierPart(source[pos])) {
          pos++;
        }
        final text = source.substring(start, pos);
        tokens.add(_Token(_TokenType.identifier, text));
        continue;
      }
      final op = _readOperator(source, pos);
      if (op != null) {
        tokens.add(_Token(_TokenType.operator, op));
        pos += op.length;
        continue;
      }
      throw _ParseError('Unexpected character: $c');
    }
    tokens.add(_Token(_TokenType.eof, ''));
    return tokens;
  }

  static String? _readOperator(String source, int pos) {
    const operators = ['||', '&&', '==', '!=', '>=', '<=', '+', '-', '*', '/', '>', '<', '!'];
    for (final op in operators) {
      if (pos + op.length <= source.length &&
          source.substring(pos, pos + op.length) == op) {
        return op;
      }
    }
    return null;
  }

  static bool _isDigit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;

  static bool _isHexDigit(String c) =>
      _isDigit(c) ||
      (c.compareTo('a') >= 0 && c.compareTo('f') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('F') <= 0);

  static bool _isIdentifierStart(String c) =>
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
      c == '_';

  static bool _isIdentifierPart(String c) =>
      _isIdentifierStart(c) || _isDigit(c);
}

/// 将表达式 AST 序列化为中缀字符串（带括号）。
String serializeExpr(Expr expr) => _serialize(expr);

String _serialize(Expr expr) {
  switch (expr) {
    case LiteralExpr():
      final value = expr.value;
      if (value is double) {
        return value.toString();
      }
      return value.toString();
    case VarExpr():
      return expr.name;
    case UnaryExpr():
      final rightStr = _serialize(expr.right);
      final rightNeedsParens = expr.right is BinaryExpr;
      return '${expr.operator}${rightNeedsParens ? '($rightStr)' : rightStr}';
    case BinaryExpr():
      final leftStr = _serialize(expr.left);
      final rightStr = _serialize(expr.right);
      final leftParens = _needsParensLeft(expr.operator, expr.left);
      final rightParens = _needsParensRight(expr.operator, expr.right);
      final leftOut = leftParens ? '($leftStr)' : leftStr;
      final rightOut = rightParens ? '($rightStr)' : rightStr;
      return '$leftOut ${expr.operator} $rightOut';
  }
}

int _precedence(String op) {
  switch (op) {
    case '||':
      return 1;
    case '&&':
      return 2;
    case '==':
    case '!=':
      return 3;
    case '>':
    case '<':
    case '>=':
    case '<=':
      return 4;
    case '+':
    case '-':
      return 5;
    case '*':
    case '/':
      return 6;
    case '!':
    case 'unary-':
      return 7;
  }
  return 0;
}

bool _needsParensLeft(String parentOp, Expr child) {
  if (child is BinaryExpr) {
    return _precedence(child.operator) < _precedence(parentOp);
  }
  return false;
}

bool _needsParensRight(String parentOp, Expr child) {
  if (child is BinaryExpr) {
    return _precedence(child.operator) <= _precedence(parentOp);
  }
  return false;
}

enum _TokenType { number, identifier, operator, lparen, rparen, eof }

class _Token {
  final _TokenType type;
  final String text;
  final dynamic value;
  _Token(this.type, this.text, {this.value});
}

class _ParseError implements Exception {
  final String message;
  _ParseError(this.message);
  @override
  String toString() => message;
}

class _Parser {
  final List<_Token> tokens;
  int _pos = 0;

  _Parser(this.tokens);

  _Token get _current => tokens[_pos];

  bool get _isAtEnd => _current.type == _TokenType.eof;

  Expr parseExpression() => _parseOr();

  Expr _parseOr() {
    var expr = _parseAnd();
    while (_match('||')) {
      expr = BinaryExpr('||', expr, _parseAnd());
    }
    return expr;
  }

  Expr _parseAnd() {
    var expr = _parseEquality();
    while (_match('&&')) {
      expr = BinaryExpr('&&', expr, _parseEquality());
    }
    return expr;
  }

  Expr _parseEquality() {
    var expr = _parseComparison();
    while (true) {
      if (_match('==')) {
        expr = BinaryExpr('==', expr, _parseComparison());
      } else if (_match('!=')) {
        expr = BinaryExpr('!=', expr, _parseComparison());
      } else {
        break;
      }
    }
    return expr;
  }

  Expr _parseComparison() {
    var expr = _parseAdditive();
    while (true) {
      if (_match('>=')) {
        expr = BinaryExpr('>=', expr, _parseAdditive());
      } else if (_match('<=')) {
        expr = BinaryExpr('<=', expr, _parseAdditive());
      } else if (_match('>')) {
        expr = BinaryExpr('>', expr, _parseAdditive());
      } else if (_match('<')) {
        expr = BinaryExpr('<', expr, _parseAdditive());
      } else {
        break;
      }
    }
    return expr;
  }

  Expr _parseAdditive() {
    var expr = _parseMultiplicative();
    while (true) {
      if (_match('+')) {
        expr = BinaryExpr('+', expr, _parseMultiplicative());
      } else if (_match('-')) {
        expr = BinaryExpr('-', expr, _parseMultiplicative());
      } else {
        break;
      }
    }
    return expr;
  }

  Expr _parseMultiplicative() {
    var expr = _parseUnary();
    while (true) {
      if (_match('*')) {
        expr = BinaryExpr('*', expr, _parseUnary());
      } else if (_match('/')) {
        expr = BinaryExpr('/', expr, _parseUnary());
      } else {
        break;
      }
    }
    return expr;
  }

  Expr _parseUnary() {
    if (_match('!')) {
      return UnaryExpr('!', _parseUnary());
    }
    if (_match('-')) {
      return UnaryExpr('-', _parseUnary());
    }
    return _parsePrimary();
  }

  Expr _parsePrimary() {
    if (_matchNumber()) {
      return LiteralExpr(_previous.value);
    }
    if (_matchIdentifier()) {
      return VarExpr(_previous.text);
    }
    if (_match('(')) {
      final expr = _parseOr();
      _expect(')');
      return expr;
    }
    throw _ParseError('Unexpected token: ${_current.text}');
  }

  bool _match(String text) {
    if (_current.type == _TokenType.operator && _current.text == text) {
      _pos++;
      return true;
    }
    if (text == '(' && _current.type == _TokenType.lparen) {
      _pos++;
      return true;
    }
    if (text == ')' && _current.type == _TokenType.rparen) {
      _pos++;
      return true;
    }
    return false;
  }

  bool _matchNumber() {
    if (_current.type == _TokenType.number) {
      _pos++;
      return true;
    }
    return false;
  }

  bool _matchIdentifier() {
    if (_current.type == _TokenType.identifier) {
      _pos++;
      return true;
    }
    return false;
  }

  void _expect(String text) {
    if (!_match(text)) {
      throw _ParseError('Expected "$text" but found ${_current.text}');
    }
  }

  _Token get _previous => tokens[_pos - 1];
}
