import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// 简单矩形裁剪页。
///
/// 图片保持比例显示，用户可以拖动/缩放一个矩形裁剪框，
/// 输出图片最长边不超过 [maxOutputSize]（默认 320），等比缩放。
class ImageCropScreen extends StatefulWidget {
  final String sourcePath;
  final int maxOutputSize;

  const ImageCropScreen({
    super.key,
    required this.sourcePath,
    this.maxOutputSize = 320,
  });

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  img.Image? _sourceImage;
  bool _processing = false;

  // 裁剪框在图片显示区域内的坐标与大小
  double _boxX = 0;
  double _boxY = 0;
  double _boxW = 0;
  double _boxH = 0;

  // 容器与图片显示尺寸
  double _containerW = 0;
  double _containerH = 0;
  double _displayW = 0;
  double _displayH = 0;
  double _offsetX = 0;
  double _offsetY = 0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final file = File(widget.sourcePath);
    if (!await file.exists()) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _sourceImage = decoded;
    });
  }

  void _initBox() {
    if (_sourceImage == null || _containerW == 0 || _containerH == 0) return;
    final imageW = _sourceImage!.width.toDouble();
    final imageH = _sourceImage!.height.toDouble();
    final scale = min(_containerW / imageW, _containerH / imageH);
    _displayW = imageW * scale;
    _displayH = imageH * scale;
    _offsetX = (_containerW - _displayW) / 2;
    _offsetY = (_containerH - _displayH) / 2;

    final minSide = min(_displayW, _displayH);
    _boxW = min(240.0, minSide);
    _boxH = _boxW;
    _boxX = (_displayW - _boxW) / 2;
    _boxY = (_displayH - _boxH) / 2;
  }

  void _clampBox() {
    _boxW = _boxW.clamp(32.0, _displayW);
    _boxH = _boxH.clamp(32.0, _displayH);
    _boxX = _boxX.clamp(0.0, _displayW - _boxW);
    _boxY = _boxY.clamp(0.0, _displayH - _boxH);
  }

  Future<void> _crop() async {
    if (_sourceImage == null || _processing) return;
    setState(() => _processing = true);

    try {
      final scale = _displayW / _sourceImage!.width;
      final cropX = (_boxX / scale).round();
      final cropY = (_boxY / scale).round();
      final cropW = (_boxW / scale).round();
      final cropH = (_boxH / scale).round();

      var cropped = img.copyCrop(
        _sourceImage!,
        x: cropX.clamp(0, _sourceImage!.width - 1),
        y: cropY.clamp(0, _sourceImage!.height - 1),
        width: cropW.clamp(1, _sourceImage!.width - cropX),
        height: cropH.clamp(1, _sourceImage!.height - cropY),
      );

      final maxSide = max(cropped.width, cropped.height);
      if (maxSide > widget.maxOutputSize) {
        final resizeScale = widget.maxOutputSize / maxSide;
        cropped = img.copyResize(
          cropped,
          width: (cropped.width * resizeScale).round(),
          height: (cropped.height * resizeScale).round(),
          interpolation: img.Interpolation.cubic,
        );
      }

      final tempDir = await getTemporaryDirectory();
      final outputPath =
          '${tempDir.path}/isolation_crop_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodeJpg(cropped, quality: 90));

      if (mounted) Navigator.of(context).pop(outputFile.path);
    } catch (e) {
      debugPrint('裁剪失败: $e');
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('裁剪模板', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _processing ? null : _crop,
            child: _processing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Text('完成', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _containerW = constraints.maxWidth;
          _containerH = constraints.maxHeight;
          _initBox();

          if (_sourceImage == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: SizedBox(
                  width: _displayW,
                  height: _displayH,
                  child: Image.file(
                    File(widget.sourcePath),
                    fit: BoxFit.fill,
                  ),
                ),
              ),
              Positioned(
                left: _offsetX + _boxX,
                top: _offsetY + _boxY,
                width: _boxW,
                height: _boxH,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _boxX += details.delta.dx;
                      _boxY += details.delta.dy;
                      _clampBox();
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    child: Stack(
                      children: [
                        // 右下角缩放手柄
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                _boxW += details.delta.dx;
                                _boxH += details.delta.dy;
                                _clampBox();
                              });
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              color: Colors.white.withValues(alpha: 0.5),
                              child: const Icon(
                                Icons.zoom_out_map,
                                size: 16,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 暗色遮罩
              IgnorePointer(
                child: CustomPaint(
                  size: Size(_containerW, _containerH),
                  painter: _CropOverlayPainter(
                    overlayRect: Rect.fromLTWH(
                      _offsetX,
                      _offsetY,
                      _displayW,
                      _displayH,
                    ),
                    cropRect: Rect.fromLTWH(
                      _offsetX + _boxX,
                      _offsetY + _boxY,
                      _boxW,
                      _boxH,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  final Rect overlayRect;
  final Rect cropRect;

  _CropOverlayPainter({required this.overlayRect, required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(overlayRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
