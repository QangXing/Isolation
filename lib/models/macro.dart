class PixelColor {
  final int x;
  final int y;
  final int color;

  PixelColor({required this.x, required this.y, required this.color});

  factory PixelColor.fromJson(Map<String, dynamic> json) {
    return PixelColor(
      x: json['x'] as int,
      y: json['y'] as int,
      color: json['color'] as int,
    );
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'color': color};
}

class MacroTarget {
  final String? resourceId;
  final String? text;
  final String? contentDescription;
  final String? className;
  final List<int> bounds;

  MacroTarget({
    this.resourceId,
    this.text,
    this.contentDescription,
    this.className,
    required this.bounds,
  });

  factory MacroTarget.fromJson(Map<String, dynamic> json) {
    return MacroTarget(
      resourceId: json['resourceId'] as String?,
      text: json['text'] as String?,
      contentDescription: json['contentDescription'] as String?,
      className: json['className'] as String?,
      bounds: (json['bounds'] as List<dynamic>?)?.cast<int>() ??
          [0, 0, 0, 0],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'resourceId': resourceId,
      'text': text,
      'contentDescription': contentDescription,
      'className': className,
      'bounds': bounds,
    };
  }
}

class MacroStep {
  final String type;
  final int delay;
  final MacroTarget? target;
  final Map<String, int>? point;
  final Map<String, int>? start;
  final Map<String, int>? end;
  final int? duration;
  final String? packageName;
  final String? text;
  final PixelColor? pixelColor;

  MacroStep({
    required this.type,
    required this.delay,
    this.target,
    this.point,
    this.start,
    this.end,
    this.duration,
    this.packageName,
    this.text,
    this.pixelColor,
  });

  factory MacroStep.fromJson(Map<String, dynamic> json) {
    PixelColor? pixelColor;
    if (json['pixelColor'] != null) {
      pixelColor = PixelColor.fromJson(json['pixelColor'] as Map<String, dynamic>);
    }
    MacroTarget? target;
    if (json['target'] != null) {
      target = MacroTarget.fromJson(json['target'] as Map<String, dynamic>);
    }
    Map<String, int>? parsePoint(String key) {
      final map = json[key] as Map<String, dynamic>?;
      if (map == null) return null;
      return {'x': map['x'] as int, 'y': map['y'] as int};
    }

    return MacroStep(
      type: json['type'] as String,
      delay: json['delay'] as int? ?? 0,
      target: target,
      point: parsePoint('point'),
      start: parsePoint('start'),
      end: parsePoint('end'),
      duration: json['duration'] as int?,
      packageName: json['packageName'] as String?,
      text: json['text'] as String?,
      pixelColor: pixelColor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'delay': delay,
      if (target != null) 'target': target!.toJson(),
      if (point != null) 'point': point,
      if (start != null) 'start': start,
      if (end != null) 'end': end,
      if (duration != null) 'duration': duration,
      if (packageName != null) 'packageName': packageName,
      if (text != null) 'text': text,
      if (pixelColor != null) 'pixelColor': pixelColor!.toJson(),
    };
  }

  String get summary {
    switch (type) {
      case 'clickNode':
        final label = target?.text ?? target?.resourceId ?? target?.className ?? '节点';
        return '点击 $label';
      case 'clickPoint':
        return '点击坐标 (${point?['x']},${point?['y']})';
      case 'swipe':
        return '滑动';
      case 'wait':
        return '等待 ${duration ?? delay}ms';
      case 'back':
        return '返回';
      case 'home':
        return '主页';
      case 'recents':
        return '最近任务';
      case 'launchApp':
        return '打开 $packageName';
      case 'inputText':
        return '输入 "$text"';
      default:
        return type;
    }
  }
}

class MacroConfig {
  final bool loop;
  final bool smartRecognition;

  MacroConfig({this.loop = false, this.smartRecognition = false});

  factory MacroConfig.fromJson(Map<String, dynamic> json) {
    return MacroConfig(
      loop: json['loop'] as bool? ?? false,
      smartRecognition: json['smartRecognition'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'loop': loop,
        'smartRecognition': smartRecognition,
      };
}
