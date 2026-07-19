import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/macro.dart';
import '../models/plugin.dart';
import '../services/native_channel.dart';
import '../services/plugin_manager.dart';

class PluginProvider extends ChangeNotifier {
  final PluginManager _manager = PluginManager();
  List<Plugin> _plugins = [];
  bool _loaded = false;
  bool _recording = false;
  List<Map<String, dynamic>> _recordedSteps = [];
  String? _runningMacroId;

  List<Plugin> get plugins => _plugins;
  bool get loaded => _loaded;
  bool get recording => _recording;
  List<Map<String, dynamic>> get recordedSteps => _recordedSteps;
  bool get isRunningMacro => _runningMacroId != null;
  String? get runningMacroId => _runningMacroId;

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
    final plugin = _plugins.firstWhere((p) => p.id == id);
    final isMacro = plugin.actions.any((a) => a.type == 'macro');
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
        await _writeEnabledMacro(plugin);
        await NativeChannel.startFloatingBall();
      } else {
        await _clearEnabledMacro();
        await NativeChannel.stopFloatingBall();
      }
    }
    _plugins = List.from(_manager.plugins);
    notifyListeners();
  }

  Future<void> executeAction(PluginAction action) async {
    await NativeChannel.executeAction(action.type, action.params);
  }

  // Recording

  Future<bool> startRecording({bool captureColors = false}) async {
    final hasAccessibility = await NativeChannel.checkAccessibilityPermission();
    if (!hasAccessibility) {
      await NativeChannel.requestAccessibilityPermission();
      return false;
    }
    final started = await NativeChannel.startRecording(captureColors: captureColors);
    if (started) {
      _recording = true;
      _recordedSteps = [];
      notifyListeners();
    }
    return started;
  }

  Future<List<Map<String, dynamic>>> stopRecording() async {
    final steps = await NativeChannel.stopRecording();
    _recording = false;
    _recordedSteps = steps;
    notifyListeners();
    return steps;
  }

  void updateRecordedSteps(List<Map<String, dynamic>> steps) {
    _recordedSteps = steps;
    notifyListeners();
  }

  void clearRecordedSteps() {
    _recordedSteps = [];
    notifyListeners();
  }

  // Macro execution

  Future<void> runEnabledMacro() async {
    final enabledMacro = _plugins.firstWhere(
      (p) => p.enabled && p.actions.any((a) => a.type == 'macro'),
      orElse: () => Plugin(id: '', name: '', version: '', description: '', author: ''),
    );
    if (enabledMacro.id.isEmpty) {
      return;
    }
    await runMacroPlugin(enabledMacro.id);
  }

  Future<bool> runMacroPlugin(String pluginId) async {
    final plugin = _plugins.firstWhere(
      (p) => p.id == pluginId,
      orElse: () => Plugin(id: '', name: '', version: '', description: '', author: ''),
    );
    if (plugin.id.isEmpty) return false;

    final macroAction = plugin.actions.firstWhere(
      (a) => a.type == 'macro',
      orElse: () => PluginAction(type: '', label: '', params: {}),
    );
    if (macroAction.type.isEmpty) return false;

    final macroFile = macroAction.params['macroFile'] as String?;
    if (macroFile == null) return false;

    final pluginDir = await _pluginDirectory();
    final macroPath = '${pluginDir.path}/${plugin.id}/$macroFile';
    final file = File(macroPath);
    if (!await file.exists()) return false;

    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    final macroData = MacroData.fromJson(decoded);

    _runningMacroId = plugin.id;
    notifyListeners();

    final success = await NativeChannel.executeMacro(
      macroData.settings.toJson(),
      macroData.steps,
    );

    _runningMacroId = null;
    notifyListeners();
    return success;
  }

  // Macro data / settings

  Future<MacroData?> loadMacroData(String pluginId) async {
    final plugin = _plugins.firstWhere(
      (p) => p.id == pluginId,
      orElse: () => Plugin(id: '', name: '', version: '', description: '', author: ''),
    );
    if (plugin.id.isEmpty) return null;

    final macroAction = plugin.actions.firstWhere(
      (a) => a.type == 'macro',
      orElse: () => PluginAction(type: '', label: '', params: {}),
    );
    if (macroAction.type.isEmpty) return null;

    final macroFile = macroAction.params['macroFile'] as String?;
    if (macroFile == null) return null;

    final pluginDir = await _pluginDirectory();
    final macroPath = '${pluginDir.path}/${plugin.id}/$macroFile';
    final file = File(macroPath);
    if (!await file.exists()) return null;

    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    return MacroData.fromJson(decoded);
  }

  Future<bool> updateMacroSettings(String pluginId, MacroSettings settings) async {
    final plugin = _plugins.firstWhere(
      (p) => p.id == pluginId,
      orElse: () => Plugin(id: '', name: '', version: '', description: '', author: ''),
    );
    if (plugin.id.isEmpty) return false;

    final macroAction = plugin.actions.firstWhere(
      (a) => a.type == 'macro',
      orElse: () => PluginAction(type: '', label: '', params: {}),
    );
    if (macroAction.type.isEmpty) return false;

    final macroFile = macroAction.params['macroFile'] as String?;
    if (macroFile == null) return false;

    final pluginDir = await _pluginDirectory();
    final macroPath = '${pluginDir.path}/${plugin.id}/$macroFile';
    final file = File(macroPath);
    if (!await file.exists()) return false;

    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    final macroData = MacroData.fromJson(decoded);
    final updated = MacroData(settings: settings, steps: macroData.steps);
    await file.writeAsString(jsonEncode(updated.toJson()));

    // If this is the enabled macro, update the floating ball copy
    if (plugin.enabled) {
      await _writeEnabledMacro(plugin);
    }

    return true;
  }

  // Macro plugin save / export

  Future<bool> saveMacroPlugin({
    required String name,
    required String description,
    required List<Map<String, dynamic>> steps,
    MacroSettings settings = const MacroSettings(),
    String? pluginId,
    String? iconPath,
  }) async {
    if (steps.isEmpty) return false;

    final id = pluginId ?? 'com.example.isolation.macro.${DateTime.now().millisecondsSinceEpoch}';
    final pluginDir = await _pluginDirectory();
    final targetDir = Directory('${pluginDir.path}/$id');
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    final macroFileName = 'macro.json';
    final macroFile = File('${targetDir.path}/$macroFileName');
    final macroData = MacroData(settings: settings, steps: steps);
    await macroFile.writeAsString(jsonEncode(macroData.toJson()));

    final manifest = {
      'id': id,
      'name': name,
      'version': '1.0.0',
      'description': description,
      'author': 'isolation',
      'icon': iconPath != null ? 'icon.png' : null,
      'actions': [
        {
          'type': 'macro',
          'label': '运行$name',
          'macroFile': macroFileName,
        }
      ],
    };

    if (iconPath != null && await File(iconPath).exists()) {
      final destIcon = File('${targetDir.path}/icon.png');
      await File(iconPath).copy(destIcon.path);
    }

    final manifestFile = File('${targetDir.path}/manifest.json');
    await manifestFile.writeAsString(jsonEncode(manifest));

    // Remove old plugin entry if editing
    _plugins.removeWhere((p) => p.id == id);

    final plugin = Plugin.fromManifest(
      manifest,
      iconPath: iconPath != null ? '${targetDir.path}/icon.png' : null,
    );
    _plugins.add(plugin);
    _manager.replacePlugins(_plugins);
    await _manager.savePlugins();
    notifyListeners();
    return true;
  }

  Future<String?> exportMacroPlugin(String pluginId) async {
    final plugin = _plugins.firstWhere(
      (p) => p.id == pluginId,
      orElse: () => Plugin(id: '', name: '', version: '', description: '', author: ''),
    );
    if (plugin.id.isEmpty) return null;

    final pluginDir = await _pluginDirectory();
    final sourceDir = Directory('${pluginDir.path}/$pluginId');
    if (!await sourceDir.exists()) return null;

    final archive = Archive();
    await _addDirectoryToArchive(sourceDir, sourceDir.path, archive);

    final tempDir = await getTemporaryDirectory();
    final exportFile = File('${tempDir.path}/$pluginId.isoplugin');
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) return null;
    await exportFile.writeAsBytes(encoded);
    return exportFile.path;
  }

  Future<void> _writeEnabledMacro(Plugin plugin) async {
    final macroAction = plugin.actions.firstWhere((a) => a.type == 'macro');
    final macroFile = macroAction.params['macroFile'] as String?;
    if (macroFile == null) return;

    final pluginDir = await _pluginDirectory();
    final macroPath = '${pluginDir.path}/${plugin.id}/$macroFile';
    final file = File(macroPath);
    if (!await file.exists()) return;

    final content = await file.readAsString();
    final filesDir = await getApplicationSupportDirectory();
    final enabledMacroFile = File('${filesDir.path}/enabled_macro.json');
    await enabledMacroFile.writeAsString(content);
  }

  Future<void> _clearEnabledMacro() async {
    final filesDir = await getApplicationSupportDirectory();
    final enabledMacroFile = File('${filesDir.path}/enabled_macro.json');
    if (await enabledMacroFile.exists()) {
      await enabledMacroFile.delete();
    }
  }

  Future<void> _addDirectoryToArchive(Directory dir, String rootPath, Archive archive) async {
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final relative = entity.path.substring(rootPath.length + 1);
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relative, bytes.length, bytes));
      }
    }
  }

  Future<Directory> _pluginDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/plugins');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
