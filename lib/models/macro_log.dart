/// 单条宏执行日志。
class MacroLogEntry {
  final DateTime time;
  final String type;
  final String message;

  const MacroLogEntry({
    required this.time,
    required this.type,
    required this.message,
  });

  factory MacroLogEntry.fromJson(Map<String, dynamic> json) {
    return MacroLogEntry(
      time: DateTime.fromMillisecondsSinceEpoch(
        (json['timeMillis'] as num?)?.toInt() ?? 0,
      ),
      type: json['type'] as String? ?? 'status',
      message: json['message'] as String? ?? '',
    );
  }

  bool get isPrint => type == 'print';
}