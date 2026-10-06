import 'package:flutter_test/flutter_test.dart';
import 'package:isolation/models/floater_program_v2.dart';
import 'package:isolation/services/floater_dsl_v2_parser.dart';

void main() {
  group('Floater DSL v2 parser', () {
    test('parses variables and ball declarations', () {
      const dsl = '''
floater "test" {
    val offset: Int = 10
    var visible: Bool = true

    ball mainBall: Main {
        size = 56dp
        radius = 28dp
        position = (100dp, 200dp)
        visible = true
        draggable = true
        anchor = topLeft
    }
}
''';
      final program = FloaterDslV2Parser.parse(dsl);

      expect(program.pluginId, 'test');
      expect(program.variables.length, 2);
      expect(program.variables[0].name, 'offset');
      expect(program.variables[0].mutable, false);
      expect(program.variables[1].name, 'visible');
      expect(program.variables[1].mutable, true);

      expect(program.balls.length, 1);
      expect(program.balls[0].name, 'mainBall');
      expect(program.balls[0].role, 'Main');
      expect(program.balls[0].properties['size']?.expression.type, FloaterType.dp);
      expect(program.balls[0].properties['size']?.expression.value, 56);
    });

    test('parses state, transition, let and bulk assignment', () {
      const dsl = '''
floater "state-test" {
    ball mainBall: Main {
        size = 56dp
        position = (100dp, 300dp)
    }

    ball sub1..3: Deputy {
        size = 40dp
        visible = false
    }

    state collapsed {
        sub1..3.visible = false
    }

    state expanded {
        let fan: Fan = Fan(center: mainBall.center, radius: 120dp, startAngle: 0deg, sweep: 90deg, count: 3)
        sub1..3.visible = true
        await animate [sub1..3] to fan[].topLeft duration 260ms easing overshoot
    }

    transition collapsed -> expanded on mainBall.click
    transition expanded -> collapsed on mainBall.click
}
''';
      final program = FloaterDslV2Parser.parse(dsl);

      expect(program.states.length, 2);
      expect(program.states[0].name, 'collapsed');
      expect(program.states[1].name, 'expanded');
      expect(program.states[1].localVariables, ['fan']);

      expect(program.transitions.length, 2);
      expect(program.transitions[0].from, 'collapsed');
      expect(program.transitions[0].to, 'expanded');
      expect(program.transitions[0].ballName, 'mainBall');
      expect(program.transitions[0].event, 'click');

      final expandedBody = program.states[1].body;
      expect(expandedBody.whereType<LetStatement>().length, 1);
      expect(expandedBody.whereType<MultiSetPropertyStatement>().length, 1);
      expect(expandedBody.whereType<AnimateStatement>().length, 1);
      final animate = expandedBody.whereType<AnimateStatement>().first;
      expect(animate.await, true);
      expect(animate.targets, ['sub1', 'sub2', 'sub3']);
      expect(animate.easing, 'overshoot');

      expect(program.balls.length, 4);
      expect(program.balls.map((b) => b.name).toList(), ['mainBall', 'sub1', 'sub2', 'sub3']);
    });

    test('parses ball event handlers and top-level on events', () {
      const dsl = '''
floater "event-test" {
    ball mainBall: Main {
        size = 56dp
        on click {
            print("clicked")
        }
    }

    on mainBall.longPress {
        print("long pressed")
    }
}
''';
      final program = FloaterDslV2Parser.parse(dsl);

      expect(program.balls[0].eventHandlers.keys, contains('click'));
      expect(program.events.length, 1);
      expect(program.events[0].target, 'mainBall');
      expect(program.events[0].event, 'longPress');
      expect(program.events[0].body.whereType<PrintStatement>().length, 1);
    });

    test('parses Fan, Ring and Grid constructors', () {
      const dsl = '''
floater "geometry-test" {
    val fan: Fan = Fan(center: (100dp, 200dp), radius: 80dp, startAngle: 0deg, sweep: 90deg, count: 3)
    val ring: Ring = Ring(center: (50dp, 50dp), radius: 100dp, count: 5)
    val grid: Grid = Grid(origin: (0dp, 0dp), columns: 2, spacing: 16dp)
}
''';
      final program = FloaterDslV2Parser.parse(dsl);

      expect(program.variables.length, 3);
      expect(program.variables[0].value.type, FloaterType.fan);
      expect(program.variables[1].value.type, FloaterType.ring);
      expect(program.variables[2].value.type, FloaterType.grid);
    });
  });
}
