class MacroStep {
  final int delayMs;
  final int x;
  final int y;
  final int? color;

  MacroStep({
    required this.delayMs,
    required this.x,
    required this.y,
    this.color,
  });

  factory MacroStep.fromJson(Map<String, dynamic> json) {
    return MacroStep(
      delayMs: json['delayMs'] as int? ?? 0,
      x: json['x'] as int? ?? 0,
      y: json['y'] as int? ?? 0,
      color: json['color'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'delayMs': delayMs,
      'x': x,
      'y': y,
      if (color != null) 'color': color,
    };
  }

  MacroStep copyWith({
    int? delayMs,
    int? x,
    int? y,
    int? color,
  }) {
    return MacroStep(
      delayMs: delayMs ?? this.delayMs,
      x: x ?? this.x,
      y: y ?? this.y,
      color: color ?? this.color,
    );
  }
}

class Macro {
  final String id;
  String name;
  List<MacroStep> steps;
  bool loop;
  bool smartRecognition;
  bool builtIn;
  bool enabled;

  Macro({
    required this.id,
    required this.name,
    this.steps = const [],
    this.loop = false,
    this.smartRecognition = false,
    this.builtIn = false,
    this.enabled = false,
  });

  factory Macro.fromJson(Map<String, dynamic> json) {
    return Macro(
      id: json['id'] as String,
      name: json['name'] as String? ?? '未命名宏',
      steps: (json['steps'] as List<dynamic>? ?? [])
          .map((e) => MacroStep.fromJson(e as Map<String, dynamic>))
          .toList(),
      loop: json['loop'] as bool? ?? false,
      smartRecognition: json['smartRecognition'] as bool? ?? false,
      builtIn: json['builtIn'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'steps': steps.map((s) => s.toJson()).toList(),
      'loop': loop,
      'smartRecognition': smartRecognition,
      'builtIn': builtIn,
      'enabled': enabled,
    };
  }

  Macro copyWith({
    String? id,
    String? name,
    List<MacroStep>? steps,
    bool? loop,
    bool? smartRecognition,
    bool? builtIn,
    bool? enabled,
  }) {
    return Macro(
      id: id ?? this.id,
      name: name ?? this.name,
      steps: steps ?? this.steps,
      loop: loop ?? this.loop,
      smartRecognition: smartRecognition ?? this.smartRecognition,
      builtIn: builtIn ?? this.builtIn,
      enabled: enabled ?? this.enabled,
    );
  }
}
