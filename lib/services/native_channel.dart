import 'package:flutter/services.dart';

class NativeChannel {
  static const MethodChannel _channel =
      MethodChannel('com.example.isolation/native');

  static Future<bool> startFloatingBall() async {
    try {
      final result = await _channel.invokeMethod<bool>('startFloatingBall');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> stopFloatingBall() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopFloatingBall');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> checkOverlayPermission() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('checkOverlayPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      // Ignore
    }
  }

  static Future<bool> checkAccessibilityPermission() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('checkAccessibilityPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> requestAccessibilityPermission() async {
    try {
      await _channel.invokeMethod('requestAccessibilityPermission');
    } catch (e) {
      // Ignore
    }
  }

  static Future<void> executeAction(
      String type, Map<String, dynamic> params) async {
    try {
      await _channel.invokeMethod('executeAction', {
        'type': type,
        'params': params,
      });
    } catch (e) {
      // Ignore
    }
  }

  static Future<bool> startRecording() async {
    try {
      final result = await _channel.invokeMethod<bool>('startRecording');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> stopRecording() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('stopRecording');
      return result?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> executeMacro(List<Map<String, dynamic>> steps) async {
    try {
      final result = await _channel.invokeMethod<bool>('executeMacro', {
        'steps': steps,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> dispatchClick(int x, int y) async {
    try {
      final result = await _channel.invokeMethod<bool>('dispatchClick', {
        'x': x,
        'y': y,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
