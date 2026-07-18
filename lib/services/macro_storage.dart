import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/macro.dart';

class MacroStorage {
  static const String _macrosKey = 'isolation_macros';
  static const String _sampleMacroLoadedKey = 'isolation_sample_macro_loaded';

  static final MacroStorage _instance = MacroStorage._internal();
  factory MacroStorage() => _instance;
  MacroStorage._internal();

  List<Macro> _macros = [];
  List<Macro> get macros => List.unmodifiable(_macros);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_macrosKey);
    if (jsonString != null && jsonString.isNotEmpty) {
      final List<dynamic> list = jsonDecode(jsonString);
      _macros = list.map((e) => Macro.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      _macros = [];
    }
    await _ensureSampleMacro();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_macros.map((m) => m.toJson()).toList());
    await prefs.setString(_macrosKey, jsonString);
  }

  Future<void> addMacro(Macro macro) async {
    _macros.removeWhere((m) => m.id == macro.id);
    _macros.add(macro);
    await save();
  }

  Future<void> updateMacro(Macro macro) async {
    final index = _macros.indexWhere((m) => m.id == macro.id);
    if (index >= 0) {
      _macros[index] = macro;
      await save();
    }
  }

  Future<void> deleteMacro(String id) async {
    _macros.removeWhere((m) => m.id == id && !m.builtIn);
    await save();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    for (final macro in _macros) {
      if (macro.id == id) {
        macro.enabled = enabled;
      } else if (enabled) {
        macro.enabled = false;
      }
    }
    await save();
  }

  Macro? getEnabledMacro() {
    try {
      return _macros.firstWhere((m) => m.enabled);
    } catch (_) {
      return null;
    }
  }

  Macro? getMacro(String id) {
    try {
      return _macros.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureSampleMacro() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = prefs.getBool(_sampleMacroLoadedKey) ?? false;
    if (loaded) return;

    final sample = Macro(
      id: 'sample_macro',
      name: '示例宏',
      steps: [
        MacroStep(delayMs: 500, x: 540, y: 960),
        MacroStep(delayMs: 1000, x: 540, y: 1200),
      ],
      loop: false,
      smartRecognition: false,
      builtIn: true,
      enabled: true,
    );
    _macros.add(sample);
    await save();
    await prefs.setBool(_sampleMacroLoadedKey, true);
  }
}
