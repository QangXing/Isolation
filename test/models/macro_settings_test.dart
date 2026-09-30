import 'package:flutter_test/flutter_test.dart';
import 'package:isolation/models/macro.dart';
import 'package:isolation/models/macro_log.dart';

void main() {
  group('MacroLogEntry 解析', () {
    test('fromJson 正确解析 timeMillis/type/message', () {
      final entry = MacroLogEntry.fromJson({
        'timeMillis': 1730000000000,
        'type': 'print',
        'message': '签到成功',
      });
      expect(entry.isPrint, true);
      expect(entry.message, '签到成功');
      expect(entry.time.millisecondsSinceEpoch, 1730000000000);
    });

    test('缺省字段回退默认值', () {
      final entry = MacroLogEntry.fromJson({'message': 'hi'});
      expect(entry.isPrint, false);
      expect(entry.message, 'hi');
    });
  });

  group('MacroSettings 定时启动宏序列化', () {
    test('默认值：定时关闭，时间为 08:00', () {
      const settings = MacroSettings();
      expect(settings.scheduleEnabled, false);
      expect(settings.scheduleHour, 8);
      expect(settings.scheduleMinute, 0);
    });

    test('toJson / fromJson 往返保留定时字段', () {
      const settings = MacroSettings(
        scheduleEnabled: true,
        scheduleHour: 23,
        scheduleMinute: 45,
      );
      final decoded = MacroSettings.fromJson(settings.toJson());
      expect(decoded.scheduleEnabled, true);
      expect(decoded.scheduleHour, 23);
      expect(decoded.scheduleMinute, 45);
    });

    test('fromJson 缺省字段时回退默认值（兼容旧宏文件）', () {
      final decoded = MacroSettings.fromJson({
        'loopCount': 1,
        'debugMode': true,
        'featurePointCount': 8,
        'featurePointThreshold': 0.8,
      });
      expect(decoded.scheduleEnabled, false);
      expect(decoded.scheduleHour, 8);
      expect(decoded.scheduleMinute, 0);
      // 旧字段不受影响
      expect(decoded.debugMode, true);
    });

    test('copyWith 修改定时字段保留其他字段', () {
      const settings = MacroSettings(debugMode: true, scheduleEnabled: false);
      final updated = settings.copyWith(
        scheduleEnabled: true,
        scheduleHour: 6,
        scheduleMinute: 30,
      );
      expect(updated.scheduleEnabled, true);
      expect(updated.scheduleHour, 6);
      expect(updated.scheduleMinute, 30);
      expect(updated.debugMode, true);
      expect(updated.featurePointCount, settings.featurePointCount);
    });
  });
}