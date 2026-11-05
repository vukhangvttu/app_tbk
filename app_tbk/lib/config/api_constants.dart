import 'package:app_tbk/features/auth/services/auth_service.dart';

class ApiConstants {
  // static const String baseUrl = 'http://192.168.0.2:8202/student-calendar/api/v1';
  static const String baseUrl = 'http://113.164.79.241:8202/student-calendar/api/v1';
  static const String appVersion = '/app-version';

  static const String googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID',
      defaultValue: '73761905325-kotojsegt56dr15adr9jvlpbi91uc017.apps.googleusercontent.com');
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