import 'package:flutter/material.dart';
import '../services/macro_syntax_highlighter.dart';

/// 专业编程区。
///
/// 全屏代码编辑器,无顶栏,左侧显示行号,底部显示快捷符号条。
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
  final ScrollController _editorScrollController = ScrollController();
  final ScrollController _lineNumberScrollController = ScrollController();
  late final Widget _editorField;

  static const List<String> _quickSymbolsRow1 = [
    '{', '}', '(', ')', ';', ',', '%', '=', '"', "'", '[', ']', '#', '->',
  ];
  static const List<String> _quickSymbolsRow2 = [
    '+', '-', '*', '/', '<', '>', '\\', '|', '&', '!', '~', ':', '_', '<-',
  ];

  static const double _gutterWidth = 42;
  static const double _fontSize = 14;
  static const double _lineHeightFactor = 1.5;
  static const EdgeInsets _contentPadding = EdgeInsets.fromLTRB(8, 12, 12, 12);

  static const TextStyle _textStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: _fontSize,
    color: Color(0xFFE0E0E0),
    height: _lineHeightFactor,
  );

  static final TextStyle _lineNumberStyle = _textStyle.copyWith(
    color: const Color(0xFF6E6E6E),
  );

  double get _singleLineHeight => _fontSize * _lineHeightFactor;

  @override
  void initState() {
    super.initState();
    _controller = CodeEditingController(text: widget.initialText);
    _editorField = _buildEditor();
    _editorScrollController.addListener(_syncLineNumbers);
  }

  @override
  void dispose() {
    _editorScrollController.removeListener(_syncLineNumbers);
    _editorScrollController.dispose();
    _lineNumberScrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncLineNumbers() {
    if (_lineNumberScrollController.hasClients) {
      _lineNumberScrollController.jumpTo(_editorScrollController.offset);
    }
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
            Expanded(child: _buildEditorArea()),
            _buildQuickSymbolBar(),
            _buildBottomActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final editorWidth = constraints.maxWidth - _gutterWidth;
        final textWidth = (editorWidth - _contentPadding.horizontal).clamp(
          0.0,
          double.infinity,
        );
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, child) {
            final lineHeights = _computeLineHeights(textWidth);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLineNumberGutter(lineHeights),
                Expanded(child: child!),
              ],
            );
          },
          child: _editorField,
        );
      },
    );
  }

  List<double> _computeLineHeights(double maxWidth) {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: const TextSpan(),
    );
    return _controller.text.split('\n').map((line) {
      painter.text = TextSpan(text: line, style: _textStyle);
      painter.layout(minWidth: 0, maxWidth: maxWidth);
      final visualLines = painter.computeLineMetrics().length;
      return visualLines * _singleLineHeight;
    }).toList();
  }

  Widget _buildLineNumberGutter(List<double> lineHeights) {
    return Container(
      width: _gutterWidth,
      color: const Color(0xFF1A1A1A),
      child: SingleChildScrollView(
        controller: _lineNumberScrollController,
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(
            top: _contentPadding.top,
            bottom: _contentPadding.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(lineHeights.length, (index) {
              return Container(
                height: lineHeights[index],
                alignment: Alignment.topRight,
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${index + 1}',
                  style: _lineNumberStyle,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return TextField(
      controller: _controller,
      scrollController: _editorScrollController,
      maxLines: null,
      expands: true,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      style: _textStyle,
      decoration: const InputDecoration(
        contentPadding: _contentPadding,
        border: InputBorder.none,
        hintText: '在此输入宏代码…',
        hintStyle: TextStyle(color: Color(0xFF757575)),
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
