import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/floater_config.dart';
import '../providers/plugin_provider.dart';
import '../services/native_channel.dart';
import '../widgets/glass_card.dart';

class DefaultFloaterSettingsScreen extends StatefulWidget {
  const DefaultFloaterSettingsScreen({super.key});

  @override
  State<DefaultFloaterSettingsScreen> createState() => _DefaultFloaterSettingsScreenState();
}

class _DefaultFloaterSettingsScreenState extends State<DefaultFloaterSettingsScreen> {
  FloaterConfig _config = const FloaterConfig();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await context.read<PluginProvider>().loadDefaultFloaterConfig();
    if (mounted) {
      setState(() {
        _config = config;
        _loading = false;
      });
    }
  }

  Future<void> _update(FloaterConfig config) async {
    await context.read<PluginProvider>().saveDefaultFloaterConfig(config);
    await NativeChannel.applyDefaultFloaterConfig(
      cornerRadius: config.cornerRadius,
      size: config.size,
      imagePath: config.imagePath,
    );
    setState(() => _config = config);
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result?.files.single.path == null) return;
    final appDir = await getApplicationDocumentsDirectory();
    final source = result!.files.single.path!;
    final target = File('${appDir.path}/default_floater_image${path.extension(source)}');
    await File(source).copy(target.path);
    await _update(_config.copyWith(imagePath: target.path));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('图片已更新'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
        ),
      );
    }
  }

  Future<void> _resetImage() async {
    await _update(_config.copyWith(imagePath: null));
  }

  Future<void> _resetDefaults() async {
    await _update(const FloaterConfig());
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
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildPreview(),
                const SizedBox(height: 20),
                _buildParamsCard(),
                const SizedBox(height: 14),
                _buildImageCard(),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _resetDefaults,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        '恢复默认',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPreview() {
    final size = _config.size.toDouble();
    final radius = _config.cornerRadius.toDouble();
    return Center(
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _config.imagePath != null && File(_config.imagePath!).existsSync()
                ? Image.file(
                    File(_config.imagePath!),
                    fit: BoxFit.cover,
                  )
                : const Icon(
                    Icons.touch_app_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            '预览',
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParamsCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '外观',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '圆角: ${_config.cornerRadius}dp',
            style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.6)),
          ),
          Slider(
            value: _config.cornerRadius.toDouble(),
            min: 0,
            max: 28,
            divisions: 28,
            activeColor: Colors.black87,
            inactiveColor: Colors.black.withValues(alpha: 0.1),
            onChanged: (v) => _update(_config.copyWith(cornerRadius: v.round())),
          ),
          Text(
            '大小: ${_config.size}dp',
            style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.6)),
          ),
          Slider(
            value: _config.size.toDouble(),
            min: 40,
            max: 80,
            divisions: 40,
            activeColor: Colors.black87,
            inactiveColor: Colors.black.withValues(alpha: 0.1),
            onChanged: (v) => _update(_config.copyWith(size: v.round())),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard() {
    final hasImage = _config.imagePath != null && File(_config.imagePath!).existsSync();
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasImage
                ? Image.file(
                    File(_config.imagePath!),
                    fit: BoxFit.cover,
                  )
                : Icon(
                    Icons.image_rounded,
                    color: Colors.black.withValues(alpha: 0.5),
                    size: 24,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '图标',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasImage ? '已使用自定义图片' : '使用默认图标',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          if (hasImage)
            GestureDetector(
              onTap: _resetImage,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '恢复默认',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                hasImage ? '更换图片' : '选择图片',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
