import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:app_tbk/config/api_constants.dart';
import 'package:app_tbk/features/auth/services/auth_service.dart';

/// Challenge data returned by GET /face-3d/challenge
class Face3DChallenge {
  final String challengeId;
  final String action; // 'blink', 'turn_left', 'turn_right', 'smile'
  final int expiresIn;

  Face3DChallenge({
    required this.challengeId,
    required this.action,
    required this.expiresIn,
  });

  factory Face3DChallenge.fromJson(Map<String, dynamic> json) {
    return Face3DChallenge(
      challengeId: json['challenge_id'] ?? json['challengeId'] ?? '',
      action: json['action'] ?? '',
      expiresIn: json['expires_in'] ?? json['expiresIn'] ?? 60,
    );
  }
}

/// Response result from server for enroll / verify
class Face3DResult {
  final bool success;
  final String? message;
  final String? errorCode;
  final Map<String, dynamic>? data;

  Face3DResult({
    required this.success,
    this.message,
    this.errorCode,
    this.data,
  });

  factory Face3DResult.fromJson(Map<String, dynamic> json) {
    return Face3DResult(
      success: json['success'] ?? (json['code'] == 200 || json['status'] == 'success'),
      message: json['message'] ?? json['msg'],
      errorCode: json['error_code'] ?? json['errorCode'] ?? json['code']?.toString(),
      data: json,
    );
  }
}

/// Real-time frame tracking event received from iOS Native EventChannel
class Face3DFrameEvent {
  final bool isTracked;
  final String status;
  final double yaw;
  final double pitch;
  final double roll;
  final List<int> completedSectors;
  final double progress;

  Face3DFrameEvent({
    required this.isTracked,
    required this.status,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.completedSectors,
    required this.progress,
  });

  factory Face3DFrameEvent.fromMap(Map<dynamic, dynamic> map) {
    return Face3DFrameEvent(
      isTracked: map['is_tracked'] ?? false,
      status: map['status'] ?? '',
      yaw: (map['yaw'] as num?)?.toDouble() ?? 0.0,
      pitch: (map['pitch'] as num?)?.toDouble() ?? 0.0,
      roll: (map['roll'] as num?)?.toDouble() ?? 0.0,
      completedSectors: List<int>.from(map['completed_sectors'] ?? []),
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class Face3DService {
  static const MethodChannel _channel = MethodChannel('com.example.app_tbk/face_3d');
  static const EventChannel _eventChannel = EventChannel('com.example.app_tbk/face_3d_events');

  // HTTPS Endpoint for Face 3D (Spec: Must use HTTPS, port 8202 under service /face-3d)
  static String get _face3dBaseUrl {
    // Convert base URL to HTTPS and append /face-3d endpoint
    final base = ApiConstants.baseUrl.replaceAll('http://', 'https://');
    final hostPort = base.split('/student-calendar').first;
    return '$hostPort/face-3d';
  }

  /// Check if Native 3D Face tracking (ARKit FaceTracking) is supported on current device
  static Future<bool> isSupported() async {
    if (!Platform.isIOS) return false;
    try {
      final bool supported = await _channel.invokeMethod('isSupported');
      return supported;
    } catch (e) {
      return false;
    }
  }

  /// Listen to real-time face tracking stream from Native iOS
  static Stream<Face3DFrameEvent> get trackingStream {
    return _eventChannel.receiveBroadcastStream().map((dynamic event) {
      return Face3DFrameEvent.fromMap(event as Map<dynamic, dynamic>);
    });
  }

  /// Start a 3D tracking session ('enroll' or 'verify')
  static Future<bool> startSession({
    required String mode,
    required String challengeId,
  }) async {
    try {
      final bool result = await _channel.invokeMethod('startSession', {
        'mode': mode,
        'challenge_id': challengeId,
      });
      return result;
    } catch (e) {
      return false;
    }
  }

  /// Stop current 3D tracking session
  static Future<bool> stopSession() async {
    try {
      final bool result = await _channel.invokeMethod('stopSession');
      return result;
    } catch (e) {
      return false;
    }
  }

  /// Get collected tracking payload (meta, rgb images, GZipped mesh & sequence)
  static Future<Map<dynamic, dynamic>?> getCollectedPayload() async {
    try {
      final payload = await _channel.invokeMethod('getCollectedPayload');
      return payload as Map<dynamic, dynamic>?;
    } catch (e) {
      return null;
    }
  }

  /// 1. GET /face-3d/challenge
  /// Fetches a randomized challenge right before scanning (TTL 60s)
  static Future<Face3DChallenge> getChallenge() async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Phiên đăng nhập hết hạn. Vui lòng đăng nhập lại.');
    }

    final url = Uri.parse('$_face3dBaseUrl/challenge');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      return Face3DChallenge.fromJson(data);
    } else {
      final errorJson = jsonDecode(response.body);
      throw Exception(errorJson['message'] ?? 'Không lấy được mã thử thách (Challenge) từ máy chủ');
    }
  }

  /// 2. POST /face-3d/enroll or POST /face-3d/verify
  /// Sends collected multipart payload to backend
  static Future<Face3DResult> submitPayload({
    required String mode, // 'enroll' or 'verify'
    required Map<dynamic, dynamic> nativePayload,
  }) async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Phiên đăng nhập hết hạn. Vui lòng đăng nhập lại.');
    }

    final url = Uri.parse('$_face3dBaseUrl/$mode');
    final request = http.MultipartRequest('POST', url);

    request.headers['Authorization'] = 'Bearer $token';

    // 1. Part: meta (text)
    final String metaJson = nativePayload['meta_json'] ?? '{}';
    request.fields['meta'] = metaJson;

    // 2. Part: rgb_0 ... rgb_N (files)
    final Map<dynamic, dynamic> rgbImages = nativePayload['rgb_images'] ?? {};
    rgbImages.forEach((key, value) {
      final fieldName = key.toString();
      final Uint8List imageBytes = Uint8List.fromList((value as List).cast<int>());
      request.files.add(
        http.MultipartFile.fromBytes(
          fieldName, // name=
          imageBytes,
          filename: '$fieldName.jpg',
        ),
      );
    });

    // 3. Part: mesh (mesh.json.gz file)
    final Uint8List meshGzBytes = Uint8List.fromList(
      ((nativePayload['mesh_gz'] as List?) ?? []).cast<int>(),
    );
    if (meshGzBytes.isNotEmpty) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'mesh', // name=
          meshGzBytes,
          filename: 'mesh.json.gz',
        ),
      );
    }

    // 4. Part: sequence (sequence.json.gz file)
    final Uint8List sequenceGzBytes = Uint8List.fromList(
      ((nativePayload['sequence_gz'] as List?) ?? []).cast<int>(),
    );
    if (sequenceGzBytes.isNotEmpty) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'sequence', // name=
          sequenceGzBytes,
          filename: 'sequence.json.gz',
        ),
      );
    }

    // Send request
    final streamedResponse = await request.send().timeout(const Duration(seconds: 25));
    final response = await http.Response.fromStream(streamedResponse);

    final responseJson = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Face3DResult.fromJson(responseJson);
    } else {
      return Face3DResult(
        success: false,
        message: responseJson['message'] ?? responseJson['detail'] ?? 'Xác thực khuôn mặt thất bại',
        errorCode: responseJson['error_code'] ?? responseJson['code']?.toString(),
        data: responseJson,
      );
    }
  }
}
