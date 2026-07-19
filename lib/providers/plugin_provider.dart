import 'dart:async';
import 'package:flutter/material.dart';
import '../models/macro.dart';
import '../models/plugin.dart';
import '../services/native_channel.dart';
import '../services/plugin_manager.dart';

class PluginProvider extends ChangeNotifier {
  final PluginManager _manager = PluginManager();
  List<Plugin> _plugins = [];
  bool _loaded = false;
  bool _recording = false;
  List<MacroStep> _recordedSteps = [];
  bool _executing = false;
  Timer? _executionTimer;

  List<Plugin> get plugins => _plugins;
  bool get loaded => _loaded;
  bool get recording => _recording;
  List<MacroStep> get recordedSteps => _recordedSteps;
  bool get executing => _executing;

  Future<void> load() async {
    await _manager.loadPlugins();
    _plugins = List.from(_manager.plugins);
    _loaded = true;
    notifyListeners();
  }

  Future<bool> importPlugin(String path) async {
    final result = await _manager.importPlugin(path);
    if (result) {
      _plugins = List.from(_manager.plugins);
      notifyListeners();
    }
    return result;
  }

  Future<void> deletePlugin(String id) async {
    await _manager.deletePlugin(id);
    _plugins = List.from(_manager.plugins);
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final plugin = _plugins.firstWhere((p) => p.id == id);
    final isMacro = plugin.actions.any((a) => a.isMacro);

    if (isMacro && enabled) {
      // only one macro can be enabled at a time
      for (final p in _plugins) {
        if (p.id != id && p.actions.any((a) => a.isMacro)) {
          p.enabled = false;
        }
      }
    }

    plugin.enabled = enabled;
    await _manager.savePlugins();

    if (isMacro) {
      if (enabled) {
        final hasOverlay = await NativeChannel.checkOverlayPermission();
        final hasAccessibility = await NativeChannel.checkAccessibilityPermission();
        if (!hasOverlay) {
          await NativeChannel.requestOverlayPermission();
        }
        if (!hasAccessibility) {
          await NativeChannel.requestAccessibilityPermission();
        }
        await NativeChannel.startFloatingBall();
        await NativeChannel.updateFloatingBallMacro();
      } else {
        final anyMacroEnabled = _plugins.any(
          (p) => p.enabled && p.actions.any((a) => a.isMacro),
        );
        if (!anyMacroEnabled) {
          await NativeChannel.stopFloatingBall();
        }
      }
    }

    _plugins = List.from(_manager.plugins);
    notifyListeners();
  }

  Future<void> executeAction(PluginAction action) async {
    await NativeChannel.executeAction(action.type, action.params);
  }

  Future<bool> startRecording() async {
    final result = await NativeChannel.startRecording();
    if (result) {
      _recording = true;
      _recordedSteps = [];
      notifyListeners();
    }
    return result;
  }

  Future<List<MacroStep>> stopRecording() async {
    final steps = await NativeChannel.stopRecording();
    _recording = false;
    _recordedSteps = steps;
    notifyListeners();
    return steps;
  }

  Future<bool> runMacro(Plugin plugin) async {
    final action = plugin.actions.firstWhere(
      (a) => a.isMacro,
      orElse: () => PluginAction(type: '', label: '', params: {}),
    );
    final steps = await NativeChannel.loadMacroSteps(plugin);
    if (steps == null || steps.isEmpty) return false;
    _executing = true;
    notifyListeners();
    final result = await NativeChannel.executeMacro(
      steps,
      loop: action.loop,
      smartRecognition: action.smartRecognition,
    );
    if (!result) {
      _executing = false;
      notifyListeners();
      return false;
    }
    _startExecutionPolling();
    return true;
  }

  Future<bool> stopMacro() async {
    _stopExecutionPolling();
    final result = await NativeChannel.cancelMacro();
    _executing = false;
    notifyListeners();
    return result;
  }

  void _startExecutionPolling() {
    _executionTimer?.cancel();
    var checking = false;
    _executionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (checking) return;
      checking = true;
      try {
        final stillRunning = await NativeChannel.isMacroExecuting();
        if (!stillRunning && _executing) {
          _executing = false;
          _executionTimer?.cancel();
          _executionTimer = null;
          notifyListeners();
        }
      } finally {
        checking = false;
      }
    });
  }

  void _stopExecutionPolling() {
    _executionTimer?.cancel();
    _executionTimer = null;
  }

  @override
  void dispose() {
    _stopExecutionPolling();
    super.dispose();
  }

  Future<Plugin?> saveMacro({
    required String name,
    String description = '',
    required List<MacroStep> steps,
    required MacroConfig config,
    String? id,
  }) async {
    final plugin = await _manager.saveMacroPlugin(
      name: name,
      description: description,
      steps: steps,
      config: config,
      id: id,
    );
    if (plugin != null) {
      _plugins = List.from(_manager.plugins);
      notifyListeners();
    }
    return plugin;
  }

  Future<String?> exportPlugin(String id) async {
    return _manager.exportPlugin(id);
  }

  Future<bool> updateFloatingBallMacro() async {
    return NativeChannel.updateFloatingBallMacro();
  }
}
