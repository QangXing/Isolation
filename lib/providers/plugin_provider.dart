import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _floatingBallVisible = false;

  List<Plugin> get plugins => _plugins;
  bool get loaded => _loaded;
  bool get recording => _recording;
  List<Map<String, dynamic>> get recordedSteps => _recordedSteps;
  bool get isRunningMacro => _runningMacroId != null;
  String? get runningMacroId => _runningMacroId;
  bool get floatingBallVisible => _floatingBallVisible;

  Future<void> load() async {
    await _manager.loadPlugins();
    _plugins = List.from(_manager.plugins);
    _loaded = true;

    // 恢复悬浮球显示状态
    final prefs = await SharedPreferences.getInstance();
    _floatingBallVisible = prefs.getBool('floating_ball_visible') ?? false;
    if (_floatingBallVisible) {
      await _startFloatingBallIfReady();
    }

    notifyListeners();
  }

  /// 设置悬浮球显隐开关（独立于宏启用状态）。
  Future<void> setFloatingBallVisible(bool visible) async {
    if (_floatingBallVisible == visible) return;

    final prefs = await SharedPreferences.getInstance();
    _floatingBallVisible = visible;
    await prefs.setBool('floating_ball_visible', visible);

    if (visible) {
      await _startFloatingBallIfReady();
    } else {
      await NativeChannel.stopFloatingBall();
    }
    notifyListeners();
  }

  /// 在拥有悬浮窗权限的前提下启动悬浮球。
  /// 注意：悬浮球仅依赖悬浮窗权限，不依赖辅助功能权限。
  Future<void> _startFloatingBallIfReady() async {
    final hasOverlay = await NativeChannel.checkOverlayPermission();
    if (!hasOverlay) {
      // 权限不足时不启动，也不自动跳转；保持开关开启，用户下次切回可继续操作
      return;
    }
    await NativeChannel.startFloatingBall();
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
        // 启用宏时若没有开启悬浮球，自动开启以便执行；并把状态持久化
        if (!_floatingBallVisible) {
          await setFloatingBallVisible(true);
        } else {
          await NativeChannel.startFloatingBall();
        }
      } else {
        await _clearEnabledMacro();
        // 关闭宏时不影响独立悬浮球开关；用户可在管理页手动关闭
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

    final assetsDir = '${pluginDir.path}/${plugin.id}/assets';
    final success = await NativeChannel.executeMacro(
      macroData.settings.toJson(),
      macroData.steps,
      assetsDir: assetsDir,
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

    // 编辑现有插件时先备份图片资源，避免覆盖式保存导致资源丢失
    String? assetsBackupDir;
    final existingAssetsDir = Directory('${targetDir.path}/assets');
    if (pluginId != null && await existingAssetsDir.exists()) {
      final tempDir = await getTemporaryDirectory();
      assetsBackupDir = '${tempDir.path}/isolation_assets_backup_${DateTime.now().millisecondsSinceEpoch}';
      await existingAssetsDir.rename(assetsBackupDir);
    }

    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    // 恢复备份的图片资源
    if (assetsBackupDir != null) {
      final backupDir = Directory(assetsBackupDir);
      if (await backupDir.exists()) {
        await backupDir.rename(existingAssetsDir.path);
      }
    }

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

  // Macro assets

  /// 将裁剪好的图片复制到插件 assets 目录，返回生成的文件名。
  Future<String?> importMacroAsset(String pluginId, String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) return null;

    final pluginDir = await _pluginDirectory();
    final assetsDir = Directory('${pluginDir.path}/$pluginId/assets');
    if (!await assetsDir.exists()) {
      await assetsDir.create(recursive: true);
    }

    final ext = path.extension(imagePath).toLowerCase();
    final fileName = 'asset_${DateTime.now().millisecondsSinceEpoch}${ext.isEmpty ? '.jpg' : ext}';
    final destFile = File('${assetsDir.path}/$fileName');
    await file.copy(destFile.path);
    return fileName;
  }

  /// 列出插件 assets 目录下的所有文件名。
  Future<List<String>> listMacroAssets(String pluginId) async {
    final pluginDir = await _pluginDirectory();
    final assetsDir = Directory('${pluginDir.path}/$pluginId/assets');
    if (!await assetsDir.exists()) return [];
    final files = await assetsDir.list().toList();
    return files.whereType<File>().map((f) => path.basename(f.path)).toList();
  }

  /// 删除插件 assets 目录下的指定文件。
  Future<bool> deleteMacroAsset(String pluginId, String fileName) async {
    final pluginDir = await _pluginDirectory();
    final file = File('${pluginDir.path}/$pluginId/assets/$fileName');
    if (await file.exists()) {
      await file.delete();
      return true;
    }
    return false;
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
