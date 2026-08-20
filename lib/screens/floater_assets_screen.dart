import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import '../providers/plugin_provider.dart';
import '../widgets/glass_card.dart';
import 'image_crop_screen.dart';

class FloaterAssetsScreen extends StatefulWidget {
  final String pluginId;

  const FloaterAssetsScreen({super.key, required this.pluginId});

  @override
  State<FloaterAssetsScreen> createState() => _FloaterAssetsScreenState();
}

class _FloaterAssetsScreenState extends State<FloaterAssetsScreen> {
  List<String> _assets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    final provider = context.read<PluginProvider>();
    final assets = await provider.listMacroAssets(widget.pluginId);
    if (mounted) {
      setState(() {
        _assets = assets;
        _loading = false;
      });
    }
  }

  Future<void> _importImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final sourcePath = result.files.single.path;
    if (sourcePath == null) return;

    String assetPath = sourcePath;
    final ext = path.extension(sourcePath).toLowerCase();
    if (ext != '.gif') {
      if (!mounted) return;
      final croppedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => ImageCropScreen(sourcePath: sourcePath),
        ),
      );
      if (croppedPath == null) return;
      assetPath = croppedPath;
    }

    final provider = context.read<PluginProvider>();
    final originalName = path.basename(sourcePath);
    final fileName = await provider.importMacroAsset(
      widget.pluginId,
      assetPath,
      desiredName: originalName,
    );
    await _loadAssets();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(fileName != null ? '已导入 $fileName' : '导入失败'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: fileName != null ? Colors.black87 : Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _importAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final sourcePath = result.files.single.path;
    if (sourcePath == null) return;

    final provider = context.read<PluginProvider>();
    final fileName = await provider.importMacroAsset(widget.pluginId, sourcePath);
    await _loadAssets();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(fileName != null ? '已导入 $fileName' : '导入失败'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: fileName != null ? Colors.black87 : Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _deleteAsset(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('删除资源'),
        content: Text('确定删除 $name 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final provider = context.read<PluginProvider>();
    await provider.deleteMacroAsset(widget.pluginId, name);
    await _loadAssets();
    if (mounted) setState(() {});
  }

  Future<void> _renameAsset(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('重命名资源'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '新文件名',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || newName == oldName) return;

    final provider = context.read<PluginProvider>();
    final result = await provider.renameMacroAsset(widget.pluginId, oldName, newName);
    await _loadAssets();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result != null ? '已重命名为 $result' : '重命名失败'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: result != null ? Colors.black87 : Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _previewAsset(String name) async {
    if (!_isImage(name)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('仅支持预览图片资源'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.black87,
          ),
        );
      }
      return;
    }
    final provider = context.read<PluginProvider>();
    final filePath = await provider.macroAssetPath(widget.pluginId, name);
    if (filePath == null || !mounted) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(
            File(filePath),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  bool _isImage(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp');
  }

  bool _isAudio(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.flac');
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
          '编程球资源',
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _importImage,
                          child: GlassCard(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image_rounded,
                                    size: 18, color: Colors.black.withValues(alpha: 0.7)),
                                const SizedBox(width: 8),
                                const Text(
                                  '导入图片',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _importAudio,
                          child: GlassCard(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.audiotrack_rounded,
                                    size: 18, color: Colors.black.withValues(alpha: 0.7)),
                                const SizedBox(width: 8),
                                const Text(
                                  '导入音频',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _assets.isEmpty
                      ? Center(
                          child: Text(
                            '暂无资源，点击上方按钮导入',
                            style: TextStyle(
                              color: Colors.grey.withValues(alpha: 0.7),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _assets.length,
                          itemBuilder: (context, index) {
                            final name = _assets[index];
                            final isImage = _isImage(name);
                            final isAudio = _isAudio(name);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: GlassCard(
                                child: Row(
                                  children: [
                                    Icon(
                                      isImage
                                          ? Icons.image_rounded
                                          : isAudio
                                              ? Icons.audiotrack_rounded
                                              : Icons.insert_drive_file_rounded,
                                      size: 22,
                                      color: Colors.black.withValues(alpha: 0.6),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _previewAsset(name),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.visibility_rounded,
                                          size: 18,
                                          color: Colors.black.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => _renameAsset(name),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.edit_rounded,
                                          size: 18,
                                          color: Colors.black.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => _deleteAsset(name),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
