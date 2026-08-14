import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 指令说明页。
///
/// 提供两个独立入口：宏指令查询（DSL_SPEC.md）与球指令查询（BALL_SPEC.md），
/// 分别对应宏教程与编程球教程。
class InstructionManualScreen extends StatelessWidget {
  const InstructionManualScreen({super.key});

  static const String _dslSpecUrl =
      'https://github.com/QangXing/Isolation/blob/main/docs/DSL_SPEC.md';
  static const String _ballSpecUrl =
      'https://github.com/QangXing/Isolation/blob/main/docs/BALL_SPEC.md';

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '指令说明',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 宏指令查询
              Card(
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.menu_book_rounded,
                        size: 56,
                        color: Colors.black54,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '宏指令查询',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '点击查看宏脚本的完整 DSL 语法规范，包括点击、查找、循环、变量等全部宏指令说明。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _openUrl(_dslSpecUrl),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('查看 DSL_SPEC.md'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 球指令查询
              Card(
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.sports_basketball_rounded,
                        size: 56,
                        color: Colors.black54,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '球指令查询',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '点击查看编程球插件的专用指令规范，包括悬浮球外观配置、事件监听、#include 引用等内容。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _openUrl(_ballSpecUrl),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('查看 BALL_SPEC.md'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
