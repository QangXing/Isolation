import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/macro.dart';
import '../providers/plugin_provider.dart';
import '../services/macro_program_parser.dart';
import '../widgets/glass_card.dart';

class ProgramMacroScreen extends StatefulWidget {
  /// 编辑现有宏时传入 pluginId；新建时不传。
  final String? pluginId;

  const ProgramMacroScreen({super.key, this.pluginId});

  @override
  State<ProgramMacroScreen> createState() => _ProgramMacroScreenState();
}

class _ProgramMacroScreenState extends State<ProgramMacroScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _smartRecognition = false;
  int _loopCount = 1;
  bool _infiniteLoop = false;
  bool _loading = true;
  String _initialName = '';

  static const String _template = '''// 编程宏示例
print("开始")
// 通过颜色找到目标后点击
find(color=0xFF5000, tolerance=20) {
    click()
    wait(500)
}
// 通过节点文字找到目标后点击
find(text="签到") {
    click()
    roll(0, 300, 400)
    wait(500)
}
for(3) {
    roll(0, 300, 400)
    wait(500)
}
if(find(color=0x00FF00)) {
    click()
} else {
    print("今日无奖励")
}
print("完成")
''';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.pluginId != null) {
      final provider = context.read<PluginProvider>();
      final data = await provider.loadMacroData(widget.pluginId!);
      if (data != null) {
        _codeController.text = MacroProgramParser.serialize(data.steps);
        _smartRecognition = data.settings.smartRecognition;
        _loopCount = data.settings.loopCount == 0 ? 1 : data.settings.loopCount;
        _infiniteLoop = data.settings.loopCount <= 0;
        final plugin =
            provider.plugins.firstWhere((p) => p.id == widget.pluginId);
        _initialName = plugin.name;
      }
    } else {
      _codeController.text = _template;
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
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
          widget.pluginId == null ? '编程宏' : '编辑编程宏',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.85),
            fontWeight: FontWeight.w500,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded,
              color: Colors.black.withValues(alpha: 0.7)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildInstructionBar(),
                Expanded(child: _buildCodeEditor()),
                _buildSettingsPanel(),
                _buildBottomBar(context),
              ],
            ),
    );
  }

  Widget _buildInstructionBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _InstructionChip(
              label: 'click(x,y)',
              icon: Icons.touch_app_rounded,
              onTap: () => _insert('click(500, 800)'),
            ),
            _InstructionChip(
              label: 'click()',
              icon: Icons.ads_click_rounded,
              onTap: () => _insert('click()'),
            ),
            _InstructionChip(
              label: 'roll',
              icon: Icons.swipe_down_rounded,
              onTap: () => _insert('roll(0, 300, 500)'),
            ),
            _InstructionChip(
              label: 'print',
              icon: Icons.chat_bubble_outline_rounded,
              onTap: () => _insert('print("提示文字")'),
            ),
            _InstructionChip(
              label: 'wait',
              icon: Icons.timer_outlined,
              onTap: () => _insert('wait(1000)'),
            ),
            _InstructionChip(
              label: 'for',
              icon: Icons.loop_rounded,
              onTap: () => _insert('for(5) {\n    \n}'),
            ),
            _InstructionChip(
              label: 'find(text=)',
              icon: Icons.find_in_page_outlined,
              onTap: () => _insert('find(text="领取") {\n    click()\n}'),
            ),
            _InstructionChip(
              label: 'find(color=)',
              icon: Icons.colorize_rounded,
              onTap: () => _insert('find(color=0xFF5000, tolerance=20) {\n    click()\n}'),
            ),
            _InstructionChip(
              label: 'if',
              icon: Icons.call_split_rounded,
              onTap: () =>
                  _insert('if(find(color=0x00FF00)) {\n    click()\n} else {\n    print("未找到")\n}'),
            ),
            _InstructionChip(
              label: 'back',
              icon: Icons.arrow_back_rounded,
              onTap: () => _insert('back()'),
            ),
            _InstructionChip(
              label: 'home',
              icon: Icons.home_outlined,
              onTap: () => _insert('home()'),
            ),
          ],
        ),
      ),
    );
  }

  void _insert(String snippet) {
    final sel = _codeController.selection;
    final text = _codeController.text;
    final pos = sel.baseOffset.clamp(0, text.length);
    final newPos = pos + snippet.length;
    _codeController.text = text.substring(0, pos) + snippet + text.substring(pos);
    _codeController.selection = TextSelection.collapsed(offset: newPos);
    setState(() {});
  }

  Widget _buildCodeEditor() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: _codeController,
        maxLines: null,
        expands: true,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          color: Color(0xFFE0E0E0),
          height: 1.5,
        ),
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.all(16),
          border: InputBorder.none,
          hintText: '在此输入宏代码…',
          hintStyle: TextStyle(color: Color(0xFF757575)),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.colorize_rounded,
                  size: 18, color: Colors.black.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '智能识别（局部像素颜色）',
                  style: TextStyle(
                      fontSize: 13, color: Colors.black.withValues(alpha: 0.75)),
                ),
              ),
              Switch(
                value: _smartRecognition,
                onChanged: (v) => setState(() => _smartRecognition = v),
                activeColor: Colors.black87,
              ),
            ],
          ),
          if (!_infiniteLoop)
            Row(
              children: [
                Icon(Icons.loop_rounded,
                    size: 18, color: Colors.black.withValues(alpha: 0.6)),
                const SizedBox(width: 8),
                Text('循环次数',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.black.withValues(alpha: 0.75))),
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
              Icon(Icons.all_inclusive_rounded,
                  size: 18, color: Colors.black.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '无限循环（三连击悬浮球停止）',
                  style: TextStyle(
                      fontSize: 13, color: Colors.black.withValues(alpha: 0.75)),
                ),
              ),
              Switch(
                value: _infiniteLoop,
                onChanged: (v) => setState(() => _infiniteLoop = v),
                activeColor: Colors.black87,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: '校验',
                onTap: _validate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                label: '保存宏',
                filled: true,
                onTap: () => _showSaveDialog(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _validate() {
    try {
      final steps = MacroProgramParser.parse(_codeController.text);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('校验通过：${steps.length} 个顶层指令'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
        ),
      );
    } on MacroParseError catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('解析失败：$e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _showSaveDialog(BuildContext context) async {
    final nameController = TextEditingController(text: _initialName);
    final descController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('保存编程宏'),
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

    if (saved != true || !mounted) return;

    final provider = context.read<PluginProvider>();
    List<Map<String, dynamic>> steps;
    try {
      steps = MacroProgramParser.parse(_codeController.text);
    } on MacroParseError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('解析失败：$e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    if (steps.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('宏内容为空'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final name =
        nameController.text.trim().isEmpty ? '未命名宏' : nameController.text.trim();
    final description = descController.text.trim();
    final settings = MacroSettings(
      smartRecognition: _smartRecognition,
      loopCount: _infiniteLoop ? 0 : _loopCount,
    );

    final success = await provider.saveMacroPlugin(
      name: name,
      description: description,
      steps: steps,
      settings: settings,
      pluginId: widget.pluginId,
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

class _InstructionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _InstructionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.black.withValues(alpha: 0.7)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
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
