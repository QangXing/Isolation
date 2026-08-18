import 'package:flutter_test/flutter_test.dart';
import 'package:isolation/services/macro_program_parser.dart';

void main() {
  group('Floater template parse', () {
    const template = '''ball(main, "mainBall") {
    size(64)
    cornerRadius(16)
    image("main.png")
    location("mainBall", 100, 200)
    status(show, "mainBall")

    singleClick(Launch_macro)

    doubleClick {
        launch("com.example.app", timeout=3000) {
        }
    }

    tripleClick(Turn_off_macros)

    longPress {
        print("长按主球")
    }
}

ball(deputy, "helper") {
    size(48)
    cornerRadius(24)
    image("helper.png")
    location("helper", 0, 0)
    status(hide, "helper")
}

// 副球显示在主球右侧
mainX = found("mainBall", x)
mainY = found("mainBall", y)
location("helper", mainX + 80, mainY)
status(show, "helper")
''';

    test('parses template without error', () {
      final program = MacroProgramParser.parseFloaterProgram(template);
      expect(program.balls.length, 2);
      expect(program.mainBall, isNotNull);
      expect(program.mainBall!.name, 'mainBall');
      expect(program.mainBall!.role, 'main');
      expect(program.mainBall!.steps.length, 4);
      expect(program.deputyBalls.length, 1);
      expect(program.steps.length, 4);
    });
  });
}
