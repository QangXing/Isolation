import 'dart:math';
import 'package:flutter/material.dart';
import '../models/macro.dart';
import '../services/macro_storage.dart';
import '../services/native_channel.dart';

class MacroProvider extends ChangeNotifier {
  final MacroStorage _storage = MacroStorage();
  List<Macro> _macros = [];
  bool _loaded = false;
  bool _isRecording = false;

  List<Macro> get macros => _macros;
  bool get loaded => _loaded;
  bool get isRecording => _isRecording;

  Future<void> load() async {
    await _storage.load();
    _macros = List.from(_storage.macros);
    _loaded = true;
    final enabled = getEnabledMacro();
    if (enabled != null) {
      await NativeChannel.setMacroConfig(
        enabled.id,
        enabled.loop,
        enabled.smartRecognition,
        enabled.steps.map((s) => s.toJson()).toList(),
      );
    } else {
      await NativeChannel.setMacroConfig('', false, false, []);
    }
    notifyListeners();
  }

  Future<void> addMacro(Macro macro) async {
    await _storage.addMacro(macro);
    _macros = List.from(_storage.macros);
    notifyListeners();
  }

  Future<void> updateMacro(Macro macro) async {
    await _storage.updateMacro(macro);
    _macros = List.from(_storage.macros);
    notifyListeners();
  }

  Future<void> deleteMacro(String id) async {
    final wasEnabled = getMacro(id)?.enabled ?? false;
    await _storage.deleteMacro(id);
    if (wasEnabled) {
      await NativeChannel.setMacroConfig('', false, false, []);
    }
    _macros = List.from(_storage.macros);
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _storage.setEnabled(id, enabled);
    if (enabled) {
      final macro = getMacro(id);
      if (macro != null) {
        await NativeChannel.setMacroConfig(
          macro.id,
          macro.loop,
          macro.smartRecognition,
          macro.steps.map((s) => s.toJson()).toList(),
        );
      }
    } else {
      await NativeChannel.setMacroConfig('', false, false, []);
    }
    _macros = List.from(_storage.macros);
    notifyListeners();
  }

  Macro? getMacro(String id) => _storage.getMacro(id);
  Macro? getEnabledMacro() => _storage.getEnabledMacro();

  Future<bool> startRecording() async {
    final result = await NativeChannel.startMacroRecording();
    _isRecording = result;
    notifyListeners();
    return result;
  }

  Future<List<MacroStep>> stopRecording() async {
    final rawSteps = await NativeChannel.stopMacroRecording();
    _isRecording = false;
    notifyListeners();
    return rawSteps.map((e) => MacroStep.fromJson(e)).toList();
  }

  Future<bool> executeMacro(Macro macro) async {
    return await NativeChannel.executeMacro(macro);
  }

  Future<bool> stopExecution() async {
    return await NativeChannel.stopMacroExecution();
  }

  Future<void> refreshExecutionState() async {
    final recording = await NativeChannel.isRecording();
    if (recording != _isRecording) {
      _isRecording = recording;
      notifyListeners();
    }
  }

  Future<void> setMacroConfig(String macroId, bool loop, bool smartRecognition) async {
    final macro = getMacro(macroId);
    if (macro == null) return;
    macro.loop = loop;
    macro.smartRecognition = smartRecognition;
    await _storage.save();
    await NativeChannel.setMacroConfig(
      macroId,
      loop,
      smartRecognition,
      macro.steps.map((s) => s.toJson()).toList(),
    );
    _macros = List.from(_storage.macros);
    notifyListeners();
  }

  static String generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(9999);
    return 'macro_${now}_$rand';
  }
}
