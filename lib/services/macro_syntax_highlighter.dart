import 'package:flutter/material.dart';

/// 宏 DSL 语法高亮器。
///
/// 用于代码编辑器,让关键字、字符串、注释、数字显示不同颜色。
class MacroSyntaxHighlighter {
  MacroSyntaxHighlighter._();

  static const List<String> _keywords = [
    'find',
    'if',
    'else',
    'for',
    'while',
    'print',
    'wait',
    'click',
    'roll',
    'swipe',
    'input',
    'back',
    'home',
    'recent',
    'true',
    'false',
  ];

  static const Color _keywordColor = Color(0xFFBB86FC); // 紫色
  static const Color _stringColor = Color(0xFF4CAF50); // 绿色
  static const Color _commentColor = Color(0xFF757575); // 灰色
  static const Color _numberColor = Color(0xFFFF9800); // 橙色
  static const Color _punctuationColor = Color(0xFF90CAF9); // 浅蓝
  static const Color _defaultColor = Color(0xFFE0E0E0); // 浅灰白

  static List<TextSpan> highlight(String code, {TextStyle? baseStyle}) {
    final defaultStyle = (baseStyle ?? const TextStyle())
        .copyWith(color: _defaultColor, fontFamily: 'monospace');
    final keywordStyle = defaultStyle.copyWith(color: _keywordColor);
    final stringStyle = defaultStyle.copyWith(color: _stringColor);
    final commentStyle = defaultStyle.copyWith(
      color: _commentColor,
      fontStyle: FontStyle.italic,
    );
    final numberStyle = defaultStyle.copyWith(color: _numberColor);
    final punctStyle = defaultStyle.copyWith(color: _punctuationColor);

    final spans = <TextSpan>[];
    final regex = RegExp(
      r'("(?:[^"\\]|\\.)*")' // 字符串
      r'|(\/\/.*$)' // 单行注释
      r'|(\b(?:' +
          _keywords.join('|') +
          r')\b)' // 关键字
      r'|(\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)' // 数字
      r'|([(){}\[\],=+\-*/<>!~%|&;:])', // 标点
      multiLine: true,
    );

    var lastEnd = 0;
    for (final match in regex.allMatches(code)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: code.substring(lastEnd, match.start),
          style: defaultStyle,
        ));
      }

      final text = match.group(0)!;
      TextStyle style;
      if (match.group(1) != null) {
        style = stringStyle;
      } else if (match.group(2) != null) {
        style = commentStyle;
      } else if (match.group(3) != null) {
        style = keywordStyle;
      } else if (match.group(4) != null) {
        style = numberStyle;
      } else {
        style = punctStyle;
      }
      spans.add(TextSpan(text: text, style: style));
      lastEnd = match.end;
    }

    if (lastEnd < code.length) {
      spans.add(TextSpan(text: code.substring(lastEnd), style: defaultStyle));
    }

    return spans;
  }
}

/// 带语法高亮的代码编辑控制器。
class CodeEditingController extends TextEditingController {
  CodeEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return TextSpan(
      style: style,
      children: MacroSyntaxHighlighter.highlight(text, baseStyle: style),
    );
  }
}
