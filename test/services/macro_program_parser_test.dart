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
    swipe(0, 300, 400)
}
'''.trim();
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.first['type'], 'for');
    expect(parsed.first.containsKey('condition'), isTrue);
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('swipeRel round-trip', () {
    const code = 'swipeRel(500, 800, 0, -300, 400)';
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'swipeRel');
    expect(parsed.first['fromX'], 500);
    expect(parsed.first['fromY'], 800);
    expect(parsed.first['dx'], 0);
    expect(parsed.first['dy'], -300);
    expect(parsed.first['duration'], 400);
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('launch command round-trip', () {
    const code = '''
launch("com.example.app", timeout=3000) {
    click(500, 800)
}
'''.trim();
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'launch');
    expect(parsed.first['packageName'], 'com.example.app');
    expect(parsed.first['timeout'], 3000);
    expect(parsed.first['children'], isA<List>());
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('launch assignment round-trip', () {
    const code = 'ok = launch("com.example.app", timeout=3000)';
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'launch');
    expect(parsed.first['assignTo'], 'ok');
    expect(parsed.first['packageName'], 'com.example.app');
    expect(parsed.first['timeout'], 3000);
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('if with launch condition round-trip', () {
    const code = '''
if (launch("com.example.app", timeout=3000)) {
    click(500, 800)
}
'''.trim();
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'if');
    final condition = parsed.first['condition'] as Map<String, dynamic>;
    expect(condition['type'], 'launch');
    expect(condition['packageName'], 'com.example.app');
    expect(condition['timeout'], 3000);
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('waitForText round-trip', () {
    const code = '''
waitForText("加载完成") {
    click()
}
'''.trim();
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'waitForText');
    expect(parsed.first['text'], '加载完成');
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('waitForColor round-trip', () {
    const code = '''
waitForColor(0xFFFA40, tolerance=30, step=1) {
    click()
}
'''.trim();
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'waitForColor');
    expect(parsed.first['color'], 0xFFFA40);
    expect(parsed.first['tolerance'], 30);
    expect(parsed.first['step'], 1);
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('waitForImage round-trip', () {
    const code = '''
waitForImage("ok.png", featureCount=12, featurePointThreshold=0.9) {
    click()
}
'''.trim();
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'waitForImage');
    expect(parsed.first['image'], 'ok.png');
    expect(parsed.first['featureCount'], 12);
    expect(parsed.first['featurePointThreshold'], 0.9);
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('waitForText assignment round-trip', () {
    const code = 'p = waitForText("加载完成")';
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'waitForText');
    expect(parsed.first['text'], '加载完成');
    expect(parsed.first['assignTo'], 'p');
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('waitForText with timeout round-trip', () {
    const code = '''
waitForText("加载完成", timeout=5000) {
    click()
}
'''.trim();
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'waitForText');
    expect(parsed.first['text'], '加载完成');
    expect(parsed.first['timeout'], 5000);
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('loop with name round-trip', () {
    const code = '''
loop("poll") {
    waitForText("签到") {
        click()
    }
    wait(2000)
}
'''.trim();
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'loop');
    expect(parsed.first['name'], 'poll');
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('breakLoop with name round-trip', () {
    const code = 'breakLoop("poll")';
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'breakLoop');
    expect(parsed.first['name'], 'poll');
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('breakLoop without name round-trip', () {
    const code = 'breakLoop()';
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'breakLoop');
    expect(parsed.first.containsKey('name'), isFalse);
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });
}
