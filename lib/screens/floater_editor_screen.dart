import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plugin_provider.dart';
import '../services/macro_program_parser.dart';
import '../services/macro_syntax_highlighter.dart';
import '../widgets/code_editor.dart';

class FloaterEditorScreen extends StatefulWidget {
  /// 编辑现有 floaterPlugin 时传入 pluginId；新建时不传。
  final String? pluginId;

  const FloaterEditorScreen({super.key, this.pluginId});

  @override
  State<FloaterEditorScreen> createState() => _FloaterEditorScreenState();
}

class _FloaterEditorScreenState extends State<FloaterEditorScreen> {
  final CodeEditingController _codeController = CodeEditingController();
  bool _loading = true;
  String _initialName = '';
  String _initialDescription = '';

  static const String _template = '''ball(main, "mainBall") {
    size(64)
    cornerRadius(16)
    image("main.png")
    location("mainBall", 100, 200)
    status(show, "mainBall")

    singleClick(Launch_macro)

    doubleClick {
        launch("com.example.app", timeout=3000) {
        }
    }

    tripleClick(Turn_off_macros)

    longPress {
        print("长按主球")
    }
}

ball(deputy, "helper") {
    size(48)
    cornerRadius(24)
    image("helper.png")
    location("helper", 0, 0)
    status(hide, "helper")
}

// 副球显示在主球右侧
mainX = found("mainBall", x)
mainY = found("mainBall", y)
location("helper", mainX + 80, mainY)
status(show, "helper")
''';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.pluginId != null) {
      final provider = context.read<PluginProvider>();
      try {
        final source = await provider.loadFloaterSource(widget.pluginId!);
        if (source != null) {
          _codeController.text = source;
        } else {
          _codeController.text = _template;
        }
        final plugin = provider.plugins.firstWhere((p) => p.id == widget.pluginId);
        _initialName = plugin.name;
        _initialDescription = plugin.description;
      } catch (e, s) {
        debugPrint('加载 floater 源码失败: $e\n$s');
        _codeController.text = _template;
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
          widget.pluginId == null ? '新建编程球' : '编辑编程球',
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
                Expanded(child: _buildCodeEditor()),
                _buildBottomBar(context),
              ],
            ),
    );
  }

  Widget _buildCodeEditor() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.hardEdge,
      child: CodeEditor(
        controller: _codeController,
        showLineNumbers: true,
        showIndentGuides: true,
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: '在此输入悬浮球 DSL…',
          hintStyle: TextStyle(color: Color(0xFF757575)),
        ),
        onChanged: (_) => setState(() {}),
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
                label: '保存',
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
      final program = MacroProgramParser.parseFloaterProgram(_codeController.text);
      final ballCount = program.balls.length;
      final hasMain = program.mainBall != null;
      final formatted = _formatDsl(_codeController.text);
      if (formatted != _codeController.text) {
        _codeController.text = formatted;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '校验通过：$ballCount 个球（主球 ${hasMain ? "√" : "×"}）',
          ),
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

  /// 对 DSL 源码进行简单格式化：根据大括号增减 4 空格缩进。
  String _formatDsl(String source) {
    final lines = LineSplitter().convert(source);
    final buffer = StringBuffer();
    var indent = 0;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        buffer.writeln();
        continue;
      }
      final openBraces = '{'.allMatches(line).length;
      final closeBraces = '}'.allMatches(line).length;
      if (closeBraces > 0) {
        indent = (indent - closeBraces).clamp(0, indent).toInt();
      }
      buffer.writeln('${'    ' * indent}$line');
      if (openBraces > 0) {
        indent += openBraces;
      }
    }
    return buffer.toString();
  }

  Future<void> _showSaveDialog(BuildContext context) async {
    final nameController = TextEditingController(text: _initialName);
    final descController = TextEditingController(text: _initialDescription);

    try {
      MacroProgramParser.parseFloaterProgram(_codeController.text);
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

    final provider = context.read<PluginProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('保存编程球'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '名称',
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

    final name = nameController.text.trim().isEmpty
        ? '未命名编程球'
        : nameController.text.trim();
    final description = descController.text.trim();

    bool success;
    try {
      success = await provider.saveFloaterPlugin(
        name: name,
        description: description,
        source: _codeController.text,
        pluginId: widget.pluginId,
      );
    } catch (e) {
      success = false;
      debugPrint('保存编程球失败: $e');
    }

    if (mounted) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(success ? '编程球已保存' : '保存失败'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: success ? Colors.black87 : Colors.redAccent,
        ),
      );
      if (success) {
        navigator.pop();
      }
    }
  }
}

class _IndentGuidePainter extends CustomPainter {
  final double indentWidth;
  final Color color;

  _IndentGuidePainter({required this.indentWidth, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final maxLevels = (size.width / indentWidth).ceil();
    for (int i = 1; i < maxLevels; i++) {
      final x = i * indentWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
