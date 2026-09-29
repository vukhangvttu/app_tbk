// lib/features/profile/services/device_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:app_tbk/core/errors/exceptions.dart';
import 'package:http/http.dart' as http;
import '../../../config/api_constants.dart';
import '../../auth/services/auth_service.dart';
import '../models/device_session.dart';

class DeviceService {
  // Gửi OTP để xác thực xem danh sách thiết bị
  static Future<Map<String, dynamic>> requestDeviceListOTP({
    required String password,
  }) async {
    if (!await AuthService.hasInternetConnection()) {
      throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    }

    final token = await AuthService.getToken();
    if (token == null) throw Exception('Token not found');

    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/devices/verify-password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'password': password}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Xác thực thất bại');
      }
    } on SocketException catch (_) {
      throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    }
  }

  // Xác thực OTP và lấy danh sách thiết bị
  static Future<List<DeviceSession>> verifyOTPAndGetDevices({
    required String otp,
  }) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception('Token not found');

    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/devices/verify-otp'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'otp': otp}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> devices = data['devices'];
      final currentDeviceId = data['current_device_id'];

      DeviceSession.setCurrentDeviceId(currentDeviceId);

      return devices.map((json) => DeviceSession.fromJson(json)).toList();
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Xác thực OTP thất bại');
    }
  }

  // Logout thiết bị từ xa
  static Future<void> logoutDevice(String deviceId) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception('Token not found');

    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/device/$deviceId/logout'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Không thể đăng xuất thiết bị');
    }
  }

  // Logout tất cả thiết bị khác
  static Future<void> logoutAllOtherDevices() async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception('Token not found');

    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/devices/logout-all-others'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Không thể đăng xuất các thiết bị');
    }
  }
}