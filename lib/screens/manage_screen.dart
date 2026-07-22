import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/plugin_provider.dart';
import '../services/native_channel.dart';
import '../widgets/glass_card.dart';
import 'coordinate_debug_screen.dart';
import 'image_crop_screen.dart';
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
                    const SizedBox(height: 12),
                    // 悬浮球总开关
                    _FloatingBallToggle(),
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

/// 悬浮球显示/隐藏总开关，附带自定义图标入口。
class _FloatingBallToggle extends StatefulWidget {
  const _FloatingBallToggle();

  @override
  State<_FloatingBallToggle> createState() => _FloatingBallToggleState();
}

class _FloatingBallToggleState extends State<_FloatingBallToggle> {
  String? _iconPath;

  @override
  void initState() {
    super.initState();
    _loadIconPath();
  }

  Future<void> _loadIconPath() async {
    final path = await NativeChannel.getFloatingBallIcon();
    if (mounted) setState(() => _iconPath = path);
  }

  @override
  Widget build(BuildContext context) {
    return Selector<PluginProvider, bool>(
      selector: (_, provider) => provider.floatingBallVisible,
      builder: (context, visible, child) {
        return GlassCard(
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: visible
                          ? Colors.black87
                          : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.touch_app_rounded,
                        color: visible ? Colors.white : Colors.black.withValues(alpha: 0.6),
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '显示悬浮球',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          visible ? '悬浮球已显示在屏幕上' : '悬浮球已隐藏',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: visible,
                    onChanged: (value) => _onToggle(context, value),
                    activeColor: Colors.black87,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: Colors.black.withValues(alpha: 0.12),
                  ),
                ],
              ),
              const Divider(height: 24),
              InkWell(
                onTap: () => _showIconOptions(context),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _iconPath != null && File(_iconPath!).existsSync()
                            ? Image.file(
                                File(_iconPath!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.touch_app_rounded,
                                  color: Colors.black.withValues(alpha: 0.6),
                                  size: 20,
                                ),
                              )
                            : Icon(
                                Icons.touch_app_rounded,
                                color: Colors.black.withValues(alpha: 0.6),
                                size: 20,
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '悬浮球图标',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black.withValues(alpha: 0.85),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _iconPath != null ? '已使用自定义图标' : '点击更换图标',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.black.withValues(alpha: 0.3),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onToggle(BuildContext context, bool value) async {
    final provider = context.read<PluginProvider>();
    final hasOverlay = await NativeChannel.checkOverlayPermission();

    if (value && !hasOverlay) {
      // 缺少悬浮窗权限时弹出提示并引导授权
      if (!context.mounted) return;
      final shouldGrant = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('需要权限'),
          content: const Text('显示悬浮球需要悬浮窗权限。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('去授权'),
            ),
          ],
        ),
      );
      if (shouldGrant != true) return;
      await NativeChannel.requestOverlayPermission();
      // 授权页返回后，仍由用户再次点击开关触发；避免自动判断时序问题
      return;
    }

    await provider.setFloatingBallVisible(value);
  }

  Future<void> _showIconOptions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('从相册选择'),
              onTap: () => Navigator.of(context).pop('pick'),
            ),
            if (_iconPath != null)
              ListTile(
                leading: const Icon(Icons.replay_rounded),
                title: const Text('恢复默认'),
                onTap: () => Navigator.of(context).pop('reset'),
              ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('取消'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );

    if (action == 'pick') {
      await _pickAndCropIcon(context);
    } else if (action == 'reset') {
      await _resetIcon(context);
    }
  }

  Future<void> _pickAndCropIcon(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final sourcePath = result.files.single.path;
    if (sourcePath == null || !context.mounted) return;

    final croppedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ImageCropScreen(
          sourcePath: sourcePath,
          maxOutputSize: 128,
          aspectRatio: 1.0,
        ),
      ),
    );
    if (croppedPath == null || !context.mounted) return;

    final appDir = await getApplicationDocumentsDirectory();
    final iconFile = File('${appDir.path}/floating_ball_icon.png');
    await File(croppedPath).copy(iconFile.path);

    final saved = await NativeChannel.setFloatingBallIcon(iconFile.path);
    if (saved) {
      await _loadIconPath();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('悬浮球图标已更新'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.black87,
          ),
        );
      }
    }
  }

  Future<void> _resetIcon(BuildContext context) async {
    final saved = await NativeChannel.setFloatingBallIcon(null);
    if (saved) {
      await _loadIconPath();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已恢复默认图标'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.black87,
          ),
        );
      }
    }
  }
}
