class FloaterConfig {
  final int cornerRadius;
  final int size;
  final String? imagePath;

  const FloaterConfig({
    this.cornerRadius = 28,
    this.size = 56,
    this.imagePath,
  });

  Map<String, dynamic> toJson() => {
        'cornerRadius': cornerRadius,
        'size': size,
        if (imagePath != null) 'imagePath': imagePath,
      };

  factory FloaterConfig.fromJson(Map<String, dynamic> json) => FloaterConfig(
        cornerRadius: (json['cornerRadius'] as num?)?.toInt() ?? 28,
        size: (json['size'] as num?)?.toInt() ?? 56,
        imagePath: json['imagePath'] as String?,
      );

  FloaterConfig copyWith({int? cornerRadius, int? size, String? imagePath}) =>
      FloaterConfig(
        cornerRadius: cornerRadius ?? this.cornerRadius,
        size: size ?? this.size,
        imagePath: imagePath ?? this.imagePath,
      );
}
