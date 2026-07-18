import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/macro.dart';
import '../providers/macro_provider.dart';
import '../services/native_channel.dart';
import '../widgets/glass_card.dart';
import 'macro_settings_screen.dart';
import 'record_macro_screen.dart';

class MacrosScreen extends StatelessWidget {
  const MacrosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MacroProvider>(
      builder: (context, provider, child) {
        if (!provider.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final macros = provider.macros;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  '宏',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                    color: Colors.black.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverToBoxAdapter(
                child: GlassCard(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RecordMacroScreen()),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.fiber_manual_record_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '录制新宏',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (macros.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    '暂无宏，点击上方录制',
                    style: TextStyle(
                      color: Colors.grey.withValues(alpha: 0.6),
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
                      final macro = macros[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          macro.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${macro.steps.length} 步 · ${macro.loop ? '循环' : '单次'} · ${macro.smartRecognition ? '智能识别开启' : '智能识别关闭'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _buildSwitch(
                                    macro,
                                    (value) => _onEnabledChanged(context, macro, value),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _buildActionChip(
                                    context,
                                    icon: Icons.play_arrow_rounded,
                                    label: '执行',
                                    onTap: macro.steps.isEmpty
                                        ? null
                                        : () => _executeMacro(context, macro, provider),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildActionChip(
                                    context,
                                    icon: Icons.settings_rounded,
                                    label: '设置',
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => MacroSettingsScreen(macro: macro),
                                      ),
                                    ),
                                  ),
                                  if (!macro.builtIn) ...[
                                    const SizedBox(width: 8),
                                    _buildActionChip(
                                      context,
                                      icon: Icons.delete_outline_rounded,
                                      label: '删除',
                                      color: Colors.redAccent,
                                      onTap: () => _confirmDelete(context, macro),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: macros.length,
                  ),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        );
      },
    );
  }

  Widget _buildSwitch(Macro macro, ValueChanged<bool> onChanged) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: macro.enabled
            ? Colors.black87
            : Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Switch(
        value: macro.enabled,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: Colors.transparent,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: Colors.transparent,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildActionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color color = Colors.black87,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: onTap == null
              ? Colors.grey.shade200
              : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: onTap == null ? Colors.grey.shade400 : color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: onTap == null ? Colors.grey.shade400 : color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onEnabledChanged(BuildContext context, Macro macro, bool enabled) async {
    final provider = context.read<MacroProvider>();
    if (enabled) {
      final hasOverlay = await NativeChannel.checkOverlayPermission();
      final hasAccessibility = await NativeChannel.checkAccessibilityPermission();
      if (!hasOverlay) {
        await NativeChannel.requestOverlayPermission();
      }
      if (!hasAccessibility) {
        await NativeChannel.requestAccessibilityPermission();
      }
      await NativeChannel.startFloatingBall();
    }
    await provider.setEnabled(macro.id, enabled);
  }

  Future<void> _executeMacro(BuildContext context, Macro macro, MacroProvider provider) async {
    final hasAccessibility = await NativeChannel.checkAccessibilityPermission();
    if (!hasAccessibility) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先开启辅助功能权限')),
        );
      }
      await NativeChannel.requestAccessibilityPermission();
      return;
    }
    await provider.executeMacro(macro);
  }

  Future<void> _confirmDelete(BuildContext context, Macro macro) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('删除宏'),
        content: Text('确定删除 "${macro.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<MacroProvider>().deleteMacro(macro.id);
    }
  }
}
