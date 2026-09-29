import 'dart:convert';
import 'dart:io';
import 'package:app_tbk/core/errors/exceptions.dart';
import 'package:http/http.dart' as http;

import '../../../config/api_constants.dart';

class RegisterService {
  // static const String baseUrl = 'YOUR_API_URL'; // Thay bằng URL API của bạn

  /// Gửi OTP qua email
  static Future<bool> sendOTP(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/v1/auth/register/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return true;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Không thể gửi OTP');
      }
    } on SocketException catch (_) {
      throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    } catch (e) {
      if (e is NoInternetException) rethrow;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socketexception') || errStr.contains('clientexception')) {
        throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
      }
      throw Exception('Lỗi kết nối: $e');
    }
  }

  /// Xác thực OTP
  static Future<bool> verifyOTP({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/v1/auth/register/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'otp': otp,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return true;
      } else {
        return false;
      }
    } on SocketException catch (_) {
      throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    } catch (e) {
      if (e is NoInternetException) rethrow;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socketexception') || errStr.contains('clientexception')) {
        throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
      }
      throw Exception('Lỗi xác thực: $e');
    }
  }

  /// Tạo mật khẩu mới
  static Future<bool> createPassword(String mssv, String password) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/v1/auth/register/create-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'mssv': mssv,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Không thể tạo mật khẩu');
      }
    } on SocketException catch (_) {
      throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    } catch (e) {
      if (e is NoInternetException) rethrow;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socketexception') || errStr.contains('clientexception')) {
        throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
      }
      throw Exception('Lỗi tạo mật khẩu: $e');
    }
  }

}


