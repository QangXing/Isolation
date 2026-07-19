import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/plugin_provider.dart';
import '../widgets/glass_card.dart';
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
                child: Row(
                  children: [
                    Expanded(
                      child: GlassCard(
                        onTap: () => _createMacro(context),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.fiber_manual_record_rounded,
                              color: Colors.black.withValues(alpha: 0.7),
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
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassCard(
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
                                GestureDetector(
                                  onTap: () => _exportPlugin(context, provider, plugin.id),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.share_rounded,
                                      color: Colors.black.withValues(alpha: 0.6),
                                      size: 20,
                                    ),
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
