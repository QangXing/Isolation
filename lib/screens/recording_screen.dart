import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/macro.dart';
import '../providers/plugin_provider.dart';
import '../services/native_channel.dart';
import '../widgets/glass_card.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  bool _showEditor = false;
  List<Map<String, dynamic>> _steps = [];
  bool _smartRecognition = false;
  int _loopCount = 1;
  bool _infiniteLoop = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _showEditor ? '编辑宏' : '录制宏',
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
      body: Consumer<PluginProvider>(
        builder: (context, provider, child) {
          if (_showEditor) {
            return _buildEditor(context, provider);
          }
          return _buildRecording(context, provider);
        },
      ),
    );
  }

  Widget _buildRecording(BuildContext context, PluginProvider provider) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: provider.recording
                          ? Colors.redAccent.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      provider.recording ? Icons.fiber_manual_record_rounded : Icons.videocam_rounded,
                      color: provider.recording ? Colors.redAccent : Colors.black54,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    provider.recording ? '正在录制...' : '准备录制',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    provider.recording
                        ? '请在其他 App 中点击目标位置，完成后返回点击完成。'
                        : '点击开始录制，然后在其他 App 中执行操作。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '已记录 ${provider.recordedSteps.length} 步',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _buildSettingsPanel(),
        _buildControlBar(context, provider),
      ],
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.colorize_rounded, size: 18, color: Colors.black.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '智能识别（局部像素颜色）',
                  style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.75)),
                ),
              ),
              Switch(
                value: _smartRecognition,
                onChanged: (value) => setState(() => _smartRecognition = value),
                activeColor: Colors.black87,
              ),
            ],
          ),
          if (!_infiniteLoop)
            Row(
              children: [
                Icon(Icons.loop_rounded, size: 18, color: Colors.black.withValues(alpha: 0.6)),
                const SizedBox(width: 8),
                Text(
                  '循环次数',
                  style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.75)),
                ),
                const SizedBox(width: 12),
                _LoopChip(
                  label: '1',
                  selected: _loopCount == 1 && !_infiniteLoop,
                  onTap: () => setState(() {
                    _loopCount = 1;
                    _infiniteLoop = false;
                  }),
                ),
                const SizedBox(width: 8),
                _LoopChip(
                  label: '3',
                  selected: _loopCount == 3,
                  onTap: () => setState(() {
                    _loopCount = 3;
                    _infiniteLoop = false;
                  }),
                ),
                const SizedBox(width: 8),
                _LoopChip(
                  label: '5',
                  selected: _loopCount == 5,
                  onTap: () => setState(() {
                    _loopCount = 5;
                    _infiniteLoop = false;
                  }),
                ),
              ],
            ),
          Row(
            children: [
              Icon(Icons.all_inclusive_rounded, size: 18, color: Colors.black.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '无限循环（三连击悬浮球停止）',
                  style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.75)),
                ),
              ),
              Switch(
                value: _infiniteLoop,
                onChanged: (value) => setState(() => _infiniteLoop = value),
                activeColor: Colors.black87,
              ),
            ],
          ),
          if (_smartRecognition)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '开启后录制每一步都会记录点击位置的像素颜色，并在执行前等待颜色匹配。需要屏幕录制权限。',
                style: TextStyle(fontSize: 11, color: Colors.grey.withValues(alpha: 0.7), height: 1.4),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlBar(BuildContext context, PluginProvider provider) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (!provider.recording && provider.recordedSteps.isEmpty)
              _ControlButton(
                icon: Icons.fiber_manual_record_rounded,
                label: '开始',
                color: Colors.redAccent,
                onTap: () => _startRecording(context, provider),
              )
            else if (provider.recording)
              _ControlButton(
                icon: Icons.stop_rounded,
                label: '完成',
                color: Colors.black87,
                onTap: () => _stopRecording(provider),
              )
            else
              _ControlButton(
                icon: Icons.play_arrow_rounded,
                label: '继续',
                color: Colors.black87,
                onTap: () => _startRecording(context, provider),
              ),
            if (provider.recordedSteps.isNotEmpty && !provider.recording)
              _ControlButton(
                icon: Icons.edit_rounded,
                label: '编辑',
                color: Colors.black87,
                onTap: () {
                  setState(() {
                    _showEditor = true;
                    _steps = List.from(provider.recordedSteps);
                  });
                },
              ),
            _ControlButton(
              icon: Icons.close_rounded,
              label: '取消',
              color: Colors.grey,
              onTap: () {
                provider.clearRecordedSteps();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context, PluginProvider provider) {
    return Column(
      children: [
        Expanded(
          child: _steps.isEmpty
              ? Center(
                  child: Text(
                    '暂无步骤',
                    style: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  itemCount: _steps.length,
                  itemBuilder: (context, index) {
                    final step = _steps[index];
                    final target = step['target'] as Map<String, dynamic>?;
                    final color = step['color'] as Map<String, dynamic>?;
                    final label = target?['text'] as String? ??
                        target?['resourceId'] as String? ??
                        target?['className'] as String? ??
                        '坐标点击';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 13,
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
                                    step['type'] as String,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (color != null)
                              Container(
                                width: 18,
                                height: 18,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: Color(color['color'] as int),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.black12),
                                ),
                              ),
                            Text(
                              '${step['delay']}ms',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _steps.removeAt(index);
                                });
                              },
                              child: Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.redAccent.withValues(alpha: 0.8),
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: '返回录制',
                    onTap: () {
                      setState(() => _showEditor = false);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    label: '保存宏',
                    filled: true,
                    onTap: () => _showSaveDialog(context, provider),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _startRecording(BuildContext context, PluginProvider provider) async {
    if (_smartRecognition) {
      final granted = await NativeChannel.checkScreenCapturePermission();
      if (!granted) {
        final requested = await NativeChannel.requestScreenCapturePermission();
        if (!requested) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('智能识别需要屏幕录制权限'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }
      }
    }

    final started = await provider.startRecording(captureColors: _smartRecognition);
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法开始录制，请检查辅助功能权限'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _stopRecording(PluginProvider provider) async {
    final steps = await provider.stopRecording();
    setState(() {
      _steps = List.from(steps);
      _showEditor = steps.isNotEmpty;
    });
  }

  Future<void> _showSaveDialog(BuildContext context, PluginProvider provider) async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('保存宏'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '宏名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: '描述',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      final name = nameController.text.trim().isEmpty ? '未命名宏' : nameController.text.trim();
      final description = descController.text.trim();
      provider.updateRecordedSteps(_steps);
      final settings = MacroSettings(
        smartRecognition: _smartRecognition,
        loopCount: _infiniteLoop ? 0 : _loopCount,
      );
      final success = await provider.saveMacroPlugin(
        name: name,
        description: description,
        steps: _steps,
        settings: settings,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '宏已保存' : '保存失败'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: success ? Colors.black87 : Colors.redAccent,
          ),
        );
        if (success) {
          Navigator.of(context).pop();
        }
      }
    }
  }
}

class _LoopChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LoopChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.black87 : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: filled ? Colors.black87 : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: filled ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
