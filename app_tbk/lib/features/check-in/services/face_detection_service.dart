// import 'dart:async';
// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/foundation.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
//
// class FaceDetectionService {
//   final FaceDetector _faceDetector = FaceDetector(
//     options: FaceDetectorOptions(
//       enableContours: false, // Tắt để tăng tốc
//       enableClassification: true,
//       enableLandmarks: false, // Tắt để tăng tốc
//       enableTracking: true,
//       minFaceSize: 0.15,
//       performanceMode: FaceDetectorMode.fast, // Chuyển sang fast mode
//     ),
//   );
//
//   // Chỉ lưu lịch sử cần thiết
//   final List<Face> _faceHistory = [];
//   final List<DateTime> _detectionTimestamps = [];
//
//   // Blink detection - đơn giản hóa
//   final List<double> _leftEyeHistory = [];
//   final List<double> _rightEyeHistory = [];
//   bool _blinkDetected = false;
//   DateTime? _lastBlinkTime;
//
//   // Phát hiện khuôn mặt từ camera image
//   Future<List<Face>> detectFaces(CameraImage image) async {
//     try {
//       final inputImage = _convertCameraImage(image);
//       if (inputImage == null) return [];
//
//       final faces = await _faceDetector.processImage(inputImage);
//
//       if (faces.isNotEmpty) {
//         _updateHistory(faces.first);
//       }
//
//       return faces;
//     } catch (e) {
//       print('Lỗi phát hiện khuôn mặt: $e');
//       return [];
//     }
//   }
//
//   // Cập nhật lịch sử - chỉ giữ dữ liệu cần thiết
//   void _updateHistory(Face face) {
//     _faceHistory.add(face);
//     _detectionTimestamps.add(DateTime.now());
//
//     // Lưu trạng thái mắt
//     if (face.leftEyeOpenProbability != null) {
//       _leftEyeHistory.add(face.leftEyeOpenProbability!);
//     }
//     if (face.rightEyeOpenProbability != null) {
//       _rightEyeHistory.add(face.rightEyeOpenProbability!);
//     }
//
//     // Giữ tối đa 15 frames (đủ để phát hiện)
//     if (_faceHistory.length > 15) {
//       _faceHistory.removeAt(0);
//       _detectionTimestamps.removeAt(0);
//     }
//     if (_leftEyeHistory.length > 12) {
//       _leftEyeHistory.removeAt(0);
//     }
//     if (_rightEyeHistory.length > 12) {
//       _rightEyeHistory.removeAt(0);
//     }
//
//     // Phát hiện nhấp nháy
//     _detectBlink();
//   }
//
//   // Phát hiện nhấp nháy mắt - tối ưu
//   void _detectBlink() {
//     if (_leftEyeHistory.length < 8 || _rightEyeHistory.length < 8) return;
//
//     // Lấy 8 giá trị gần nhất
//     final recentLeft = _leftEyeHistory.skip(_leftEyeHistory.length - 8).toList();
//     final recentRight = _rightEyeHistory.skip(_rightEyeHistory.length - 8).toList();
//
//     // Pattern đơn giản: mắt mở -> mắt nhắm -> mắt mở
//     bool foundBlinkPattern = false;
//
//     for (int i = 0; i < recentLeft.length - 2; i++) {
//       final wasOpen = recentLeft[i] > 0.6 && recentRight[i] > 0.6;
//       final wasClosed = recentLeft[i + 1] < 0.4 && recentRight[i + 1] < 0.4;
//       final isOpen = recentLeft[i + 2] > 0.6 && recentRight[i + 2] > 0.6;
//
//       if (wasOpen && wasClosed && isOpen) {
//         foundBlinkPattern = true;
//         break;
//       }
//     }
//
//     if (foundBlinkPattern &&
//         (_lastBlinkTime == null ||
//             DateTime.now().difference(_lastBlinkTime!).inSeconds > 1)) {
//       _blinkDetected = true;
//       _lastBlinkTime = DateTime.now();
//       print('👁️ ✅ Phát hiện nhấp nháy!');
//     }
//   }
//
//   // Kiểm tra khuôn mặt - CHỈ GIỮ 4 TESTS QUAN TRỌNG NHẤT
//   FaceValidationResult validateFace(Face face, Size imageSize) {
//     final adjustedSize = Size(imageSize.height, imageSize.width);
//
//     // ===== TEST 1: KÍCH THƯỚC & VỊ TRÍ (Kết hợp 2 test cũ) =====
//     final faceWidth = face.boundingBox.width;
//     final faceHeight = face.boundingBox.height;
//     final minSize = adjustedSize.width * 0.22; // Giảm từ 0.25 để dễ hơn
//
//     final faceCenterX = face.boundingBox.center.dx;
//     final faceCenterY = face.boundingBox.center.dy;
//     final imageCenterX = adjustedSize.width / 2;
//     final imageCenterY = adjustedSize.height / 2;
//
//     final offsetX = (faceCenterX - imageCenterX).abs();
//     final offsetY = (faceCenterY - imageCenterY).abs();
//
//     // Kiểm tra cả kích thước và vị trí
//     if (faceWidth < minSize || faceHeight < minSize) {
//       return FaceValidationResult(
//         isValid: false,
//         message: 'Vui lòng di chuyển gần hơn',
//         livenessScore: 0.2,
//       );
//     }
//
//     if (offsetX > adjustedSize.width * 0.3 || offsetY > adjustedSize.height * 0.3) {
//       return FaceValidationResult(
//         isValid: false,
//         message: 'Đưa khuôn mặt vào giữa khung',
//         livenessScore: 0.3,
//       );
//     }
//
//     // ===== TEST 2: GÓC QUAY ĐẦU =====
//     final headY = face.headEulerAngleY ?? 0;
//     final headX = face.headEulerAngleX ?? 0;
//     final headZ = face.headEulerAngleZ ?? 0;
//
//     if (headY.abs() > 30 || headX.abs() > 30 || headZ.abs() > 30) {
//       return FaceValidationResult(
//         isValid: false,
//         message: 'Giữ khuôn mặt thẳng',
//         livenessScore: 0.1,
//       );
//     }
//
//     // ===== TEST 3: CHUYỂN ĐỘNG (Anti-Spoofing chính) =====
//     double movementScore = 0;
//     if (_faceHistory.length >= 5) {
//       movementScore = _detectMovement();
//
//       if (movementScore < 0.4) { // Giảm ngưỡng từ 0.5
//         return FaceValidationResult(
//           isValid: false,
//           message: 'Di chuyển nhẹ đầu',
//           livenessScore: movementScore,
//         );
//       }
//     }
//
//     // ===== TEST 4: NHẤP NHÁY MẮT (Anti-Spoofing phụ) =====
//     final leftEye = face.leftEyeOpenProbability ?? 0;
//     final rightEye = face.rightEyeOpenProbability ?? 0;
//
//     // Kiểm tra mắt mở
//     if (leftEye < 0.4 || rightEye < 0.4) {
//       return FaceValidationResult(
//         isValid: false,
//         message: 'Mở to mắt',
//         livenessScore: 0.3,
//       );
//     }
//
//     // Yêu cầu nhấp nháy nếu chưa phát hiện
//     if (!_blinkDetected && _leftEyeHistory.length >= 10) {
//       return FaceValidationResult(
//         isValid: false,
//         message: 'Nhấp nháy mắt để xác thực',
//         livenessScore: 0.5,
//         requiresBlink: true,
//       );
//     }
//
//     // ===== KIỂM TRA THỜI GIAN TỒN TẠI =====
//     if (_detectionTimestamps.length >= 2) {
//       final duration = _detectionTimestamps.last
//           .difference(_detectionTimestamps.first)
//           .inMilliseconds;
//
//       if (duration < 800) { // Giảm từ 1000ms
//         return FaceValidationResult(
//           isValid: false,
//           message: 'Giữ vững khuôn mặt...',
//           livenessScore: 0.2,
//         );
//       }
//     }
//
//     // ===== TÍNH TỔNG ĐIỂM LIVENESS (Đơn giản hóa) =====
//     final livenessScore = (
//         movementScore * 0.6 +  // Chuyển động là quan trọng nhất
//             (_blinkDetected ? 0.4 : 0.2)  // Nhấp nháy quan trọng thứ 2
//     );
//
//     if (livenessScore < 0.5) { // Giảm ngưỡng từ 0.6
//       return FaceValidationResult(
//         isValid: false,
//         message: 'Xác thực không thành công',
//         livenessScore: livenessScore,
//       );
//     }
//
//     print('✅ Xác thực thành công! Score: ${livenessScore.toStringAsFixed(2)}');
//     return FaceValidationResult(
//       isValid: true,
//       message: 'Xác thực thành công',
//       face: face,
//       livenessScore: livenessScore,
//     );
//   }
//
//   // Phát hiện chuyển động - TỐI ƯU
//   double _detectMovement() {
//     if (_faceHistory.length < 5) return 0;
//
//     double totalMovement = 0;
//     double totalAngleChange = 0;
//     int count = 0;
//
//     for (int i = 1; i < _faceHistory.length; i++) {
//       final prev = _faceHistory[i - 1];
//       final curr = _faceHistory[i];
//
//       // Tính khoảng cách di chuyển vị trí
//       final dx = (curr.boundingBox.center.dx - prev.boundingBox.center.dx).abs();
//       final dy = (curr.boundingBox.center.dy - prev.boundingBox.center.dy).abs();
//       totalMovement += dx + dy;
//
//       // Tính thay đổi góc (phát hiện xoay đầu = 3D)
//       final angleY = ((curr.headEulerAngleY ?? 0) - (prev.headEulerAngleY ?? 0)).abs();
//       final angleX = ((curr.headEulerAngleX ?? 0) - (prev.headEulerAngleX ?? 0)).abs();
//       totalAngleChange += angleY + angleX;
//
//       count++;
//     }
//
//     final avgMovement = count > 0 ? totalMovement / count : 0;
//     final avgAngleChange = count > 0 ? totalAngleChange / count : 0;
//
//     // Kết hợp cả 2: chuyển động vị trí + xoay góc
//     double positionScore = 0;
//     if (avgMovement < 1) positionScore = 0.3;  // Quá tĩnh
//     else if (avgMovement < 4) positionScore = 0.6;
//     else if (avgMovement < 12) positionScore = 1.0;  // Tốt nhất
//     else if (avgMovement < 25) positionScore = 0.7;
//     else positionScore = 0.4;  // Quá nhanh
//
//     double angleScore = 0;
//     if (avgAngleChange < 0.5) angleScore = 0.2;  // Không xoay = ảnh phẳng
//     else if (avgAngleChange < 2) angleScore = 0.7;
//     else if (avgAngleChange < 5) angleScore = 1.0;  // Xoay nhẹ = 3D thật
//     else angleScore = 0.5;  // Xoay quá nhiều
//
//     // Trọng số: 60% vị trí, 40% góc
//     return positionScore * 0.6 + angleScore * 0.4;
//   }
//
//   // Reset lịch sử
//   void resetHistory() {
//     _faceHistory.clear();
//     _detectionTimestamps.clear();
//     _leftEyeHistory.clear();
//     _rightEyeHistory.clear();
//     _blinkDetected = false;
//     _lastBlinkTime = null;
//     print('🔄 Đã reset');
//   }
//
//   // Chuyển đổi CameraImage sang InputImage
//   InputImage? _convertCameraImage(CameraImage image) {
//     try {
//       final WriteBuffer allBytes = WriteBuffer();
//       for (final Plane plane in image.planes) {
//         allBytes.putUint8List(plane.bytes);
//       }
//       final bytes = allBytes.done().buffer.asUint8List();
//
//       final imageSize = Size(image.width.toDouble(), image.height.toDouble());
//       const InputImageRotation imageRotation = InputImageRotation.rotation270deg;
//
//       final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ??
//           InputImageFormat.nv21;
//
//       final inputImageMetadata = InputImageMetadata(
//         size: imageSize,
//         rotation: imageRotation,
//         format: inputImageFormat,
//         bytesPerRow: image.planes.first.bytesPerRow,
//       );
//
//       return InputImage.fromBytes(
//         bytes: bytes,
//         metadata: inputImageMetadata,
//       );
//     } catch (e) {
//       print('Lỗi chuyển đổi image: $e');
//       return null;
//     }
//   }
//
//   void dispose() {
//     _faceDetector.close();
//   }
// }
//
// class FaceValidationResult {
//   final bool isValid;
//   final String message;
//   final Face? face;
//   final double livenessScore;
//   final bool requiresBlink;
//
//   FaceValidationResult({
//     required this.isValid,
//     required this.message,
//     this.face,
//     this.livenessScore = 0,
//     this.requiresBlink = false,
//   });
// }


import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectionService {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      enableLandmarks: true,
      enableTracking: true,
      minFaceSize: 0.15,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  // Lưu trữ lịch sử để phát hiện chuyển động
  final List<Face> _faceHistory = [];
  final List<double> _brightnessHistory = [];
  final List<DateTime> _detectionTimestamps = [];

  // Blink detection
  final List<double> _leftEyeHistory = [];
  final List<double> _rightEyeHistory = [];
  bool _blinkDetected = false;
  DateTime? _lastBlinkTime;

  // Phát hiện khuôn mặt từ camera image
  Future<List<Face>> detectFaces(CameraImage image) async {
    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) {
        print('⚠️ inputImage is null');
        return [];
      }

      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        _updateHistory(faces.first, image);
      }

      print('👥 Detected ${faces.length} face(s)');
      return faces;
    } catch (e) {
      print('Lỗi phát hiện khuôn mặt: $e');
      return [];
    }
  }

  // Cập nhật lịch sử để phát hiện chuyển động
  void _updateHistory(Face face, CameraImage image) {
    _faceHistory.add(face);
    _detectionTimestamps.add(DateTime.now());

    // Tính độ sáng trung bình của ảnh
    final brightness = _calculateAverageBrightness(image);
    _brightnessHistory.add(brightness);

    // Lưu trạng thái mắt
    if (face.leftEyeOpenProbability != null) {
      _leftEyeHistory.add(face.leftEyeOpenProbability!);
    }
    if (face.rightEyeOpenProbability != null) {
      _rightEyeHistory.add(face.rightEyeOpenProbability!);
    }

    // Giữ tối đa 30 frames (khoảng 1 giây)
    if (_faceHistory.length > 30) {
      _faceHistory.removeAt(0);
      _detectionTimestamps.removeAt(0);
    }
    if (_brightnessHistory.length > 30) {
      _brightnessHistory.removeAt(0);
    }
    if (_leftEyeHistory.length > 15) {
      _leftEyeHistory.removeAt(0);
    }
    if (_rightEyeHistory.length > 15) {
      _rightEyeHistory.removeAt(0);
    }

    // Phát hiện nhấp nháy
    _detectBlink();
  }

  // Tính độ sáng trung bình (sample một số pixel)
  double _calculateAverageBrightness(CameraImage image) {
    if (image.planes.isEmpty) return 0;

    final plane = image.planes[0];
    final bytes = plane.bytes;

    // Sample 100 pixels ngẫu nhiên
    int sum = 0;
    int count = 0;
    final step = bytes.length ~/ 100;

    for (int i = 0; i < bytes.length; i += step) {
      sum += bytes[i];
      count++;
      if (count >= 100) break;
    }

    return count > 0 ? sum / count : 0;
  }

  // Phát hiện nhấp nháy mắt
  void _detectBlink() {
    if (_leftEyeHistory.length < 10 || _rightEyeHistory.length < 10) return;

    // Lấy 10 giá trị gần nhất
    final recentLeft = _leftEyeHistory.skip(_leftEyeHistory.length - 10).toList();
    final recentRight = _rightEyeHistory.skip(_rightEyeHistory.length - 10).toList();

    // Tìm pattern: mắt mở (>0.7) -> mắt nhắm (<0.3) -> mắt mở (>0.7)
    bool foundBlinkPattern = false;

    for (int i = 0; i < recentLeft.length - 2; i++) {
      final wasOpen = recentLeft[i] > 0.7 && recentRight[i] > 0.7;
      final wasClosed = recentLeft[i + 1] < 0.3 && recentRight[i + 1] < 0.3;
      final isOpen = recentLeft[i + 2] > 0.7 && recentRight[i + 2] > 0.7;

      if (wasOpen && wasClosed && isOpen) {
        foundBlinkPattern = true;
        break;
      }
    }

    if (foundBlinkPattern &&
        (_lastBlinkTime == null ||
            DateTime.now().difference(_lastBlinkTime!).inSeconds > 1)) {
      _blinkDetected = true;
      _lastBlinkTime = DateTime.now();
      print('👁️ ✅ BLINK DETECTED!');
    }
  }

  // Kiểm tra khuôn mặt có hợp lệ không với ANTI-SPOOFING
  FaceValidationResult validateFace(Face face, Size imageSize) {
    print('🔍 === ADVANCED FACE VALIDATION WITH ANTI-SPOOFING ===');

    final adjustedSize = Size(imageSize.height, imageSize.width);

    print('📐 Image Size: ${adjustedSize.width} x ${adjustedSize.height}');
    print('📦 Bounding Box: ${face.boundingBox}');

    // ===== TEST 1: KIỂM TRA GÓC QUAY ĐẦU =====
    final headY = face.headEulerAngleY ?? 0;
    final headX = face.headEulerAngleX ?? 0;
    final headZ = face.headEulerAngleZ ?? 0;

    print('🔄 Head Angles - Y: $headY, X: $headX, Z: $headZ');

    if (headY.abs() > 25 || headX.abs() > 25 || headZ.abs() > 25) {
      print('❌ FAILED: Head angle too large');
      return FaceValidationResult(
        isValid: false,
        message: 'Vui lòng giữ khuôn mặt thẳng và nhìn vào camera',
        livenessScore: 0,
      );
    }

    // ===== TEST 2: KIỂM TRA KÍCH THƯỚC =====
    final faceWidth = face.boundingBox.width;
    final faceHeight = face.boundingBox.height;
    final minSize = adjustedSize.width * 0.25;

    print('📏 Min Size: $minSize, Face: $faceWidth x $faceHeight');

    if (faceWidth < minSize || faceHeight < minSize) {
      print('❌ FAILED: Face too small');
      return FaceValidationResult(
        isValid: false,
        message: 'Vui lòng di chuyển gần hơn camera',
        livenessScore: 0,
      );
    }

    // ===== TEST 3: KIỂM TRA VỊ TRÍ GIỮA =====
    final faceCenterX = face.boundingBox.center.dx;
    final faceCenterY = face.boundingBox.center.dy;
    final imageCenterX = adjustedSize.width / 2;
    final imageCenterY = adjustedSize.height / 2;

    final offsetX = (faceCenterX - imageCenterX).abs();
    final offsetY = (faceCenterY - imageCenterY).abs();

    print('📍 Offset: X=$offsetX, Y=$offsetY');

    if (offsetX > adjustedSize.width * 0.25 || offsetY > adjustedSize.height * 0.25) {
      print('❌ FAILED: Face not centered');
      return FaceValidationResult(
        isValid: false,
        message: 'Vui lòng đưa khuôn mặt vào giữa khung',
        livenessScore: 0,
      );
    }

    // ===== TEST 4: ANTI-SPOOFING - KIỂM TRA CHUYỂN ĐỘNG =====
    double movementScore = 0;
    if (_faceHistory.length >= 5) {
      movementScore = _detectMovement();
      print('🏃 Movement Score: ${movementScore.toStringAsFixed(2)}');

      if (movementScore < 0.3) {
        print('⚠️ WARNING: Very low movement detected (possible photo)');
        return FaceValidationResult(
          isValid: false,
          message: 'Không phát hiện chuyển động. Vui lòng nhìn thẳng vào camera',
          livenessScore: movementScore,
        );
      }
    }

    // ===== TEST 5: ANTI-SPOOFING - KIỂM TRA ĐỘ SÁNG THAY ĐỔI =====
    double brightnessScore = 0;
    if (_brightnessHistory.length >= 10) {
      brightnessScore = _detectBrightnessVariation();
      print('💡 Brightness Variation Score: ${brightnessScore.toStringAsFixed(2)}');

      if (brightnessScore < 0.3) {
        print('⚠️ WARNING: No brightness variation (possible photo/video)');
        return FaceValidationResult(
          isValid: false,
          message: 'Ảnh quá tĩnh. Vui lòng di chuyển nhẹ đầu',
          livenessScore: brightnessScore,
        );
      }
    }

    // ===== TEST 6: ANTI-SPOOFING - KIỂM TRA TEXTURE/CHẤT LƯỢNG =====
    double textureScore = 0;
    if (face.landmarks.isNotEmpty) {
      textureScore = _analyzeTexture(face);
      print('🖼️ Texture Quality Score: ${textureScore.toStringAsFixed(2)}');

      if (textureScore < 0.6) {
        print('⚠️ WARNING: Low texture quality (possible printed photo)');
        return FaceValidationResult(
          isValid: false,
          message: 'Chất lượng ảnh không đạt. Vui lòng cải thiện ánh sáng',
          livenessScore: textureScore,
        );
      }
    }

    // ===== TEST 7: ANTI-SPOOFING - PHÁT HIỆN NHẤP NHÁY =====
    print('👁️ Blink Status: ${_blinkDetected ? "DETECTED ✅" : "NOT YET ⏳"}');

    if (!_blinkDetected && _leftEyeHistory.length >= 15) {
      print('⚠️ WARNING: No blink detected yet');
      return FaceValidationResult(
        isValid: false,
        message: 'Vui lòng nhấp nháy mắt để xác thực',
        livenessScore: 0.3,
        requiresBlink: true,
      );
    }

    // ===== TEST 8: KIỂM TRA MẮT MỞ =====
    final leftEye = face.leftEyeOpenProbability ?? 0;
    final rightEye = face.rightEyeOpenProbability ?? 0;

    print('👁️ Eyes: Left=$leftEye, Right=$rightEye');

    if (leftEye < 0.5 || rightEye < 0.5) {
      print('❌ FAILED: Eyes not fully open');
      return FaceValidationResult(
        isValid: false,
        message: 'Vui lòng mở to mắt',
        livenessScore: 0.3,
      );
    }

    // ===== TEST 9: KIỂM TRA THỜI GIAN TỒN TẠI =====
    if (_detectionTimestamps.length >= 2) {
      final duration = _detectionTimestamps.last
          .difference(_detectionTimestamps.first)
          .inMilliseconds;

      print('⏱️ Detection Duration: ${duration}ms');

      if (duration < 1000) {
        print('⚠️ WARNING: Too quick detection (need at least 1 second)');
        return FaceValidationResult(
          isValid: false,
          message: 'Vui lòng giữ vững khuôn mặt trong 2-3 giây',
          livenessScore: 0.2,
        );
      }
    }

    // ===== TEST 10: KIỂM TRA ĐỘ SÂU (3D) =====
    double depthScore = 0;
    if (face.contours.isNotEmpty) {
      depthScore = _analyze3DDepth(face);
      print('📐 3D Depth Score: ${depthScore.toStringAsFixed(2)}');

      if (depthScore < 0.4) {
        print('⚠️ WARNING: Flat surface detected (possible 2D photo)');
        return FaceValidationResult(
          isValid: false,
          message: 'Không phát hiện độ sâu khuôn mặt. Vui lòng quay nhẹ đầu',
          livenessScore: depthScore,
        );
      }
    }

    // ===== TÍNH TỔNG ĐIỂM LIVENESS =====
    final livenessScore = (movementScore * 0.3 +
        brightnessScore * 0.2 +
        textureScore * 0.2 +
        depthScore * 0.2 +
        (_blinkDetected ? 0.1 : 0)) / 1.0;

    print('🎯 FINAL LIVENESS SCORE: ${livenessScore.toStringAsFixed(2)}');

    if (livenessScore < 0.6) {
      print('❌ FAILED: Low liveness score');
      return FaceValidationResult(
        isValid: false,
        message: 'Xác thực không thành công. Vui lòng thử lại',
        livenessScore: livenessScore,
      );
    }

    print('✅ ✅ ✅ PASSED ALL TESTS - REAL HUMAN DETECTED!');
    return FaceValidationResult(
      isValid: true,
      message: 'Khuôn mặt hợp lệ - Đã xác thực thành công',
      face: face,
      livenessScore: livenessScore,
    );
  }

  // Phát hiện chuyển động giữa các frame
  double _detectMovement() {
    if (_faceHistory.length < 5) return 0;

    double totalMovement = 0;
    int count = 0;

    for (int i = 1; i < _faceHistory.length; i++) {
      final prev = _faceHistory[i - 1].boundingBox;
      final curr = _faceHistory[i].boundingBox;

      // Tính khoảng cách di chuyển
      final dx = (curr.center.dx - prev.center.dx).abs();
      final dy = (curr.center.dy - prev.center.dy).abs();
      final movement = dx + dy;

      totalMovement += movement;
      count++;
    }

    final avgMovement = count > 0 ? totalMovement / count : 0;

    // Normalize: 0-5 pixels = low, 5-20 = good, >20 = too much
    if (avgMovement < 2) return 0.3;  // Too static
    if (avgMovement < 5) return 0.6;
    if (avgMovement < 15) return 1.0;  // Perfect
    if (avgMovement < 30) return 0.7;
    return 0.4;  // Too much movement
  }

  // Phát hiện biến đổi độ sáng
  double _detectBrightnessVariation() {
    if (_brightnessHistory.length < 5) return 0;

    double minBrightness = _brightnessHistory[0];
    double maxBrightness = _brightnessHistory[0];

    for (final brightness in _brightnessHistory) {
      if (brightness < minBrightness) minBrightness = brightness;
      if (brightness > maxBrightness) maxBrightness = brightness;
    }

    final variation = maxBrightness - minBrightness;

    // Normalize: 0-5 = static (bad), 5-30 = good, >30 = too much
    if (variation < 3) return 0.2;  // Too static (photo)
    if (variation < 10) return 0.6;
    if (variation < 30) return 1.0;  // Perfect
    if (variation < 50) return 0.7;
    return 0.5;  // Too much (video)
  }

  // Phân tích texture/chất lượng
  double _analyzeTexture(Face face) {
    // Số lượng landmarks là indicator của chất lượng
    final landmarkCount = face.landmarks.length;

    // Kiểm tra contours
    final contourCount = face.contours.length;

    // Face có đầy đủ landmarks = chất lượng cao
    if (landmarkCount >= 5 && contourCount >= 3) return 1.0;
    if (landmarkCount >= 3 && contourCount >= 2) return 0.7;
    if (landmarkCount >= 2) return 0.5;
    return 0.3;
  }

  // Phân tích độ sâu 3D
  double _analyze3DDepth(Face face) {
    if (_faceHistory.length < 5) return 0.5;

    // Phân tích sự thay đổi của các góc Euler
    final recentFaces = _faceHistory.skip(_faceHistory.length - 5).toList();

    double angleVariation = 0;
    for (int i = 1; i < recentFaces.length; i++) {
      final prevY = recentFaces[i - 1].headEulerAngleY ?? 0;
      final currY = recentFaces[i].headEulerAngleY ?? 0;
      final prevX = recentFaces[i - 1].headEulerAngleX ?? 0;
      final currX = recentFaces[i].headEulerAngleX ?? 0;

      angleVariation += (prevY - currY).abs() + (prevX - currX).abs();
    }

    // Có sự thay đổi góc = có độ sâu 3D
    if (angleVariation > 10) return 1.0;
    if (angleVariation > 5) return 0.8;
    if (angleVariation > 2) return 0.6;
    return 0.3;  // Quá phẳng = ảnh 2D
  }

  // Reset lịch sử khi bắt đầu session mới
  void resetHistory() {
    _faceHistory.clear();
    _brightnessHistory.clear();
    _detectionTimestamps.clear();
    _leftEyeHistory.clear();
    _rightEyeHistory.clear();
    _blinkDetected = false;
    _lastBlinkTime = null;
    print('🔄 History reset');
  }

  // Chuyển đổi CameraImage sang InputImage
  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      const InputImageRotation imageRotation = InputImageRotation.rotation270deg;

      final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;

      final inputImageMetadata = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageMetadata,
      );
    } catch (e) {
      print('Lỗi chuyển đổi image: $e');
      return null;
    }
  }

  void dispose() {
    _faceDetector.close();
  }
}

class FaceValidationResult {
  final bool isValid;
  final String message;
  final Face? face;
  final double livenessScore;
  final bool requiresBlink;

  FaceValidationResult({
    required this.isValid,
    required this.message,
    this.face,
    this.livenessScore = 0,
    this.requiresBlink = false,
  });
}
