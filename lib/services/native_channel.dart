import 'dart:convert';
import 'package:flutter/services.dart';

class NativeChannel {
  /// Must match `MainActivity.CHANNEL` on the Android side.
  static const String channelName = 'com.qangxing.isolation';
  static const MethodChannel _channel = MethodChannel(channelName);

  static Future<bool> checkOverlayPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkOverlayPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 检查 Android 13 (API 33)+ 的通知运行时权限。
  /// 低版本始终返回 true（通知权限不需要运行时请求）。
  static Future<bool> checkNotificationPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkNotificationPermission');
      return result ?? true;
    } catch (e) {
      return true;
    }
  }

  /// 请求通知权限（Android 13+ 生效）。用于确保前台服务的通知能正常显示。
  static Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (e) {
      // Ignore
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

  static Future<bool> applyDefaultFloaterConfig({
    required int cornerRadius,
    required int size,
    String? imagePath,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('applyDefaultFloaterConfig', {
        'cornerRadius': cornerRadius,
        'size': size,
        'imagePath': imagePath,
      });
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

  static Future<bool> isFloatingBallRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isFloatingBallRunning');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> checkManageExternalStorage() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkManageExternalStorage');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> requestManageExternalStorage() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestManageExternalStorage');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 注册并显示一组悬浮球（多球插件）。
  ///
  /// [program] 为 [FloaterProgram.toJson()] 后的结构，包含 balls 与 steps。
  static Future<bool> registerFloaters(
    Map<String, dynamic> program,
    String pluginId, {
    String? assetsDir,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('registerFloaters', {
        'pluginId': pluginId,
        'program': program,
        'assetsDir': assetsDir,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 清除当前显示的所有插件球（禁用编程球时调用）。
  static Future<bool> unregisterFloaters() async {
    try {
      final result = await _channel.invokeMethod<bool>('unregisterFloaters');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 获取指定名称悬浮球的当前位置。
  static Future<Map<String, dynamic>?> getFloaterPosition(String name) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getFloaterPosition',
        {'name': name},
      );
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return null;
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

  /// 开始录制会话。返回是否成功启动。
  ///
  /// [gestureMode] 为 true 时挂载全屏手势捕获层，背景不可直接点击，但能录滑动/拖拽；
  /// [shizukuMode] 为 true 时通过 Shizuku 读取系统输入事件，背景可正常交互且能录滑动。
  /// 两者同时开启时 Shizuku 模式优先。
  static Future<bool> startRecordingSession({
    String mode = 'simple',
    bool captureColors = false,
    bool recordSystemKeys = true,
    int minClickIntervalMs = 100,
    bool replayGestures = true,
    bool gestureMode = false,
    bool shizukuMode = false,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('startRecordingSession', {
        'mode': mode,
        'captureColors': captureColors,
        'recordSystemKeys': recordSystemKeys,
        'minClickIntervalMs': minClickIntervalMs,
        'replayGestures': replayGestures,
        'gestureMode': gestureMode,
        'shizukuMode': shizukuMode,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 检查 Shizuku 状态。
  /// 返回 0=就绪，1=未安装，2=服务未运行，3=未授权。
  static Future<int> checkShizukuState() async {
    try {
      return await _channel.invokeMethod<int>('checkShizukuState') ?? 1;
    } catch (e) {
      return 1;
    }
  }

  /// 请求 Shizuku 授权。
  static Future<void> requestShizukuPermission() async {
    try {
      await _channel.invokeMethod('requestShizukuPermission');
    } catch (e) {
      // Ignore
    }
  }

  /// 打开 Shizuku 应用（未安装时跳转到官网）。
  static Future<void> openShizuku() async {
    try {
      await _channel.invokeMethod('openShizuku');
    } catch (e) {
      // Ignore
    }
  }

  /// 暂停录制（移除捕获层，可正常使用手机）。
  static Future<void> pauseRecording() async {
    try {
      await _channel.invokeMethod('pauseRecording');
    } catch (e) {
      // Ignore
    }
  }

  /// 继续录制（重新挂载捕获层）。
  static Future<void> resumeRecording() async {
    try {
      await _channel.invokeMethod('resumeRecording');
    } catch (e) {
      // Ignore
    }
  }

  /// 结束录制：原生侧完成指令后处理并持久化结果，随后回到 App 编辑页。
  static Future<void> finishRecording() async {
    try {
      await _channel.invokeMethod('finishRecording');
    } catch (e) {
      // Ignore
    }
  }

  /// 取消录制（丢弃结果）。
  static Future<void> cancelRecording() async {
    try {
      await _channel.invokeMethod('cancelRecording');
    } catch (e) {
      // Ignore
    }
  }

  /// 查询原生侧录制会话状态（state / stepCount / mode）。
  static Future<Map<String, dynamic>?> getRecordingState() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getRecordingState');
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return null;
    }
  }

  /// 读取并消费待处理录制结果（读取后原生侧文件即被清除）。
  static Future<Map<String, dynamic>?> consumePendingRecordingResult() async {
    try {
      final raw = await _channel.invokeMethod<String>('consumePendingRecordingResult');
      if (raw == null) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map<dynamic, dynamic>);
    } catch (e) {
      return null;
    }
  }

  static Future<bool> executeMacro(
    Map<String, dynamic> settings,
    List<Map<String, dynamic>> steps, {
    String? assetsDir,
    String? pluginId,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('executeMacro', {
        'settings': settings,
        'steps': steps,
        'assetsDir': assetsDir,
        'pluginId': pluginId,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 查询当前是否有宏正在原生侧运行。
  static Future<bool> isMacroRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isMacroRunning') ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 读取某宏的执行日志（时间升序，最多 300 条）。
  static Future<List<Map<String, dynamic>>> getMacroLogs(String pluginId) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getMacroLogs', {
        'pluginId': pluginId,
      });
      return result
              ?.map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
              .toList() ??
          [];
    } catch (e) {
      return [];
    }
  }

  /// 清空某宏的执行日志。
  static Future<bool> clearMacroLogs(String pluginId) async {
    try {
      final result = await _channel.invokeMethod<bool>('clearMacroLogs', {
        'pluginId': pluginId,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 注册指定宏的每日定时触发；[enabled] 为 false 时取消该宏的定时。
  static Future<bool> setMacroSchedule({
    required String pluginId,
    required String macroFile,
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('setMacroSchedule', {
        'pluginId': pluginId,
        'macroFile': macroFile,
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 取消某宏的每日定时。
  static Future<bool> clearMacroSchedule(String pluginId) async {
    try {
      final result = await _channel.invokeMethod<bool>('clearMacroSchedule', {
        'pluginId': pluginId,
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

  /// 开启 / 关闭通知栏状态通知（展示运行状态与宏 print 输出）。
  static Future<bool> setStatusNotificationEnabled(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<bool>('setStatusNotificationEnabled', {
        'enabled': enabled,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 查询通知栏状态通知是否开启（以原生持久化状态为准）。
  static Future<bool> isStatusNotificationEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isStatusNotificationEnabled');
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
