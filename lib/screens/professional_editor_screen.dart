import 'package:flutter/material.dart';
import '../services/macro_syntax_highlighter.dart';
import '../widgets/code_editor.dart';

/// 专业编程区（全屏编辑器）。
///
/// 支持双指缩放、横向滚动、文本延伸至屏幕外，并带有行号与缩进对齐线。
class ProfessionalEditorScreen extends StatefulWidget {
  final String initialText;

  const ProfessionalEditorScreen({
    super.key,
    required this.initialText,
  });

  @override
  State<ProfessionalEditorScreen> createState() =>
      _ProfessionalEditorScreenState();
}

class _ProfessionalEditorScreenState extends State<ProfessionalEditorScreen> {
  late final CodeEditingController _controller;

  static const List<String> _quickSymbolsRow1 = [
    '{', '}', '(', ')', ';', ',', '%', '=', '"', "'", '[', ']', '#', '->',
  ];
  static const List<String> _quickSymbolsRow2 = [
    '+', '-', '*', '/', '<', '>', '\\', '|', '&', '!', '~', ':', '_', '<-',
  ];

  @override
  void initState() {
    super.initState();
    _controller = CodeEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _insertSymbol(String symbol) {
    final sel = _controller.selection;
    final text = _controller.text;
    final pos = sel.baseOffset.clamp(0, text.length);
    final newText = text.substring(0, pos) + symbol + text.substring(pos);
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: pos + symbol.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CodeEditor(
                controller: _controller,
                showLineNumbers: true,
                showIndentGuides: true,
                enableHorizontalScroll: true,
                enableZoom: true,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '在此输入宏代码…',
                  hintStyle: TextStyle(color: Color(0xFF757575)),
                ),
              ),
            ),
            _buildQuickSymbolBar(),
            _buildBottomActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSymbolBar() {
    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildQuickSymbolRow(_quickSymbolsRow1),
          const SizedBox(height: 6),
          _buildQuickSymbolRow(_quickSymbolsRow2),
        ],
      ),
    );
  }

  Widget _buildQuickSymbolRow(List<String> symbols) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: symbols.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final symbol = symbols[index];
          return GestureDetector(
            onTap: () => _insertSymbol(symbol),
            child: Container(
              width: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                symbol,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFFE0E0E0),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.close, size: 18, color: Color(0xFFE0E0E0)),
                  SizedBox(width: 6),
                  Text(
                    '取消',
                    style: TextStyle(color: Color(0xFFE0E0E0), fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(_controller.text),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check, size: 18, color: Colors.black87),
                  SizedBox(width: 6),
                  Text(
                    '完成',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
