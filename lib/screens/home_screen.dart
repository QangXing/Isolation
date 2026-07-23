import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plugin_provider.dart';
import '../services/native_channel.dart';
import '../widgets/glass_card.dart';
import '../widgets/plugin_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PluginProvider>(
      builder: (context, provider, child) {
        if (!provider.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final plugins = provider.plugins;
        return CustomScrollView(
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
            if (plugins.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: GlassCard(
                    child: Text(
                      '暂无插件，请在管理页导入',
                      style: TextStyle(
                        color: Colors.grey.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final plugin = plugins[index];
                      final isMacro = plugin.actions.any((a) => a.type == 'macro');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: PluginCard(
                          plugin: plugin,
                          onEnabledChanged: (value) {
                            provider.setEnabled(plugin.id, value);
                          },
                          trailing: isMacro && plugin.enabled
                              ? _RunButton(
                                  running: provider.runningMacroId == plugin.id,
                                  onTap: () => _runMacro(context, provider, plugin.id),
                                )
                              : null,
                          onTap: () {
                            if (isMacro) {
                              _runMacro(context, provider, plugin.id);
                            } else if (plugin.actions.isNotEmpty) {
                              _showActions(context, plugin);
                            }
                          },
                        ),
                      );
                    },
                    childCount: plugins.length,
                  ),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        );
      },
    );
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
      if (children != null && _usesColorOrImage(children.cast<Map<String, dynamic>>())) {
        return true;
      }
      final then = step['then'] as List<dynamic>?;
      if (then != null && _usesColorOrImage(then.cast<Map<String, dynamic>>())) {
        return true;
      }
      final elseBranch = step['else'] as List<dynamic>?;
      if (elseBranch != null && _usesColorOrImage(elseBranch.cast<Map<String, dynamic>>())) {
        return true;
      }
    }
    return false;
  }

  Future<void> _runMacro(BuildContext context, PluginProvider provider, String pluginId) async {
    final data = await provider.loadMacroData(pluginId);
    if (data != null && (data.settings.loopCount <= 0 || _usesColorOrImage(data.steps))) {
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

  void _showActions(BuildContext context, plugin) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plugin.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: plugin.actions.map<Widget>((action) {
                  return ActionButton(
                    label: action.label,
                    onTap: () {
                      context.read<PluginProvider>().executeAction(action);
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RunButton extends StatelessWidget {
  final bool running;
  final VoidCallback onTap;

  const _RunButton({required this.running, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: running ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: running ? Colors.grey.withValues(alpha: 0.2) : Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (running)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 6),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ),
            Text(
              running ? '运行中' : '运行',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const ActionButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }
}
