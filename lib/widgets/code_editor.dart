import 'dart:math';
import 'package:flutter/material.dart';

/// 通用代码编辑器组件。
///
/// 支持行号、缩进对齐线；可选横向滚动与双指缩放，
/// 用于普通编辑页与全屏专业编辑页。
class CodeEditor extends StatefulWidget {
  final TextEditingController controller;
  final bool showLineNumbers;
  final bool showIndentGuides;
  final bool enableHorizontalScroll;
  final bool enableZoom;
  final EdgeInsets contentPadding;
  final TextStyle style;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;

  const CodeEditor({
    super.key,
    required this.controller,
    this.showLineNumbers = true,
    this.showIndentGuides = true,
    this.enableHorizontalScroll = false,
    this.enableZoom = false,
    this.contentPadding = const EdgeInsets.fromLTRB(8, 12, 12, 12),
    this.style = const TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      color: Color(0xFFE0E0E0),
      height: 1.5,
    ),
    this.decoration,
    this.onChanged,
  });

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final ScrollController _editorScrollController = ScrollController();
  final ScrollController _lineNumberScrollController = ScrollController();

  double _scaleAtStart = 1.0;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _editorScrollController.addListener(_syncLineNumbers);
  }

  @override
  void dispose() {
    _editorScrollController.removeListener(_syncLineNumbers);
    _editorScrollController.dispose();
    _lineNumberScrollController.dispose();
    super.dispose();
  }

  /// 行号区域跟随主编辑区垂直滚动。
  void _syncLineNumbers() {
    if (_lineNumberScrollController.hasClients) {
      _lineNumberScrollController.jumpTo(_editorScrollController.offset);
    }
  }

  double get _singleLineHeight =>
      (widget.style.fontSize ?? 14) * (widget.style.height ?? 1.0) * _scale;

  /// 测量当前字体下 4 个空格的宽度，作为缩进对齐线的间距。
  double _measureIndentWidth(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: '    ', style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    return painter.width;
  }

  /// 计算所有行中最宽一行的宽度，用于横向滚动。
  double _computeMaxLineWidth(TextStyle style) {
    final lines = widget.controller.text.split('\n');
    final painter = TextPainter(textDirection: TextDirection.ltr);
    double maxWidth = 0;
    for (final line in lines) {
      painter.text = TextSpan(text: line, style: style);
      painter.layout(minWidth: 0, maxWidth: double.infinity);
      if (painter.width > maxWidth) maxWidth = painter.width;
    }
    return maxWidth;
  }

  /// 根据文本折行情况计算每一逻辑行对应的高度。
  List<double> _computeLineHeights(double maxWidth, TextStyle style) {
    final lines = widget.controller.text.split('\n');
    if (widget.enableHorizontalScroll) {
      // 横向滚动模式下文本不折行，每逻辑行都是单行高度。
      return List.filled(lines.length, _singleLineHeight);
    }
    final painter = TextPainter(textDirection: TextDirection.ltr);
    return lines.map((line) {
      painter.text = TextSpan(text: line, style: style);
      painter.layout(minWidth: 0, maxWidth: maxWidth);
      final visualLines = painter.computeLineMetrics().length;
      return visualLines * _singleLineHeight;
    }).toList();
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _scaleAtStart = _scale;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final newScale = (_scaleAtStart * details.scale).clamp(0.8, 2.5);
    if ((newScale - _scale).abs() > 0.01) {
      setState(() => _scale = newScale);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, child) {
            final scaledStyle = widget.style.copyWith(
              fontSize: (widget.style.fontSize ?? 14) * _scale,
            );
            final lineNumberStyle = scaledStyle.copyWith(
              color: const Color(0xFF6E6E6E),
            );
            final indentWidth = widget.showIndentGuides
                ? _measureIndentWidth(scaledStyle)
                : 0.0;

            final gutterWidth = widget.showLineNumbers
                ? max(
                    42.0,
                    '${widget.controller.text.split('\n').length}'.length *
                            14.0 +
                        20.0)
                : 0.0;
            final editorWidth = constraints.maxWidth - gutterWidth;
            final maxLineWidth = widget.enableHorizontalScroll
                ? _computeMaxLineWidth(scaledStyle)
                : 0.0;
            final contentWidth = widget.enableHorizontalScroll
                ? max(editorWidth,
                    maxLineWidth + widget.contentPadding.horizontal)
                : editorWidth;

            final lineHeights = _computeLineHeights(
              contentWidth - widget.contentPadding.horizontal,
              scaledStyle,
            );

            final editor = Stack(
              children: [
                if (widget.showIndentGuides)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _IndentGuidePainter(
                        indentWidth: indentWidth,
                        color: const Color(0xFFE0E0E0)
                            .withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                TextField(
                  controller: widget.controller,
                  scrollController: _editorScrollController,
                  maxLines: null,
                  expands: true,
                  style: scaledStyle,
                  decoration: (widget.decoration ??
                          const InputDecoration(border: InputBorder.none))
                      .copyWith(contentPadding: widget.contentPadding),
                  onChanged: widget.onChanged,
                ),
              ],
            );

            Widget editorArea = widget.enableHorizontalScroll
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: contentWidth,
                      child: editor,
                    ),
                  )
                : SizedBox(width: contentWidth, child: editor);

            if (widget.enableZoom) {
              editorArea = GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                child: editorArea,
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.showLineNumbers)
                  _buildLineNumberGutter(
                      lineHeights, gutterWidth, lineNumberStyle),
                Expanded(child: editorArea),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLineNumberGutter(
      List<double> lineHeights, double width, TextStyle style) {
    return Container(
      width: width,
      color: const Color(0xFF1A1A1A),
      child: SingleChildScrollView(
        controller: _lineNumberScrollController,
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(
            top: widget.contentPadding.top,
            bottom: widget.contentPadding.bottom,
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
                  style: style,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// 缩进对齐线绘制器。
///
/// 按 4 空格宽度的倍数绘制垂直参考线，模拟普通 IDE 的缩进提示效果。
class _IndentGuidePainter extends CustomPainter {
  final double indentWidth;
  final Color color;

  _IndentGuidePainter({required this.indentWidth, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (indentWidth <= 0) return;
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
