// lib/features/profile/services/device_service.dart
import 'dart:convert';
import 'package:app_tbk/core/errors/exceptions.dart';
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

    final response = await AuthService.authenticatedRequestLichSinhVien(
      method: 'POST',
      endpoint: '/devices/verify-password',
      body: {'password': password},
    );

    if (response == null) {
      throw Exception('Phiên đăng nhập đã hết hạn hoặc không thể kết nối server.');
    }

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Xác thực thất bại');
    }
  }

  // Xác thực OTP và lấy danh sách thiết bị
  static Future<List<DeviceSession>> verifyOTPAndGetDevices({
    required String otp,
  }) async {
    final response = await AuthService.authenticatedRequestLichSinhVien(
      method: 'POST',
      endpoint: '/devices/verify-otp',
      body: {'otp': otp},
    );

    if (response == null) {
      throw Exception('Phiên đăng nhập đã hết hạn hoặc không thể kết nối server.');
    }

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
    final response = await AuthService.authenticatedRequestLichSinhVien(
      method: 'POST',
      endpoint: '/device/$deviceId/logout',
    );

    if (response == null) {
      throw Exception('Phiên đăng nhập đã hết hạn hoặc không thể kết nối server.');
    }

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Không thể đăng xuất thiết bị');
    }
  }

  // Logout tất cả thiết bị khác
  static Future<void> logoutAllOtherDevices() async {
    final response = await AuthService.authenticatedRequestLichSinhVien(
      method: 'POST',
      endpoint: '/devices/logout-all-others',
    );

    if (response == null) {
      throw Exception('Phiên đăng nhập đã hết hạn hoặc không thể kết nối server.');
    }

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Không thể đăng xuất các thiết bị');
    }
  }
}
