import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// 圆形裁剪页。
///
/// 图片保持比例显示，用户可以拖动/捏合缩放一个圆形裁剪框，
/// 右下角也提供手柄进行单指缩放。输出图片最长边不超过 [maxOutputSize]（默认 320）。
///
/// [aspectRatio] 参数保留以兼容旧调用，但本页始终使用正圆形（宽高比 1.0）。
class ImageCropScreen extends StatefulWidget {
  final String sourcePath;
  final int maxOutputSize;
  final double? aspectRatio;

  const ImageCropScreen({
    super.key,
    required this.sourcePath,
    this.maxOutputSize = 320,
    this.aspectRatio,
  });

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  img.Image? _sourceImage;
  bool _processing = false;

  // 圆形裁剪框：直径与圆心（坐标基于图片显示区域）
  double _diameter = 0;
  double _centerX = 0;
  double _centerY = 0;

  // 捏合缩放开始时记录的直径
  double _initialDiameter = 0;

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

    if (_diameter == 0) {
      final minSide = min(_displayW, _displayH);
      _diameter = min(240.0, minSide).clamp(32.0, minSide);
      _centerX = _displayW / 2;
      _centerY = _displayH / 2;
    }

    _clampCircle();
  }

  void _clampCircle() {
    final maxD = min(_displayW, _displayH);
    _diameter = _diameter.clamp(32.0, maxD);
    _centerX = _centerX.clamp(_diameter / 2, _displayW - _diameter / 2);
    _centerY = _centerY.clamp(_diameter / 2, _displayH - _diameter / 2);
  }

  Future<void> _crop() async {
    if (_sourceImage == null || _processing) return;
    setState(() => _processing = true);

    try {
      final pixelScale = _sourceImage!.width / _displayW;
      final srcCenterX = (_centerX * pixelScale).round();
      final srcCenterY = (_centerY * pixelScale).round();
      final srcRadius = ((_diameter / 2) * pixelScale).round();
      final srcDiameter = (srcRadius * 2).clamp(1, _sourceImage!.width);

      final cropX = (srcCenterX - srcRadius).clamp(0, _sourceImage!.width - 1);
      final cropY = (srcCenterY - srcRadius).clamp(0, _sourceImage!.height - 1);
      final cropW = min(srcDiameter, _sourceImage!.width - cropX);
      final cropH = min(srcDiameter, _sourceImage!.height - cropY);

      var cropped = img.copyCrop(
        _sourceImage!,
        x: cropX,
        y: cropY,
        width: cropW,
        height: cropH,
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

          final screenCenter = Offset(
            _offsetX + _centerX,
            _offsetY + _centerY,
          );
          final radius = _diameter / 2;

          return Stack(
            fit: StackFit.expand,
            children: [
              // 原图
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
              // 圆形裁剪框（可拖拽/捏合缩放）
              Positioned(
                left: _offsetX + _centerX - radius,
                top: _offsetY + _centerY - radius,
                width: _diameter,
                height: _diameter,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onScaleStart: (_) {
                    _initialDiameter = _diameter;
                  },
                  onScaleUpdate: (details) {
                    setState(() {
                      _diameter = _initialDiameter * details.scale;
                      _centerX += details.focalPointDelta.dx;
                      _centerY += details.focalPointDelta.dy;
                      _clampCircle();
                    });
                  },
                  child: Container(
                    decoration: const ShapeDecoration(
                      shape: CircleBorder(
                        side: BorderSide(color: Colors.white, width: 2),
                      ),
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
                                _diameter += details.delta.dx;
                                _clampCircle();
                              });
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.85),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.black12,
                                  width: 1,
                                ),
                              ),
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
              // 暗色圆形遮罩
              IgnorePointer(
                child: CustomPaint(
                  size: Size(_containerW, _containerH),
                  painter: _CircularOverlayPainter(
                    overlayRect: Rect.fromLTWH(
                      _offsetX,
                      _offsetY,
                      _displayW,
                      _displayH,
                    ),
                    circleCenter: screenCenter,
                    radius: radius,
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

class _CircularOverlayPainter extends CustomPainter {
  final Rect overlayRect;
  final Offset circleCenter;
  final double radius;

  _CircularOverlayPainter({
    required this.overlayRect,
    required this.circleCenter,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: circleCenter, radius: radius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(circleCenter, radius, borderPaint);
    canvas.drawRect(overlayRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
