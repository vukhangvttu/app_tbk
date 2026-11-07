import 'dart:async';
import 'dart:convert';
import 'package:app_tbk/config/api_constants.dart';
import 'package:app_tbk/config/api_notification.dart';
import 'package:app_tbk/core/errors/exceptions.dart';
import 'package:app_tbk/features/auth/services/post_login_initializer.dart';
import 'package:app_tbk/services/next_class_widget_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:retry/retry.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

import 'auth_state_manager.dart';

/// Ném ra khi email Google đăng nhập chưa được liên kết với MSSV nào trong hệ thống
class GoogleAccountNotLinkedException implements Exception {
  final String email;
  GoogleAccountNotLinkedException(this.email);

  @override
  String toString() => 'Email $email chưa được liên kết với tài khoản sinh viên';
}

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const Duration _timeoutDuration = Duration(seconds: 20);

  // 🔹 Mutex / Single Flight Lock cho refresh token (tránh Token Reuse Error khi gọi song song)
  static bool _isRefreshingToken = false;
  static Completer<bool>? _refreshTokenCompleter;
  static DateTime? _lastRefreshTime;
  static final _authStateManager = AuthStateManager();

  // ========== STORAGE KEYS ==========
  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyDeviceId = 'device_id';
  static const String _keyMssv = 'saved_mssv';
  static const String _keyIdSinhVien = 'id_sinhvien';
  static const String _keyUserId = 'user_id';

  static Future<bool> _hasInternetConnection() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      if (connectivityResults.isEmpty ||
          connectivityResults.contains(ConnectivityResult.none)) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Public helper kiểm tra kết nối Internet
  static Future<bool> hasInternetConnection() => _hasInternetConnection();

  // ========== LOGIN ==========

  /// 🔑 Đăng nhập thông thường
  static Future<bool> login(String username, String password) async {
    if (!await _hasInternetConnection()) {
      throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    }

    final retryOptions = RetryOptions(
      maxAttempts: 3,
      delayFactor: Duration(seconds: 2),
    );
    http.Client? client;

    final deviceInfo = await DeviceHelper.getDeviceInfo();

    final bodyData = {
      'mssv': username,
      'password': password,
      'device_id': deviceInfo['device_id'],
      'device_name': deviceInfo['device_name'],
      'device_type': deviceInfo['device_type'],
      'os': deviceInfo['os'],
      'os_version': deviceInfo['os_version'],
      'app_version': deviceInfo['app_version'],
    };

    try {
      final response = await retryOptions.retry(
            () async {
          client = http.Client();
          return await client
              ?.post(
            Uri.parse('${ApiConstants.baseUrl}/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(bodyData),
          )
              .timeout(_timeoutDuration);
        },
        retryIf: (e) => e is SocketException || e is TimeoutException,
      );

      if (response?.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response!.body);

        if (data['success'] == true && data['data'] != null) {
          final result = data['data'];
          final String accessToken = result['access_token'];
          final String refreshToken = result['refresh_token'];
          final int expiresIn = result['expires_in'] ?? 900;

          // Decode access token để lấy thông tin user
          try {
            Map<String, dynamic> decodedToken = JwtDecoder.decode(accessToken);
            String userId = decodedToken['user_id'] ?? '';
            String mssv = decodedToken['mssv'] ?? username;
            String idSinhVien = decodedToken['id_sinh_vien'];

            // ✅ Lưu tokens và thông tin user
            await _storage.write(key: _keyAccessToken, value: accessToken);
            await _storage.write(key: _keyRefreshToken, value: refreshToken);
            await _storage.write(key: _keyDeviceId, value: deviceInfo['device_id']);
            await _storage.write(key: _keyMssv, value: mssv);
            await _storage.write(key: _keyIdSinhVien, value: idSinhVien);
            await _storage.write(key: _keyUserId, value: userId);

            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('login_timestamp', DateTime.now().millisecondsSinceEpoch);

            print('✅ Login thành công');
            print('📊 Access Token expires in: ${expiresIn}s');
            print('🔑 Sinh Vien ID: $idSinhVien');

            // ✅ QUAN TRỌNG: Notify UI rằng đã login thành công
            _authStateManager.notifyAuthenticationSuccess();

            return true;
          } catch (e) {
            print('❌ Lỗi giải mã JWT: $e');
            return false;
          }
        } else {
          print('❌ Login thất bại: ${data['error'] ?? 'Unknown error'}');
          return false;
        }
      } else {
        throw Exception('Lỗi server: ${response?.statusCode} - ${response?.body}');
      }
    } on TimeoutException catch (e) {
      throw Exception('Lỗi timeout khi kết nối đến server: $e');
    } on SocketException catch (_) {
      throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    } on http.ClientException catch (_) {
      throw NoInternetException('Không thể kết nối đến máy chủ. Vui lòng kiểm tra lại kết nối mạng.');
    } on HttpException catch (e) {
      throw Exception('Lỗi HTTP: $e');
    } catch (e) {
      if (e is NoInternetException) rethrow;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('badpadding') || 
          errStr.contains('bad_decrypt') || 
          errStr.contains('mac check failed') ||
          errStr.contains('invalidkeyexception')) {
        print('🧹 Lỗi keystore phát hiện khi login, tiến hành xóa storage...');
        try {
          await _storage.deleteAll();
        } catch (_) {}
        throw Exception('Thiết lập bảo mật đã thay đổi. Vui lòng bấm Đăng nhập lại.');
      }
      if (errStr.contains('socketexception') ||
          errStr.contains('clientexception') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('network is unreachable') ||
          errStr.contains('no route to host') ||
          errStr.contains('connection refused') ||
          errStr.contains('kết nối mạng')) {
        throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
      }
      throw Exception('Lỗi không xác định khi đăng nhập: $e');
    } finally {
      client?.close();
    }
  }

  /// 🔐 Đăng nhập với Biometric (Giống login thông thường)
  static Future<bool> loginWithBiometric(String username, String password) async {
    // Backend tự xử lý token expiry time
    return await login(username, password);
  }

  // ========== REFRESH TOKEN ==========

  static void _completerFinish(bool result) {
    if (_refreshTokenCompleter != null && !_refreshTokenCompleter!.isCompleted) {
      _refreshTokenCompleter!.complete(result);
    }
    _isRefreshingToken = false;
    _refreshTokenCompleter = null;
  }

  /// 🔄 Refresh Access Token khi hết hạn (Có cơ chế Lock tránh Race Condition / Token Reuse)
  static Future<bool> refreshAccessToken({String? failedToken}) async {
    // 1. Kiểm tra xem token đã được refresh bởi request khác gần đây chưa (tránh gọi trùng lặp)
    final currentAccessToken = await _storage.read(key: _keyAccessToken);
    if (failedToken != null && currentAccessToken != null && currentAccessToken != failedToken) {
      if (!JwtDecoder.isExpired(currentAccessToken)) {
        print('ℹ️ Access token đã được refresh bởi request trước đó, sử dụng token mới.');
        return true;
      }
    }

    // 2. Cooldown check: Nếu vừa refresh thành công trong vòng 3 giây
    if (_lastRefreshTime != null &&
        DateTime.now().difference(_lastRefreshTime!) < const Duration(seconds: 3)) {
      if (currentAccessToken != null && !JwtDecoder.isExpired(currentAccessToken)) {
        print('ℹ️ Token vừa được refresh cách đây dưới 3 giây, dùng token mới.');
        return true;
      }
    }

    // 3. Nếu đang có 1 request refresh token chạy dở, chờ kết quả từ request đó
    if (_isRefreshingToken && _refreshTokenCompleter != null) {
      print('⏳ Token đang được refresh bởi request khác, chờ kết quả...');
      return await _refreshTokenCompleter!.future;
    }

    _isRefreshingToken = true;
    _refreshTokenCompleter = Completer<bool>();

    try {
      if (!await _hasInternetConnection()) {
        print('❌ Không có kết nối internet');
        _completerFinish(false);
        return false;
      }

      final refreshToken = await _storage.read(key: _keyRefreshToken);
      if (refreshToken == null || refreshToken.isEmpty) {
        print('❌ Không có refresh token');
        await _handleAuthenticationFailure();
        _completerFinish(false);
        return false;
      }

      // Kiểm tra refresh token đã hết hạn chưa
      if (JwtDecoder.isExpired(refreshToken)) {
        print('❌ Refresh token đã hết hạn - Cần đăng nhập lại');
        await _handleAuthenticationFailure();
        _completerFinish(false);
        return false;
      }

      final client = http.Client();

      try {
        final deviceId = await _storage.read(key: _keyDeviceId);
        final headers = {
          'Content-Type': 'application/json',
        };

        final bodyData = {
          'refresh_token': refreshToken,
          if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
        };

        final response = await client
            .post(
          Uri.parse('${ApiConstants.baseUrl}/auth/refresh'),
          headers: headers,
          body: jsonEncode(bodyData),
        )
            .timeout(_timeoutDuration);

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(response.body);

          if (data['success'] == true && data['data'] != null) {
            final result = data['data'];
            final String newAccessToken = result['access_token'];
            final String newRefreshToken = result['refresh_token'];

            await _storage.write(key: _keyAccessToken, value: newAccessToken);
            await _storage.write(key: _keyRefreshToken, value: newRefreshToken);

            try {
              Map<String, dynamic> decodedToken = JwtDecoder.decode(newAccessToken);
              if (decodedToken['mssv'] != null) {
                await _storage.write(key: _keyMssv, value: decodedToken['mssv'].toString());
              }
              if (decodedToken['id_sinh_vien'] != null) {
                await _storage.write(key: _keyIdSinhVien, value: decodedToken['id_sinh_vien'].toString());
              }
              if (decodedToken['user_id'] != null) {
                await _storage.write(key: _keyUserId, value: decodedToken['user_id'].toString());
              }
            } catch (e) {
              print('⚠️ Không thể giải mã JWT khi refresh: $e');
            }

            _lastRefreshTime = DateTime.now();

            print('✅ Refresh token thành công (Đã lưu refresh_token mới)');

            // ✅ QUAN TRỌNG: Notify UI rằng đã authenticated thành công
            _authStateManager.notifyAuthenticationSuccess();

            _completerFinish(true);
            return true;
          }
        } else if (response.statusCode == 401) {
          print('❌ Refresh token không hợp lệ hoặc token reuse detected (401): ${response.body}');
          await _handleAuthenticationFailure();
          _completerFinish(false);
          return false;
        }

        print('❌ Refresh token thất bại (${response.statusCode}): ${response.body}');
        await _handleAuthenticationFailure();
        _completerFinish(false);
        return false;
      } finally {
        client.close();
      }
    } on TimeoutException catch (e) {
      print('❌ Lỗi refresh token timeout: $e');
      _completerFinish(false);
      return false;
    } catch (e) {
      print('❌ Lỗi refresh token: $e');
      _completerFinish(false);
      return false;
    }
  }

  /// 🔑 Đăng nhập bằng Google OAuth2 (idToken lấy từ Flutter google_sign_in)
  static Future<bool> loginWithGoogle(String idToken) async {
    if (!await _hasInternetConnection()) {
      throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    }

    final retryOptions = RetryOptions(
      maxAttempts: 3,
      delayFactor: Duration(seconds: 2),
    );
    http.Client? client;

    final deviceInfo = await DeviceHelper.getDeviceInfo();

    final bodyData = {
      'id_token': idToken,
      'device_id': deviceInfo['device_id'],
      'device_name': deviceInfo['device_name'],
      'device_type': deviceInfo['device_type'],
      'os': deviceInfo['os'],
      'os_version': deviceInfo['os_version'],
      'app_version': deviceInfo['app_version'],
    };

    try {
      final response = await retryOptions.retry(
            () async {
          client = http.Client();
          return await client
              ?.post(
            Uri.parse('${ApiConstants.baseUrl}/auth/google'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(bodyData),
          )
              .timeout(_timeoutDuration);
        },
        retryIf: (e) => e is SocketException || e is TimeoutException,
      );

      if (response?.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response!.body);

        if (data['success'] == true && data['data'] != null) {
          final result = data['data'];
          final String accessToken = result['access_token'];
          final String refreshToken = result['refresh_token'];

          try {
            Map<String, dynamic> decodedToken = JwtDecoder.decode(accessToken);
            String userId = decodedToken['user_id'] ?? '';
            String mssv = decodedToken['mssv'] ?? '';
            String idSinhVien = decodedToken['id_sinh_vien'] ?? '';

            await _storage.write(key: _keyAccessToken, value: accessToken);
            await _storage.write(key: _keyRefreshToken, value: refreshToken);
            await _storage.write(key: _keyDeviceId, value: deviceInfo['device_id']);
            await _storage.write(key: _keyMssv, value: mssv);
            await _storage.write(key: _keyIdSinhVien, value: idSinhVien);
            await _storage.write(key: _keyUserId, value: userId);

            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('login_timestamp', DateTime.now().millisecondsSinceEpoch);

            print('✅ Đăng nhập Google thành công');
            print('🔑 Sinh Vien ID: $idSinhVien');

            _authStateManager.notifyAuthenticationSuccess();

            return true;
          } catch (e) {
            print('❌ Lỗi giải mã JWT (Google): $e');
            return false;
          }
        } else {
          print('❌ Đăng nhập Google thất bại: ${data['error'] ?? data['message'] ?? 'Unknown error'}');
          return false;
        }
      } else if (response?.statusCode == 404) {
        // Email Google chưa được liên kết với MSSV nào (nếu backend trả về JSON 404)
        try {
          final Map<String, dynamic> data = jsonDecode(response!.body);
          throw GoogleAccountNotLinkedException(data['email'] ?? '');
        } catch (e) {
          if (e is GoogleAccountNotLinkedException) rethrow;
          throw Exception('API không tồn tại (HTTP 404 Not Found) tại: ${ApiConstants.baseUrl}/auth/google-login. Vui lòng kiểm tra lại endpoint backend.');
        }
      } else {
        throw Exception('Lỗi server (${response?.statusCode}): ${response?.body}');
      }
    } on TimeoutException catch (e) {
      throw Exception('Lỗi timeout khi kết nối đến server: $e');
    } on SocketException catch (_) {
      throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    } on http.ClientException catch (_) {
      throw NoInternetException('Không thể kết nối đến máy chủ. Vui lòng kiểm tra lại kết nối mạng.');
    } on HttpException catch (e) {
      throw Exception('Lỗi HTTP: $e');
    } catch (e) {
      if (e is GoogleAccountNotLinkedException || e is NoInternetException) rethrow;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socketexception') ||
          errStr.contains('clientexception') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('network is unreachable') ||
          errStr.contains('no route to host') ||
          errStr.contains('connection refused') ||
          errStr.contains('kết nối mạng')) {
        throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
      }
      throw Exception('Lỗi không xác định khi đăng nhập Google: $e');
    } finally {
      client?.close();
    }
  }

  // ========== GET TOKENS ==========

  /// 🔑 Lấy Access Token (Tự động refresh nếu hết hạn)
  static Future<String?> getAccessToken() async {
    try {
      final accessToken = await _storage.read(key: _keyAccessToken);
      if (accessToken == null || accessToken.isEmpty) {
        print('❌ Không có access token');
        await _handleAuthenticationFailure();
        return null;
      }

      // Kiểm tra token đã hết hạn chưa
      if (JwtDecoder.isExpired(accessToken)) {
        print('⚠️ Access token đã hết hạn - Đang refresh...');
        final refreshed = await refreshAccessToken(failedToken: accessToken);
        if (refreshed) {
          return await _storage.read(key: _keyAccessToken);
        }
        return null;
      }

      // Kiểm tra sắp hết hạn (< 15 giây) thì refresh trước
      try {
        final remainingTime = JwtDecoder.getRemainingTime(accessToken);
        if (remainingTime.inSeconds < 15) {
          print('⚠️ Access token sắp hết hạn (${remainingTime.inSeconds}s) - Đang refresh...');
          final refreshed = await refreshAccessToken(failedToken: accessToken);
          if (refreshed) {
            return await _storage.read(key: _keyAccessToken);
          }
          // Nếu refresh thất bại nhưng token chưa hết hạn hẳn, ta có thể thử dùng tiếp
          // thay vì return null ngay lập tức. (Tuy nhiên refreshAccessToken đã gọi logout nếu 401)
        }
      } catch (e) {
        print('⚠️ Không thể lấy remaining time: $e');
      }

      return accessToken;
    } catch (e) {
      print('❌ Lỗi lấy access token: $e');
      await _handleAuthenticationFailure();
      return null;
    }
  }


  /// 🚨 Xử lý khi authentication thất bại
  static Future<void> _handleAuthenticationFailure() async {
    if (_authStateManager.currentState == AuthState.unauthenticated) {
      print('ℹ️ Đã ở trạng thái unauthenticated - Bỏ qua logout trùng lặp');
      return;
    }
    print('🚨 Authentication failed - Triggering logout...');
    await logout(notifyBackend: false);
    _authStateManager.notifyAuthenticationFailed();
  }

  // ========== LOGOUT ========== (CẬP NHẬT)

  static Future<void> logout({bool notifyBackend = true}) async {
    try {
      if (notifyBackend) {
        String? deviceId;
        try {
          deviceId = await _storage.read(key: _keyDeviceId);
        } catch (e) {
          print('⚠️ Không thể đọc device_id khi logout: $e');
        }
        
        try {
          await authenticatedRequestLichSinhVien(
            method: 'POST',
            endpoint: '/auth/logout',
            body: deviceId != null ? {'device_id': deviceId} : {},
            retry: false,
          );
          print('✅ Đã gọi API logout thành công');
        } catch (e) {
          print('⚠️ Không thể gọi API logout: $e');
        }
      }

      // Xóa tất cả dữ liệu local
      _lastRefreshTime = null;
      try {
        await _storage.deleteAll();
      } catch (e) {
        print('⚠️ Lỗi khi xóa secure storage: $e');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('login_timestamp');
      await prefs.remove('biometric_login_timestamp');
      await prefs.remove('biometric_authenticated');
      await prefs.remove('biometric_enabled');

      PostLoginInitializer.reset();
      await NextClassWidgetService.xoa();

      print('✅ Đăng xuất thành công');
    } catch (e) {
      print('Lỗi khi đăng xuất: $e');
    }
  }


  static Future<String?> getRefreshToken() async {
    try {
      return await _storage.read(key: _keyRefreshToken);
    } catch (e) {
      print('Lỗi khi lấy refresh token: $e');
      return null;
    }
  }

  /// 🔄 Lấy token cũ (để tương thích với code cũ)
  static Future<String?> getToken() async {
    return await getAccessToken();
  }

  // ========== AUTHENTICATED REQUEST ==========

  /// 🌐 HTTP Request với tự động refresh token
  static Future<http.Response?> authenticatedRequestNotification({
    required String method,
    required String endpoint,
    Map<String, String>? headers,
    dynamic body,
    bool retry = true,
  }) async {
    if (!await _hasInternetConnection()) {
      throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    }

    try {
      final accessToken = await getAccessToken();
      if (accessToken == null) {
        throw Exception('Không có access token - Cần đăng nhập lại');
      }

      final client = http.Client();
      final url = Uri.parse('${ApiConstantsNotification.baseUrl}$endpoint');

      final requestHeaders = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
        if (method.toUpperCase() == 'GET') ...{
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
        ...?headers,
      };

      http.Response? response;

      switch (method.toUpperCase()) {
        case 'GET':
          response = await client.get(url, headers: requestHeaders).timeout(_timeoutDuration);
          break;
        case 'POST':
          response = await client.post(
            url,
            headers: requestHeaders,
            body: body != null ? jsonEncode(body) : null,
          ).timeout(_timeoutDuration);
          break;
        case 'PUT':
          response = await client.put(
            url,
            headers: requestHeaders,
            body: body != null ? jsonEncode(body) : null,
          ).timeout(_timeoutDuration);
          break;
        case 'DELETE':
          response = await client.delete(url, headers: requestHeaders).timeout(_timeoutDuration);
          break;
        case 'PATCH':  // ← Thêm case này
          response = await client.patch(
            url,
            headers: requestHeaders,
            body: body != null ? jsonEncode(body) : null,
          ).timeout(_timeoutDuration);
          break;
        default:
          throw Exception('HTTP method không hỗ trợ: $method');
      }

      client.close();

      // Nếu 401 và còn retry -> refresh token và thử lại
      if (response.statusCode == 401 && retry) {
        print('⚠️ 401 Unauthorized tại $endpoint - Đang refresh token và thử lại...');
        final refreshed = await refreshAccessToken(failedToken: accessToken);
        if (refreshed) {
          return await authenticatedRequestNotification(
            method: method,
            endpoint: endpoint,
            headers: headers,
            body: body,
            retry: false, // Không retry lần 2
          );
        }
        throw Exception('Session hết hạn - Vui lòng đăng nhập lại');
      }

      return response;
    } on TimeoutException catch (_) {
      print('⏰ Timeout sau 20 giây: $endpoint');
      throw Exception('Kết nối máy chủ quá thời gian phản hồi (timeout), vui lòng thử lại.');
    } on SocketException catch (e) {
      print('❌ Lỗi kết nối mạng: $e');
      throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    } on http.ClientException catch (e) {
      print('❌ Lỗi client HTTP: $e');
      throw NoInternetException('Không thể kết nối đến máy chủ. Vui lòng kiểm tra lại kết nối mạng.');
    } catch (e) {
      if (e is NoInternetException) rethrow;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('badpadding') || 
          errStr.contains('bad_decrypt') || 
          errStr.contains('mac check failed') ||
          errStr.contains('invalidkeyexception')) {
        print('🧹 Lỗi keystore phát hiện khi login, tiến hành xóa storage...');
        try {
          await _storage.deleteAll();
        } catch (_) {}
        throw Exception('Thiết lập bảo mật đã thay đổi. Vui lòng bấm Đăng nhập lại.');
      }
      if (errStr.contains('socketexception') ||
          errStr.contains('clientexception') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('network is unreachable') ||
          errStr.contains('no route to host') ||
          errStr.contains('connection refused') ||
          errStr.contains('kết nối mạng')) {
        throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
      }
      print('❌ Lỗi authenticated request: $e');
      rethrow;
    }
  }


  /// 🌐 HTTP Request với tự động refresh token
  static Future<http.Response?> authenticatedRequestLichSinhVien({
    required String method,
    required String endpoint,
    Map<String, String>? headers,
    dynamic body,
    bool retry = true,
    bool isMultipart = false,
    Map<String, File>? files,
    Map<String, String>? fields,
  }) async {
    // 🔹 Thiết lập timeout 20 giây cho tất cả request
    const timeoutDuration = Duration(seconds: 20);

    if (!await _hasInternetConnection()) {
      throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    }

    try {
      final accessToken = await getAccessToken();
      if (accessToken == null) {
        throw Exception('Không có access token - Cần đăng nhập lại');
      }

      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final requestHeaders = {
        'Authorization': 'Bearer $accessToken',
        if (method.toUpperCase() == 'GET') ...{
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
        ...?headers,
      };

      http.Response? response;

      if (isMultipart) {
        // 🔹 Request upload file (Multipart)
        final request = http.MultipartRequest(method.toUpperCase(), url);
        request.headers.addAll(requestHeaders);

        if (fields != null) {
          request.fields.addAll(fields);
        }

        if (files != null && files.isNotEmpty) {
          for (final entry in files.entries) {
            final file = entry.value;
            request.files.add(
              await http.MultipartFile.fromPath(entry.key, file.path),
            );
          }
        }

        // Áp dụng timeout 20 giây cho MultipartRequest
        final streamedResponse = await request.send().timeout(timeoutDuration);
        response = await http.Response.fromStream(streamedResponse);
      } else {
        // 🔹 Request JSON thông thường
        final client = http.Client();
        final jsonHeaders = {
          'Content-Type': 'application/json',
          ...requestHeaders,
        };

        try {
          switch (method.toUpperCase()) {
            case 'GET':
              response = await client
                  .get(url, headers: jsonHeaders)
                  .timeout(timeoutDuration);
              break;
            case 'POST':
              response = await client
                  .post(url, headers: jsonHeaders, body: body != null ? jsonEncode(body) : null)
                  .timeout(timeoutDuration);
              break;
            case 'PUT':
              response = await client
                  .put(url, headers: jsonHeaders, body: body != null ? jsonEncode(body) : null)
                  .timeout(timeoutDuration);
              break;
            case 'DELETE':
              response = await client
                  .delete(url, headers: jsonHeaders)
                  .timeout(timeoutDuration);
              break;
            default:
              throw Exception('HTTP method không hỗ trợ: $method');
          }
        } finally {
          client.close();
        }
      }

      // 🔁 Xử lý token hết hạn (401)
      if (response.statusCode == 401 && retry) {
        print('⚠️ 401 Unauthorized tại $endpoint - Đang refresh token và thử lại...');
        final refreshed = await refreshAccessToken(failedToken: accessToken);
        if (refreshed) {
          return await authenticatedRequestLichSinhVien(
            method: method,
            endpoint: endpoint,
            headers: headers,
            body: body,
            retry: false,
            isMultipart: isMultipart,
            files: files,
            fields: fields,
          );
        }
        throw Exception('Session hết hạn - Vui lòng đăng nhập lại');
      }

      return response;
    } on TimeoutException catch (_) {
      print('⏰ Timeout sau 20 giây: $endpoint');
      throw Exception('Kết nối máy chủ quá thời gian phản hồi (timeout), vui lòng thử lại.');
    } on SocketException catch (e) {
      print('❌ Lỗi kết nối mạng: $e');
      throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    } on http.ClientException catch (e) {
      print('❌ Lỗi client HTTP: $e');
      throw NoInternetException('Không thể kết nối đến máy chủ. Vui lòng kiểm tra lại kết nối mạng.');
    } catch (e) {
      if (e is NoInternetException) rethrow;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('badpadding') || 
          errStr.contains('bad_decrypt') || 
          errStr.contains('mac check failed') ||
          errStr.contains('invalidkeyexception')) {
        print('🧹 Lỗi keystore phát hiện khi login, tiến hành xóa storage...');
        try {
          await _storage.deleteAll();
        } catch (_) {}
        throw Exception('Thiết lập bảo mật đã thay đổi. Vui lòng bấm Đăng nhập lại.');
      }
      if (errStr.contains('socketexception') ||
          errStr.contains('clientexception') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('network is unreachable') ||
          errStr.contains('no route to host') ||
          errStr.contains('connection refused') ||
          errStr.contains('kết nối mạng')) {
        throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
      }
      print('❌ Lỗi authenticated request: $e');
      rethrow;
    }
  }


  static Future<http.Response> authenticatedMultipartRequest({
    required String method,
    required String endpoint,
    required Map<String, String> fields,
    required Map<String, List<File>> files,
  }) async {
    const timeoutDuration = Duration(seconds: 20);

    final accessToken = await getAccessToken();
    if (accessToken == null) {
      throw Exception('Không có access token - Cần đăng nhập lại');
    }

    final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');

    final request = http.MultipartRequest(method.toUpperCase(), url);
    request.headers['Authorization'] = 'Bearer $accessToken';

    // 🔹 Add text fields
    request.fields.addAll(fields);

    // 🔹 Add multi files
    for (final entry in files.entries) {
      final fieldName = entry.key;
      for (final file in entry.value) {
        request.files.add(
          await http.MultipartFile.fromPath(
            fieldName, // backend nhận nhiều file cùng key
            file.path,
          ),
        );
      }
    }

    final streamedResponse =
    await request.send().timeout(timeoutDuration);

    final response = await http.Response.fromStream(streamedResponse);

    // 🔁 Token hết hạn → refresh 1 lần
    if (response.statusCode == 401) {
      final refreshed = await refreshAccessToken(failedToken: accessToken);
      if (!refreshed) {
        throw Exception('Session hết hạn - Vui lòng đăng nhập lại');
      }
      return authenticatedMultipartRequest(
        method: method,
        endpoint: endpoint,
        fields: fields,
        files: files,
      );
    }

    return response;
  }


  // ========== TOKEN VALIDATION ==========

  /// ✅ Kiểm tra token có còn hợp lệ không
  static Future<bool> isTokenValid() async {
    try {
      final accessToken = await _storage.read(key: _keyAccessToken);
      if (accessToken == null || accessToken.isEmpty) return false;

      // Nếu access token đã hết hạn, tự động refresh ngầm
      if (JwtDecoder.isExpired(accessToken)) {
        return await refreshAccessToken(failedToken: accessToken);
      }

      return true;
    } catch (e) {
      print('❌ Lỗi kiểm tra token: $e');
      final errStr = e.toString();
      if (errStr.contains('BadPadding') || 
          errStr.contains('BAD_DECRYPT') || 
          errStr.contains('MAC check failed') ||
          errStr.contains('InvalidKeyException')) {
        print('🧹 Phát hiện lỗi keystore, đang xóa toàn bộ storage...');
        try {
          await _storage.deleteAll();
        } catch (e2) {
          print('❌ Lỗi khi xóa storage: $e2');
        }
      }
      return false;
    }
  }

  /// ✅ Kiểm tra có thể tự động đăng nhập bằng biometric không
  static Future<bool> canAutoLoginWithBiometric() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;

      if (!biometricEnabled) return false;

      return await isTokenValid();
    } catch (e) {
      print('❌ Lỗi kiểm tra auto login: $e');
      return false;
    }
  }

  // ========== GETTERS ==========

  static Future<String?> getSavedMssv() async {
    try {
      return await _storage.read(key: _keyMssv);
    } catch (e) {
      print('Lỗi khi lấy MSSV: $e');
      return null;
    }
  }

  static Future<String?> getIdSinhVien() async {
    try {
      return await _storage.read(key: _keyIdSinhVien);
    } catch (e) {
      print('Lỗi khi lấy id_sinhvien: $e');
      return null;
    }
  }

  static Future<String?> getDeviceId() async {
    try {
      return await _storage.read(key: _keyDeviceId);
    } catch (e) {
      print('Lỗi khi lấy device_id: $e');
      return null;
    }
  }

  static Future<String?> getUserId() async {
    try {
      return await _storage.read(key: _keyUserId);
    } catch (e) {
      print('Lỗi khi lấy MSSV: $e');
      return null;
    }
  }

  // ========== BIOMETRIC ==========

  static Future<void> enableBiometric(bool enable) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometric_enabled', enable);

      if (!enable) {
        print('🔒 Đã tắt biometric');
      } else {
        print('🔓 Đã bật biometric');
      }
    } catch (e) {
      print('Lỗi khi bật/tắt sinh trắc học: $e');
    }
  }

  static Future<bool> isBiometricEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('biometric_enabled') ?? false;
    } catch (e) {
      print('Lỗi khi kiểm tra sinh trắc học: $e');
      return false;
    }
  }

  // ========== LOGOUT ==========

  static Future<void> logout_cu() async {
    try {
      // Gọi API logout (nếu cần)
      final deviceId = await _storage.read(key: _keyDeviceId);
      if (deviceId != null) {
        try {
          await authenticatedRequestLichSinhVien(
            method: 'POST',
            endpoint: '/auth/logout',
            body: {'device_id': deviceId},
            retry: false,
          );
          print('✅ Đã gọi API logout thành công');
        } catch (e) {
          print('⚠️ Không thể gọi API logout: $e');
        }
      }

      // Xóa tất cả dữ liệu local
      await _storage.delete(key: _keyAccessToken);
      await _storage.delete(key: _keyRefreshToken);
      await _storage.delete(key: _keyDeviceId);
      await _storage.delete(key: _keyMssv);
      await _storage.delete(key: _keyIdSinhVien);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('login_timestamp');
      await prefs.remove('biometric_login_timestamp');
      await prefs.remove('biometric_authenticated');
      await prefs.remove('biometric_enabled');

      // ✅ Reset services
      PostLoginInitializer.reset();

      print('✅ Đăng xuất thành công');
    } catch (e) {
      print('Lỗi khi đăng xuất: $e');
    }
  }
}

// ========== DEVICE HELPER ==========
class DeviceHelper {
  static String? _cachedDeviceId;

  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    final packageInfo = await PackageInfo.fromPlatform();

    String os = '';
    String osVersion = '';
    String model = '';
    String deviceName = '';
    bool isPhysicalDevice = true;

    // Tạo hoặc lấy Device ID
    final deviceId = await _getOrCreateDeviceId();

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      os = 'Android';
      osVersion = androidInfo.version.release ?? 'Unknown';
      model = androidInfo.model ?? 'Unknown';
      deviceName = '${androidInfo.manufacturer} ${androidInfo.model}';
      isPhysicalDevice = androidInfo.isPhysicalDevice;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      os = 'iOS';
      osVersion = iosInfo.systemVersion ?? 'Unknown';
      model = iosInfo.utsname.machine ?? 'Unknown';
      deviceName = iosInfo.name ?? 'iPhone';
      isPhysicalDevice = iosInfo.isPhysicalDevice;
    }

    final locale = Platform.localeName;
    final connectivityResults = await Connectivity().checkConnectivity();
    String connectivity = 'unknown';
    if (connectivityResults.isNotEmpty) {
      if (connectivityResults.contains(ConnectivityResult.wifi)) {
        connectivity = 'wifi';
      } else if (connectivityResults.contains(ConnectivityResult.mobile)) {
        connectivity = 'mobile';
      } else if (connectivityResults.contains(ConnectivityResult.none)) {
        connectivity = 'offline';
      }
    }

    return {
      'device_id': deviceId,
      'device_name': deviceName,
      'device_type': isPhysicalDevice ? 'mobile' : 'emulator',
      'os': os,
      'os_version': osVersion,
      'app_version': packageInfo.version,
      'model': model,
      'is_physical_device': isPhysicalDevice,
      'locale': locale,
      'connectivity': connectivity,
    };
  }

  /// Tạo hoặc lấy Device ID duy nhất
  static Future<String> _getOrCreateDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    const storage = FlutterSecureStorage();
    const key = 'device_unique_id';

    // Lấy từ storage
    String? deviceId = await storage.read(key: key);

    if (deviceId == null || deviceId.isEmpty) {
      // Tạo mới từ device info
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id; // Android ID
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'ios-${DateTime.now().millisecondsSinceEpoch}';
      } else {
        deviceId = 'unknown-${DateTime.now().millisecondsSinceEpoch}';
      }

      // Lưu vào storage
      await storage.write(key: key, value: deviceId);
      print('🆔 Created new device ID: $deviceId');
    }

    _cachedDeviceId = deviceId;
    return deviceId;
  }

  static Future<void> printDeviceInfo() async {
    final info = await getDeviceInfo();
    print('📱 Device Info: ${jsonEncode(info)}');
  }
}

// ========== FCM TOKEN ==========
Future<String?> getFcmToken() async {
  try {
    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken != null) {
      print('🔔 FCM Token: $fcmToken');
      return fcmToken;
    } else {
      print('❌ Failed to get FCM token');
      return null;
    }
  } catch (e) {
    print('❌ Error getting FCM token: $e');
    return null;
  }
}