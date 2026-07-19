import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/macro.dart';
import '../models/plugin.dart';

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

  static Future<bool> updateFloatingBallMacro() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('updateFloatingBallMacro');
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

  static Future<List<MacroStep>> stopRecording() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('stopRecording');
      if (result == null) return [];
      return result
          .map((e) => MacroStep.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      return [];
    }
  }

  static Future<bool> executeMacro(
    List<MacroStep> steps, {
    bool loop = false,
    bool smartRecognition = false,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('executeMacro', {
        'steps': steps.map((s) => s.toJson()).toList(),
        'loop': loop,
        'smartRecognition': smartRecognition,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> cancelMacro() async {
    try {
      final result = await _channel.invokeMethod<bool>('cancelMacro');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> isMacroExecuting() async {
    try {
      final result = await _channel.invokeMethod<bool>('isMacroExecuting');
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

  static Future<List<MacroStep>?> loadMacroSteps(Plugin plugin) async {
    final action = plugin.actions.firstWhere(
      (a) => a.isMacro,
      orElse: () => PluginAction(type: '', label: '', params: {}),
    );
    final macroFile = action.macroFile;
    if (macroFile == null || macroFile.isEmpty) return null;

    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/plugins/${plugin.id}/$macroFile');
    if (!await file.exists()) return null;

    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final steps = (json['steps'] as List<dynamic>? ?? [])
        .map((e) => MacroStep.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return steps;
  }
}
