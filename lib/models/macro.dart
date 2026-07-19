class MacroSettings {
  final bool smartRecognition;
  final int loopCount; // -1 for infinite, 0 treated as 1

  const MacroSettings({
    this.smartRecognition = false,
    this.loopCount = 1,
  });

  factory MacroSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MacroSettings();
    return MacroSettings(
      smartRecognition: json['smartRecognition'] as bool? ?? false,
      loopCount: json['loopCount'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'smartRecognition': smartRecognition,
        'loopCount': loopCount,
      };

  MacroSettings copyWith({bool? smartRecognition, int? loopCount}) {
    return MacroSettings(
      smartRecognition: smartRecognition ?? this.smartRecognition,
      loopCount: loopCount ?? this.loopCount,
    );
  }
}

class StepColor {
  final int x;
  final int y;
  final int color; // ARGB

  StepColor({required this.x, required this.y, required this.color});

  factory StepColor.fromJson(Map<String, dynamic> json) {
    return StepColor(
      x: json['x'] as int,
      y: json['y'] as int,
      color: json['color'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'color': color,
      };
}

class MacroData {
  final MacroSettings settings;
  final List<Map<String, dynamic>> steps;

  MacroData({required this.settings, required this.steps});

  factory MacroData.fromJson(dynamic json) {
    if (json is List) {
      return MacroData(
        settings: const MacroSettings(),
        steps: json
            .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
            .toList(),
      );
    }
    final map = Map<String, dynamic>.from(json as Map<dynamic, dynamic>);
    return MacroData(
      settings: MacroSettings.fromJson(
          map['settings'] as Map<String, dynamic>?),
      steps: (map['steps'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'settings': settings.toJson(),
        'steps': steps,
      };
}
