import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/plugin.dart';

class PluginManager {
  static const String _pluginsKey = 'isolation_plugins';
  static const String _builtInId = 'com.example.isolation.builtin.daily-checkin';
  static final PluginManager _instance = PluginManager._internal();
  factory PluginManager() => _instance;
  PluginManager._internal();

  List<Plugin> _plugins = [];
  List<Plugin> get plugins => List.unmodifiable(_plugins);

  Future<void> loadPlugins() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_pluginsKey);
    if (jsonString != null) {
      final List<dynamic> list = jsonDecode(jsonString);
      _plugins = list.map((e) => Plugin.fromJson(e)).toList();
    }
    // Migrate legacy floating keyboard plugin to macro plugin
    _plugins.removeWhere((p) => p.id == 'com.example.isolation.floating_keyboard');
    await _ensureBuiltInMacroPlugin();
  }

  Future<void> savePlugins() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_plugins.map((p) => p.toJson()).toList());
    await prefs.setString(_pluginsKey, jsonString);
  }

  void replacePlugins(List<Plugin> plugins) {
    _plugins = List.from(plugins);
  }

  Future<void> _ensureBuiltInMacroPlugin() async {
    final exists = _plugins.any((p) => p.id == _builtInId);
    if (!exists) {
      final plugin = await _createBuiltInMacroPlugin();
      _plugins.insert(0, plugin);
      await savePlugins();
    }
  }

  Future<Plugin> _createBuiltInMacroPlugin() async {
    final pluginDir = await _pluginDirectory();
    final targetDir = Directory('${pluginDir.path}/$_builtInId');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    const macroFileName = 'macro.json';
    final macroFile = File('${targetDir.path}/$macroFileName');
    if (!await macroFile.exists()) {
      final exampleMacro = {
        'settings': {
          'smartRecognition': false,
          'loopCount': 1,
        },
        'steps': [
          {
            'type': 'clickNode',
            'delay': 0,
            'target': {
              'text': '签到',
              'className': 'android.widget.Button',
              'bounds': [100, 200, 300, 400],
            },
          },
        ],
      };
      await macroFile.writeAsString(jsonEncode(exampleMacro));
    }

    final manifest = {
      'id': _builtInId,
      'name': '每日签到宏',
      'version': '1.0.0',
      'description': '打开目标 App 后自动点击签到按钮（示例宏，请录制替换）。',
      'author': 'isolation',
      'actions': [
        {
          'type': 'macro',
          'label': '运行签到宏',
          'macroFile': macroFileName,
        }
      ],
    };

    final manifestFile = File('${targetDir.path}/manifest.json');
    await manifestFile.writeAsString(jsonEncode(manifest));

    return Plugin.fromManifest(manifest, builtIn: true);
  }

  Future<bool> importPlugin(String zipPath) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final manifestFile = archive.files.firstWhere(
        (f) => f.name == 'manifest.json',
        orElse: () => throw Exception('manifest.json not found'),
      );
      final manifestJson = utf8.decode(manifestFile.content as List<int>);
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

      final pluginDir = await _pluginDirectory();
      final pluginId = manifest['id'] as String;
      final targetDir = Directory('${pluginDir.path}/$pluginId');
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
      await targetDir.create(recursive: true);

      String? iconPath;
      for (final file in archive.files) {
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File('${targetDir.path}/${file.name}');
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(data);
          if (file.name == manifest['icon']) {
            iconPath = outFile.path;
          }
        }
      }

      final plugin = Plugin.fromManifest(manifest, iconPath: iconPath);
      _plugins.removeWhere((p) => p.id == plugin.id);
      _plugins.add(plugin);
      await savePlugins();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> deletePlugin(String id) async {
    _plugins.removeWhere((p) => p.id == id && !p.builtIn);
    final pluginDir = await _pluginDirectory();
    final dir = Directory('${pluginDir.path}/$id');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await savePlugins();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final plugin = _plugins.firstWhere((p) => p.id == id);
    final isMacro = plugin.actions.any((a) => a.type == 'macro');

    // 互斥规则：宏插件启用时，强制关闭其他所有宏插件
    if (enabled && isMacro) {
      for (final p in _plugins) {
        if (p.id != id && p.actions.any((a) => a.type == 'macro') && p.enabled) {
          p.enabled = false;
        }
      }
    }
    plugin.enabled = enabled;
    await savePlugins();
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
