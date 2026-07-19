import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/macro.dart';
import '../providers/plugin_provider.dart';
import '../widgets/glass_card.dart';
import 'macro_edit_screen.dart';

class MacroRecordScreen extends StatefulWidget {
  const MacroRecordScreen({super.key});

  @override
  State<MacroRecordScreen> createState() => _MacroRecordScreenState();
}

class _MacroRecordScreenState extends State<MacroRecordScreen> {
  bool _recording = false;
  bool _stopped = false;
  List<MacroStep> _steps = [];

  Future<void> _start() async {
    final provider = context.read<PluginProvider>();
    final ok = await provider.startRecording();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('无法开始录制，请检查辅助功能权限'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }
    setState(() {
      _recording = true;
      _stopped = false;
      _steps = [];
    });
  }

  Future<void> _stop() async {
    final provider = context.read<PluginProvider>();
    final steps = await provider.stopRecording();
    setState(() {
      _recording = false;
      _stopped = true;
      _steps = steps;
    });
  }

  String _targetDetail(MacroTarget target) {
    final parts = <String>[];
    if (target.text?.isNotEmpty == true) parts.add('text: ${target.text}');
    if (target.resourceId?.isNotEmpty == true) parts.add('id: ${target.resourceId}');
    if (target.className?.isNotEmpty == true) parts.add('class: ${target.className}');
    parts.add('bounds: ${target.bounds}');
    return parts.join(' · ');
  }

  void _finish() {
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有录制到任何步骤'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MacroEditScreen(steps: _steps),
      ),
    );
  }

  void _cancel() {
    if (_recording) {
      context.read<PluginProvider>().stopRecording();
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white.withValues(alpha: 0.9),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.black87),
          onPressed: _cancel,
        ),
        title: Text(
          '录制宏',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black.withValues(alpha: 0.85),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassCard(
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _recording ? Colors.redAccent : (_stopped ? Colors.green : Colors.grey),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _recording
                            ? '正在录制，请在目标 App 中点击'
                            : _stopped
                                ? '已录制 ${_steps.length} 步'
                                : '点击开始录制',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '已录制步骤',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _steps.isEmpty
                    ? GlassCard(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                size: 32,
                                color: Colors.grey.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _stopped ? '未录制到任何步骤' : '等待点击…',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _steps.length,
                        itemBuilder: (context, index) {
                          final step = _steps[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GlassCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
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
                                        child: Text(
                                          step.summary,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${step.delay}ms',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (step.target != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      _targetDetail(step.target!),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.withValues(alpha: 0.6),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (step.pixelColor != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: Color(step.pixelColor!.color),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.grey.withValues(alpha: 0.3),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '智能识别点 (${step.pixelColor!.x}, ${step.pixelColor!.y})',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildControlBar(),
    );
  }

  Widget _buildControlBar() {
    return Container(
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
        child: Row(
          children: [
            Expanded(
              child: _ControlButton(
                label: _recording ? '停止录制' : '开始录制',
                color: _recording ? Colors.redAccent : Colors.black87,
                onTap: _recording ? _stop : _start,
              ),
            ),
            if (_stopped) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _ControlButton(
                  label: '完成',
                  color: Colors.green,
                  onTap: _finish,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
