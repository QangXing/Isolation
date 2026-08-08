class MacroSettings {
  // 旧字段保留仅用于兼容旧数据反序列化，新保存时不再写入
  final bool smartRecognition;
  final int loopCount;

  /// 调试模式：开启后每执行一步都会通过悬浮球显示默认提示。
  final bool debugMode;

  /// 图片匹配特征点采样数目，越多越稳定但越慢。
  final int featurePointCount;

  /// 图片匹配特征点命中比例阈值，例如 0.8 表示至少 80% 特征点命中才算识别成功。
  final double featurePointThreshold;

  const MacroSettings({
    this.smartRecognition = false,
    this.loopCount = 1,
    this.debugMode = false,
    this.featurePointCount = 8,
    this.featurePointThreshold = 0.80,
  });

  factory MacroSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MacroSettings();
    return MacroSettings(
      smartRecognition: json['smartRecognition'] as bool? ?? false,
      loopCount: json['loopCount'] as int? ?? 1,
      debugMode: json['debugMode'] as bool? ?? false,
      featurePointCount: (json['featurePointCount'] as num?)?.toInt() ?? 8,
      featurePointThreshold: (json['featurePointThreshold'] as num?)?.toDouble() ?? 0.80,
    );
  }

  Map<String, dynamic> toJson() => {
        // 旧字段不再写入新文件，保留向前兼容读取
        'loopCount': loopCount,
        'debugMode': debugMode,
        'featurePointCount': featurePointCount,
        'featurePointThreshold': featurePointThreshold,
      };

  MacroSettings copyWith({
    bool? smartRecognition,
    int? loopCount,
    bool? debugMode,
    int? featurePointCount,
    double? featurePointThreshold,
  }) {
    return MacroSettings(
      smartRecognition: smartRecognition ?? this.smartRecognition,
      loopCount: loopCount ?? this.loopCount,
      debugMode: debugMode ?? this.debugMode,
      featurePointCount: featurePointCount ?? this.featurePointCount,
      featurePointThreshold: featurePointThreshold ?? this.featurePointThreshold,
    );
  }
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
