import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/macro.dart';
import '../providers/macro_provider.dart';
import '../services/native_channel.dart';
import '../widgets/glass_card.dart';

class RecordMacroScreen extends StatefulWidget {
  const RecordMacroScreen({super.key});

  @override
  State<RecordMacroScreen> createState() => _RecordMacroScreenState();
}

class _RecordMacroScreenState extends State<RecordMacroScreen> {
  bool _isRecording = false;
  List<MacroStep> _steps = [];
  final TextEditingController _nameController = TextEditingController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final recording = await NativeChannel.isRecording();
      if (recording != _isRecording) {
        setState(() => _isRecording = recording);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '录制宏',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.redAccent : Colors.grey.shade300,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isRecording ? '录制中' : '未录制',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: _isRecording ? Colors.redAccent : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text(
                  '1. 点击"开始录制"。\n2. 切换到目标 App，点击需要自动化的按钮。\n3. 返回本页，点击"停止录制"并保存。',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                    height: 1.6,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: _isRecording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
                        label: _isRecording ? '停止录制' : '开始录制',
                        color: _isRecording ? Colors.black87 : Colors.redAccent,
                        onTap: _toggleRecording,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.save_rounded,
                        label: '保存宏',
                        color: Colors.black87,
                        onTap: _steps.isEmpty ? null : _saveMacro,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '已录制步骤',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _steps = []),
                      child: Text(
                        '清空',
                        style: TextStyle(
                          fontSize: 14,
                          color: _steps.isEmpty ? Colors.grey.shade400 : Colors.redAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_steps.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 48,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '暂无录制步骤',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final step = _steps[index];
                      final color = step.color;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GlassCard(
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '点击 (${step.x}, ${step.y})',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '延迟 ${step.delayMs}ms',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (color != null) ...[
                                Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: Color(color | 0xFF000000),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Icon(
                                Icons.drag_handle_rounded,
                                color: Colors.grey.shade300,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: _steps.length,
                  ),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleRecording() async {
    final provider = context.read<MacroProvider>();
    if (!_isRecording) {
      final hasAccessibility = await NativeChannel.checkAccessibilityPermission();
      if (!hasAccessibility && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先开启辅助功能权限')),
        );
        await NativeChannel.requestAccessibilityPermission();
        return;
      }
      final result = await provider.startRecording();
      setState(() => _isRecording = result);
      if (result && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已开始录制，请切换到目标应用进行操作')),
        );
      }
    } else {
      final steps = await provider.stopRecording();
      setState(() {
        _isRecording = false;
        _steps = steps;
      });
    }
  }

  Future<void> _saveMacro() async {
    _nameController.text = '我的宏 ${_formatTime()}';
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('保存宏'),
          content: TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: '输入宏名称',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, _nameController.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty || !mounted) return;

    final macro = Macro(
      id: MacroProvider.generateId(),
      name: name,
      steps: _steps,
    );
    await context.read<MacroProvider>().addMacro(macro);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('宏已保存')),
      );
      setState(() => _steps = []);
    }
  }

  String _formatTime() {
    final now = DateTime.now();
    return '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: onTap == null ? Colors.grey.shade200 : color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: onTap == null ? Colors.grey.shade400 : Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: onTap == null ? Colors.grey.shade400 : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
