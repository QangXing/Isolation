import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/floater_config.dart';
import '../models/plugin.dart';
import '../providers/plugin_provider.dart';
import '../services/native_channel.dart';
import '../widgets/glass_card.dart';
import '../widgets/programming_type_sheet.dart';
import 'coordinate_debug_screen.dart';
import 'default_floater_settings_screen.dart';
import 'floater_settings_screen.dart';
import 'macro_settings_screen.dart';
import 'program_macro_screen.dart';
import 'floater_editor_screen.dart';
import 'programming_screen.dart';
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
                            label: '编程',
                            onTap: () => _showProgrammingOptions(context),
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
                    // 默认悬浮球（含显示开关与外观配置入口）
                    const _DefaultFloaterSection(),
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
                      final isFloater = plugin.isFloater;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PluginListItem(
                          plugin: plugin,
                          isMacro: isMacro,
                          isFloater: isFloater,
                          onToggle: (value) => _setPluginEnabled(context, provider, plugin.id, value),
                          onEditCode: () => _editCode(context, plugin.id, isFloater: isFloater),
                          onSettings: () => _openSettings(context, plugin.id, isFloater: isFloater),
                          onExport: () => _exportPlugin(context, provider, plugin.id),
                          onDelete: () => provider.deletePlugin(plugin.id),
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

  Future<void> _showProgrammingOptions(BuildContext context) async {
    final type = await showModalBottomSheet<ProgrammingType>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const ProgrammingTypeSheet(),
    );
    if (type == null || !context.mounted) return;
    if (type == ProgrammingType.macro) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProgramMacroScreen()),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProgrammingScreen()),
      );
    }
  }

  void _editAsProgramMacro(BuildContext context, String pluginId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProgramMacroScreen(pluginId: pluginId),
      ),
    );
  }

  void _editAsFloater(BuildContext context, String pluginId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FloaterEditorScreen(pluginId: pluginId),
      ),
    );
  }

  void _editCode(BuildContext context, String pluginId, {required bool isFloater}) {
    if (isFloater) {
      _editAsFloater(context, pluginId);
    } else {
      _editAsProgramMacro(context, pluginId);
    }
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

  void _openFloaterSettings(BuildContext context, String pluginId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FloaterSettingsScreen(pluginId: pluginId)),
    );
  }

  void _openSettings(BuildContext context, String pluginId, {required bool isFloater}) {
    if (isFloater) {
      _openFloaterSettings(context, pluginId);
    } else {
      _openMacroSettings(context, pluginId);
    }
  }

  Future<void> _setPluginEnabled(BuildContext context, PluginProvider provider, String pluginId, bool enabled) async {
    await provider.setEnabled(pluginId, enabled);
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

/// 插件列表项卡片：显示名称/类型、启用开关与操作按钮。
class _PluginListItem extends StatelessWidget {
  final Plugin plugin;
  final bool isMacro;
  final bool isFloater;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onEditCode;
  final VoidCallback onSettings;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _PluginListItem({
    required this.plugin,
    required this.isMacro,
    required this.isFloater,
    required this.onToggle,
    this.onEditCode,
    required this.onSettings,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final typeLabel = isFloater ? ' · 球' : (isMacro ? ' · 宏' : '');
    return GlassCard(
      child: Column(
        children: [
          Row(
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
                      'v${plugin.version}$typeLabel',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              _CustomSwitch(value: plugin.enabled, onChanged: onToggle),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onEditCode != null)
                _IconAction(
                  icon: Icons.code_rounded,
                  tooltip: '编辑代码',
                  onTap: onEditCode!,
                ),
              _IconAction(
                icon: Icons.settings_rounded,
                tooltip: '设置',
                onTap: onSettings,
              ),
              _IconAction(
                icon: Icons.share_rounded,
                tooltip: '导出',
                onTap: onExport,
              ),
              _IconAction(
                icon: Icons.delete_outline_rounded,
                tooltip: '删除',
                danger: true,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CustomSwitch({required this.value, required this.onChanged});

  @override
  State<_CustomSwitch> createState() => _CustomSwitchState();
}

class _CustomSwitchState extends State<_CustomSwitch> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(covariant _CustomSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _value = !_value);
        widget.onChanged(_value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50,
        height: 28,
        decoration: BoxDecoration(
          color: _value ? Colors.black87 : Colors.black.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: _value ? Alignment.centerRight : Alignment.centerLeft,
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

/// 默认悬浮球入口：包含显示/隐藏开关、外观参数摘要和图标预览。
class _DefaultFloaterSection extends StatefulWidget {
  const _DefaultFloaterSection();

  @override
  State<_DefaultFloaterSection> createState() => _DefaultFloaterSectionState();
}

class _DefaultFloaterSectionState extends State<_DefaultFloaterSection> {
  bool _loading = true;
  FloaterConfig _config = const FloaterConfig();
  String? _iconPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<PluginProvider>();
    final config = await provider.loadDefaultFloaterConfig();
    final icon = await NativeChannel.getFloatingBallIcon();
    if (mounted) {
      setState(() {
        _config = config;
        _iconPath = icon;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const GlassCard(
        child: SizedBox(
          height: 72,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Selector<PluginProvider, bool>(
      selector: (_, provider) => provider.floatingBallVisible,
      builder: (context, visible, child) {
        return GlassCard(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DefaultFloaterSettingsScreen()),
            );
            await _load();
          },
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(_config.cornerRadius.toDouble()),
                ),
                clipBehavior: Clip.antiAlias,
                child: _iconPath != null && File(_iconPath!).existsSync()
                    ? Image.file(
                        File(_iconPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.touch_app_rounded,
                          color: Colors.black.withValues(alpha: 0.6),
                          size: 24,
                        ),
                      )
                    : Icon(
                        Icons.touch_app_rounded,
                        color: Colors.black.withValues(alpha: 0.6),
                        size: 24,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '默认悬浮球',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      visible
                          ? '悬浮球已显示在屏幕上'
                          : '圆角 ${_config.cornerRadius}dp · 大小 ${_config.size}dp · ${_iconPath != null ? "自定义图标" : "默认图标"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.withValues(alpha: 0.7),
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
        );
      },
    );
  }

  Future<void> _onToggle(BuildContext context, bool value) async {
    final provider = context.read<PluginProvider>();
    final hasOverlay = await NativeChannel.checkOverlayPermission();
    final hasNotification = await NativeChannel.checkNotificationPermission();

    if (value && !hasOverlay) {
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
      return;
    }

    if (value && !hasNotification) {
      await NativeChannel.requestNotificationPermission();
    }

    await provider.setFloatingBallVisible(value);
  }
}
