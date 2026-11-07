import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_tbk/features/check-in/services/face_3d_service.dart';

class FaceIdScanningScreen extends StatefulWidget {
  const FaceIdScanningScreen({super.key});

  @override
  State<FaceIdScanningScreen> createState() => _FaceIdScanningScreenState();
}

class _FaceIdScanningScreenState extends State<FaceIdScanningScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';

  // 3D Face Tracking state
  bool _use3DFace = false;
  Face3DChallenge? _challenge;
  StreamSubscription<Face3DFrameEvent>? _face3dSub;
  bool _isSubmitting3D = false;

  // Detector phát hiện khuôn mặt ML Kit (Fallback cho Android / iOS cũ)
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    ),
  );

  bool _isProcessingFrame = false;
  int _faceDetectedFrameCount = 0;
  bool _hasDetectedFaceInStep0 = false;

  // Các bước quét Face ID:
  // 0 = Định vị & Kiểm tra khuôn mặt trong khung
  // 1 = Quét xoay khuôn mặt 360 độ (64 vạch quanh đường tròn)
  // 2 = Hoàn tất thành công
  int _scanStep = 0;

  final List<bool> _completedTicks = List.filled(64, false);
  double _scanProgress = 0.0;
  String _statusMessage = 'Định vị khuôn mặt của bạn trong khung.';

  @override
  void initState() {
    super.initState();
    _check3DSupportAndInit();
  }

  Future<void> _check3DSupportAndInit() async {
    final bool is3dSupported = await Face3DService.isSupported();
    if (is3dSupported) {
      setState(() {
        _use3DFace = true;
      });
      await _start3DFaceEnrollFlow();
    } else {
      await _initCamera();
    }
  }

  // =========================================================================
  // 3D NATIVE FACE ENROLLMENT FLOW (iOS ARKit v1.2)
  // =========================================================================
  Future<void> _start3DFaceEnrollFlow() async {
    try {
      setState(() {
        _statusMessage = 'Đang khởi tạo thử thách quét 3D...';
      });

      // 1. Fetch challenge before starting
      _challenge = await Face3DService.getChallenge();

      // 2. Start native ARSession
      final bool started = await Face3DService.startSession(
        mode: 'enroll',
        challengeId: _challenge!.challengeId,
      );

      if (!started) {
        throw Exception('Không thể khởi tạo ARSession 3D');
      }

      setState(() {
        _scanStep = 1;
        _statusMessage = 'Nghiêng đầu vẽ 1 hình tròn (10–12 giây)';
      });

      // 3. Listen to native tracking stream
      _face3dSub?.cancel();
      _face3dSub = Face3DService.trackingStream.listen(_handle3DFrameEvent);
    } catch (e) {
      debugPrint('Lỗi 3D Face Enroll Init: $e');
      if (mounted) {
        setState(() {
          _use3DFace = false;
          _statusMessage = 'Chuyển sang luồng nhận diện 2D...';
        });
        _initCamera();
      }
    }
  }

  void _handle3DFrameEvent(Face3DFrameEvent event) {
    if (!mounted || _isSubmitting3D || _scanStep != 1) return;

    if (!event.isTracked) {
      setState(() {
        _statusMessage = 'Không tìm thấy khuôn mặt.\nVui lòng nhìn vào camera.';
      });
      return;
    }

    // Map Completed sectors (0..8) to 64 UI ticks
    for (int sector in event.completedSectors) {
      int centerTick = ((sector / 9.0) * 64).round() % 64;
      for (int offset = -3; offset <= 3; offset++) {
        int idx = (centerTick + offset + 64) % 64;
        _completedTicks[idx] = true;
      }
    }

    double progress = event.progress;
    int percentage = (progress * 100).round();

    setState(() {
      _scanProgress = progress;
      if (event.completedSectors.length >= 8 || progress >= 0.95) {
        _scanProgress = 1.0;
        _statusMessage = 'Đang tải dữ liệu đăng ký 3D...';
        _on3DScanComplete();
      } else {
        _statusMessage = 'Nghiêng đầu xoay hình tròn ($percentage%)';
      }
    });
  }

  Future<void> _on3DScanComplete() async {
    if (_isSubmitting3D) return;
    _isSubmitting3D = true;

    try {
      await Face3DService.stopSession();
      final payload = await Face3DService.getCollectedPayload();

      if (payload == null) {
        throw Exception('Không thu thập được dữ liệu 3D từ thiết bị');
      }

      final result = await Face3DService.submitPayload(
        mode: 'enroll',
        nativePayload: payload,
      );

      if (!mounted) return;

      if (result.success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('biometric_enabled', true);
        setState(() {
          _scanStep = 2;
          _statusMessage = 'Hoàn tất đăng ký Face ID 3D!';
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Đăng ký 3D thất bại. Vui lòng quét lại.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        _isSubmitting3D = false;
        _start3DFaceEnrollFlow(); // Retry with new challenge
      }
    } catch (e) {
      debugPrint('Lỗi gửi payload 3D enroll: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
        _isSubmitting3D = false;
        _start3DFaceEnrollFlow();
      }
    }
  }

  // =========================================================================
  // 2D FALLBACK FLOW (Camera + ML Kit)
  // =========================================================================
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage = 'Không tìm thấy camera trên thiết bị';
        });
        return;
      }

      final CameraDescription selectedCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isCameraInitialized = true;
        _statusMessage = 'Định vị khuôn mặt của bạn trong khung.';
      });

      await controller.startImageStream(_processCameraImage);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Lỗi khởi tạo camera: $e';
      });
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessingFrame || !mounted || _scanStep == 2 || _use3DFace) return;
    _isProcessingFrame = true;

    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) {
        _isProcessingFrame = false;
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted) {
        _isProcessingFrame = false;
        return;
      }

      if (_scanStep == 0) {
        if (faces.isEmpty) {
          _faceDetectedFrameCount = 0;
          if (_hasDetectedFaceInStep0 ||
              _statusMessage !=
                  'Không tìm thấy khuôn mặt.\nVui lòng đặt khuôn mặt vào khung.') {
            setState(() {
              _hasDetectedFaceInStep0 = false;
              _statusMessage =
                  'Không tìm thấy khuôn mặt.\nVui lòng đặt khuôn mặt vào khung.';
            });
          }
        } else {
          _faceDetectedFrameCount++;
          if (!_hasDetectedFaceInStep0) {
            setState(() {
              _hasDetectedFaceInStep0 = true;
              _statusMessage = 'Đã nhận diện khuôn mặt.\nGiữ nguyên vị trí...';
            });
          }

          if (_faceDetectedFrameCount >= 3) {
            setState(() {
              _scanStep = 1;
              _statusMessage = 'Xoay chậm đầu của bạn theo hình tròn 360°';
            });
          }
        }
      } else if (_scanStep == 1) {
        if (faces.isEmpty) {
          if (_statusMessage !=
              'Không tìm thấy khuôn mặt.\nVui lòng quay lại khung hình.') {
            setState(() {
              _statusMessage =
                  'Không tìm thấy khuôn mặt.\nVui lòng quay lại khung hình.';
            });
          }
        } else {
          final face = faces.first;
          final double yaw = face.headEulerAngleY ?? 0.0;
          final double pitch = face.headEulerAngleX ?? 0.0;

          final double dx = yaw;
          final double dy = pitch;
          final double magnitude = sqrt(dx * dx + dy * dy);

          if (magnitude >= 5.0) {
            double angleRad = atan2(yaw, pitch);
            if (angleRad < 0) {
              angleRad += 2 * pi;
            }

            int centerTick = ((angleRad / (2 * pi)) * 64).round() % 64;
            bool updated = false;

            for (int offset = -2; offset <= 2; offset++) {
              int tIndex = (centerTick + offset + 64) % 64;
              if (!_completedTicks[tIndex]) {
                _completedTicks[tIndex] = true;
                updated = true;
              }
            }

            if (updated) {
              int filledCount = _completedTicks.where((t) => t).length;
              double progress = filledCount / 64.0;
              int percentage = (progress * 100).round();

              setState(() {
                _scanProgress = progress;
                if (filledCount >= 62 || progress >= 0.97) {
                  _scanProgress = 1.0;
                  _statusMessage = 'Hoàn tất quét khuôn mặt!';
                } else {
                  _statusMessage =
                      'Xoay chậm đầu của bạn theo hình tròn ($percentage%)';
                }
              });

              if (_scanProgress >= 1.0) {
                _on2DScanComplete();
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Lỗi xử lý frame camera: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  InputImage? _convertCameraImage(CameraImage image) {
    if (_cameraController == null) return null;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final camera = _cameraController!.description;
      final sensorOrientation = camera.sensorOrientation;

      InputImageRotation rotation;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ??
            InputImageRotation.rotation0deg;
      } else {
        switch (sensorOrientation) {
          case 90:
            rotation = InputImageRotation.rotation90deg;
            break;
          case 180:
            rotation = InputImageRotation.rotation180deg;
            break;
          case 270:
            rotation = InputImageRotation.rotation270deg;
            break;
          case 0:
          default:
            rotation = InputImageRotation.rotation0deg;
            break;
        }
      }

      final inputImageFormat =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21;

      final inputImageMetadata = InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: inputImageFormat,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageMetadata,
      );
    } catch (e) {
      debugPrint('Lỗi chuyển đổi ảnh camera: $e');
      return null;
    }
  }

  Future<void> _on2DScanComplete() async {
    try {
      await _cameraController?.stopImageStream();
    } catch (e) {
      debugPrint('Lỗi dừng camera stream: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', true);

    if (!mounted) return;
    setState(() {
      _scanStep = 2;
    });
  }

  @override
  void dispose() {
    _face3dSub?.cancel();
    if (_use3DFace) {
      Face3DService.stopSession();
    }
    try {
      _cameraController?.stopImageStream();
    } catch (_) {}
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    behavior: HitTestBehavior.opaque,
                    child: const Text(
                      'Hủy',
                      style: TextStyle(
                        color: Color(0xFF007AFF),
                        fontSize: 17,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                  if (_use3DFace)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '3D TrueDepth',
                        style: TextStyle(color: Color(0xFF007AFF), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),

            // Main Content Area
            Expanded(
              child: _buildBodyContent(),
            ),

            // Completion Button
            if (_scanStep == 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 370),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: Material(
                      color: const Color(0xFF007AFF),
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                        },
                        child: const Center(
                          child: Text(
                            'Xong',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyContent() {
    if (_scanStep == 0 && !_use3DFace) {
      return Column(
        children: [
          Expanded(
            flex: 65,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFF18181B),
                    child: _isCameraInitialized && _cameraController != null
                        ? ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.center,
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _cameraController!
                                      .value.previewSize!.height,
                                  height: _cameraController!
                                      .value.previewSize!.width,
                                  child: CameraPreview(_cameraController!),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: _hasError
                                ? Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: Text(
                                      _errorMessage,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 15,
                                      ),
                                    ),
                                  )
                                : const CircularProgressIndicator(
                                    color: Color(0xFF007AFF),
                                  ),
                          ),
                  ),
                ),
                _ReticleOverlay(
                  size: 260,
                  color: _hasDetectedFaceInStep0
                      ? const Color(0xFF34C759)
                      : Colors.white,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 35,
            child: Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.only(top: 32, left: 24, right: 24),
              child: Column(
                children: [
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _hasDetectedFaceInStep0
                          ? const Color(0xFF34C759)
                          : Colors.white,
                      fontSize: 22,
                      height: 1.32,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.375,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    } else if (_scanStep == 1 || (_use3DFace && _scanStep == 0)) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          SizedBox(
            width: 300,
            height: 300,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(300, 300),
                  painter: _FaceId64TicksPainter(
                    completedTicks: _completedTicks,
                    progress: _scanProgress,
                  ),
                ),
                Container(
                  width: 216,
                  height: 216,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: ClipOval(
                    child: _use3DFace
                        ? Container(
                            color: const Color(0xFF1C1C1E),
                            child: const Center(
                              child: Icon(
                                Icons.face_retouching_natural,
                                color: Color(0xFF007AFF),
                                size: 80,
                              ),
                            ),
                          )
                        : (_isCameraInitialized && _cameraController != null
                            ? OverflowBox(
                                alignment: Alignment.center,
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _cameraController!
                                        .value.previewSize!.height,
                                    height: _cameraController!
                                        .value.previewSize!.width,
                                    child: CameraPreview(_cameraController!),
                                  ),
                                ),
                              )
                            : Container(color: Colors.black)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 48),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                height: 1.3,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const Spacer(),
        ],
      );
    } else {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              color: Color(0xFF34C759),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 64,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Face ID hoàn tất',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _use3DFace
                ? 'Dữ liệu khuôn mặt 3D đã được đăng ký thành công.'
                : 'Face ID hiện đã được thiết lập thành công.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFEBEBF5),
              fontSize: 17,
            ),
          ),
          const Spacer(),
        ],
      );
    }
  }
}

class _ReticleOverlay extends StatelessWidget {
  final double size;
  final Color color;

  const _ReticleOverlay({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ReticlePainter(color: color),
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  final Color color;

  _ReticlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double cornerLength = 32.0;

    // Top-Left corner
    canvas.drawPath(
      Path()
        ..moveTo(0, cornerLength)
        ..lineTo(0, 0)
        ..lineTo(cornerLength, 0),
      paint,
    );

    // Top-Right corner
    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLength, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, cornerLength),
      paint,
    );

    // Bottom-Left corner
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - cornerLength)
        ..lineTo(0, size.height)
        ..lineTo(cornerLength, size.height),
      paint,
    );

    // Bottom-Right corner
    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLength, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, size.height - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _FaceId64TicksPainter extends CustomPainter {
  final List<bool> completedTicks;
  final double progress;

  _FaceId64TicksPainter({
    required this.completedTicks,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double outerRadius = (size.width / 2) - 8;
    final double innerRadius = outerRadius - 16;

    const int totalTicks = 64;
    const double angleStep = (2 * pi) / totalTicks;

    final Paint defaultPaint = Paint()
      ..color = const Color(0xFF3A3A3C)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final Paint activePaint = Paint()
      ..color = const Color(0xFF34C759)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < totalTicks; i++) {
      final double angle = i * angleStep;
      final double dx1 = cx + innerRadius * sin(angle);
      final double dy1 = cy - innerRadius * cos(angle);
      final double dx2 = cx + outerRadius * sin(angle);
      final double dy2 = cy - outerRadius * cos(angle);

      final isCompleted = completedTicks[i];
      canvas.drawLine(
        Offset(dx1, dy1),
        Offset(dx2, dy2),
        isCompleted ? activePaint : defaultPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FaceId64TicksPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.completedTicks != completedTicks;
  }
}
