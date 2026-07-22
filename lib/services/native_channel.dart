import 'package:flutter/services.dart';

class NativeChannel {
  static const MethodChannel _channel = MethodChannel('com.example.isolation');

  static Future<bool> checkOverlayPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkOverlayPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> requestOverlayPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestOverlayPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> setFloatingBallIcon(String? imagePath) async {
    try {
      final result = await _channel.invokeMethod<bool>('setFloatingBallIcon', {
        'imagePath': imagePath,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<String?> getFloatingBallIcon() async {
    try {
      return await _channel.invokeMethod<String>('getFloatingBallIcon');
    } catch (e) {
      return null;
    }
  }

  static Future<bool> checkAccessibilityPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkAccessibilityPermission');
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

  static Future<bool> startRecording({bool captureColors = false}) async {
    try {
      final result = await _channel.invokeMethod<bool>('startRecording', {
        'captureColors': captureColors,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> stopRecording() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('stopRecording');
      return result
              ?.map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
              .toList() ??
          [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> executeMacro(
    Map<String, dynamic> settings,
    List<Map<String, dynamic>> steps, {
    String? assetsDir,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('executeMacro', {
        'settings': settings,
        'steps': steps,
        'assetsDir': assetsDir,
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

  static Future<bool> checkScreenCapturePermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkScreenCapturePermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> requestScreenCapturePermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestScreenCapturePermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<int?> captureScreenColor(int x, int y) async {
    try {
      final result = await _channel.invokeMethod<int>('captureScreenColor', {
        'x': x,
        'y': y,
      });
      return result;
    } catch (e) {
      return null;
    }
  }
}
