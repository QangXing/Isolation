import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/floater_config.dart';
import '../models/floater_program.dart';
import '../models/macro.dart';
import '../models/macro_log.dart';
import '../models/plugin.dart';
import '../services/floater_dsl_v2_parser.dart';
import '../services/macro_program_parser.dart';
import '../services/native_channel.dart';
import '../services/plugin_manager.dart';

class PluginProvider extends ChangeNotifier {
  final PluginManager _manager = PluginManager();
  List<Plugin> _plugins = [];
  bool _loaded = false;
  String? _runningMacroId;
  bool _floatingBallVisible = false;

  List<Plugin> get plugins => _plugins;
  bool get loaded => _loaded;
  bool get isRunningMacro => _runningMacroId != null;
  String? get runningMacroId => _runningMacroId;
  bool get floatingBallVisible => _floatingBallVisible;

  static const _defaultFloaterConfigKey = 'default_floater_config';

  Future<FloaterConfig> loadDefaultFloaterConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_defaultFloaterConfigKey);
    FloaterConfig config;
    if (raw == null) {
      config = const FloaterConfig();
    } else {
      try {
        config = FloaterConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        config = const FloaterConfig();
      }
    }
    // 若 Flutter 侧未记录图标路径，尝试从 Native 侧获取已设置的自定义图标
    if (config.imagePath == null || config.imagePath!.isEmpty) {
      final nativeIcon = await NativeChannel.getFloatingBallIcon();
      if (nativeIcon != null && nativeIcon.isNotEmpty) {
        config = config.copyWith(imagePath: nativeIcon);
      }
    }
    return config;
  }

  Future<void> saveDefaultFloaterConfig(FloaterConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultFloaterConfigKey, jsonEncode(config.toJson()));
    // 同步到正在运行的悬浮球服务，确保修改实时生效（包括开机自启场景）
    await NativeChannel.applyDefaultFloaterConfig(
      cornerRadius: config.cornerRadius,
      size: config.size,
      imagePath: config.imagePath,
    );
  }

  Future<void> load() async {
    await _manager.loadPlugins();
    _plugins = List.from(_manager.plugins);
    _loaded = true;

    // 恢复悬浮球显示状态
    final prefs = await SharedPreferences.getInstance();
    _floatingBallVisible = prefs.getBool('floating_ball_visible') ?? false;
    if (_floatingBallVisible) {
      final ok = await _startFloatingBallIfReady();
      if (!ok) {
        // 启动失败时清除持久化状态，避免应用启动即崩溃
        _floatingBallVisible = false;
        await prefs.setBool('floating_ball_visible', false);
      } else {
        // 启动成功后立即应用默认悬浮球配置，确保开机自启/恢复显示时参数与设置一致
        final config = await loadDefaultFloaterConfig();
        await NativeChannel.applyDefaultFloaterConfig(
          cornerRadius: config.cornerRadius,
          size: config.size,
          imagePath: config.imagePath,
        );
      }
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
      final ok = await _startFloatingBallIfReady();
      if (ok) {
        // 开启后立即应用默认悬浮球配置（含当前自定义图标），确保与设置页一致
        final config = await loadDefaultFloaterConfig();
        final iconPath = await NativeChannel.getFloatingBallIcon();
        await NativeChannel.applyDefaultFloaterConfig(
          cornerRadius: config.cornerRadius,
          size: config.size,
          imagePath: iconPath,
        );
      } else {
        // 启动失败时回退状态，避免下次进入应用再次尝试启动导致闪退
        _floatingBallVisible = false;
        await prefs.setBool('floating_ball_visible', false);
      }
    } else {
      await NativeChannel.stopFloatingBall();
    }
    notifyListeners();
  }

  /// 在拥有悬浮窗权限的前提下启动悬浮球。
  /// 注意：悬浮球仅依赖悬浮窗权限，不依赖辅助功能权限。
  /// 返回是否真正成功启动并存活。
  Future<bool> _startFloatingBallIfReady() async {
    final hasOverlay = await NativeChannel.checkOverlayPermission();
    if (!hasOverlay) {
      // 权限不足时不启动，也不自动跳转
      return false;
    }
    final started = await NativeChannel.startFloatingBall();
    if (!started) return false;
    // startForegroundService 是异步的，轮询最多 1 秒确认服务实例真的存活
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (await NativeChannel.isFloatingBallRunning()) return true;
    }
    return false;
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
    // 删除宏时同步取消其每日定时
    final plugin = _plugins.firstWhere(
      (p) => p.id == id,
      orElse: () => Plugin(id: '', name: '', version: '', description: '', author: ''),
    );
    if (plugin.id.isNotEmpty && plugin.actions.any((a) => a.type == 'macro')) {
      await NativeChannel.clearMacroSchedule(id);
    }
    await _manager.deletePlugin(id);
    _plugins = List.from(_manager.plugins);
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _manager.setEnabled(id, enabled);
    final plugin = _plugins.firstWhere((p) => p.id == id);
    final isMacro = plugin.actions.any((a) => a.type == 'macro');
    final isFloater = plugin.isFloater;
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
        // 启用宏时同步其定时启动配置（读取 macro.json 中的设置）
        final macroData = await loadMacroData(id);
        if (macroData != null) {
          await _syncMacroSchedule(plugin, macroData.settings);
        }
        // 启用宏时若没有开启悬浮球，自动开启以便执行
        bool ballStarted;
        if (!_floatingBallVisible) {
          await setFloatingBallVisible(true);
          ballStarted = _floatingBallVisible;
        } else {
          // 即使开关是开的状态，也要确认服务实例真的在运行
          ballStarted = await NativeChannel.isFloatingBallRunning() ||
              await _startFloatingBallIfReady();
        }
        // 悬浮球启动失败时回退宏启用状态，避免服务异常导致反复崩溃
        if (!ballStarted) {
          await _clearEnabledMacro();
          await _manager.setEnabled(id, false);
          _plugins = List.from(_manager.plugins);
          notifyListeners();
          return;
        }
      } else {
        await _clearEnabledMacro();
        // 禁用宏时同步取消其每日定时
        await NativeChannel.clearMacroSchedule(id);
        // 关闭宏时不影响独立悬浮球开关；用户可在管理页手动关闭
      }
    } else if (isFloater && enabled) {
      final hasOverlay = await NativeChannel.checkOverlayPermission();
      if (!hasOverlay) {
        await NativeChannel.requestOverlayPermission();
      }
      bool ballStarted;
      if (!_floatingBallVisible) {
        await setFloatingBallVisible(true);
        ballStarted = _floatingBallVisible;
      } else {
        ballStarted = await NativeChannel.isFloatingBallRunning() ||
            await _startFloatingBallIfReady();
      }
      if (!ballStarted) {
        await _manager.setEnabled(id, false);
        _plugins = List.from(_manager.plugins);
        notifyListeners();
        return;
      }
      // 球文件未声明外观参数时，以默认悬浮球参数为准
      final config = await loadDefaultFloaterConfig();
      await NativeChannel.applyDefaultFloaterConfig(
        cornerRadius: config.cornerRadius,
        size: config.size,
        imagePath: config.imagePath,
      );
      final program = await loadFloaterProgram(plugin.id);
      if (program != null) {
        final pluginDir = await _pluginDirectory();
        final assetsDir = '${pluginDir.path}/${plugin.id}/assets';
        await NativeChannel.registerFloaters(
          program,
          plugin.id,
          assetsDir: assetsDir,
        );
      }
    } else if (isFloater && !enabled) {
      // 禁用编程球时清除屏幕上的插件球
      await NativeChannel.unregisterFloaters();
      // 若默认悬浮球开关仍开启，恢复显示默认悬浮球
      if (_floatingBallVisible) {
        final ok = await _startFloatingBallIfReady();
        if (ok) {
          final config = await loadDefaultFloaterConfig();
          final iconPath = await NativeChannel.getFloatingBallIcon();
          await NativeChannel.applyDefaultFloaterConfig(
            cornerRadius: config.cornerRadius,
            size: config.size,
            imagePath: iconPath,
          );
        }
      }
    }
    _plugins = List.from(_manager.plugins);
    notifyListeners();
  }

  Future<void> executeAction(PluginAction action) async {
    await NativeChannel.executeAction(action.type, action.params);
  }

  Future<bool> updatePluginPin(String pluginId, bool pinned) async {
    await _manager.setPinned(pluginId, pinned);
    _plugins = List.from(_manager.plugins);
    notifyListeners();
    return true;
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
      pluginId: plugin.id,
    );
    if (!success) {
      _runningMacroId = null;
      notifyListeners();
      return false;
    }
    // executeMacro 只负责启动原生线程，这里后台轮询原生执行状态，
    // 宏真正结束后才清除"运行中"标记
    _pollMacroRunning(plugin.id);
    return true;
  }

  /// 轮询原生宏执行状态，结束后清除"运行中"标记。
  Future<void> _pollMacroRunning(String pluginId) async {
    while (_runningMacroId == pluginId) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (_runningMacroId != pluginId) return;
      if (!await NativeChannel.isMacroRunning()) {
        _runningMacroId = null;
        notifyListeners();
        return;
      }
    }
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

  /// 更新宏插件的元数据（名称、简介、图标）与运行设置。
  Future<bool> updateMacroMetadata(
    String pluginId, {
    required String name,
    required String description,
    required MacroSettings settings,
    String? iconName,
  }) async {
    final pluginIndex = _plugins.indexWhere((p) => p.id == pluginId);
    if (pluginIndex < 0) return false;

    final plugin = _plugins[pluginIndex];
    final pluginDir = await _pluginDirectory();

    // 更新 manifest.json
    final manifestFile = File('${pluginDir.path}/$pluginId/manifest.json');
    if (await manifestFile.exists()) {
      final manifestContent = await manifestFile.readAsString();
      final manifest = jsonDecode(manifestContent) as Map<String, dynamic>;
      manifest['name'] = name;
      manifest['description'] = description;
      if (iconName != null) {
        manifest['iconName'] = iconName;
      }
      await manifestFile.writeAsString(jsonEncode(manifest));
    }

    // 更新 macro.json 中的 settings
    final macroAction = plugin.actions.firstWhere(
      (a) => a.type == 'macro',
      orElse: () => PluginAction(type: '', label: '', params: {}),
    );
    final macroFileName = macroAction.params['macroFile'] as String?;
    if (macroFileName != null) {
      final macroFile = File('${pluginDir.path}/$pluginId/$macroFileName');
      if (await macroFile.exists()) {
        final content = await macroFile.readAsString();
        final decoded = jsonDecode(content);
        final macroData = MacroData.fromJson(decoded);
        final updated = MacroData(settings: settings, steps: macroData.steps);
        await macroFile.writeAsString(jsonEncode(updated.toJson()));
      }
    }

    // 更新内存模型并持久化插件列表
    final updatedPlugin = Plugin(
      id: plugin.id,
      name: name,
      version: plugin.version,
      description: description,
      author: plugin.author,
      iconPath: plugin.iconPath,
      iconName: iconName ?? plugin.iconName,
      builtIn: plugin.builtIn,
      actions: plugin.actions,
      enabled: plugin.enabled,
      pinned: plugin.pinned,
      pinnedAt: plugin.pinnedAt,
    );
    _plugins[pluginIndex] = updatedPlugin;
    // 同步 PluginManager 单例内部的插件列表，否则 savePlugins 序列化的仍是旧数据，
    // 导致应用重启后名称/简介/图标读回旧值
    _manager.replacePlugins(_plugins);
    await _manager.savePlugins();

    // 若当前为启用宏，同步更新悬浮球侧缓存
    if (updatedPlugin.enabled) {
      await _writeEnabledMacro(updatedPlugin);
    }

    // 同步定时启动宏配置：启用中的宏按设置注册/取消每日定时
    await _syncMacroSchedule(updatedPlugin, settings);

    notifyListeners();
    return true;
  }

  /// 读取某宏的执行日志（时间升序，最多 300 条）。
  Future<List<MacroLogEntry>> loadMacroLogs(String pluginId) async {
    final raw = await NativeChannel.getMacroLogs(pluginId);
    return raw
        .map((e) => MacroLogEntry.fromJson(e))
        .toList();
  }

  /// 清空某宏的执行日志。
  Future<void> clearMacroLogs(String pluginId) async {
    await NativeChannel.clearMacroLogs(pluginId);
  }

  /// 更新编程球（floaterPlugin）的元数据（名称、简介）。
  /// 与宏插件不同：同时更新 manifest.json 与 SharedPreferences 中的插件列表，
  /// 避免直接写 manifest 后调用 load() 仍读回旧数据。
  Future<bool> updateFloaterMetadata(
    String pluginId, {
    required String name,
    required String description,
    String? iconName,
    String? iconPath,
  }) async {
    final pluginIndex = _plugins.indexWhere((p) => p.id == pluginId);
    if (pluginIndex < 0) return false;

    final plugin = _plugins[pluginIndex];
    final pluginDir = await _pluginDirectory();
    final targetDir = Directory('${pluginDir.path}/$pluginId');

    // 更新 manifest.json
    final manifestFile = File('${targetDir.path}/manifest.json');
    String? effectiveIconPath = plugin.iconPath;
    if (await manifestFile.exists()) {
      final manifestContent = await manifestFile.readAsString();
      final manifest = jsonDecode(manifestContent) as Map<String, dynamic>;
      manifest['name'] = name;
      manifest['description'] = description;
      if (iconName != null) {
        manifest['iconName'] = iconName;
      }
      if (iconPath != null && await File(iconPath).exists()) {
        final ext = path.extension(iconPath);
        final iconFileName = 'icon$ext';
        final destIcon = File('${targetDir.path}/$iconFileName');
        await File(iconPath).copy(destIcon.path);
        manifest['icon'] = iconFileName;
        effectiveIconPath = destIcon.path;
      } else if (iconPath == null && iconName == null && plugin.iconName == null) {
        // 显式恢复默认时不保留自定义图标
        manifest.remove('icon');
        effectiveIconPath = null;
      }
      await manifestFile.writeAsString(jsonEncode(manifest));
    }

    // 更新内存模型并持久化插件列表
    final updatedPlugin = Plugin(
      id: plugin.id,
      name: name,
      version: plugin.version,
      description: description,
      author: plugin.author,
      iconPath: effectiveIconPath,
      iconName: iconName ?? plugin.iconName,
      builtIn: plugin.builtIn,
      actions: plugin.actions,
      enabled: plugin.enabled,
      type: plugin.type,
      pinned: plugin.pinned,
      pinnedAt: plugin.pinnedAt,
    );
    _plugins[pluginIndex] = updatedPlugin;
    // 同步 PluginManager 单例内部的插件列表，否则 savePlugins 序列化的仍是旧数据
    _manager.replacePlugins(_plugins);
    await _manager.savePlugins();

    notifyListeners();
    return true;
  }

  // Macro plugin save / export

  Future<bool> saveMacroPlugin({
    required String name,
    required String description,
    required List<Map<String, dynamic>> steps,
    MacroSettings? settings,
    String? pluginId,
    String? iconPath,
  }) async {
    if (steps.isEmpty) return false;

    final id = pluginId ?? 'com.qangxing.isolation.macro.${DateTime.now().millisecondsSinceEpoch}';
    final pluginDir = await _pluginDirectory();
    final targetDir = Directory('${pluginDir.path}/$id');

    // 编辑现有插件时先读取原 settings 与备份图片资源，避免覆盖式保存导致设置/资源丢失
    MacroSettings? existingSettings;
    String? assetsBackupDir;
    final existingAssetsDir = Directory('${targetDir.path}/assets');
    if (pluginId != null && await targetDir.exists()) {
      final existingMacroFile = File('${targetDir.path}/macro.json');
      if (await existingMacroFile.exists()) {
        try {
          final decoded = jsonDecode(await existingMacroFile.readAsString());
          existingSettings = MacroData.fromJson(decoded).settings;
        } catch (_) {
          // 忽略损坏的旧文件
        }
      }
      if (await existingAssetsDir.exists()) {
        final tempDir = await getTemporaryDirectory();
        assetsBackupDir = '${tempDir.path}/isolation_assets_backup_${DateTime.now().millisecondsSinceEpoch}';
        await existingAssetsDir.rename(assetsBackupDir);
      }
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
    final effectiveSettings = settings ?? existingSettings ?? const MacroSettings();
    final macroData = MacroData(settings: effectiveSettings, steps: steps);
    await macroFile.writeAsString(jsonEncode(macroData.toJson()));

    final ext = iconPath != null ? path.extension(iconPath) : '';
    final iconFileName = iconPath != null ? 'icon$ext' : null;

    final manifest = {
      'id': id,
      'name': name,
      'version': '1.0.0',
      'description': description,
      'author': 'isolation',
      'icon': iconFileName,
      'actions': [
        {
          'type': 'macro',
          'label': '运行$name',
          'macroFile': macroFileName,
        }
      ],
    };

    if (iconPath != null && await File(iconPath).exists()) {
      final destIcon = File('${targetDir.path}/$iconFileName');
      await File(iconPath).copy(destIcon.path);
    }

    final manifestFile = File('${targetDir.path}/manifest.json');
    await manifestFile.writeAsString(jsonEncode(manifest));

    // 编辑时保留置顶状态
    final oldPlugin = _plugins.firstWhere(
      (p) => p.id == id,
      orElse: () => Plugin(id: id, name: name, version: '', description: '', author: ''),
    );

    // Remove old plugin entry if editing
    _plugins.removeWhere((p) => p.id == id);

    final plugin = Plugin.fromManifest(
      manifest,
      iconPath: iconPath != null ? '${targetDir.path}/$iconFileName' : null,
    );
    plugin.pinned = oldPlugin.pinned;
    plugin.pinnedAt = oldPlugin.pinnedAt;
    _plugins.add(plugin);
    _manager.replacePlugins(_plugins);
    await _manager.savePlugins();
    notifyListeners();
    return true;
  }

  // Floater plugin save / load

  Future<bool> saveFloaterPlugin({
    required String name,
    required String description,
    required String source,
    String? pluginId,
  }) async {
    final id = pluginId ?? 'com.qangxing.isolation.floater.${DateTime.now().millisecondsSinceEpoch}';
    final pluginDir = await _pluginDirectory();
    final targetDir = Directory('${pluginDir.path}/$id');

    // 保留已有插件目录，避免清空已导入的 assets 与设置文件。
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    // 检测 DSL 版本：以 floater "..." { 开头为 v2，否则为 v1。
    final dslVersion = source.trim().startsWith('floater ') ? 2 : 1;

    Map<String, dynamic>? programJson;
    List<Map<String, dynamic>> fallbackSteps = [];
    if (dslVersion == 2) {
      try {
        final program = FloaterDslV2Parser.parse(source);
        programJson = program.toJson();
      } catch (_) {
        // v2 解析失败时回退到 v1 解析器，兼容旧写法
      }
    }
    if (programJson == null) {
      try {
        final program = MacroProgramParser.parseFloaterProgram(source);
        programJson = program.toJson();
      } catch (_) {
        fallbackSteps = MacroProgramParser.parse(source);
        programJson = {'dslVersion': 1, 'balls': [], 'steps': fallbackSteps};
      }
    }

    // 保留原插件的启用状态与图标设置，避免保存后设置被清空。
    final oldPlugin = _plugins.firstWhere(
      (p) => p.id == id,
      orElse: () => Plugin(
        id: id,
        name: name,
        version: '1.0.0',
        description: description,
        author: 'user',
        type: 'floaterPlugin',
      ),
    );

    final manifest = {
      'id': id,
      'type': 'floaterPlugin',
      'name': name,
      'version': '1.0.0',
      'description': description,
      'author': 'user',
      'iconName': oldPlugin.iconName ?? 'favorite',
      'dslVersion': dslVersion,
    };

    await File('${targetDir.path}/manifest.json').writeAsString(jsonEncode(manifest));
    await File('${targetDir.path}/floater.dsl').writeAsString(source);
    await File('${targetDir.path}/floater.json').writeAsString(jsonEncode(programJson));
    await Directory('${targetDir.path}/assets').create(recursive: true);

    _plugins.removeWhere((p) => p.id == id);
    final plugin = Plugin.fromManifest(
      manifest,
      iconPath: oldPlugin.iconPath,
      iconName: oldPlugin.iconName,
    );
    plugin.enabled = oldPlugin.enabled;
    plugin.pinned = oldPlugin.pinned;
    plugin.pinnedAt = oldPlugin.pinnedAt;
    _plugins.add(plugin);
    _manager.replacePlugins(_plugins);
    await _manager.savePlugins();
    notifyListeners();
    return true;
  }

  Future<String?> loadFloaterSource(String pluginId) async {
    final pluginDir = await _pluginDirectory();
    final file = File('${pluginDir.path}/$pluginId/floater.dsl');
    if (await file.exists()) return file.readAsString();
    return null;
  }

  Future<Map<String, dynamic>?> loadFloaterProgram(String pluginId) async {
    final pluginDir = await _pluginDirectory();
    final file = File('${pluginDir.path}/$pluginId/floater.json');
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    // 旧格式：floater.json 是纯步骤列表，包装成 v1 默认主球
    if (decoded is List) {
      return {
        'dslVersion': 1,
        'balls': [
          {
            'role': 'main',
            'name': 'main',
            'steps': decoded.cast<Map<String, dynamic>>(),
          }
        ],
        'steps': <Map<String, dynamic>>[],
      };
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> loadFloaterSteps(String pluginId) async {
    final program = await loadFloaterProgram(pluginId);
    if (program == null) return null;
    final dslVersion = program['dslVersion'] as int? ?? 1;
    if (dslVersion == 2) return [];
    final balls = (program['balls'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final steps = (program['steps'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return [
      ...balls.expand((b) => (b['steps'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()),
      ...steps,
    ];
  }

  // Macro assets

  /// 将文件复制到插件 assets 目录，返回生成的文件名。
  ///
  /// [desiredName] 可指定保存后的文件名；为 null 时使用 [sourcePath] 的 basename。
  /// 同名文件会覆盖，便于 DSL 中 image("xxx.jpg") 直接引用。
  Future<String?> importMacroAsset(
    String pluginId,
    String sourcePath, {
    String? desiredName,
  }) async {
    final file = File(sourcePath);
    if (!await file.exists()) return null;

    final pluginDir = await _pluginDirectory();
    final assetsDir = Directory('${pluginDir.path}/$pluginId/assets');
    if (!await assetsDir.exists()) {
      await assetsDir.create(recursive: true);
    }

    final fileName = desiredName ?? path.basename(sourcePath);
    final destFile = File('${assetsDir.path}/$fileName');
    if (await destFile.exists()) {
      await destFile.delete();
    }
    await file.copy(destFile.path);

    // 同时复制到公共目录 /storage/emulated/0/Isolation/，方便其他文件管理器访问
    await _copyToPublicWorkspace(destFile.path, fileName);

    return fileName;
  }

  /// 公共工作目录，位于 /storage/emulated/0/Isolation/。
  static const String publicWorkspacePath = '/storage/emulated/0/Isolation';

  /// 确保公共工作目录存在，返回实际路径。
  Future<String?> ensurePublicWorkspace({String? subFolder}) async {
    final dirPath = subFolder == null || subFolder.isEmpty
        ? publicWorkspacePath
        : '$publicWorkspacePath/$subFolder';
    final dir = Directory(dirPath);
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir.path;
    } catch (e) {
      debugPrint('创建公共目录失败: $e');
      return null;
    }
  }

  /// 将指定文件复制到公共目录。
  Future<String?> _copyToPublicWorkspace(String sourcePath, String fileName, {String? subFolder}) async {
    final publicDir = await ensurePublicWorkspace(subFolder: subFolder);
    if (publicDir == null) return null;
    final destFile = File('$publicDir/$fileName');
    try {
      if (await destFile.exists()) await destFile.delete();
      await File(sourcePath).copy(destFile.path);
      return destFile.path;
    } catch (e) {
      debugPrint('复制到公共目录失败: $e');
      return null;
    }
  }

  /// 将插件 assets 中的文件导出到公共目录。
  Future<String?> exportMacroAssetToPublic(
    String pluginId,
    String fileName, {
    String? subFolder,
  }) async {
    final pluginDir = await _pluginDirectory();
    final sourceFile = File('${pluginDir.path}/$pluginId/assets/$fileName');
    if (!await sourceFile.exists()) return null;
    return _copyToPublicWorkspace(sourceFile.path, fileName, subFolder: subFolder);
  }

  /// 列出公共目录下的文件（仅一层）。
  Future<List<String>> listPublicAssets({String? subFolder}) async {
    final publicDirPath = subFolder == null || subFolder.isEmpty
        ? publicWorkspacePath
        : '$publicWorkspacePath/$subFolder';
    final dir = Directory(publicDirPath);
    if (!await dir.exists()) return [];
    try {
      return await dir
          .list()
          .where((e) => e is File)
          .map((e) => path.basename(e.path))
          .toList();
    } catch (e) {
      debugPrint('列出公共目录失败: $e');
      return [];
    }
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

  /// 重命名插件 assets 目录下的指定文件。
  Future<String?> renameMacroAsset(String pluginId, String oldName, String newName) async {
    final pluginDir = await _pluginDirectory();
    final assetsDir = Directory('${pluginDir.path}/$pluginId/assets');
    final oldFile = File('${assetsDir.path}/$oldName');
    if (!await oldFile.exists()) return null;
    final sanitized = newName.trim();
    if (sanitized.isEmpty || sanitized == oldName) return null;
    final newFile = File('${assetsDir.path}/$sanitized');
    if (await newFile.exists()) return null;
    await oldFile.rename(newFile.path);
    return sanitized;
  }

  /// 获取插件 assets 目录下指定文件的绝对路径。
  Future<String?> macroAssetPath(String pluginId, String fileName) async {
    final pluginDir = await _pluginDirectory();
    final file = File('${pluginDir.path}/$pluginId/assets/$fileName');
    if (await file.exists()) return file.path;
    return null;
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

  /// 同步某宏的每日定时配置到原生侧。
  /// 仅当宏处于启用状态且设置中打开定时开关时才注册，否则取消已注册的定时。
  Future<void> _syncMacroSchedule(Plugin plugin, MacroSettings settings) async {
    final macroAction = plugin.actions.firstWhere(
      (a) => a.type == 'macro',
      orElse: () => PluginAction(type: '', label: '', params: {}),
    );
    final macroFile = macroAction.params['macroFile'] as String?;
    if (macroFile == null) return;

    if (plugin.enabled && settings.scheduleEnabled) {
      await NativeChannel.setMacroSchedule(
        pluginId: plugin.id,
        macroFile: macroFile,
        enabled: true,
        hour: settings.scheduleHour,
        minute: settings.scheduleMinute,
      );
    } else {
      await NativeChannel.clearMacroSchedule(plugin.id);
    }
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
