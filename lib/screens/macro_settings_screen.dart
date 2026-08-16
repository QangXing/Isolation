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
  String? _iconName;
  bool _loading = true;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _featurePointCountController = TextEditingController();
  final _featurePointThresholdController = TextEditingController();

  static const List<MapEntry<String, IconData>> _presetIcons = [
    MapEntry('touch', Icons.touch_app_rounded),
    MapEntry('mouse', Icons.mouse_rounded),
    MapEntry('gamepad', Icons.gamepad_rounded),
    MapEntry('smartToy', Icons.smart_toy_rounded),
    MapEntry('android', Icons.android_rounded),
    MapEntry('favorite', Icons.favorite_rounded),
    MapEntry('star', Icons.star_rounded),
    MapEntry('flash', Icons.flash_on_rounded),
    MapEntry('rocket', Icons.rocket_rounded),
    MapEntry('settings', Icons.settings_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _featurePointCountController.dispose();
    _featurePointThresholdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = context.read<PluginProvider>();
    final plugin = provider.plugins.cast<Plugin?>().firstWhere(
          (p) => p?.id == widget.pluginId,
          orElse: () => null,
        );
    final data = await provider.loadMacroData(widget.pluginId);
    if (mounted) {
      setState(() {
        _settings = data?.settings ?? const MacroSettings();
        _iconName = plugin?.iconName;
        _nameController.text = plugin?.name ?? '';
        _descriptionController.text = plugin?.description ?? '';
        _featurePointCountController.text = _settings!.featurePointCount.toString();
        _featurePointThresholdController.text = (_settings!.featurePointThreshold * 100).round().toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_settings == null) return;
    final count = int.tryParse(_featurePointCountController.text) ?? _settings!.featurePointCount;
    final thresholdPercent = int.tryParse(_featurePointThresholdController.text) ?? 80;
    final settings = _settings!.copyWith(
      featurePointCount: count.clamp(1, 32),
      featurePointThreshold: (thresholdPercent.clamp(1, 100) / 100.0),
    );
    final provider = context.read<PluginProvider>();
    final success = await provider.updateMacroMetadata(
      widget.pluginId,
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      settings: settings,
      iconName: _iconName,
    );
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          '宏设置',
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
                      // 宏名称
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '宏名称',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                hintText: '输入宏名称',
                                hintStyle: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.3),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.1),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.1),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: Colors.black87),
                                ),
                                filled: true,
                                fillColor: Colors.black.withValues(alpha: 0.03),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // 宏简介
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '宏简介',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _descriptionController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: '输入宏简介（会显示在插件卡片下方）',
                                hintStyle: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.3),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.1),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.1),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: Colors.black87),
                                ),
                                filled: true,
                                fillColor: Colors.black.withValues(alpha: 0.03),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // 宏图标
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '宏图标',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: _presetIcons.map((entry) {
                                final selected = _iconName == entry.key;
                                return GestureDetector(
                                  onTap: () => setState(() => _iconName = entry.key),
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? Colors.black87
                                          : Colors.black.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      entry.value,
                                      color: selected ? Colors.white : Colors.black.withValues(alpha: 0.6),
                                      size: 24,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // 调试模式
                      _buildSwitchCard(
                        icon: Icons.bug_report_rounded,
                        title: '调试模式',
                        subtitle: '开启后每执行一步都在悬浮球显示默认提示',
                        value: _settings!.debugMode,
                        onChanged: (value) {
                          setState(() {
                            _settings = _settings!.copyWith(debugMode: value);
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      // 无限循环
                      _buildSwitchCard(
                        icon: Icons.all_inclusive_rounded,
                        title: '无限循环',
                        subtitle: '宏执行完后自动从头开始，三连击悬浮球强制停止',
                        value: _settings!.loopCount <= 0,
                        onChanged: (value) {
                          setState(() {
                            _settings = _settings!.copyWith(loopCount: value ? 0 : 1);
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      // 特征点采样数目
                      _buildNumberCard(
                        icon: Icons.scatter_plot_rounded,
                        title: '特征点采样数目',
                        subtitle: '图片匹配时围绕中心原点采样的特征点数量（1-32），越大越稳定但越慢',
                        controller: _featurePointCountController,
                        suffix: '',
                        onChanged: (value) {
                          final count = int.tryParse(value);
                          if (count != null) {
                            setState(() {
                              _settings = _settings!.copyWith(
                                featurePointCount: count.clamp(1, 32),
                              );
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      // 特征点匹配比例阈值
                      _buildNumberCard(
                        icon: Icons.percent_rounded,
                        title: '特征点匹配比例阈值',
                        subtitle: '命中特征点比例达到该值才算识别成功（1%-100%），默认 80%',
                        controller: _featurePointThresholdController,
                        suffix: ' %',
                        onChanged: (value) {
                          final percent = int.tryParse(value);
                          if (percent != null) {
                            setState(() {
                              _settings = _settings!.copyWith(
                                featurePointThreshold: percent.clamp(1, 100) / 100.0,
                              );
                            });
                          }
                        },
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
                        width: double.infinity,
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

  Widget _buildSwitchCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GlassCard(
      child: Row(
        children: [
          Icon(icon, size: 22, color: Colors.black.withValues(alpha: 0.6)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.45),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CustomSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildNumberCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String suffix,
    required ValueChanged<String> onChanged,
  }) {
    return GlassCard(
      child: Row(
        children: [
          Icon(icon, size: 22, color: Colors.black.withValues(alpha: 0.6)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.45),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                suffixText: suffix.isEmpty ? null : suffix.trim(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.black.withValues(alpha: 0.1),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.black.withValues(alpha: 0.1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black87),
                ),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.03),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CustomSwitch({required this.value, required this.onChanged});

  @override
  State<_CustomSwitch> createState() => _CustomSwitchState();
}

class _CustomSwitchState extends State<_CustomSwitch> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(covariant _CustomSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _value = !_value);
        widget.onChanged(_value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50,
        height: 28,
        decoration: BoxDecoration(
          color: _value ? Colors.black87 : Colors.black.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: _value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
