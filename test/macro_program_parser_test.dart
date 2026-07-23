import 'package:flutter_test/flutter_test.dart';
import 'package:isolation/services/macro_program_parser.dart';

void main() {
  test('find image with feature and minMatches round-trip', () {
    final steps = [
      {
        'type': 'find',
        'image': 'btn.jpg',
        'feature': 'akaze',
        'minMatches': 8,
        'threshold': 0.85,
        'children': <Map<String, dynamic>>[
          {'type': 'click'},
        ],
      },
    ];
    final code = MacroProgramParser.serialize(steps);
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.first['feature'], 'akaze');
    expect(parsed.first['minMatches'], 8);
    expect(parsed.first['image'], 'btn.jpg');
  });

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

  group('if-else round-trip', () {
    final ifSteps = [
      {
        'type': 'if',
        'condition': {
          'type': 'find',
          'target': {'text': '领取'},
        },
        'then': <Map<String, dynamic>>[
          {'type': 'print', 'message': 'yes'},
        ],
        'else': <Map<String, dynamic>>[
          {'type': 'print', 'message': 'no'},
        ],
      },
    ];

    test('inline } else { preserves else branch', () {
      final code = MacroProgramParser.serialize(ifSteps);
      final parsed = MacroProgramParser.parse(code);
      expect(parsed.length, 1);
      expect(parsed.first['type'], 'if');
      expect(parsed.first['then'], isA<List>());
      expect(parsed.first['else'], isA<List>());
      expect((parsed.first['then'] as List).length, 1);
      expect((parsed.first['else'] as List).length, 1);
      expect((parsed.first['else'] as List).first['message'], 'no');
    });

    test('separate-line else { preserves else branch', () {
      const code = '''
if(find(text="领取")) {
    print("yes")
}
else {
    print("no")
}
''';
      final parsed = MacroProgramParser.parse(code);
      expect(parsed.length, 1);
      expect(parsed.first['type'], 'if');
      expect(parsed.first['else'], isA<List>());
      expect((parsed.first['else'] as List).length, 1);
    });

    test('if without else keeps no else key', () {
      final steps = [
        {
          'type': 'if',
          'condition': {
            'type': 'find',
            'target': {'text': '领取'},
          },
          'then': <Map<String, dynamic>>[
            {'type': 'print', 'message': 'yes'},
          ],
        },
      ];
      final code = MacroProgramParser.serialize(steps);
      final parsed = MacroProgramParser.parse(code);
      expect(parsed.first['type'], 'if');
      expect(parsed.first.containsKey('else'), isFalse);
    });

    test('nested if-else preserves both branches', () {
      final steps = [
        {
          'type': 'if',
          'condition': {
            'type': 'find',
            'target': {'text': 'A'},
          },
          'then': <Map<String, dynamic>>[
            {
              'type': 'if',
              'condition': {
                'type': 'find',
                'target': {'text': 'B'},
              },
              'then': <Map<String, dynamic>>[
                {'type': 'print', 'message': 'both'},
              ],
              'else': <Map<String, dynamic>>[
                {'type': 'print', 'message': 'only A'},
              ],
            },
          ],
          'else': <Map<String, dynamic>>[
            {'type': 'print', 'message': 'neither'},
          ],
        },
      ];
      final code = MacroProgramParser.serialize(steps);
      final parsed = MacroProgramParser.parse(code);
      final outerElse = parsed.first['else'] as List;
      expect(outerElse.length, 1);
      expect(outerElse.first['message'], 'neither');
      final innerIf = (parsed.first['then'] as List).first as Map<String, dynamic>;
      expect(innerIf['type'], 'if');
      expect((innerIf['else'] as List).first['message'], 'only A');
    });
  });
}
