import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../services/face_detection_service.dart';

class FaceCameraWidget extends StatefulWidget {
  final Function(String base64Image, Uint8List imageBytes) onCapture;
  final VoidCallback? onCancel;

  const FaceCameraWidget({
    Key? key,
    required this.onCapture,
    this.onCancel,
  }) : super(key: key);

  @override
  State<FaceCameraWidget> createState() => _FaceCameraWidgetState();
}

class _FaceCameraWidgetState extends State<FaceCameraWidget>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  final FaceDetectionService _faceDetectionService = FaceDetectionService();

  bool _isInitialized = false;
  bool _isProcessing = false;
  String _statusMessage = 'Đang khởi tạo camera...';
  bool _faceDetected = false;
  List<Rect> _faceBoxes = [];
  double _livenessScore = 0;
  bool _requiresBlink = false;

  // Beauty filter settings
  double _beautyLevel = 0.3; // 0.0 - 1.0

  int _lastDetectionTime = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // _faceDetectionService.resetHistory();
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    _faceDetectionService.dispose();
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

      if (!mounted) return;

      setState(() {
        _cameraController = controller;
        _isInitialized = true;
        _statusMessage = 'Đưa khuôn mặt vào khung';
      });

      _cameraController!.startImageStream(_processCameraImage);
    } catch (e) {
      setState(() {
        _statusMessage = 'Lỗi khởi tạo camera: $e';
      });
    }
  }

  bool _isDisposing = false; // THÊM BIẾN NÀY
  Future<void> _stopCamera() async {
    if (_isDisposing || _cameraController == null) return;
    _isDisposing = true;

    try {
      final controller = _cameraController!;
      _cameraController = null; // NULL NGAY LẬP TỨC

      if (controller.value.isInitialized) {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream().timeout(const Duration(milliseconds: 100));
        }
        await controller.dispose().timeout(const Duration(milliseconds: 100));
      }
    } catch (e) {
      debugPrint('Stop camera error: $e');
    }
    }

  Future<void> _processCameraImage(CameraImage image) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastDetectionTime < 500) return;
    _lastDetectionTime = now;

    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final faces = await _faceDetectionService.detectFaces(image);

      if (mounted) {
        if (faces.isEmpty) {
          setState(() {
            _faceDetected = false;
            _faceBoxes = [];
            _statusMessage = 'Không phát hiện khuôn mặt';
            _livenessScore = 0;
          });
        } else if (faces.length > 1) {
          setState(() {
            _faceDetected = false;
            _faceBoxes = faces.map((f) => f.boundingBox).toList();
            _statusMessage = 'Chỉ cho phép 1 khuôn mặt';
            _livenessScore = 0;
          });
        } else {
          final result = _faceDetectionService.validateFace(
            faces.first,
            Size(image.width.toDouble(), image.height.toDouble()),
          );

          setState(() {
            _faceDetected = result.isValid;
            _faceBoxes = [faces.first.boundingBox];
            _statusMessage = result.message;
            _livenessScore = result.livenessScore;
            _requiresBlink = result.requiresBlink;
          });
        }
      }
    } catch (e) {
      debugPrint('Lỗi xử lý image: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _captureImage() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_faceDetected) {
      _showMessage('Vui lòng đưa khuôn mặt vào khung');
      return;
    }

    try {
      await _cameraController!.stopImageStream();

      final XFile imageFile = await _cameraController!.takePicture();
      final Uint8List imageBytes = await imageFile.readAsBytes();

      // Xử lý ảnh với beauty filter
      final processedBytes = await _processImage(imageBytes);

      final base64Image = base64Encode(processedBytes);

      widget.onCapture(base64Image, processedBytes);
    } catch (e) {
      _showMessage('Lỗi chụp ảnh: $e');
      _cameraController!.startImageStream(_processCameraImage);
    }
  }

  Future<Uint8List> _processImage(Uint8List bytes) async {
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // === BEAUTY FILTER CHUYÊN NGHIỆP ===

    // 1. Làm mịn da (Bilateral filter)
    for (int i = 0; i < 2; i++) {
      image = img.gaussianBlur(image!, radius: 2);
    }

    // 2. Sharpen nhẹ để giữ chi tiết
    final sharpened = _applySharpen(image!, amount: 0.3);

    // 3. Tăng độ sáng và saturation
    image = img.adjustColor(sharpened,
      brightness: 1.08,
      saturation: 1.05,
    );

    // 4. Tăng độ tương phản
    image = img.adjustColor(image, contrast: 1.12);

    // 5. Giảm độ đỏ
    image = _reduceRedness(image);

    // 6. Soft glow effect
    image = _applySoftGlow(image, intensity: 0.15);

    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  img.Image _applySharpen(img.Image src, {double amount = 0.5}) {
    final kernel = [
      0.0, -amount, 0.0,
      -amount, 1.0 + 4 * amount, -amount,
      0.0, -amount, 0.0,
    ];

    return img.convolution(src,
      filter: kernel,
      div: 1.0,
    );
  }

  img.Image _reduceRedness(img.Image src) {
    final result = img.Image.from(src);

    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final pixel = result.getPixel(x, y);

        int r = pixel.r.toInt();
        int g = pixel.g.toInt();
        int b = pixel.b.toInt();

        if (r > g + 10 && r > b + 10) {
          r = (r * 0.92).toInt();
          g = (g * 1.05).toInt();
        }

        result.setPixelRgba(x, y, r, g, b, pixel.a.toInt());
      }
    }

    return result;
  }

  img.Image _applySoftGlow(img.Image src, {double intensity = 0.2}) {
    final blurred = img.gaussianBlur(src, radius: 15);
    final result = img.Image.from(src);

    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final original = src.getPixel(x, y);
        final blur = blurred.getPixel(x, y);

        int r = _screenBlend(original.r.toInt(), blur.r.toInt(), intensity);
        int g = _screenBlend(original.g.toInt(), blur.g.toInt(), intensity);
        int b = _screenBlend(original.b.toInt(), blur.b.toInt(), intensity);

        result.setPixelRgba(x, y, r, g, b, original.a.toInt());
      }
    }

    return result;
  }

  int _screenBlend(int base, int blend, double intensity) {
    final result = 255 - ((255 - base) * (255 - blend)) ~/ 255;
    return ((base * (1 - intensity)) + (result * intensity))
        .toInt()
        .clamp(0, 255);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleBackPressed() async {
    await _stopCamera();
    widget.onCancel?.call();
    if (context.mounted) Navigator.of(context).pop();
  }

  Widget _buildCameraPreview() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Container(color: Colors.black);
    }

    final size = _cameraController!.value.previewSize!;
    final aspectRatio = size.height / size.width;

    return Transform.scale(
      scale: 1 /
          (_cameraController!.value.aspectRatio *
              MediaQuery.of(context).size.aspectRatio),
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Camera preview gốc
              CameraPreview(_cameraController!),

              // === BEAUTY FILTER REAL-TIME ===
              if (_beautyLevel > 0) ...[
                // Layer 1: Skin Smoothing (Blur nhẹ)
                BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: _beautyLevel * 1.8,
                    sigmaY: _beautyLevel * 1.8,
                  ),
                  child: Container(color: Colors.transparent),
                ),

                // Layer 2: Soft Light Center Glow
                Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.8,
                      colors: [
                        Colors.white.withOpacity(_beautyLevel * 0.12),
                        Colors.white.withOpacity(_beautyLevel * 0.06),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),

                // Layer 3: Warm Tone Overlay (Giảm xanh lạnh)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.amber.withOpacity(_beautyLevel * 0.03),
                        Colors.white.withOpacity(_beautyLevel * 0.04),
                        Colors.orange.withOpacity(_beautyLevel * 0.02),
                      ],
                    ),
                  ),
                ),

                // Layer 4: Brightness Boost (Làm sáng da)
                Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.2,
                      colors: [
                        Colors.white.withOpacity(_beautyLevel * 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),

                // Layer 5: Subtle Pink Tone (Má hồng)
                Positioned.fill(
                  child: CustomPaint(
                    painter: BeautyGlowPainter(
                      intensity: _beautyLevel * 0.6,
                      faceBoxes: _faceBoxes,
                    ),
                  ),
                ),
              ],
              if (_cameraController == null || !_cameraController!.value.isInitialized)
                Container(color: Colors.black),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _cameraController == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_statusMessage),
          ],
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !mounted) return;

        await _stopCamera();
        widget.onCancel?.call();

        // if (mounted) {
        //   WidgetsBinding.instance.addPostFrameCallback((_) {
        //     if (mounted) Navigator.of(context).pop();
        //   });
        // }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview với beauty filter
          _buildCameraPreview(),

          // Face overlay với beauty enhancement
          CustomPaint(
            size: MediaQuery.of(context).size,
            painter: FaceOverlayPainter(
              faceBoxes: _faceBoxes,
              imageSize: MediaQuery.of(context).size,
              faceDetected: _faceDetected,
              beautyLevel: _beautyLevel,
            ),
          ),

          // Status message với liveness score
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: BoxDecoration(
                    color: _faceDetected
                        ? Colors.green.withOpacity(0.9)
                        : (_requiresBlink
                        ? Colors.orange.withOpacity(0.9)
                        : Colors.red.withOpacity(0.9)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_livenessScore > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Độ tin cậy: ',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '${(_livenessScore * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: _livenessScore,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _livenessScore > 0.7
                                ? Colors.greenAccent
                                : (_livenessScore > 0.4
                                ? Colors.orangeAccent
                                : Colors.redAccent),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_requiresBlink) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.visibility, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          '👁️ Hãy nhấp nháy mắt',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Beauty level slider và buttons
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Beauty slider
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.face_retouching_natural,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 140,
                        child: SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: Colors.pinkAccent,
                            inactiveTrackColor: Colors.white30,
                            thumbColor: Colors.white,
                            overlayColor: Colors.pinkAccent.withOpacity(0.3),
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 8),
                          ),
                          child: Slider(
                            value: _beautyLevel,
                            min: 0,
                            max: 1,
                            divisions: 10,
                            onChanged: (value) {
                              setState(() {
                                _beautyLevel = value;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 45,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${(_beautyLevel * 100).toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (widget.onCancel != null)
                      FloatingActionButton(
                        onPressed: widget.onCancel,
                        backgroundColor: Colors.grey.shade800,
                        child: const Icon(Icons.close),
                      ),
                    FloatingActionButton.extended(
                      onPressed: _faceDetected ? _captureImage : null,
                      backgroundColor:
                      _faceDetected ? Colors.green : Colors.grey.shade700,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Check-in'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===== BEAUTY GLOW PAINTER =====
class BeautyGlowPainter extends CustomPainter {
  final double intensity;
  final List<Rect> faceBoxes;

  BeautyGlowPainter({
    required this.intensity,
    required this.faceBoxes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0 || faceBoxes.isEmpty) return;

    // Vẽ soft glow xung quanh khuôn mặt
    for (final faceBox in faceBoxes) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.pink.withOpacity(intensity * 0.08),
            Colors.white.withOpacity(intensity * 0.05),
            Colors.transparent,
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(faceBox);

      canvas.drawRect(faceBox, paint);
    }
  }

  @override
  bool shouldRepaint(BeautyGlowPainter oldDelegate) {
    return oldDelegate.intensity != intensity ||
        oldDelegate.faceBoxes != faceBoxes;
  }
}

// ===== FACE OVERLAY PAINTER VỚI BEAUTY ENHANCEMENT =====
class FaceOverlayPainter extends CustomPainter {
  final List<Rect> faceBoxes;
  final Size imageSize;
  final bool faceDetected;
  final double beautyLevel;

  FaceOverlayPainter({
    required this.faceBoxes,
    required this.imageSize,
    required this.faceDetected,
    this.beautyLevel = 0.6,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background overlay với soft vignette
    final overlayPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.2,
        colors: [
          Colors.black.withOpacity(0.4),
          Colors.black.withOpacity(0.7),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.7,
      height: size.height * 0.5,
    );

    path.addOval(ovalRect);
    path.fillType = PathFillType.evenOdd;

    canvas.drawPath(path, overlayPaint);

    // Vẽ soft glow bên trong oval (beauty enhancement)
    if (beautyLevel > 0.3) {
      final glowPaint = Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.4,
          colors: [
            Colors.white.withOpacity(beautyLevel * 0.15),
            Colors.amber.withOpacity(beautyLevel * 0.08),
            Colors.transparent,
          ],
        ).createShader(ovalRect);

      canvas.drawOval(ovalRect, glowPaint);
    }

    // Vẽ viền oval với gradient
    final borderPaint = Paint()
      ..shader = LinearGradient(
        colors: faceDetected
            ? [
          Colors.greenAccent.shade400,
          Colors.green,
          Colors.greenAccent.shade700,
        ]
            : [
          Colors.white,
          Colors.white70,
          Colors.white,
        ],
      ).createShader(ovalRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawOval(ovalRect, borderPaint);

    // Vẽ corners với glow effect
    _drawEnhancedCorners(canvas, ovalRect, borderPaint);

    // Vẽ decorative particles (nếu face detected)
    if (faceDetected && beautyLevel > 0.5) {
      _drawBeautyParticles(canvas, ovalRect);
    }
  }

  void _drawEnhancedCorners(Canvas canvas, Rect rect, Paint paint) {
    const cornerLength = 35.0;
    const glowSpread = 8.0;

    // Glow effect cho corners
    final glowPaint = Paint()
      ..color = (paint.shader != null ? Colors.white : Colors.white)
          .withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, glowSpread);

    // Top left
    canvas.drawLine(
        rect.topLeft, rect.topLeft + const Offset(cornerLength, 0), glowPaint);
    canvas.drawLine(
        rect.topLeft, rect.topLeft + const Offset(0, cornerLength), glowPaint);
    canvas.drawLine(
        rect.topLeft, rect.topLeft + const Offset(cornerLength, 0), paint);
    canvas.drawLine(
        rect.topLeft, rect.topLeft + const Offset(0, cornerLength), paint);

    // Top right
    canvas.drawLine(rect.topRight,
        rect.topRight + const Offset(-cornerLength, 0), glowPaint);
    canvas.drawLine(
        rect.topRight, rect.topRight + const Offset(0, cornerLength), glowPaint);
    canvas.drawLine(
        rect.topRight, rect.topRight + const Offset(-cornerLength, 0), paint);
    canvas.drawLine(
        rect.topRight, rect.topRight + const Offset(0, cornerLength), paint);

    // Bottom left
    canvas.drawLine(rect.bottomLeft,
        rect.bottomLeft + const Offset(cornerLength, 0), glowPaint);
    canvas.drawLine(rect.bottomLeft,
        rect.bottomLeft + const Offset(0, -cornerLength), glowPaint);
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft + const Offset(cornerLength, 0), paint);
    canvas.drawLine(rect.bottomLeft,
        rect.bottomLeft + const Offset(0, -cornerLength), paint);

    // Bottom right
    canvas.drawLine(rect.bottomRight,
        rect.bottomRight + const Offset(-cornerLength, 0), glowPaint);
    canvas.drawLine(rect.bottomRight,
        rect.bottomRight + const Offset(0, -cornerLength), glowPaint);
    canvas.drawLine(rect.bottomRight,
        rect.bottomRight + const Offset(-cornerLength, 0), paint);
    canvas.drawLine(rect.bottomRight,
        rect.bottomRight + const Offset(0, -cornerLength), paint);
  }

  void _drawBeautyParticles(Canvas canvas, Rect rect) {
    final particlePaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Vẽ 8 particles xung quanh oval
    final particles = [
      Offset(rect.center.dx, rect.top - 15),
      Offset(rect.center.dx, rect.bottom + 15),
      Offset(rect.left - 15, rect.center.dy),
      Offset(rect.right + 15, rect.center.dy),
      Offset(rect.left + 30, rect.top + 20),
      Offset(rect.right - 30, rect.top + 20),
      Offset(rect.left + 30, rect.bottom - 20),
      Offset(rect.right - 30, rect.bottom - 20),
    ];

    for (final particle in particles) {
      canvas.drawCircle(particle, 3, particlePaint);
    }
  }

  @override
  bool shouldRepaint(FaceOverlayPainter oldDelegate) {
    return oldDelegate.faceBoxes != faceBoxes ||
        oldDelegate.faceDetected != faceDetected ||
        oldDelegate.beautyLevel != beautyLevel;
  }
}