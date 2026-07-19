import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/macro.dart';
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
    await _ensureBuiltInPlugin();
  }

  Future<void> savePlugins() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_plugins.map((p) => p.toJson()).toList());
    await prefs.setString(_pluginsKey, jsonString);
  }

  Future<void> _ensureBuiltInPlugin() async {
    final id = 'com.example.isolation.builtin.daily-checkin';
    final exists = _plugins.any((p) => p.id == id);
    if (!exists) {
      final plugin = await _ensureBuiltInMacro(id);
      _plugins.insert(0, plugin);
    }
  }

  Future<Plugin> _ensureBuiltInMacro(String id) async {
    final pluginDir = await _pluginDirectory();
    final dir = Directory('${pluginDir.path}/$id');
    await dir.create(recursive: true);

    final manifest = {
      'id': id,
      'name': '示例签到宏',
      'version': '1.0.0',
      'description': '打开目标 App 后自动点击签到按钮（示例宏，请按实际界面重新录制）。',
      'author': 'isolation',
      'actions': [
        {
          'type': 'macro',
          'label': '运行签到宏',
          'macroFile': 'macro.json',
          'loop': false,
          'smartRecognition': true,
        }
      ]
    };

    final macro = {
      'steps': [
        {
          'type': 'wait',
          'delay': 500,
          'duration': 500,
        },
        {
          'type': 'clickNode',
          'delay': 800,
          'target': {
            'resourceId': '',
            'text': '签到',
            'contentDescription': '',
            'className': 'android.widget.Button',
            'bounds': [100, 200, 300, 400]
          }
        }
      ]
    };

    final manifestFile = File('${dir.path}/manifest.json');
    await manifestFile.writeAsString(jsonEncode(manifest));
    final macroFile = File('${dir.path}/macro.json');
    await macroFile.writeAsString(jsonEncode(macro));

    return Plugin.fromManifest(
      manifest,
      builtIn: true,
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

  Future<Plugin?> saveMacroPlugin({
    required String name,
    String description = '',
    required List<MacroStep> steps,
    required MacroConfig config,
    String? id,
  }) async {
    try {
      final pluginId = id ??
          'com.example.isolation.macro.${DateTime.now().millisecondsSinceEpoch}.${Random().nextInt(9999)}';
      final pluginDir = await _pluginDirectory();
      final dir = Directory('${pluginDir.path}/$pluginId');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);

      final manifest = {
        'id': pluginId,
        'name': name,
        'version': '1.0.0',
        'description': description,
        'author': 'user',
        'actions': [
          {
            'type': 'macro',
            'label': '运行宏',
            'macroFile': 'macro.json',
            'loop': config.loop,
            'smartRecognition': config.smartRecognition,
          }
        ]
      };

      final macro = {'steps': steps.map((s) => s.toJson()).toList()};

      await File('${dir.path}/manifest.json')
          .writeAsString(jsonEncode(manifest));
      await File('${dir.path}/macro.json').writeAsString(jsonEncode(macro));

      final zipBytes = _createZip(dir);
      await File('${dir.path}/$pluginId.isoplugin').writeAsBytes(zipBytes);

      final existing = _plugins.firstWhere(
        (p) => p.id == pluginId,
        orElse: () => Plugin.fromManifest(manifest),
      );
      final plugin = Plugin.fromManifest(manifest)
        ..enabled = existing.enabled;
      _plugins.removeWhere((p) => p.id == plugin.id);
      _plugins.add(plugin);
      await savePlugins();
      return plugin;
    } catch (e) {
      return null;
    }
  }

  Future<String?> exportPlugin(String id) async {
    try {
      final pluginDir = await _pluginDirectory();
      final dir = Directory('${pluginDir.path}/$id');
      if (!await dir.exists()) return null;
      final zipPath = '${dir.path}/$id.isoplugin';
      if (await File(zipPath).exists()) return zipPath;
      final zipBytes = _createZip(dir);
      await File(zipPath).writeAsBytes(zipBytes);
      return zipPath;
    } catch (e) {
      return null;
    }
  }

  List<int> _createZip(Directory dir) {
    final archive = Archive();
    for (final entity in dir.listSync(recursive: false)) {
      if (entity is File && !entity.path.endsWith('.isoplugin')) {
        final bytes = entity.readAsBytesSync();
        final name = entity.path.split('/').last;
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }
    }
    return ZipEncoder().encode(archive) ?? [];
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
