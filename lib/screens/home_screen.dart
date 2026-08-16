import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/plugin.dart';
import '../providers/plugin_provider.dart';
import '../services/native_channel.dart';
import '../widgets/glass_card.dart';
import '../widgets/plugin_card.dart';
import 'floater_editor_screen.dart';
import 'program_macro_screen.dart';

enum _HomeTab { macro, floater }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _HomeTab _tab = _HomeTab.macro;

  @override
  Widget build(BuildContext context) {
    return Consumer<PluginProvider>(
      builder: (context, provider, child) {
        if (!provider.loaded) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final plugins = provider.plugins;
        final macros = plugins.where((p) => !p.isFloater).toList();
        final floaters = plugins.where((p) => p.isFloater).toList();
        final items = _tab == _HomeTab.macro ? macros : floaters;

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
                        Icon(
                          Icons.code_rounded,
                          size: 22,
                          color: Colors.black.withValues(alpha: 0.7),
                        ),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.add_circle_outline_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _tab == _HomeTab.macro ? '新建编程宏' : '新建编程球',
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
                          selected: _tab == _HomeTab.macro,
                          onTap: () => setState(() => _tab = _HomeTab.macro),
                        ),
                        const SizedBox(width: 10),
                        _TabChip(
                          label: '球',
                          selected: _tab == _HomeTab.floater,
                          onTap: () => setState(() => _tab = _HomeTab.floater),
                        ),
                      ],
                    ),
                  ),
                ),
                if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: GlassCard(
                        child: Text(
                          _tab == _HomeTab.macro
                              ? '暂无编程宏，请在管理页导入或新建'
                              : '暂无编程球，请在管理页导入或新建',
                          style: TextStyle(
                            color: Colors.grey.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final plugin = items[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: PluginCard(
                              plugin: plugin,
                              onEnabledChanged: (value) => _onEnabledChanged(
                                context,
                                provider,
                                plugin,
                                value,
                              ),
                              onTap: plugin.isFloater
                                  ? null
                                  : () => _runMacro(context, provider, plugin.id),
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
      },
    );
  }

  Future<void> _onEnabledChanged(
    BuildContext context,
    PluginProvider provider,
    Plugin plugin,
    bool value,
  ) async {
    await provider.setEnabled(plugin.id, value);
  }

  Future<void> _runMacro(
      BuildContext context, PluginProvider provider, String pluginId) async {
    final data = await provider.loadMacroData(pluginId);
    if (data != null &&
        (data.settings.loopCount <= 0 || _usesColorOrImage(data.steps))) {
      final granted = await NativeChannel.checkScreenCapturePermission();
      if (!granted) {
        await NativeChannel.requestScreenCapturePermission();
      }
    }
    final success = await provider.runMacroPlugin(pluginId);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('运行失败，请检查辅助功能权限'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  bool _usesColorOrImage(List<Map<String, dynamic>> steps) {
    for (final step in steps) {
      if (step['color'] != null || step['image'] != null) return true;
      final condition = step['condition'] as Map<String, dynamic>?;
      if (condition != null &&
          (condition['color'] != null || condition['image'] != null)) {
        return true;
      }
      final children = step['children'] as List<dynamic>?;
      if (children != null &&
          _usesColorOrImage(children.cast<Map<String, dynamic>>())) {
        return true;
      }
      final then = step['then'] as List<dynamic>?;
      if (then != null && _usesColorOrImage(then.cast<Map<String, dynamic>>())) {
        return true;
      }
      final elseBranch = step['else'] as List<dynamic>?;
      if (elseBranch != null &&
          _usesColorOrImage(elseBranch.cast<Map<String, dynamic>>())) {
        return true;
      }
    }
    return false;
  }

  void _createNew(BuildContext context) {
    if (_tab == _HomeTab.macro) {
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
