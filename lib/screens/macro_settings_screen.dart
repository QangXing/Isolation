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

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _featurePointCountController = TextEditingController();
  final _featurePointThresholdController = TextEditingController();

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
        _nameController.text = plugin?.name ?? '';
        _descriptionController.text = plugin?.description ?? '';
        _featurePointCountController.text =
            _settings!.featurePointCount.toString();
        _featurePointThresholdController.text =
            (_settings!.featurePointThreshold * 100).round().toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_settings == null) return;
    final count = int.tryParse(_featurePointCountController.text) ?? _settings!.featurePointCount;
    final thresholdPercent = int.tryParse(_featurePointThresholdController.text) ?? 80;
    _settings = _settings!.copyWith(
      featurePointCount: count.clamp(1, 32),
      featurePointThreshold: (thresholdPercent.clamp(1, 100) / 100.0),
    );
    final provider = context.read<PluginProvider>();
    final success = await provider.updateMacroMetadata(
      widget.pluginId,
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      settings: _settings!,
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
                            const SizedBox(height: 8),
                            TextField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                hintText: '输入宏名称',
                                hintStyle: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.3),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
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
                            const SizedBox(height: 8),
                            TextField(
                              controller: _descriptionController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: '输入宏简介（会显示在插件卡片下方）',
                                hintStyle: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.3),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
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
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // 调试模式
                      GlassCard(
                        child: Row(
                          children: [
                            Icon(
                              Icons.bug_report_rounded,
                              size: 20,
                              color: Colors.black.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '调试模式',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '开启后每执行一步都在悬浮球显示默认提示',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _settings!.debugMode,
                              onChanged: (value) {
                                setState(() {
                                  _settings = _settings!.copyWith(debugMode: value);
                                });
                              },
                              activeColor: Colors.black87,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // 无限循环
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.all_inclusive_rounded,
                                  size: 20,
                                  color: Colors.black.withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '无限循环',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '宏执行完后自动从头开始，三连击悬浮球强制停止',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _settings!.loopCount <= 0,
                                  onChanged: (value) {
                                    setState(() {
                                      _settings = _settings!.copyWith(
                                        loopCount: value ? 0 : 1,
                                      );
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
                      // 特征点采样数目
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.scatter_plot_rounded,
                                  size: 20,
                                  color: Colors.black.withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '特征点采样数目',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '图片匹配时围绕中心原点采样的特征点数量（1-32），越大越稳定但越慢',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 64,
                                  child: TextField(
                                    controller: _featurePointCountController,
                                    textAlign: TextAlign.center,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
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
                                    ),
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
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // 特征点匹配比例阈值
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.percent_rounded,
                                  size: 20,
                                  color: Colors.black.withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '特征点匹配比例阈值',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '命中特征点比例达到该值才算识别成功（1%-100%），默认 80%',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 64,
                                  child: TextField(
                                    controller: _featurePointThresholdController,
                                    textAlign: TextAlign.center,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      suffixText: '%',
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
                                    ),
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
                                ),
                              ],
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
