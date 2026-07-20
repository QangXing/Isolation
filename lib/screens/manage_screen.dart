import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/plugin_provider.dart';
import '../widgets/glass_card.dart';
import 'coordinate_debug_screen.dart';
import 'macro_settings_screen.dart';
import 'program_macro_screen.dart';
import 'recording_screen.dart';

class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PluginProvider>(
      builder: (context, provider, child) {
        final plugins = provider.plugins.where((p) => !p.builtIn).toList();
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  '管理',
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
                child: Column(
                  children: [
                    // 主操作：3 个等宽按钮
                    Row(
                      children: [
                        Expanded(
                          child: _ActionTile(
                            icon: Icons.fiber_manual_record_rounded,
                            label: '新建宏',
                            onTap: () => _createMacro(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ActionTile(
                            icon: Icons.code_rounded,
                            label: '编程宏',
                            onTap: () => _createProgramMacro(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ActionTile(
                            icon: Icons.add_rounded,
                            label: '导入',
                            onTap: () => _importPlugin(context, provider),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 辅助操作：坐标调试（占满整行，与主操作区分）
                    _ActionTile(
                      icon: Icons.my_location_rounded,
                      label: '坐标调试',
                      onTap: () => _openCoordinateDebug(context),
                      full: true,
                    ),
                  ],
                ),
              ),
            ),
            if (plugins.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    '暂无导入的插件',
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
                      final plugin = plugins[index];
                      final isMacro = plugin.actions.any((a) => a.type == 'macro');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      plugin.name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'v${plugin.version}${isMacro ? ' · 宏' : ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isMacro)
                                _IconAction(
                                  icon: Icons.code_rounded,
                                  tooltip: '编辑代码',
                                  onTap: () => _editAsProgramMacro(context, plugin.id),
                                ),
                              if (isMacro)
                                _IconAction(
                                  icon: Icons.settings_rounded,
                                  tooltip: '设置',
                                  onTap: () => _openMacroSettings(context, plugin.id),
                                ),
                              if (isMacro)
                                _IconAction(
                                  icon: Icons.share_rounded,
                                  tooltip: '导出',
                                  onTap: () => _exportPlugin(context, provider, plugin.id),
                                ),
                              _IconAction(
                                icon: Icons.delete_outline_rounded,
                                tooltip: '删除',
                                danger: true,
                                onTap: () => provider.deletePlugin(plugin.id),
                              ),
                            ],
                          ),
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

  void _createMacro(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RecordingScreen()),
    );
  }

  void _createProgramMacro(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProgramMacroScreen()),
    );
  }

  void _editAsProgramMacro(BuildContext context, String pluginId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProgramMacroScreen(pluginId: pluginId),
      ),
    );
  }

  void _openCoordinateDebug(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CoordinateDebugScreen()),
    );
  }

  void _openMacroSettings(BuildContext context, String pluginId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MacroSettingsScreen(pluginId: pluginId)),
    );
  }

  Future<void> _importPlugin(BuildContext context, PluginProvider provider) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['isoplugin', 'zip'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    final success = await provider.importPlugin(path);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '插件导入成功' : '插件导入失败'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: success ? Colors.black87 : Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _exportPlugin(BuildContext context, PluginProvider provider, String pluginId) async {
    final path = await provider.exportMacroPlugin(pluginId);
    if (path == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('导出失败'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    await Share.shareXFiles([XFile(path)]);
  }
}

/// 管理页顶部的动作按钮卡片。
/// 统一高度、统一样式，[full] 控制是否横向占满。
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool full;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.full = false,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: Colors.black.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.black.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 插件卡片右侧的图标按钮。统一尺寸与间距，[danger] 标记危险操作。
class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? Colors.redAccent
        : Colors.black.withValues(alpha: 0.6);
    final bg = danger
        ? Colors.red.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(8),
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}
