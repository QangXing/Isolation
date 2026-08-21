import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/plugin.dart';
import '../providers/plugin_provider.dart';
import '../widgets/glass_card.dart';
import 'floater_assets_screen.dart';

class FloaterSettingsScreen extends StatefulWidget {
  final String pluginId;

  const FloaterSettingsScreen({super.key, required this.pluginId});

  @override
  State<FloaterSettingsScreen> createState() => _FloaterSettingsScreenState();
}

class _FloaterSettingsScreenState extends State<FloaterSettingsScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _loading = true;
  bool _pinned = false;
  String? _iconName;
  String? _iconPath;

  static const Map<String, IconData> _presetIcons = {
    'touch': Icons.touch_app_rounded,
    'mouse': Icons.mouse_rounded,
    'gamepad': Icons.gamepad_rounded,
    'smartToy': Icons.smart_toy_rounded,
    'android': Icons.android_rounded,
    'favorite': Icons.favorite_rounded,
    'star': Icons.star_rounded,
    'flash': Icons.flash_on_rounded,
    'rocket': Icons.rocket_rounded,
    'settings': Icons.settings_rounded,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = context.read<PluginProvider>();
    final plugin = provider.plugins.cast<Plugin?>().firstWhere(
          (p) => p?.id == widget.pluginId,
          orElse: () => null,
        );
    if (mounted) {
      setState(() {
        _nameController.text = plugin?.name ?? '';
        _descriptionController.text = plugin?.description ?? '';
        _iconName = plugin?.iconName;
        _iconPath = plugin?.iconPath;
        _pinned = plugin?.pinned ?? false;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final provider = context.read<PluginProvider>();
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();

    final success = await provider.updateFloaterMetadata(
      widget.pluginId,
      name: name,
      description: description,
      iconName: _iconName,
      iconPath: _iconPath,
    );
    if (success) {
      await provider.updatePluginPin(widget.pluginId, _pinned);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '设置已保存' : '保存失败'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: success ? Colors.black87 : Colors.redAccent,
        ),
      );
      if (success) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _showIconPicker() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '设置图标',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _presetIcons.entries.map((entry) {
                  final selected = _iconName == entry.key;
                  return GestureDetector(
                    onTap: () => Navigator.of(context).pop('preset:${entry.key}'),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: selected ? Colors.black87 : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        entry.value,
                        color: selected ? Colors.white : Colors.black.withValues(alpha: 0.6),
                        size: 24,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.of(context).pop('pick'),
                child: GlassCard(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library_rounded,
                          size: 18, color: Colors.black.withValues(alpha: 0.7)),
                      const SizedBox(width: 8),
                      const Text(
                        '从相册选择',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_iconName != null || _iconPath != null)
                GestureDetector(
                  onTap: () => Navigator.of(context).pop('reset'),
                  child: GlassCard(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.replay_rounded,
                            size: 18, color: Colors.black.withValues(alpha: 0.7)),
                        const SizedBox(width: 8),
                        const Text(
                          '恢复默认',
                          style: TextStyle(
                            fontSize: 14,
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
    );

    if (action == null) return;
    if (action.startsWith('preset:')) {
      setState(() {
        _iconName = action.substring(7);
        _iconPath = null;
      });
    } else if (action == 'pick') {
      await _pickIconFromGallery();
    } else if (action == 'reset') {
      setState(() {
        _iconName = null;
        _iconPath = null;
      });
    }
  }

  Future<void> _pickIconFromGallery() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final sourcePath = result.files.single.path;
    if (sourcePath == null || !mounted) return;

    final appDir = await getApplicationDocumentsDirectory();
    final ext = path.extension(result.files.single.name);
    final tempIcon = File('${appDir.path}/floater_icon_temp$ext');
    await File(sourcePath).copy(tempIcon.path);

    setState(() {
      _iconPath = tempIcon.path;
      _iconName = null;
    });
  }

  void _openAssets() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FloaterAssetsScreen(pluginId: widget.pluginId),
      ),
    );
  }

  Widget _buildIconPreview() {
    if (_iconPath != null && File(_iconPath!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(_iconPath!),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
        ),
      );
    }
    final preset = _iconName != null ? _presetIcons[_iconName] : null;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        preset ?? Icons.extension_rounded,
        color: Colors.black.withValues(alpha: 0.6),
        size: 24,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          '编程球设置',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.85),
            fontWeight: FontWeight.w500,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Colors.black.withValues(alpha: 0.7)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '名称',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                hintText: '输入编程球名称',
                                hintStyle: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.3),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.1),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.1),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: Colors.black87),
                                ),
                                filled: true,
                                fillColor: Colors.black.withValues(alpha: 0.03),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '简介',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _descriptionController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: '输入编程球简介（会显示在插件卡片下方）',
                                hintStyle: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.3),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.1),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.1),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: Colors.black87),
                                ),
                                filled: true,
                                fillColor: Colors.black.withValues(alpha: 0.03),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: _showIconPicker,
                        child: GlassCard(
                          child: Row(
                            children: [
                              _buildIconPreview(),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '图标设置',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _iconPath != null
                                          ? '已使用自定义图标'
                                          : (_iconName != null ? '已选择预设图标' : '点击选择图标'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.withValues(alpha: 0.7),
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
                      const SizedBox(height: 14),
                      _buildSwitchCard(
                        icon: Icons.push_pin_rounded,
                        title: '置顶卡片',
                        subtitle: '在首页和管理区列表中优先显示该卡片',
                        value: _pinned,
                        onChanged: (value) {
                          setState(() {
                            _pinned = value;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: _openAssets,
                        child: GlassCard(
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
                                  Icons.folder_open_rounded,
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
                                      '文件导入',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '导入或删除图片、音频素材',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.withValues(alpha: 0.7),
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
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: SafeArea(
                    top: false,
                    child: GestureDetector(
                      onTap: _save,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text(
                            '保存设置',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSwitchCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GlassCard(
      child: Row(
        children: [
          Icon(icon, size: 22, color: Colors.black.withValues(alpha: 0.6)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.45),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CustomSwitch(value: value, onChanged: onChanged),
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
