import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Detector phát hiện khuôn mặt ML Kit
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
    _initCamera();
  }

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

      // Chọn camera trước (Front Camera)
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

      // Bắt đầu luồng xử lý ảnh camera để nhận diện khuôn mặt
      await controller.startImageStream(_processCameraImage);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Lỗi khởi tạo camera: $e';
      });
    }
  }

  // Xử lý từng frame hình từ camera
  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessingFrame || !mounted || _scanStep == 2) return;
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

      // ----------------------------------------------------
      // BƯỚC 0: KIỂM TRA PHÁT HIỆN KHUÔN MẶT BAN ĐẦU
      // ----------------------------------------------------
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

          // Yêu cầu phát hiện liên tục 3 frames mới bắt đầu chuyển sang Bước 1 (Quét 360 độ)
          if (_faceDetectedFrameCount >= 3) {
            setState(() {
              _scanStep = 1;
              _statusMessage = 'Xoay chậm đầu của bạn theo hình tròn 360°';
            });
          }
        }
      }
      // ----------------------------------------------------
      // BƯỚC 1: XÁC THỰC BẰNG CÁCH XOAY KHUÔN MẶT 360 ĐỘ
      // ----------------------------------------------------
      else if (_scanStep == 1) {
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
          final double yaw = face.headEulerAngleY ?? 0.0; // Quay trái (-), phải (+)
          final double pitch = face.headEulerAngleX ?? 0.0; // Cúi xuống (-), ngẩng lên (+)

          final double dx = yaw;
          final double dy = pitch;
          final double magnitude = sqrt(dx * dx + dy * dy);

          // Ngưỡng phát hiện độ nghiêng/xoay của đầu (>= 5 độ)
          if (magnitude >= 5.0) {
            // Tính góc hướng đầu theo radian từ vị trí 12 giờ theo chiều kim đồng hồ
            double angleRad = atan2(yaw, pitch);
            if (angleRad < 0) {
              angleRad += 2 * pi;
            }

            // Quy đổi góc sang vạch tương ứng (0 -> 63)
            int centerTick = ((angleRad / (2 * pi)) * 64).round() % 64;

            bool updated = false;
            // Đánh dấu các vạch xung quanh góc quay (độ phủ 5 vạch)
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
                _onScanComplete();
              }
            }
          } else {
            int percentage = (_scanProgress * 100).round();
            String prompt = percentage == 0
                ? 'Hãy xoay chậm đầu của bạn theo hình tròn 360°'
                : 'Tiếp tục xoay đầu theo hình tròn ($percentage%)';
            if (_statusMessage != prompt) {
              setState(() {
                _statusMessage = prompt;
              });
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

  // Chuyển đổi CameraImage thành InputImage cho ML Kit
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

  Future<void> _onScanComplete() async {
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
            // Thanh điều hướng trên
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
                ],
              ),
            ),

            // Nội dung chính
            Expanded(
              child: _buildBodyContent(),
            ),

            // Nút tùy chọn trợ năng (khi đang quét)
            if (_scanStep == 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0, top: 8.0),
                child: TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Chức năng trợ năng cho Face ID'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: const Text(
                    'Tùy chọn Trợ năng',
                    style: TextStyle(
                      color: Color(0xFF007AFF),
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),

            // Nút Hoàn tất
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
    if (_scanStep == 0) {
      // Bước 0: Định vị & Kiểm tra nhận diện khuôn mặt
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
    } else if (_scanStep == 1) {
      // Bước 1: Quét xoay khuôn mặt 360 độ (64 vạch)
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          // Container 300x300 chứa 64 vạch tròn và xem camera
          SizedBox(
            width: 300,
            height: 300,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Vẽ 64 vạch tròn theo tiến trình xoay mặt
                CustomPaint(
                  size: const Size(300, 300),
                  painter: _FaceId64TicksPainter(
                    completedTicks: _completedTicks,
                    progress: _scanProgress,
                  ),
                ),
                // Ô xem camera hình tròn 216x216
                Container(
                  width: 216,
                  height: 216,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: ClipOval(
                    child: _isCameraInitialized && _cameraController != null
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
                        : Container(color: Colors.black),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 48),

          // Hướng dẫn người dùng xoay đầu
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
      // Bước 2: Thành công / Completed
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: const Text(
              'Xác thực Face ID đã được thiết lập thành công.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFEBEBF5),
                fontSize: 16.5,
                height: 1.4,
              ),
            ),
          ),
          const Spacer(),
        ],
      );
    }
  }
}

class _FaceId64TicksPainter extends CustomPainter {
  final List<bool> completedTicks;
  final double progress;

  const _FaceId64TicksPainter({
    required this.completedTicks,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double outerRadius = (size.width / 2) - 8;
    final double innerRadius = outerRadius - 14;

    const int totalTicks = 64;
    const double angleStep = (2 * pi) / totalTicks;

    final Paint inactivePaint = Paint()
      ..color = const Color(0x59D1D5DB)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final Paint activePaint = Paint()
      ..color = const Color(0xFF007AFF)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < totalTicks; i++) {
      final double angle = i * angleStep;
      final double dx1 = cx + innerRadius * sin(angle);
      final double dy1 = cy - innerRadius * cos(angle);
      final double dx2 = cx + outerRadius * sin(angle);
      final double dy2 = cy - outerRadius * cos(angle);

      final bool isActive = (i < completedTicks.length && completedTicks[i]);
      canvas.drawLine(
        Offset(dx1, dy1),
        Offset(dx2, dy2),
        isActive ? activePaint : inactivePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FaceId64TicksPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.completedTicks != completedTicks;
  }
}

class _ReticleOverlay extends StatelessWidget {
  final double size;
  final Color color;

  const _ReticleOverlay({
    this.size = 260.0,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    const double cornerSize = 44.0;
    const double strokeWidth = 4.5;
    const double radius = 24.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Góc trên bên trái
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: cornerSize,
              height: cornerSize,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: color, width: strokeWidth),
                  left: BorderSide(color: color, width: strokeWidth),
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(radius),
                ),
              ),
            ),
          ),
          // Góc trên bên phải
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: cornerSize,
              height: cornerSize,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: color, width: strokeWidth),
                  right: BorderSide(color: color, width: strokeWidth),
                ),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(radius),
                ),
              ),
            ),
          ),
          // Góc dưới bên trái
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: cornerSize,
              height: cornerSize,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: color, width: strokeWidth),
                  left: BorderSide(color: color, width: strokeWidth),
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(radius),
                ),
              ),
            ),
          ),
          // Góc dưới bên phải
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: cornerSize,
              height: cornerSize,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: color, width: strokeWidth),
                  right: BorderSide(color: color, width: strokeWidth),
                ),
                borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(radius),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
