import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../services/face_detection_service.dart';
import '../services/face_3d_service.dart';

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

  // 3D Face Verification state
  bool _use3DFace = false;
  Face3DChallenge? _challenge3D;
  StreamSubscription<Face3DFrameEvent>? _face3dSub;
  bool _isVerifying3D = false;
  double _verifyProgress = 0.0;
  Timer? _verifyTimer;

  // Beauty filter settings
  double _beautyLevel = 0.3; // 0.0 - 1.0

  int _lastDetectionTime = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check3DSupportAndInit();
  }

  Future<void> _check3DSupportAndInit() async {
    final bool is3dSupported = await Face3DService.isSupported();
    if (is3dSupported) {
      setState(() {
        _use3DFace = true;
      });
      await _start3DFaceVerifyFlow();
    } else {
      await _initializeCamera();
    }
  }

  // =========================================================================
  // 3D NATIVE FACE VERIFY FLOW (iOS ARKit v1.2 ~2 giây với Challenge)
  // =========================================================================
  Future<void> _start3DFaceVerifyFlow() async {
    try {
      setState(() {
        _isInitialized = true;
        _statusMessage = 'Đang lấy thử thách xác thực 3D...';
        _verifyProgress = 0.0;
      });

      // 1. Fetch challenge before starting
      _challenge3D = await Face3DService.getChallenge();

      final String actionText = _getActionInstruction(_challenge3D!.action);

      // 2. Start native tracking session
      final bool started = await Face3DService.startSession(
        mode: 'verify',
        challengeId: _challenge3D!.challengeId,
      );

      if (!started) {
        throw Exception('Không thể khởi tạo ARSession 3D');
      }

      setState(() {
        _statusMessage = actionText;
        _faceDetected = true;
      });

      // 3. Listen to stream and auto-submit after ~2 seconds session
      _face3dSub?.cancel();
      _face3dSub = Face3DService.trackingStream.listen(_handle3DVerifyFrame);

      _verifyTimer?.cancel();
      int elapsedMs = 0;
      _verifyTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        elapsedMs += 100;
        if (mounted) {
          setState(() {
            _verifyProgress = (elapsedMs / 2000.0).clamp(0.0, 1.0);
          });
        }

        if (elapsedMs >= 2200) {
          timer.cancel();
          _submit3DVerification();
        }
      });
    } catch (e) {
      debugPrint('Lỗi 3D Verify Init: $e');
      if (mounted) {
        setState(() {
          _use3DFace = false;
        });
        _initializeCamera();
      }
    }
  }

  String _getActionInstruction(String action) {
    switch (action) {
      case 'blink':
        return 'Vui lòng CHỚP MẮT để xác nhận';
      case 'turn_left':
        return 'Vui lòng XOAY MẶT SANG TRÁI';
      case 'turn_right':
        return 'Vui lòng XOAY MẶT SANG PHẢI';
      case 'smile':
        return 'Vui lòng MỈM CƯỜI';
      default:
        return 'Nhìn thẳng vào camera';
    }
  }

  void _handle3DVerifyFrame(Face3DFrameEvent event) {
    if (!mounted || _isVerifying3D) return;

    if (!event.isTracked) {
      setState(() {
        _statusMessage = 'Không tìm thấy khuôn mặt';
        _faceDetected = false;
      });
    } else {
      final String actionText = _challenge3D != null
          ? _getActionInstruction(_challenge3D!.action)
          : 'Đang xác thực 3D...';
      setState(() {
        _statusMessage = actionText;
        _faceDetected = true;
      });
    }
  }

  Future<void> _submit3DVerification() async {
    if (_isVerifying3D) return;
    _isVerifying3D = true;

    try {
      setState(() {
        _statusMessage = 'Đang kiểm tra chống giả lập 3D...';
      });

      await Face3DService.stopSession();
      final payload = await Face3DService.getCollectedPayload();

      if (payload == null) {
        throw Exception('Không lấy được dữ liệu 3D từ thiết bị');
      }

      final result = await Face3DService.submitPayload(
        mode: 'verify',
        nativePayload: payload,
      );

      if (!mounted) return;

      if (result.success) {
        final rgbImages = payload['rgb_images'] as Map<dynamic, dynamic>?;
        final Uint8List primaryBytes = rgbImages != null && rgbImages.containsKey('rgb_0')
            ? Uint8List.fromList((rgbImages['rgb_0'] as List).cast<int>())
            : Uint8List(0);

        final base64Image = base64Encode(primaryBytes);
        widget.onCapture(base64Image, primaryBytes);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Xác thực 3D rớt. Thử lại...'),
            backgroundColor: Colors.redAccent,
          ),
        );
        _isVerifying3D = false;
        _start3DFaceVerifyFlow(); // Retry with fresh challenge
      }
    } catch (e) {
      debugPrint('Lỗi submit 3D verify: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
        _isVerifying3D = false;
        _start3DFaceVerifyFlow();
      }
    }
  }

  // =========================================================================
  // 2D FALLBACK FLOW
  // =========================================================================
  @override
  void dispose() {
    _face3dSub?.cancel();
    _verifyTimer?.cancel();
    if (_use3DFace) {
      Face3DService.stopSession();
    }
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    _faceDetectionService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_use3DFace) return;
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

  bool _isDisposing = false;
  Future<void> _stopCamera() async {
    if (_isDisposing || _cameraController == null) return;
    _isDisposing = true;

    try {
      final controller = _cameraController!;
      _cameraController = null;

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
    if (_use3DFace) return;
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
    if (_use3DFace) {
      _submit3DVerification();
      return;
    }

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

    for (int i = 0; i < 2; i++) {
      image = img.gaussianBlur(image!, radius: 2);
    }
    final sharpened = _applySharpen(image!, amount: 0.3);
    image = img.adjustColor(sharpened, brightness: 1.08, saturation: 1.05);
    image = img.adjustColor(image, contrast: 1.12);
    image = _reduceRedness(image);
    image = _applySoftGlow(image, intensity: 0.15);

    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  img.Image _applySharpen(img.Image src, {double amount = 0.5}) {
    final kernel = [
      0.0, -amount, 0.0,
      -amount, 1.0 + 4 * amount, -amount,
      0.0, -amount, 0.0,
    ];
    return img.convolution(src, filter: kernel, div: 1.0);
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
    return ((base * (1 - intensity)) + (result * intensity)).toInt().clamp(0, 255);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleBackPressed() async {
    await _stopCamera();
    widget.onCancel?.call();
    if (context.mounted) Navigator.of(context).pop();
  }

  Widget _buildCameraPreview() {
    if (_use3DFace) {
      return Container(
        color: const Color(0xFF18181B),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF007AFF), width: 3),
                  color: const Color(0xFF1C1C1E),
                ),
                child: const Icon(
                  Icons.face_retouching_natural,
                  size: 72,
                  color: Color(0xFF007AFF),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 220,
                child: LinearProgressIndicator(
                  value: _verifyProgress,
                  backgroundColor: Colors.white12,
                  color: const Color(0xFF007AFF),
                ),
              ),
            ],
          ),
        ),
      );
    }

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
              CameraPreview(_cameraController!),
              if (_beautyLevel > 0) ...[
                BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: _beautyLevel * 1.8,
                    sigmaY: _beautyLevel * 1.8,
                  ),
                  child: Container(color: Colors.transparent),
                ),
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
                Positioned.fill(
                  child: CustomPaint(
                    painter: BeautyGlowPainter(
                      intensity: _beautyLevel * 0.6,
                      faceBoxes: _faceBoxes,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
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
        await _handleBackPressed();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraPreview(),

          if (!_use3DFace)
            CustomPaint(
              size: MediaQuery.of(context).size,
              painter: FaceOverlayPainter(
                faceBoxes: _faceBoxes,
                imageSize: MediaQuery.of(context).size,
                faceDetected: _faceDetected,
                beautyLevel: _beautyLevel,
              ),
            ),

          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _faceDetected ? Icons.check_circle : Icons.warning,
                        color: _faceDetected ? Colors.green : Colors.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _statusMessage,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_use3DFace)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Xác thực 3D TrueDepth (Active Challenge)',
                        style: TextStyle(color: Color(0xFF007AFF), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  heroTag: 'cancel_btn',
                  backgroundColor: Colors.white24,
                  onPressed: () => _handleBackPressed(),
                  child: const Icon(Icons.close, color: Colors.white),
                ),
                GestureDetector(
                  onTap: _captureImage,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: _faceDetected ? const Color(0xFF007AFF) : Colors.grey,
                    ),
                    child: Center(
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BeautyGlowPainter extends CustomPainter {
  final double intensity;
  final List<Rect> faceBoxes;

  BeautyGlowPainter({required this.intensity, required this.faceBoxes});

  @override
  void paint(Canvas canvas, Size size) {
    if (faceBoxes.isEmpty) return;

    final paint = Paint()
      ..color = Colors.pinkAccent.withOpacity(intensity * 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);

    for (final box in faceBoxes) {
      final cheekLeft = Offset(box.left + box.width * 0.25, box.top + box.height * 0.6);
      final cheekRight = Offset(box.right - box.width * 0.25, box.top + box.height * 0.6);
      final radius = box.width * 0.15;

      canvas.drawCircle(cheekLeft, radius, paint);
      canvas.drawCircle(cheekRight, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant BeautyGlowPainter oldDelegate) {
    return oldDelegate.intensity != intensity || oldDelegate.faceBoxes != faceBoxes;
  }
}

class FaceOverlayPainter extends CustomPainter {
  final List<Rect> faceBoxes;
  final Size imageSize;
  final bool faceDetected;
  final double beautyLevel;

  FaceOverlayPainter({
    required this.faceBoxes,
    required this.imageSize,
    required this.faceDetected,
    required this.beautyLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    final paint = Paint()
      ..color = faceDetected ? Colors.green : Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    for (final box in faceBoxes) {
      final rect = Rect.fromLTRB(
        box.left * scaleX,
        box.top * scaleY,
        box.right * scaleX,
        box.bottom * scaleY,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant FaceOverlayPainter oldDelegate) {
    return oldDelegate.faceDetected != faceDetected || oldDelegate.faceBoxes != faceBoxes;
  }
}
