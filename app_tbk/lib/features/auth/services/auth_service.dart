import 'dart:async';
import 'dart:convert';
import 'package:app_tbk/config/api_constants.dart';
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

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const Duration _timeoutDuration = Duration(seconds: 20);

  static Future<bool> _hasInternetConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  /// Đăng nhập thông thường - token ngắn hạn (1 ngày)
  static Future<bool> login(String username, String password) async {
    if (!await _hasInternetConnection()) {
      throw Exception('Không có kết nối internet');
    }

    final retryOptions = RetryOptions(maxAttempts: 3, delayFactor: Duration(seconds: 2));
    http.Client? client;

    final deviceInfo = await DeviceHelper.getDeviceInfo();

    final bodyData = {
      'username': username,
      'password': password,
      'rememberMe': false, // ❌ Bỏ remember me - luôn là false
      ...deviceInfo,
    };

    try {
      final response = await retryOptions.retry(
            () async {
          client = http.Client();
          return await client
              ?.post(
            Uri.parse('${ApiConstants.baseUrl}/auth/log-in'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(bodyData),
          )
              .timeout(_timeoutDuration);
        },
        retryIf: (e) => e is SocketException || e is TimeoutException,
      );

      if (response?.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response!.body);
        if (data['code'] == 1000 && data['result']['authenticated'] == true) {
          final String token = data['result']['token'];

          try {
            Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
            String idSinhVien = decodedToken['idsinhvien'] ?? '';

            // ✅ Lưu token ngắn hạn
            await _storage.write(key: 'auth_token', value: token);
            await _storage.write(key: 'id_sinhvien', value: idSinhVien);
            await _storage.write(key: 'saved_mssv', value: username);

            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('login_timestamp', DateTime.now().millisecondsSinceEpoch);

            return true;
          } catch (e) {
            print('❌ Lỗi giải mã JWT: $e');
            return false;
          }
        }
        return false;
      } else {
        throw Exception('Lỗi server: ${response?.statusCode} - ${response?.body}');
      }
    } on TimeoutException catch (e) {
      throw Exception('Lỗi timeout khi kết nối đến server: $e');
    } on SocketException catch (e) {
      throw Exception('Lỗi kết nối: $e');
    } on HttpException catch (e) {
      throw Exception('Lỗi HTTP: $e');
    } catch (e) {
      throw Exception('Lỗi không xác định khi đăng nhập: $e');
    } finally {
      client?.close();
    }
  }

  /// 🔐 Đăng nhập với Biometric - token dài hạn (30-90 ngày)
  static Future<bool> loginWithBiometric(String username, String password) async {
    if (!await _hasInternetConnection()) {
      throw Exception('Không có kết nối internet');
    }

    final retryOptions = RetryOptions(maxAttempts: 3, delayFactor: Duration(seconds: 2));
    http.Client? client;

    final deviceInfo = await DeviceHelper.getDeviceInfo();

    final bodyData = {
      'username': username,
      'password': password,
      'rememberMe': true, // ✅ Biometric = token dài hạn
      ...deviceInfo,
    };

    try {
      final response = await retryOptions.retry(
            () async {
          client = http.Client();
          return await client
              ?.post(
            Uri.parse('${ApiConstants.baseUrl}/auth/log-in'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(bodyData),
          )
              .timeout(_timeoutDuration);
        },
        retryIf: (e) => e is SocketException || e is TimeoutException,
      );

      if (response?.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response!.body);
        if (data['code'] == 1000 && data['result']['authenticated'] == true) {
          final String token = data['result']['token'];

          try {
            Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
            String idSinhVien = decodedToken['idsinhvien'] ?? '';

            // ✅ Lưu token dài hạn cho biometric
            await _storage.write(key: 'auth_token_biometric', value: token);
            await _storage.write(key: 'auth_token', value: token);
            await _storage.write(key: 'id_sinhvien', value: idSinhVien);
            await _storage.write(key: 'saved_mssv', value: username);

            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('biometric_login_timestamp', DateTime.now().millisecondsSinceEpoch);

            return true;
          } catch (e) {
            print('❌ Lỗi giải mã JWT: $e');
            return false;
          }
        }
        return false;
      } else {
        throw Exception('Lỗi server: ${response?.statusCode} - ${response?.body}');
      }
    } catch (e) {
      throw Exception('Lỗi đăng nhập biometric: $e');
    } finally {
      client?.close();
    }
  }

  /// ✅ Kiểm tra token có còn hợp lệ không
  static Future<bool> isTokenValid() async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) return false;

      // Kiểm tra token đã hết hạn chưa
      bool isExpired = JwtDecoder.isExpired(token);
      return !isExpired;
    } catch (e) {
      print('❌ Lỗi kiểm tra token: $e');
      return false;
    }
  }

  /// ✅ Kiểm tra có thể tự động đăng nhập bằng biometric không
  static Future<bool> canAutoLoginWithBiometric() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;

      if (!biometricEnabled) return false;

      final token = await _storage.read(key: 'auth_token_biometric');
      if (token == null || token.isEmpty) return false;

      // Kiểm tra token biometric còn hạn không
      bool isExpired = JwtDecoder.isExpired(token);
      return !isExpired;
    } catch (e) {
      print('❌ Lỗi kiểm tra auto login: $e');
      return false;
    }
  }

  static Future<String?> getSavedMssv() async {
    try {
      return await _storage.read(key: 'saved_mssv');
    } catch (e) {
      print('Lỗi khi lấy MSSV: $e');
      return null;
    }
  }

  static Future<String?> getIdSinhVien() async {
    try {
      return await _storage.read(key: 'id_sinhvien');
    } catch (e) {
      print('Lỗi khi lấy id_sinhvien: $e');
      return null;
    }
  }

  static Future<String?> getToken() async {
    try {
      return await _storage.read(key: 'auth_token');
    } catch (e) {
      print('Lỗi khi lấy token: $e');
      return null;
    }
  }

  static Future<void> enableBiometric(bool enable) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometric_enabled', enable);

      if (!enable) {
        // ❌ Tắt biometric = xóa token dài hạn
        await _storage.delete(key: 'auth_token_biometric');
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

  static Future<void> logout() async {
    try {
      await _storage.delete(key: 'auth_token');
      await _storage.delete(key: 'auth_token_biometric');
      await _storage.delete(key: 'saved_mssv');
      await _storage.delete(key: 'id_sinhvien');

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('login_timestamp');
      await prefs.remove('biometric_login_timestamp');
      await prefs.remove('biometric_authenticated');
    } catch (e) {
      print('Lỗi khi đăng xuất: $e');
    }
  }
}

class DeviceHelper {
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    final packageInfo = await PackageInfo.fromPlatform();

    String os = '';
    String osVersion = '';
    String model = '';
    bool isPhysicalDevice = true;

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      os = 'Android';
      osVersion = androidInfo.version.release ?? 'Unknown';
      model = androidInfo.model ?? 'Unknown';
      isPhysicalDevice = androidInfo.isPhysicalDevice;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      os = 'iOS';
      osVersion = iosInfo.systemVersion ?? 'Unknown';
      model = iosInfo.utsname.machine ?? 'Unknown';
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
      'appVersion': packageInfo.version,
      'os': os,
      'osVersion': osVersion,
      'model': model,
      'isPhysicalDevice': isPhysicalDevice,
      'locale': locale,
      'connectivity': connectivity,
    };
  }

  static Future<void> printDeviceInfo() async {
    final info = await getDeviceInfo();
    print('📱 Device Info: ${jsonEncode(info)}');
  }
}

Future<String?> getFcmToken() async {
  try {
    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken != null) {
      print('FCM Token: $fcmToken');
      return fcmToken;
    } else {
      print('Failed to get FCM token');
      return null;
    }
  } catch (e) {
    print('Error getting FCM token: $e');
    return null;
  }
}