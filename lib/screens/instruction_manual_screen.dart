import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 宏指令说明书。
///
/// 点击后跳转到 GitHub 仓库的 DSL_SPEC.md 查看最新完整语法规范。
class InstructionManualScreen extends StatelessWidget {
  const InstructionManualScreen({super.key});

  static const String _dslSpecUrl =
      'https://github.com/QangXing/Isolation/blob/main/docs/DSL_SPEC.md';

  Future<void> _openSpec() async {
    final uri = Uri.parse(_dslSpecUrl);
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
          child: Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    'DSL 指令规范',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '最新、完整的宏指令语法说明已迁移到 GitHub 仓库的 DSL_SPEC.md，点击下面按钮即可查看。',
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
                      onPressed: _openSpec,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('查看 DSL_SPEC.md'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
