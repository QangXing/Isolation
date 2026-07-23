import 'package:flutter_test/flutter_test.dart';
import 'package:isolation/services/macro_program_parser.dart';

void main() {
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
}
