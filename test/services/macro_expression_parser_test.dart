import 'package:flutter_test/flutter_test.dart';
import 'package:isolation/services/macro_expression_parser.dart';

void main() {
  test('score + 1 > 5 produces expected AST JSON', () {
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

  test('&& has higher precedence than ||', () {
    final expr = ExpressionParser.parse('a && b || c');
    expect(expr.toJson(), {
      'op': 'binary',
      'operator': '||',
      'left': {
        'op': 'binary',
        'operator': '&&',
        'left': {'op': 'var', 'name': 'a'},
        'right': {'op': 'var', 'name': 'b'},
      },
      'right': {'op': 'var', 'name': 'c'},
    });
  });

  test('parentheses override precedence', () {
    final expr = ExpressionParser.parse('(a || b) && c');
    expect(expr.toJson(), {
      'op': 'binary',
      'operator': '&&',
      'left': {
        'op': 'binary',
        'operator': '||',
        'left': {'op': 'var', 'name': 'a'},
        'right': {'op': 'var', 'name': 'b'},
      },
      'right': {'op': 'var', 'name': 'c'},
    });
  });

  test('hex literal parses to integer value', () {
    final expr = ExpressionParser.parse('0xFF');
    expect(expr, isA<LiteralExpr>());
    expect((expr as LiteralExpr).value, 255);
    expect(expr.toJson(), {'op': 'literal', 'value': 255});
  });

  test('variable parses to var node', () {
    final expr = ExpressionParser.parse('score');
    expect(expr, isA<VarExpr>());
    expect((expr as VarExpr).name, 'score');
  });

  test('serializeExpr produces parenthesized infix string', () {
    final expr = ExpressionParser.parse('score + 1 > 5');
    expect(serializeExpr(expr), 'score + 1 > 5');
  });

  test('serialize preserves parentheses when needed', () {
    final expr = ExpressionParser.parse('(a + b) * c');
    expect(serializeExpr(expr), '(a + b) * c');
  });
}
