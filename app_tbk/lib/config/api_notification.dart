import 'package:app_tbk/features/auth/services/auth_service.dart';

class ApiConstantsNotification {

  static const String baseUrl = 'http://192.168.0.8:8202/notification/api/v1';
}


class ApiGetToken {
  /// Hàm chung để lấy headers có token (Bearer)
  static Future<Map<String, String>> getAuthHeaders({bool json = true}) async {
    final token = await AuthService.getToken();

    if (token == null || token.isEmpty) {
      throw Exception('Không tìm thấy token. Vui lòng đăng nhập lại.');
    }

    return {
      if (json) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Hàm headers không cần token (cho login, register, ...)
  static Map<String, String> getBasicHeaders({bool json = true}) {
    return {
      if (json) 'Content-Type': 'application/json',
    };
  }
}