/// Floater DSL v2 程序 AST 模型。
///
/// v2 采用声明式语法 + 强类型：
/// - 球的尺寸、位置、可见性等通过属性声明
/// - 所有数值都带类型（dp/px/deg/ms 等）
/// - 事件体是语句列表
class FloaterProgramV2 {
  final String pluginId;
  final List<FloaterVariable> variables;
  final List<FloaterBallV2> balls;
  final List<FloaterEvent> events;

  const FloaterProgramV2({
    required this.pluginId,
    required this.variables,
    required this.balls,
    required this.events,
  });

  Map<String, dynamic> toJson() => {
        'dslVersion': 2,
        'pluginId': pluginId,
        'variables': variables.map((v) => v.toJson()).toList(),
        'balls': balls.map((b) => b.toJson()).toList(),
        'events': events.map((e) => e.toJson()).toList(),
      };
}

/// 变量声明：val 不可变，var 可变。
class FloaterVariable {
  final String name;
  final FloaterType type;
  final FloaterValue value;
  final bool mutable;

  const FloaterVariable({
    required this.name,
    required this.type,
    required this.value,
    required this.mutable,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.toJson(),
        'value': value.toJson(),
        'mutable': mutable,
      };
}

/// 单个球声明。
class FloaterBallV2 {
  final String name;
  final String role;
  final Map<String, FloaterProperty> properties;
  final Map<String, List<FloaterStatement>> eventHandlers;

  const FloaterBallV2({
    required this.name,
    required this.role,
    required this.properties,
    required this.eventHandlers,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'role': role,
        'properties': properties.map((k, v) => MapEntry(k, v.toJson())),
        'eventHandlers': eventHandlers.map(
          (k, v) => MapEntry(k, v.map((s) => s.toJson()).toList()),
        ),
      };
}

/// 球的属性，记录声明时的类型、表达式和源码位置（用于报错）。
/// 属性值在运行时求值，因此保存表达式 AST 而非立即字面量。
class FloaterProperty {
  final FloaterType declaredType;
  final FloaterExpression expression;
  final int line;

  const FloaterProperty({
    required this.declaredType,
    required this.expression,
    required this.line,
  });

  Map<String, dynamic> toJson() => {
        'declaredType': declaredType.toJson(),
        'expression': expression.toJson(),
        'line': line,
      };
}

/// 事件处理器。
class FloaterEvent {
  final String target;
  final String event;
  final List<FloaterStatement> body;

  const FloaterEvent({
    required this.target,
    required this.event,
    required this.body,
  });

  Map<String, dynamic> toJson() => {
        'target': target,
        'event': event,
        'body': body.map((s) => s.toJson()).toList(),
      };
}

/// 语句基类。
sealed class FloaterStatement {
  Map<String, dynamic> toJson();
}

/// 变量赋值：name = value。
class AssignStatement extends FloaterStatement {
  final String target;
  final FloaterExpression value;

  AssignStatement({required this.target, required this.value});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'assign',
        'target': target,
        'value': value.toJson(),
      };
}

/// 属性赋值：ballName.prop = value。
class SetPropertyStatement extends FloaterStatement {
  final String ballName;
  final String property;
  final FloaterExpression value;

  SetPropertyStatement({
    required this.ballName,
    required this.property,
    required this.value,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'setProperty',
        'ballName': ballName,
        'property': property,
        'value': value.toJson(),
      };
}

/// print 语句。
class PrintStatement extends FloaterStatement {
  final FloaterExpression expression;

  PrintStatement({required this.expression});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'print',
        'expression': expression.toJson(),
      };
}

/// wait 语句。
class WaitStatement extends FloaterStatement {
  final FloaterExpression duration;

  WaitStatement({required this.duration});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'wait',
        'duration': duration.toJson(),
      };
}

/// if 语句。
class IfStatement extends FloaterStatement {
  final FloaterExpression condition;
  final List<FloaterStatement> thenBody;
  final List<FloaterStatement>? elseBody;

  IfStatement({
    required this.condition,
    required this.thenBody,
    this.elseBody,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'if',
        'condition': condition.toJson(),
        'thenBody': thenBody.map((s) => s.toJson()).toList(),
        if (elseBody != null)
          'elseBody': elseBody!.map((s) => s.toJson()).toList(),
      };
}

/// for 循环。
class ForStatement extends FloaterStatement {
  final String variable;
  final FloaterExpression from;
  final FloaterExpression to;
  final List<FloaterStatement> body;

  ForStatement({
    required this.variable,
    required this.from,
    required this.to,
    required this.body,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'for',
        'variable': variable,
        'from': from.toJson(),
        'to': to.toJson(),
        'body': body.map((s) => s.toJson()).toList(),
      };
}

/// 表达式基类。
sealed class FloaterExpression {
  Map<String, dynamic> toJson();
}

/// 字面量表达式。
class LiteralExpression extends FloaterExpression {
  final FloaterValue value;

  LiteralExpression({required this.value});

  @override
  Map<String, dynamic> toJson() => {
        'op': 'literal',
        'value': value.toJson(),
      };
}

/// 变量引用。
class VarExpression extends FloaterExpression {
  final String name;

  VarExpression({required this.name});

  @override
  Map<String, dynamic> toJson() => {
        'op': 'var',
        'name': name,
      };
}

/// 属性访问：ballName.prop。
class PropertyExpression extends FloaterExpression {
  final String ballName;
  final String property;

  PropertyExpression({required this.ballName, required this.property});

  @override
  Map<String, dynamic> toJson() => {
        'op': 'property',
        'ballName': ballName,
        'property': property,
      };
}

/// 二元表达式。
class BinaryExpression extends FloaterExpression {
  final String operator;
  final FloaterExpression left;
  final FloaterExpression right;

  BinaryExpression({
    required this.operator,
    required this.left,
    required this.right,
  });

  @override
  Map<String, dynamic> toJson() => {
        'op': 'binary',
        'operator': operator,
        'left': left.toJson(),
        'right': right.toJson(),
      };
}

/// 一元表达式。
class UnaryExpression extends FloaterExpression {
  final String operator;
  final FloaterExpression right;

  UnaryExpression({required this.operator, required this.right});

  @override
  Map<String, dynamic> toJson() => {
        'op': 'unary',
        'operator': operator,
        'right': right.toJson(),
      };
}

/// 函数调用。
class CallExpression extends FloaterExpression {
  final String name;
  final List<FloaterExpression> args;
  final Map<String, FloaterExpression> namedArgs;

  CallExpression({
    required this.name,
    this.args = const [],
    this.namedArgs = const {},
  });

  @override
  Map<String, dynamic> toJson() => {
        'op': 'call',
        'name': name,
        'args': args.map((a) => a.toJson()).toList(),
        'namedArgs': namedArgs.map((k, v) => MapEntry(k, v.toJson())),
      };
}

/// 类型定义。
enum FloaterTypeKind {
  dp,
  px,
  int,
  float,
  bool,
  string,
  duration,
  angle,
  point,
  size,
  color,
  unknown,
}

class FloaterType {
  final FloaterTypeKind kind;

  const FloaterType(this.kind);

  static const FloaterType dp = FloaterType(FloaterTypeKind.dp);
  static const FloaterType px = FloaterType(FloaterTypeKind.px);
  static const FloaterType int = FloaterType(FloaterTypeKind.int);
  static const FloaterType float = FloaterType(FloaterTypeKind.float);
  static const FloaterType bool = FloaterType(FloaterTypeKind.bool);
  static const FloaterType string = FloaterType(FloaterTypeKind.string);
  static const FloaterType duration = FloaterType(FloaterTypeKind.duration);
  static const FloaterType angle = FloaterType(FloaterTypeKind.angle);
  static const FloaterType point = FloaterType(FloaterTypeKind.point);
  static const FloaterType size = FloaterType(FloaterTypeKind.size);
  static const FloaterType color = FloaterType(FloaterTypeKind.color);
  static const FloaterType unknown = FloaterType(FloaterTypeKind.unknown);

  factory FloaterType.fromName(String name) {
    switch (name) {
      case 'Dp':
        return FloaterType.dp;
      case 'Px':
        return FloaterType.px;
      case 'Int':
        return FloaterType.int;
      case 'Float':
        return FloaterType.float;
      case 'Bool':
        return FloaterType.bool;
      case 'String':
        return FloaterType.string;
      case 'Duration':
        return FloaterType.duration;
      case 'Angle':
        return FloaterType.angle;
      case 'Point':
        return FloaterType.point;
      case 'Size':
        return FloaterType.size;
      case 'Color':
        return FloaterType.color;
      default:
        return FloaterType.unknown;
    }
  }

  String get name {
    switch (kind) {
      case FloaterTypeKind.dp:
        return 'Dp';
      case FloaterTypeKind.px:
        return 'Px';
      case FloaterTypeKind.int:
        return 'Int';
      case FloaterTypeKind.float:
        return 'Float';
      case FloaterTypeKind.bool:
        return 'Bool';
      case FloaterTypeKind.string:
        return 'String';
      case FloaterTypeKind.duration:
        return 'Duration';
      case FloaterTypeKind.angle:
        return 'Angle';
      case FloaterTypeKind.point:
        return 'Point';
      case FloaterTypeKind.size:
        return 'Size';
      case FloaterTypeKind.color:
        return 'Color';
      case FloaterTypeKind.unknown:
        return 'Unknown';
    }
  }

  Map<String, dynamic> toJson() => {'kind': name};
}

/// 带类型的值。
class FloaterValue {
  final FloaterType type;
  final dynamic value;

  const FloaterValue({required this.type, required this.value});

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'value': value,
      };
}
