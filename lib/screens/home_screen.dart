import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plugin_provider.dart';
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
                      final isMacro = plugin.actions.any((a) => a.isMacro);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: PluginCard(
                          plugin: plugin,
                          executing: provider.executing && plugin.enabled,
                          onEnabledChanged: (value) {
                            provider.setEnabled(plugin.id, value);
                          },
                          onRun: () async {
                            if (isMacro) {
                              if (provider.executing) {
                                await provider.stopMacro();
                              } else {
                                await provider.runMacro(plugin);
                              }
                            } else if (plugin.actions.isNotEmpty) {
                              _showActions(context, plugin);
                            }
                          },
                          onEdit: () {
                            if (isMacro) {
                              _editMacro(context, plugin);
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

  void _editMacro(BuildContext context, plugin) {
    // Handled in manage screen; show a hint for built-in macro.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请在管理页长按或导出宏插件'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
      ),
    );
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
