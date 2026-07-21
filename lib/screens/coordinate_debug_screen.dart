import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

/// 坐标调试页
///
/// 用户从相册选一张屏幕截图作为背景，在图片上点击任意位置，
/// 获取该点在屏幕坐标系下的坐标与像素颜色，并一键复制为 `click(x, y)` 或
/// `find(color=0xRRGGBB, tolerance=20) { click() }` 代码片段。
///
/// 坐标系约定：图片像素坐标 = Android 屏幕像素坐标
///   - 原点：图片左上角 = 屏幕左上角
///   - 单位：像素（px）
///   - 范围：0 ≤ x < image.width，0 ≤ y < image.height
class CoordinateDebugScreen extends StatefulWidget {
  const CoordinateDebugScreen({super.key});

  @override
  State<CoordinateDebugScreen> createState() => _CoordinateDebugScreenState();
}

class _CoordinateDebugScreenState extends State<CoordinateDebugScreen> {
  img.Image? _image;
  Uint8List? _imagePreviewBytes; // 预编码的图片字节，避免每帧重新编码
  final List<_DebugPoint> _points = [];
  bool _loading = false;

  // 图片在显示区域内的实际尺寸与偏移（fit: contain 的 letterbox 计算）
  Size _imageDisplaySize = Size.zero;
  Offset _imageDisplayOffset = Offset.zero;

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null) return;
    final path = result.files.single.path;
    if (path == null) return;

    setState(() => _loading = true);
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法解析该图片')),
          );
        }
        return;
      }
      setState(() {
        _image = decoded;
        _imagePreviewBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
        _points.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取图片失败：$e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  /// 计算 fit: contain 下图片的实际显示矩形（去掉 letterbox 黑边）。
  void _computeImageRect(BoxConstraints constraints) {
    final image = _image;
    if (image == null) return;
    final cw = constraints.maxWidth;
    final ch = constraints.maxHeight;
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final scale = (cw / iw < ch / ih) ? cw / iw : ch / ih;
    final dw = iw * scale;
    final dh = ih * scale;
    _imageDisplaySize = Size(dw, dh);
    _imageDisplayOffset = Offset((cw - dw) / 2, (ch - dh) / 2);
  }

  void _onTapImage(TapDownDetails details) {
    final image = _image;
    if (image == null || _imageDisplaySize == Size.zero) return;

    final localX = details.localPosition.dx - _imageDisplayOffset.dx;
    final localY = details.localPosition.dy - _imageDisplayOffset.dy;
    if (localX < 0 || localY < 0 ||
        localX > _imageDisplaySize.width ||
        localY > _imageDisplaySize.height) {
      // 点击落在 letterbox 黑边，忽略
      return;
    }

    final scaleX = image.width / _imageDisplaySize.width;
    final scaleY = image.height / _imageDisplaySize.height;
    final imgX = (localX * scaleX).round().clamp(0, image.width - 1);
    final imgY = (localY * scaleY).round().clamp(0, image.height - 1);

    final pixel = image.getPixel(imgX, imgY);
    final r = pixel.r.toInt() & 0xFF;
    final g = pixel.g.toInt() & 0xFF;
    final b = pixel.b.toInt() & 0xFF;
    final color = (r << 16) | (g << 8) | b;

    setState(() {
      _points.add(_DebugPoint(
        x: imgX,
        y: imgY,
        color: color,
        displayX: details.localPosition.dx,
        displayY: details.localPosition.dy,
      ));
    });
  }

  String _colorHex(int color) =>
      '0x${color.toRadixString(16).padLeft(6, '0').toUpperCase()}';

  String _colorCss(int color) {
    final r = (color >> 16) & 0xFF;
    final g = (color >> 8) & 0xFF;
    final b = color & 0xFF;
    return '#${r.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${g.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  Color _flutterColor(int color) => Color(0xFF000000 | color);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          '坐标调试',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w500),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.black54),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_rounded, color: Colors.black54),
            tooltip: '选择截图',
            onPressed: _loading ? null : _pickImage,
          ),
          if (_points.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.black54),
              tooltip: '清空所有点',
              onPressed: () => setState(_points.clear),
            ),
        ],
      ),
      body: _image == null ? _buildEmpty() : _buildImageViewer(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_search_rounded,
                size: 72, color: Colors.black.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
            const Text('坐标调试', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            const Text(
              '从相册选择一张屏幕截图作为背景\n点击图片任意位置即可获取该点坐标与颜色',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.6),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '坐标 = 图片像素坐标 = Android 屏幕像素\n原点：左上角 (0,0)  ·  单位：像素(px)',
                style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.5),
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _loading ? null : _pickImage,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loading)
                      const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    else
                      const Icon(Icons.photo_library_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      '选择截图',
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
    );
  }

  Widget _buildImageViewer() {
    return Column(
      children: [
        // 顶部信息条
        Container(
          width: double.infinity,
          color: Colors.black.withValues(alpha: 0.04),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '图片分辨率：${_image!.width} × ${_image!.height} px',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(width: 8),
              const Text('·', style: TextStyle(color: Colors.black26)),
              const SizedBox(width: 8),
              Text(
                '已采点 ${_points.length} 个',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        // 图片显示区：采样列表以浮层方式覆盖在底部，不挤压图片，
        // 避免新增点时图片重新布局导致已采集标记位置偏移。
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _computeImageRect(constraints);
              return Stack(
                children: [
                  GestureDetector(
                    onTapDown: _onTapImage,
                    child: Container(
                      color: Colors.black,
                      width: double.infinity,
                      height: double.infinity,
                      child: Stack(
                        children: [
                          Positioned(
                            left: _imageDisplayOffset.dx,
                            top: _imageDisplayOffset.dy,
                            width: _imageDisplaySize.width,
                            height: _imageDisplaySize.height,
                            child: _imagePreviewBytes == null
                                ? const SizedBox.shrink()
                                : Image.memory(
                                    _imagePreviewBytes!,
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                  ),
                          ),
                          // 点击点标记
                          ..._points.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final p = entry.value;
                            return Positioned(
                              left: p.displayX - 14,
                              top: p.displayY - 14,
                              child: GestureDetector(
                                onTap: () => _showPointSheet(context, idx),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.5),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: _flutterColor(p.color),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 1),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  // 底部采样列表浮层
                  if (_points.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildPointsList(),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPointsList() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _points.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
        itemBuilder: (context, index) {
          final p = _points[index];
          return ListTile(
            leading: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _flutterColor(p.color),
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            title: Text(
              '(${p.x}, ${p.y})',
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${_colorCss(p.color)}  ·  ${_colorHex(p.color)}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.touch_app_rounded, size: 18),
                  tooltip: '复制 click(x, y)',
                  onPressed: () => _copyCode(
                    'click(${p.x}, ${p.y})',
                    'click(${p.x}, ${p.y})',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.colorize_rounded, size: 18),
                  tooltip: '复制 find(color=)',
                  onPressed: () => _copyCode(
                    'find(color=${_colorHex(p.color)}, tolerance=20) {\n    click()\n}',
                    'find(color=${_colorHex(p.color)}) 代码',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: Colors.redAccent),
                  tooltip: '删除',
                  onPressed: () => setState(() => _points.removeAt(index)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _copyCode(String code, String label) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制：$label'), behavior: SnackBarBehavior.floating),
    );
  }

  void _showPointSheet(BuildContext context, int index) {
    final p = _points[index];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _flutterColor(p.color),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('点 #${index + 1}',
                            style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        Text(
                          '(${p.x}, ${p.y})',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${_colorCss(p.color)}  ·  ${_colorHex(p.color)}',
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.touch_app_rounded),
              title: const Text('复制 click(x, y)'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _copyCode('click(${p.x}, ${p.y})', 'click(${p.x}, ${p.y})');
              },
            ),
            ListTile(
              leading: const Icon(Icons.colorize_rounded),
              title: const Text('复制 find(color=) { click() }'),
              subtitle: const Text('颜色 + 坐标一并生成', style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _copyCode(
                  'find(color=${_colorHex(p.color)}, tolerance=20) {\n    click()\n}',
                  'find(color=${_colorHex(p.color)}) 代码',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('删除该点', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                setState(() => _points.removeAt(index));
                Navigator.pop(sheetCtx);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugPoint {
  final int x; // 图片像素坐标 = 屏幕坐标
  final int y;
  final int color; // 0xRRGGBB
  final double displayX; // 在 widget 中的显示坐标（用于绘制标记）
  final double displayY;

  _DebugPoint({
    required this.x,
    required this.y,
    required this.color,
    required this.displayX,
    required this.displayY,
  });
}
