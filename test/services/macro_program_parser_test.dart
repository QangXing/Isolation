import 'package:flutter_test/flutter_test.dart';
import 'package:isolation/services/macro_program_parser.dart';

void main() {
  test('variable declaration and assignment round-trip', () {
    final code = '''
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
    final code = '''
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
    final code = '''
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
    final code = 'swipeRel(500, 800, 0, -300, 400)';
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
    final code = '''
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
    final code = 'ok = launch("com.example.app", timeout=3000)';
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
    final code = '''
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
    final code = '''
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
    final code = '''
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
    final code = '''
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
    final code = 'p = waitForText("加载完成")';
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'waitForText');
    expect(parsed.first['text'], '加载完成');
    expect(parsed.first['assignTo'], 'p');
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('waitForText with timeout round-trip', () {
    final code = '''
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
    final code = '''
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
    final code = 'breakLoop("poll")';
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'breakLoop');
    expect(parsed.first['name'], 'poll');
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('breakLoop without name round-trip', () {
    final code = 'breakLoop()';
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'breakLoop');
    expect(parsed.first.containsKey('name'), isFalse);
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('comments are preserved round-trip', () {
    final code = '''
// 初始化
print("开始")
// 循环查找
loop {
    // 等待签到按钮
    waitForText("签到") {
        // 点击按钮
        click()
    }
}
// 结束
'''.trim();
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.where((s) => s['type'] == 'comment').length, 3);
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('include directive round-trip', () {
    final code = '#include <开心球>';
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 1);
    expect(parsed.first['type'], 'include');
    expect(parsed.first['displayName'], '开心球');
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('floater directive with else round-trip', () {
    final code = '''floater("click") {
    image("click.png")
    audio("click.mp3")
} else {
    print("失败")
}'''.trim();
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.first['type'], 'floater');
    expect(parsed.first['event'], 'click');
    expect(parsed.first['else'], isA<List>());
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });

  test('cornerRadius, size, image, audio round-trip', () {
    final code = '''cornerRadius(16)
size(56)
image("default.png")
audio("ding.mp3")'''.trim();
    final parsed = MacroProgramParser.parse(code);
    expect(parsed.length, 4);
    expect(parsed[0]['type'], 'cornerRadius');
    expect(parsed[1]['type'], 'size');
    expect(parsed[2]['type'], 'image');
    expect(parsed[3]['type'], 'audio');
    final serialized = MacroProgramParser.serialize(parsed).trim();
    expect(serialized, code);
  });
}
