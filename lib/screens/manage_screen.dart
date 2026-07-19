import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/plugin.dart';
import '../providers/plugin_provider.dart';
import '../services/native_channel.dart';
import '../widgets/glass_card.dart';
import 'macro_edit_screen.dart';
import 'macro_record_screen.dart';

class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PluginProvider>(
      builder: (context, provider, child) {
        final macros = provider.plugins.where(_isMacro).toList();
        final others = provider.plugins.where((p) => !_isMacro(p) && !p.builtIn).toList();
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
                    GlassCard(
                      onTap: () => _createMacro(context),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.fiber_manual_record_rounded,
                            color: Colors.redAccent.withValues(alpha: 0.8),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '新建宏',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      onTap: () => _importPlugin(context, provider),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_rounded,
                            color: Colors.black.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '导入插件',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (macros.isNotEmpty)
              _buildSectionTitle(context, '宏插件'),
            if (macros.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final plugin = macros[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _MacroListTile(
                          plugin: plugin,
                          onExport: () => _exportMacro(context, provider, plugin),
                          onEdit: () => _editMacro(context, plugin),
                          onDelete: plugin.builtIn
                              ? null
                              : () => provider.deletePlugin(plugin.id),
                        ),
                      );
                    },
                    childCount: macros.length,
                  ),
                ),
              ),
            if (others.isNotEmpty)
              _buildSectionTitle(context, '其他插件'),
            if (others.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final plugin = others[index];
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
                                      'v${plugin.version}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => provider.deletePlugin(plugin.id),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: others.length,
                  ),
                ),
              ),
            if (macros.isEmpty && others.isEmpty)
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
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Future<void> _editMacro(BuildContext context, Plugin plugin) async {
    final steps = await NativeChannel.loadMacroSteps(plugin);
    if (steps == null || steps.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('无法读取宏步骤'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MacroEditScreen(
            steps: steps,
            editingId: plugin.id,
          ),
        ),
      );
    }
  }

  Future<void> _createMacro(BuildContext context) async {
    final hasAccessibility = await context.read<PluginProvider>().ensureAccessibility(context);
    if (!hasAccessibility) return;
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MacroRecordScreen()),
      );
    }
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

  Future<void> _exportMacro(
    BuildContext context,
    PluginProvider provider,
    Plugin plugin,
  ) async {
    final path = await provider.exportPlugin(plugin.id);
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
    await Share.shareXFiles([XFile(path)], text: '${plugin.name}.isoplugin');
  }

  static bool _isMacro(Plugin p) => p.actions.any((a) => a.isMacro);
}

class _MacroListTile extends StatelessWidget {
  final Plugin plugin;
  final VoidCallback? onExport;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _MacroListTile({
    required this.plugin,
    this.onExport,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
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
                  'v${plugin.version}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.edit_rounded,
                color: Colors.black54,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onExport,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.share_rounded,
                color: Colors.blueAccent,
                size: 20,
              ),
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 20,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension PluginProviderExtension on PluginProvider {
  Future<bool> ensureAccessibility(BuildContext context) async {
    final has = await NativeChannel.checkAccessibilityPermission();
    if (has) return true;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('录制需要辅助功能权限'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
        ),
      );
      await NativeChannel.requestAccessibilityPermission();
    }
    return false;
  }
}
