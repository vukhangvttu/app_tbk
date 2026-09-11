import 'dart:convert';
import 'package:app_tbk/features/auth/services/auth_service.dart';
import 'package:app_tbk/features/notification-setting/models/notification.dart';
import 'package:flutter/material.dart';

class NotificationSettingService {
  /// Lấy cài đặt thông báo của sinh viên theo MSSV
  static Future<AppNotificationSettings?> fetchNotificationSetting(BuildContext context) async {
    try {
      final mssv = await AuthService.getSavedMssv();
      if (mssv == null || mssv.isEmpty) {
        debugPrint('ProfileService: Không tìm thấy MSSV');
        return null;
      }

      final response = await AuthService.authenticatedRequestLichSinhVien(
        method: 'GET',
        endpoint: '/users/get-settings/$mssv',
      );

      // Kiểm tra response có null không
      if (response == null) {
        debugPrint('ProfileService: Không nhận được phản hồi từ server');
        return null;
      }

      // Parse JSON an toàn
      final Map<String, dynamic> jsonMap = jsonDecode(response.body);

      // Kiểm tra success
      final bool success = jsonMap['success'] == true;
      if (!success) {
        final message = jsonMap['message'] ?? 'Lấy cài đặt thất bại';
        debugPrint('ProfileService: $message');
        return null;
      }

      // Lấy data
      final dynamic data = jsonMap['data'];
      if (data == null || data is! Map<String, dynamic>) {
        debugPrint('ProfileService: Dữ liệu data không hợp lệ hoặc rỗng');
        return null;
      }

      // Parse thành NotificationSettings
      return AppNotificationSettings.fromJson(data);

    } catch (e) {
      debugPrint('ProfileService.fetchProfile Error: $e');
      // Không throw nữa → trả về null để UI xử lý gracefully
      return null;
    }
  }
}