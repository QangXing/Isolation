import 'package:flutter_test/flutter_test.dart';
import 'package:isolation/services/macro_program_parser.dart';

void main() {
  test('findImage with feature options round-trip', () {
    final steps = [
      {
        'type': 'findImage',
        'image': 'btn.jpg',
        'featureCount': 12,
        'featurePointThreshold': 0.9,
        'colorTolerance': 25,
        'children': <Map<String, dynamic>>[
          {'type': 'click'},
        ],
      },
    ];
    final code = MacroProgramParser.serialize(steps);
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.first['featureCount'], 12);
    expect(parsed.first['featurePointThreshold'], 0.9);
    expect(parsed.first['colorTolerance'], 25);
    expect(parsed.first['image'], 'btn.jpg');
  });

  test('swipe absolute coordinates round-trip', () {
    const code = 'swipe(100, 200, 100, 800, 500)';
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'swipe');
    expect(parsed.first['start'], {'x': 100, 'y': 200});
    expect(parsed.first['end'], {'x': 100, 'y': 800});
    expect(parsed.first['duration'], 500);
    final serialized = MacroProgramParser.serialize(parsed);
    expect(serialized.trim(), code);
  });

  group('if-else round-trip', () {
    final ifSteps = [
      {
        'type': 'ifText',
        'text': '领取',
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
      expect(parsed.first['type'], 'ifText');
      expect(parsed.first['then'], isA<List>());
      expect(parsed.first['else'], isA<List>());
      expect((parsed.first['then'] as List).length, 1);
      expect((parsed.first['else'] as List).length, 1);
      expect((parsed.first['else'] as List).first['message'], 'no');
    });

    test('separate-line else { preserves else branch', () {
      const code = '''
ifText("领取") {
    print("yes")
}
else {
    print("no")
}
''';
      final parsed = MacroProgramParser.parse(code);
      expect(parsed.length, 1);
      expect(parsed.first['type'], 'ifText');
      expect(parsed.first['else'], isA<List>());
      expect((parsed.first['else'] as List).length, 1);
    });

    test('ifText without else keeps no else key', () {
      final steps = [
        {
          'type': 'ifText',
          'text': '领取',
          'then': <Map<String, dynamic>>[
            {'type': 'print', 'message': 'yes'},
          ],
        },
      ];
      final code = MacroProgramParser.serialize(steps);
      final parsed = MacroProgramParser.parse(code);
      expect(parsed.first['type'], 'ifText');
      expect(parsed.first.containsKey('else'), isFalse);
    });

    test('nested if-else preserves both branches', () {
      final steps = [
        {
          'type': 'ifText',
          'text': 'A',
          'then': <Map<String, dynamic>>[
            {
              'type': 'ifText',
              'text': 'B',
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
      expect(innerIf['type'], 'ifText');
      expect((innerIf['else'] as List).first['message'], 'only A');
    });
  });

  group('change round-trip', () {
    test('change with explicit name and all properties', () {
      const code = 'change("mainBall", size=80, cornerRadius=16, image="new.png", opacity=0.8)';
      final parsed = MacroProgramParser.parse(code);
      expect(parsed.length, 1);
      final step = parsed.first;
      expect(step['type'], 'change');
      expect(step['name'], 'mainBall');
      expect(step['size'], 80);
      expect(step['cornerRadius'], 16);
      expect(step['image'], 'new.png');
      expect(step['opacity'], 0.8);
    });

    test('change without name targets current ball', () {
      const code = 'change(size=56, opacity=0.5)';
      final parsed = MacroProgramParser.parse(code);
      expect(parsed.first['type'], 'change');
      expect(parsed.first['name'], '');
      expect(parsed.first['size'], 56);
      expect(parsed.first['opacity'], 0.5);
    });

    test('change serialize round-trip preserves order', () {
      const code = 'change("helper", size=48, cornerRadius=24, image="icon.png", opacity=0.6)';
      final parsed = MacroProgramParser.parse(code);
      final serialized = MacroProgramParser.serialize(parsed).trim();
      expect(serialized, code);
    });

    test('change inside ball event becomes ball step', () {
      final source = '''
ball(main, "mainBall") {
    size(64)
    singleClick {
        change(size=80, opacity=0.8)
    }
}
'''.trim();
      final program = MacroProgramParser.parseFloaterProgram(source);
      expect(program.balls.length, 1);
      final ball = program.balls.first;
      expect(ball.size, 64);
      expect(ball.steps.length, 1);
      final singleClick = ball.steps.first;
      expect(singleClick['type'], 'singleClick');
      final children = singleClick['children'] as List;
      expect(children.length, 1);
      final step = children.first as Map<String, dynamic>;
      expect(step['type'], 'change');
      expect(step['size'], 80);
      expect(step['opacity'], 0.8);
    });
  });
}
