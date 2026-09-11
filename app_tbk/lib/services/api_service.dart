import 'dart:convert';
import 'package:app_tbk/config/api_constants.dart';
import 'package:app_tbk/features/auth/services/auth_service.dart';
import 'package:http/http.dart' as http;

class HttpClientWrapper {
  // static const baseUrl = 'http://113.164.79.241:8202/api/thoi-khoa-bieu';
  static const Duration timeout = Duration(seconds: 15);

  // GET request với token
  static Future<http.Response> get(
      String endpoint, {
        Map<String, String>? queryParams,
      }) async {
    final token = await AuthService.getToken();
    if (token == null) {
      throw UnauthorizedException('Token không tồn tại');
    }

    final uri = Uri.parse(ApiConstants.baseUrl).replace(
      queryParameters: queryParams,
    );

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    try {
      final response = await http.get(uri, headers: headers).timeout(timeout);
      return _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // POST request với token
  static Future<http.Response> post(
      String endpoint, {
        Map<String, dynamic>? body,
      }) async {
    final token = await AuthService.getToken();
    if (token == null) {
      throw UnauthorizedException('Token không tồn tại');
    }

    final uri = Uri.parse(ApiConstants.baseUrl);

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    try {
      final response = await http
          .post(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      )
          .timeout(timeout);
      return _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // PUT request với token
  static Future<http.Response> put(
      String endpoint, {
        Map<String, dynamic>? body,
      }) async {
    final token = await AuthService.getToken();
    if (token == null) {
      throw UnauthorizedException('Token không tồn tại');
    }

    final uri = Uri.parse(ApiConstants.baseUrl);

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    try {
      final response = await http
          .put(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      )
          .timeout(timeout);
      return _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // DELETE request với token
  static Future<http.Response> delete(String endpoint) async {
    final token = await AuthService.getToken();
    if (token == null) {
      throw UnauthorizedException('Token không tồn tại');
    }

    final uri = Uri.parse(ApiConstants.baseUrl);

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    try {
      final response = await http.delete(uri, headers: headers).timeout(timeout);
      return _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // Xử lý response
  static http.Response _handleResponse(http.Response response) {
    if (response.statusCode == 401) {
      AuthService.logout();
      throw UnauthorizedException('Phiên đăng nhập hết hạn');
    }

    if (response.statusCode >= 400) {
      throw ApiException(
        'Lỗi ${response.statusCode}',
        response.statusCode,
        response.body,
      );
    }

    return response;
  }

  // Xử lý lỗi
  static Exception _handleError(dynamic error) {
    if (error is UnauthorizedException) {
      return error;
    }
    if (error is ApiException) {
      return error;
    }
    return Exception('Lỗi kết nối: $error');
  }
}

// Custom Exceptions
class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);

  @override
  String toString() => message;
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String body;

  ApiException(this.message, this.statusCode, this.body);

  @override
  String toString() => '$message - $body';
}

class ApiService {

  // Lấy headers với token
   static Future<Map<String, String>> _getHeaders() async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Không tìm thấy token. Vui lòng đăng nhập lại.');
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token', // Hoặc 'Token $token' tùy vào API
    };
  }

  // Xử lý lỗi 401 - Token hết hạn
  static void _handleUnauthorized() {
    // Xóa token cũ và yêu cầu đăng nhập lại
    AuthService.logout();
    throw Exception('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.');
  }

   /// Lấy thời khóa biểu - Tự động refresh token khi hết hạn
   static Future<List<dynamic>> getThoiKhoaBieu({
     required String idSinhVien,
     required int hocKy,
     required String namHoc,
   }) async {
     try {
       final response = await AuthService.authenticatedRequestLichSinhVien(
         method: 'POST',
         endpoint: '/thoi-khoa-bieu',
         body: {
           'id_sinh_vien': idSinhVien,
           'hoc_ky': hocKy,
           'nam_hoc': namHoc,
         }
       );

       if (response?.statusCode == 200) {
         final data = jsonDecode(response!.body);

         if (data['success'] == true) {
           return data['data'] ?? [];
         } else {
           throw Exception('Lỗi: ${data['error'] ?? 'Unknown error'}');
         }
       } else {
         throw Exception('Lỗi server: ${response?.statusCode}');
       }
     } catch (e) {
       print('❌ Lỗi lấy thời khóa biểu: $e');
       rethrow;
     }
   }

  static Future<List<dynamic>> getSchedule(
      int idSinhVien,
      int hocKy,
      String namHoc
      ) async {
    try {
      final headers = await _getHeaders();
      final url = Uri.parse(
          '${ApiConstants.baseUrl}/lich-hoc-lich-thi?idSinhVien=$idSinhVien&hocKy=$hocKy&namHoc=$namHoc'
      );

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        _handleUnauthorized();
        return [];
      } else {
        throw Exception('Lỗi ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (e.toString().contains('Không tìm thấy token') ||
          e.toString().contains('hết hạn')) {
        rethrow;
      }
      throw Exception('Không tải được lịch học: $e');
    }
  }

  // Ví dụ các method khác cũng sử dụng token
  static Future<Map<String, dynamic>> getUserInfo(int idSinhVien) async {
    try {
      final headers = await _getHeaders();
      final url = Uri.parse('${ApiConstants.baseUrl}/sinh-vien/$idSinhVien');

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        _handleUnauthorized();
        return {};
      } else {
        throw Exception('Lỗi ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Không tải được thông tin sinh viên: $e');
    }
  }

  // Method POST với token
  static Future<bool> updateSchedule(Map<String, dynamic> data) async {
    try {
      final headers = await _getHeaders();
      final url = Uri.parse('${ApiConstants.baseUrl}/cap-nhat');

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 401) {
        _handleUnauthorized();
        return false;
      } else {
        throw Exception('Lỗi ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Không cập nhật được lịch học: $e');
    }
  }
}