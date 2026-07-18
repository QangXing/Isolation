import 'package:flutter/material.dart';
import '../models/plugin.dart';
import '../services/native_channel.dart';
import '../services/plugin_manager.dart';

class PluginProvider extends ChangeNotifier {
  final PluginManager _manager = PluginManager();
  List<Plugin> _plugins = [];
  bool _loaded = false;

  List<Plugin> get plugins => _plugins;
  bool get loaded => _loaded;

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
    await _manager.setEnabled(id, enabled);
    if (id == 'com.example.isolation.floating_keyboard') {
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
      } else {
        await NativeChannel.stopFloatingBall();
      }
    }
    _plugins = List.from(_manager.plugins);
    notifyListeners();
  }

  Future<void> executeAction(PluginAction action) async {
    await NativeChannel.executeAction(action.type, action.params);
  }
}
