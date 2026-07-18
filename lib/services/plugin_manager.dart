import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/plugin.dart';

class PluginManager {
  static const String _pluginsKey = 'isolation_plugins';
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
    _ensureBuiltInPlugin();
  }

  Future<void> savePlugins() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_plugins.map((p) => p.toJson()).toList());
    await prefs.setString(_pluginsKey, jsonString);
  }

  void _ensureBuiltInPlugin() {
    final exists = _plugins.any((p) => p.id == 'com.example.isolation.floating_keyboard');
    if (!exists) {
      _plugins.insert(0, _builtInPlugin());
    }
  }

  Plugin _builtInPlugin() {
    return Plugin(
      id: 'com.example.isolation.floating_keyboard',
      name: '悬浮球小键盘',
      version: '1.0.0',
      description: '启用后显示可拖动悬浮球，单击唤起输入法，长按打开迷你键盘。',
      author: 'isolation',
      builtIn: true,
      enabled: false,
    );
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
