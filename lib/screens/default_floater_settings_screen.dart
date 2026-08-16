import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/floater_config.dart';
import '../providers/plugin_provider.dart';
import '../services/native_channel.dart';
import '../widgets/glass_card.dart';
import 'image_crop_screen.dart';

class DefaultFloaterSettingsScreen extends StatefulWidget {
  const DefaultFloaterSettingsScreen({super.key});

  @override
  State<DefaultFloaterSettingsScreen> createState() => _DefaultFloaterSettingsScreenState();
}

class _DefaultFloaterSettingsScreenState extends State<DefaultFloaterSettingsScreen> {
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

  Future<void> _save() async {
    final provider = context.read<PluginProvider>();
    await provider.saveDefaultFloaterConfig(_config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设置已保存'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
        ),
      );
    }
  }

  Future<void> _pickIcon() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final sourcePath = result.files.single.path;
    if (sourcePath == null || !mounted) return;

    final croppedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ImageCropScreen(
          sourcePath: sourcePath,
          maxOutputSize: 128,
          aspectRatio: 1.0,
        ),
      ),
    );
    if (croppedPath == null || !mounted) return;

    final appDir = await getApplicationDocumentsDirectory();
    final iconFile = File('${appDir.path}/floating_ball_icon.png');
    await File(croppedPath).copy(iconFile.path);

    final saved = await NativeChannel.setFloatingBallIcon(iconFile.path);
    if (saved && mounted) {
      setState(() => _iconPath = iconFile.path);
      await _save();
    }
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
          '默认悬浮球',
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
                      // 预览
                      Column(
                        children: [
                          Text(
                            '预览',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.black.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: _config.size.toDouble(),
                            height: _config.size.toDouble(),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(_config.cornerRadius.toDouble()),
                              image: _iconPath != null && File(_iconPath!).existsSync()
                                  ? DecorationImage(
                                      image: FileImage(File(_iconPath!)),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _iconPath == null || !File(_iconPath!).existsSync()
                                ? Icon(
                                    Icons.touch_app_rounded,
                                    color: Colors.black.withValues(alpha: 0.6),
                                    size: (_config.size * 0.4).clamp(20, 48).toDouble(),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${_config.size}dp · 圆角 ${_config.cornerRadius}dp',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.black.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // 外观
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '外观',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Text(
                                  '圆角',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.black.withValues(alpha: 0.7),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_config.cornerRadius}dp',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.black.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: Colors.black87,
                                inactiveTrackColor: Colors.black.withValues(alpha: 0.1),
                                thumbColor: Colors.black87,
                                overlayColor: Colors.black.withValues(alpha: 0.08),
                                trackHeight: 5,
                              ),
                              child: Slider(
                                value: _config.cornerRadius.toDouble(),
                                min: 0,
                                max: 60,
                                onChanged: (value) {
                                  setState(() {
                                    _config = _config.copyWith(cornerRadius: value.round());
                                  });
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Text(
                                  '大小',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.black.withValues(alpha: 0.7),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_config.size}dp',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.black.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Slider(
                              value: _config.size.toDouble(),
                              min: 40,
                              max: 120,
                              onChanged: (value) {
                                setState(() {
                                  _config = _config.copyWith(size: value.round());
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 图标
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '图标',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 16),
                            GestureDetector(
                              onTap: _pickIcon,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.image_rounded, color: Colors.white, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      '选择图片',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
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
                      const SizedBox(height: 16),
                      // 说明
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '说明',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildBullet('圆角 28dp 对应 56dp 大小时的正圆形。'),
                            _buildBullet('大小推荐 48-96dp 之间，过小不易点击，过大遮挡屏幕。'),
                            _buildBullet('修改参数后会实时同步到当前悬浮球；若悬浮球未显示，参数会在下一次开启时生效。'),
                          ],
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
                        width: double.infinity,
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

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 7),
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: Colors.black.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
