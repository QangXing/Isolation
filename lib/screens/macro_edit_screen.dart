import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/macro.dart';
import '../providers/plugin_provider.dart';
import '../widgets/glass_card.dart';

class MacroEditScreen extends StatefulWidget {
  final List<MacroStep> steps;
  final String? editingId;

  const MacroEditScreen({
    super.key,
    required this.steps,
    this.editingId,
  });

  @override
  State<MacroEditScreen> createState() => _MacroEditScreenState();
}

class _MacroEditScreenState extends State<MacroEditScreen> {
  late List<MacroStep> _steps;
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _loop = false;
  bool _smartRecognition = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _steps = List.from(widget.steps);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入宏名称'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('宏至少需要一步'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final provider = context.read<PluginProvider>();
    final plugin = await provider.saveMacro(
      name: name,
      description: _descController.text.trim(),
      steps: _steps,
      config: MacroConfig(loop: _loop, smartRecognition: _smartRecognition),
      id: widget.editingId,
    );

    if (!mounted) return;
    setState(() => _saving = false);
    if (plugin != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('宏已保存'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('保存失败'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _deleteStep(int index) {
    setState(() => _steps.removeAt(index));
  }

  String _targetDetail(MacroTarget target) {
    final parts = <String>[];
    if (target.text?.isNotEmpty == true) parts.add('text: ${target.text}');
    if (target.resourceId?.isNotEmpty == true) parts.add('id: ${target.resourceId}');
    if (target.className?.isNotEmpty == true) parts.add('class: ${target.className}');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white.withValues(alpha: 0.9),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '编辑宏',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black.withValues(alpha: 0.85),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: '宏名称',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _descController,
                          decoration: const InputDecoration(
                            labelText: '描述（可选）',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassCard(
                    child: Column(
                      children: [
                        _SwitchTile(
                          label: '循环执行',
                          subtitle: '任务完成后自动重新开始',
                          value: _loop,
                          onChanged: (v) => setState(() => _loop = v),
                        ),
                        const Divider(height: 1, color: Color(0xFFEAEAEA)),
                        _SwitchTile(
                          label: '智能识别',
                          subtitle: '执行时等待目标像素颜色匹配',
                          value: _smartRecognition,
                          onChanged: (v) => setState(() => _smartRecognition = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '步骤列表',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_steps.isEmpty)
                    GlassCard(
                      child: Center(
                        child: Text(
                          '暂无步骤',
                          style: TextStyle(
                            color: Colors.grey.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    )
                  else
                    ..._steps.asMap().entries.map((entry) {
                      final index = entry.key;
                      final step = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      step.summary,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '等待 ${step.delay}ms',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    if (step.target != null)
                                      Text(
                                        _targetDetail(step.target!),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.withValues(alpha: 0.5),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (step.pixelColor != null)
                                      Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: Color(step.pixelColor!.color),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.grey.withValues(alpha: 0.3),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '识别点 (${step.pixelColor!.x}, ${step.pixelColor!.y})',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.withValues(alpha: 0.5),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _deleteStep(index),
                                child: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          border: Border(
            top: BorderSide(
              color: Colors.grey.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: SafeArea(
          child: GestureDetector(
            onTap: _saving ? null : _save,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: _saving ? Colors.grey : Colors.black87,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Text(
                        '保存宏',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: Colors.black87,
            activeColor: Colors.white,
          ),
        ],
      ),
    );
  }
}
