import 'package:flutter/material.dart';
import '../services/macro_syntax_highlighter.dart';

/// 宏指令说明书。
///
/// 列出所有支持的 DSL 指令、语法、说明和示例。
class InstructionManualScreen extends StatelessWidget {
  const InstructionManualScreen({super.key});

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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _SectionTitle('基础操作'),
          _InstructionCard(
            title: '点击坐标',
            syntax: 'click(x, y)',
            description: '在屏幕指定坐标执行一次点击。',
            example: 'click(500, 800)',
          ),
          _InstructionCard(
            title: '点击当前目标',
            syntax: 'click()',
            description: '只能写在 find 块内部,点击 find 找到的目标。',
            example: 'find(text="签到") {\n  click()\n}',
          ),
          _InstructionCard(
            title: '滑动/滚动',
            syntax: 'roll(dx, dy, duration)',
            description: '从当前位置按相对偏移滑动。duration 单位为毫秒。',
            example: 'roll(0, 300, 400)',
          ),
          _InstructionCard(
            title: '输入文字',
            syntax: 'input("文字")',
            description: '在已聚焦的输入框中输入文字。',
            example: 'input("Hello world")',
          ),
          _InstructionCard(
            title: '等待',
            syntax: 'wait(ms)',
            description: '暂停指定毫秒。',
            example: 'wait(1000)',
          ),
          _InstructionCard(
            title: '打印日志',
            syntax: 'print("文字")',
            description: '在调试日志中输出信息。',
            example: 'print("开始执行任务")',
          ),
          _SectionTitle('查找目标'),
          _InstructionCard(
            title: '按文字查找',
            syntax: 'find(text="...") { ... }',
            description: '查找屏幕上包含指定文字的节点,然后执行块内指令。',
            example: 'find(text="签到") {\n  click()\n  wait(500)\n}',
          ),
          _InstructionCard(
            title: '按颜色查找',
            syntax: 'find(color=0xRRGGBB, tolerance=10) { ... }',
            description: '在屏幕中查找最近匹配颜色,将坐标压入栈,块内 click() 使用该坐标。',
            example: 'find(color=0xFF5000, tolerance=20) {\n  click()\n}',
          ),
          _InstructionCard(
            title: '按图片查找',
            syntax: 'find(image="图片路径", feature="orb", minMatches=6, threshold=0.8) { ... }',
            description: '在屏幕中查找与参考图片最匹配的位置。threshold 为相似度阈值,范围 0~1。\nfeature: orb（默认）/ akaze / template，template 仅使用传统模板匹配。\nminMatches: 特征点匹配通过的最少内点数，默认 6。\n执行图片/颜色查找时若未授权屏幕录制，会自动弹出授权。',
            example: 'find(image="/sdcard/Pictures/btn.png", feature="akaze", minMatches=8, threshold=0.85) {\n  click()\n}',
          ),
          _InstructionCard(
            title: '限定查找区域',
            syntax: 'find(..., region=[x, y, x2, y2]) { ... }',
            description: '只在指定矩形区域内查找目标。',
            example: 'find(text="确定", region=[100, 500, 900, 1100]) {\n  click()\n}',
          ),
          _SectionTitle('流程控制'),
          _InstructionCard(
            title: '条件判断',
            syntax: 'if(find(...)) { ... } else { ... }',
            description: '如果找到目标则执行 then 块,否则执行 else 块(else 可省略)。',
            example: 'if(find(text="同意")) {\n  click()\n} else {\n  print("未找到")\n}',
          ),
          _InstructionCard(
            title: '按图片条件判断',
            syntax: 'if(find(image="...", threshold=0.8)) { ... }',
            description: '如果屏幕中存在匹配图片,则执行 then 块。',
            example: 'if(find(image="popup.png", threshold=0.85)) {\n  click()\n  wait(500)\n}',
          ),
          _InstructionCard(
            title: '循环',
            syntax: 'for(n) { ... }',
            description: '将块内指令重复执行 n 次。',
            example: 'for(3) {\n  roll(0, 300, 400)\n  wait(500)\n}',
          ),
          _InstructionCard(
            title: '无限循环查找',
            syntax: 'find(loop) { ... }',
            description: '找到目标后持续循环执行块内指令,直到通过三连击悬浮球手动停止。适用于轮询签到、刷新奖励等场景。',
            example: 'find(loop) {\n  find(text="签到") {\n    click()\n    wait(1000)\n  }\n}',
          ),
          _SectionTitle('系统按键'),
          _InstructionCard(
            title: '返回 / 主页 / 最近任务',
            syntax: 'back() / home() / recents()',
            description: '模拟系统按键。',
            example: 'back()\nhome()\nrecents()',
          ),
          _SectionTitle('注意事项'),
          _BulletCard([
            'click() 没有参数时必须放在 find 块内,否则无法执行。',
            '坐标、颜色等数值均使用屏幕像素坐标系。',
            '图片路径可以是绝对路径,建议把图片放在宏资源目录下。',
            'find 的 tolerance 越大,颜色匹配越宽松,默认 20。',
            'if 条件目前支持 find(text/color/image)。',
          ]),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.black54,
        ),
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  final String title;
  final String syntax;
  final String description;
  final String example;

  const _InstructionCard({
    required this.title,
    required this.syntax,
    required this.description,
    required this.example,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            _CodeBlock(syntax),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '示例',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black38,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _CodeBlock(example),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulletCard extends StatelessWidget {
  final List<String> items;
  const _BulletCard(this.items);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: Colors.black54)),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String code;
  const _CodeBlock(this.code);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            fontFamily: 'monospace',
          ),
          children: MacroSyntaxHighlighter.highlight(code),
        ),
      ),
    );
  }
}
