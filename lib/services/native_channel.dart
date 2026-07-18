import 'package:flutter/services.dart';
import '../models/macro.dart';

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

  static Future<bool> startMacroRecording() async {
    try {
      final result = await _channel.invokeMethod<bool>('startMacroRecording');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> stopMacroRecording() async {
    try {
      final result = await _channel.invokeListMethod<Map>('stopMacroRecording');
      if (result == null) return [];
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<bool> executeMacro(Macro macro) async {
    try {
      final result = await _channel.invokeMethod<bool>('executeMacro', {
        'macroId': macro.id,
        'loop': macro.loop,
        'smartRecognition': macro.smartRecognition,
        'steps': macro.steps.map((s) => s.toJson()).toList(),
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> stopMacroExecution() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopMacroExecution');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> isRecording() async {
    try {
      final result = await _channel.invokeMethod<bool>('isRecording');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> isExecuting() async {
    try {
      final result = await _channel.invokeMethod<bool>('isExecuting');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> setMacroConfig(
    String macroId,
    bool loop,
    bool smartRecognition,
    List<Map<String, dynamic>> steps,
  ) async {
    try {
      await _channel.invokeMethod('setMacroConfig', {
        'macroId': macroId,
        'loop': loop,
        'smartRecognition': smartRecognition,
        'steps': steps,
      });
    } catch (e) {
      // Ignore
    }
  }

  static Future<void> showFloatingBallToast(String message) async {
    try {
      await _channel.invokeMethod('showFloatingBallToast', {'message': message});
    } catch (e) {
      // Ignore
    }
  }
}
