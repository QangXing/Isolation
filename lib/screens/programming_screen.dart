import 'package:flutter/material.dart';
import '../widgets/glass_card.dart';
import 'floater_editor_screen.dart';
import 'program_macro_screen.dart';

enum _ProgrammingTab { macro, floater }

class ProgrammingScreen extends StatefulWidget {
  const ProgrammingScreen({super.key});

  @override
  State<ProgrammingScreen> createState() => _ProgrammingScreenState();
}

class _ProgrammingScreenState extends State<ProgrammingScreen> {
  _ProgrammingTab _tab = _ProgrammingTab.floater;

  final List<_ListItemData> _macroItems = const [
    _ListItemData(
      name: '每日签到宏',
      description: '打开目标 App 后自动点击签到按钮（示例宏，请录制替换...',
      icon: Icons.touch_app_rounded,
      enabled: false,
    ),
    _ListItemData(
      name: '未命名宏',
      description: '',
      icon: Icons.extension_rounded,
      enabled: false,
    ),
  ];

  final List<_ListItemData> _floaterItems = const [
    _ListItemData(
      name: '默认悬浮球',
      description: '与系统内置悬浮球效果完全一致的默认模板，可自定义外...',
      icon: Icons.touch_app_rounded,
      enabled: false,
    ),
    _ListItemData(
      name: '未命名编程球',
      description: '',
      icon: Icons.favorite_rounded,
      enabled: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final items = _tab == _ProgrammingTab.macro ? _macroItems : _floaterItems;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'isolation',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                    color: Colors.black.withValues(alpha: 0.85),
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Icon(Icons.code_rounded, size: 22, color: Colors.black.withValues(alpha: 0.7)),
                    const SizedBox(width: 8),
                    Text(
                      '编程',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withValues(alpha: 0.85),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _createNew(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_circle_outline_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _tab == _ProgrammingTab.macro ? '新建编程宏' : '新建编程球',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    _TabChip(
                      label: '编程宏',
                      selected: _tab == _ProgrammingTab.macro,
                      onTap: () => setState(() => _tab = _ProgrammingTab.macro),
                    ),
                    const SizedBox(width: 10),
                    _TabChip(
                      label: '球',
                      selected: _tab == _ProgrammingTab.floater,
                      onTap: () => setState(() => _tab = _ProgrammingTab.floater),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = items[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ProgrammingListItem(
                        data: item,
                        onToggle: (value) {
                          // UI only: no functional change
                        },
                      ),
                    );
                  },
                  childCount: items.length,
                ),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      ),
    );
  }

  void _createNew(BuildContext context) {
    if (_tab == _ProgrammingTab.macro) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProgramMacroScreen()),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FloaterEditorScreen()),
      );
    }
  }
}

class _ListItemData {
  final String name;
  final String description;
  final IconData icon;
  final bool enabled;

  const _ListItemData({
    required this.name,
    required this.description,
    required this.icon,
    required this.enabled,
  });
}

class _ProgrammingListItem extends StatefulWidget {
  final _ListItemData data;
  final ValueChanged<bool>? onToggle;

  const _ProgrammingListItem({required this.data, this.onToggle});

  @override
  State<_ProgrammingListItem> createState() => _ProgrammingListItemState();
}

class _ProgrammingListItemState extends State<_ProgrammingListItem> {
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.data.enabled;
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              widget.data.icon,
              color: Colors.black.withValues(alpha: 0.6),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.data.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (widget.data.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.data.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.withValues(alpha: 0.7),
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildSwitch(),
        ],
      ),
    );
  }

  Widget _buildSwitch() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _enabled = !_enabled);
        widget.onToggle?.call(_enabled);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50,
        height: 28,
        decoration: BoxDecoration(
          color: _enabled
              ? Colors.black87
              : Colors.grey.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: _enabled ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.black87 : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
