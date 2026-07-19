import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/macro.dart';
import '../models/plugin.dart';
import '../providers/plugin_provider.dart';
import '../widgets/glass_card.dart';

class MacroSettingsScreen extends StatefulWidget {
  final String pluginId;

  const MacroSettingsScreen({super.key, required this.pluginId});

  @override
  State<MacroSettingsScreen> createState() => _MacroSettingsScreenState();
}

class _MacroSettingsScreenState extends State<MacroSettingsScreen> {
  MacroSettings? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<PluginProvider>();
    final data = await provider.loadMacroData(widget.pluginId);
    if (mounted) {
      setState(() {
        _settings = data?.settings ?? const MacroSettings();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_settings == null) return;
    final provider = context.read<PluginProvider>();
    final success = await provider.updateMacroSettings(widget.pluginId, _settings!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '设置已保存' : '保存失败'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: success ? Colors.black87 : Colors.redAccent,
        ),
      );
      if (success) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plugin = context.select<PluginProvider, Plugin?>(
      (p) => p.plugins.cast<Plugin?>().firstWhere(
            (x) => x?.id == widget.pluginId,
            orElse: () => null,
          ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          '${plugin?.name ?? '宏'} 设置',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.85),
            fontWeight: FontWeight.w500,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Colors.black.withValues(alpha: 0.7)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading || _settings == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      GlassCard(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.colorize_rounded,
                                  size: 20,
                                  color: Colors.black.withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '智能识别',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '执行前等待点击位置像素颜色与录制时一致',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _settings!.smartRecognition,
                                  onChanged: (value) {
                                    setState(() {
                                      _settings = _settings!.copyWith(smartRecognition: value);
                                    });
                                  },
                                  activeColor: Colors.black87,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.loop_rounded,
                                  size: 20,
                                  color: Colors.black.withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  '循环执行',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _LoopChip(
                                  label: '执行 1 次',
                                  selected: _settings!.loopCount == 1,
                                  onTap: () => setState(() {
                                    _settings = _settings!.copyWith(loopCount: 1);
                                  }),
                                ),
                                _LoopChip(
                                  label: '执行 3 次',
                                  selected: _settings!.loopCount == 3,
                                  onTap: () => setState(() {
                                    _settings = _settings!.copyWith(loopCount: 3);
                                  }),
                                ),
                                _LoopChip(
                                  label: '执行 5 次',
                                  selected: _settings!.loopCount == 5,
                                  onTap: () => setState(() {
                                    _settings = _settings!.copyWith(loopCount: 5);
                                  }),
                                ),
                                _LoopChip(
                                  label: '无限循环',
                                  selected: _settings!.loopCount <= 0,
                                  onTap: () => setState(() {
                                    _settings = _settings!.copyWith(loopCount: 0);
                                  }),
                                ),
                              ],
                            ),
                            if (_settings!.loopCount <= 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  '三连击悬浮球可强制停止循环',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: SafeArea(
                    top: false,
                    child: GestureDetector(
                      onTap: _save,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text(
                            '保存设置',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _LoopChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LoopChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black87 : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
