import 'package:flutter_test/flutter_test.dart';
import 'package:isolation/models/macro.dart';

void main() {
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