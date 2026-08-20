/// 多球 DSL 解析后的程序结构。
///
/// 一个 `floater.dsl` 可以包含一个主球、多个副球，以及全局流程步骤。
class FloaterProgram {
  final List<FloaterBall> balls;
  final List<Map<String, dynamic>> steps;

  const FloaterProgram({
    required this.balls,
    required this.steps,
  });

  Map<String, dynamic> toJson() => {
        'balls': balls.map((b) => b.toJson()).toList(),
        'steps': steps,
      };

  factory FloaterProgram.fromJson(Map<String, dynamic> json) {
    final ballsJson = json['balls'] as List<dynamic>? ?? [];
    final stepsJson = json['steps'] as List<dynamic>? ?? [];
    return FloaterProgram(
      balls: ballsJson
          .map((e) => FloaterBall.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      steps: stepsJson.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }

  /// 获取主球，理论上必须存在。
  FloaterBall? get mainBall {
    try {
      return balls.firstWhere((b) => b.role == 'main');
    } catch (_) {
      return null;
    }
  }

  /// 获取所有副球。
  List<FloaterBall> get deputyBalls =>
      balls.where((b) => b.role == 'deputy').toList();
}

/// 单个球的声明。
class FloaterBall {
  final String role;
  final String name;
  final int? size;
  final int? cornerRadius;
  final String? image;
  final dynamic locationX;
  final dynamic locationY;
  final bool? visible;
  final String? followTarget;
  final int? followDx;
  final int? followDy;
  final List<Map<String, dynamic>> steps;

  const FloaterBall({
    required this.role,
    required this.name,
    this.size,
    this.cornerRadius,
    this.image,
    this.locationX,
    this.locationY,
    this.visible,
    this.followTarget,
    this.followDx,
    this.followDy,
    required this.steps,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'name': name,
        if (size != null) 'size': size,
        if (cornerRadius != null) 'cornerRadius': cornerRadius,
        if (image != null) 'image': image,
        if (locationX != null) 'locationX': locationX,
        if (locationY != null) 'locationY': locationY,
        if (visible != null) 'visible': visible,
        if (followTarget != null) 'followTarget': followTarget,
        if (followDx != null) 'followDx': followDx,
        if (followDy != null) 'followDy': followDy,
        'steps': steps,
      };

  factory FloaterBall.fromJson(Map<String, dynamic> json) {
    final stepsJson = json['steps'] as List<dynamic>? ?? [];
    return FloaterBall(
      role: json['role'] as String? ?? 'deputy',
      name: json['name'] as String? ?? '',
      size: json['size'] as int?,
      cornerRadius: json['cornerRadius'] as int?,
      image: json['image'] as String?,
      locationX: json['locationX'],
      locationY: json['locationY'],
      visible: json['visible'] as bool?,
      followTarget: json['followTarget'] as String?,
      followDx: json['followDx'] as int?,
      followDy: json['followDy'] as int?,
      steps: stepsJson.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }
}
