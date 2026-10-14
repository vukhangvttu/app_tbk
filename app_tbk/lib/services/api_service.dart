import 'dart:convert';
import 'dart:io';
import 'package:app_tbk/core/errors/exceptions.dart';
import 'package:app_tbk/features/auth/services/auth_service.dart';
import 'package:http/http.dart' as http;

class HttpClientWrapper {
  static const Duration timeout = Duration(seconds: 15);

  // GET request với token & tự động refresh token
  static Future<http.Response> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    String formattedEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    if (queryParams != null && queryParams.isNotEmpty) {
      final uri = Uri(queryParameters: queryParams);
      formattedEndpoint += '?${uri.query}';
    }

    try {
      final response = await AuthService.authenticatedRequestLichSinhVien(
        method: 'GET',
        endpoint: formattedEndpoint,
      );

      if (response == null) {
        throw UnauthorizedException('Phiên đăng nhập hết hạn hoặc không kết nối được máy chủ');
      }

      return _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // POST request với token & tự động refresh token
  static Future<http.Response> post(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    String formattedEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';

    try {
      final response = await AuthService.authenticatedRequestLichSinhVien(
        method: 'POST',
        endpoint: formattedEndpoint,
        body: body,
      );

      if (response == null) {
        throw UnauthorizedException('Phiên đăng nhập hết hạn hoặc không kết nối được máy chủ');
      }

      return _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // PUT request với token & tự động refresh token
  static Future<http.Response> put(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    String formattedEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';

    try {
      final response = await AuthService.authenticatedRequestLichSinhVien(
        method: 'PUT',
        endpoint: formattedEndpoint,
        body: body,
      );

      if (response == null) {
        throw UnauthorizedException('Phiên đăng nhập hết hạn hoặc không kết nối được máy chủ');
      }

      return _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // DELETE request với token & tự động refresh token
  static Future<http.Response> delete(String endpoint) async {
    String formattedEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';

    try {
      final response = await AuthService.authenticatedRequestLichSinhVien(
        method: 'DELETE',
        endpoint: formattedEndpoint,
      );

      if (response == null) {
        throw UnauthorizedException('Phiên đăng nhập hết hạn hoặc không kết nối được máy chủ');
      }

      return _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // Xử lý response
  static http.Response _handleResponse(http.Response response) {
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
    if (error is NoInternetException || error is UnauthorizedException || error is ApiException) {
      return error;
    }
    if (error is SocketException || error is http.ClientException) {
      return NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    }
    final errStr = error.toString().toLowerCase();
    if (errStr.contains('socketexception') ||
        errStr.contains('clientexception') ||
        errStr.contains('failed host lookup') ||
        errStr.contains('network is unreachable')) {
      return NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
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
        },
      );

      if (response != null && response.statusCode == 200) {
        final data = jsonDecode(response.body);

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

  /// Lấy lịch học & lịch thi - Tự động refresh token khi hết hạn
  static Future<List<dynamic>> getSchedule(
    int idSinhVien,
    int hocKy,
    String namHoc,
  ) async {
    try {
      final response = await AuthService.authenticatedRequestLichSinhVien(
        method: 'GET',
        endpoint: '/lich-hoc-lich-thi?idSinhVien=$idSinhVien&hocKy=$hocKy&namHoc=$namHoc',
      );

      if (response != null && response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Lỗi ${response?.statusCode}: ${response?.body}');
      }
    } catch (e) {
      if (e.toString().contains('Không tìm thấy token') || e.toString().contains('hết hạn')) {
        rethrow;
      }
      throw Exception('Không tải được lịch học: $e');
    }
  }

  /// Lấy thông tin sinh viên - Tự động refresh token khi hết hạn
  static Future<Map<String, dynamic>> getUserInfo(int idSinhVien) async {
    try {
      final response = await AuthService.authenticatedRequestLichSinhVien(
        method: 'GET',
        endpoint: '/sinh-vien/$idSinhVien',
      );

      if (response != null && response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Lỗi ${response?.statusCode}: ${response?.body}');
      }
    } catch (e) {
      throw Exception('Không tải được thông tin sinh viên: $e');
    }
  }

  /// Cập nhật lịch học - Tự động refresh token khi hết hạn
  static Future<bool> updateSchedule(Map<String, dynamic> data) async {
    try {
      final response = await AuthService.authenticatedRequestLichSinhVien(
        method: 'POST',
        endpoint: '/cap-nhat',
        body: data,
      );

      if (response != null && response.statusCode == 200) {
        return true;
      } else {
        throw Exception('Lỗi ${response?.statusCode}: ${response?.body}');
      }
    } catch (e) {
      throw Exception('Không cập nhật được lịch học: $e');
    }
  }

  /// Lấy điểm rèn luyện
  static Future<List<dynamic>> getTrainingPoints(int idSinhVien) async {
    try {
      final response = await AuthService.authenticatedRequestLichSinhVien(
        method: 'GET',
        endpoint: '/diem-ren-luyen/$idSinhVien',
      );

      if (response != null && response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['data'] ?? [];
        } else {
          throw Exception('Lỗi: ${data['error'] ?? 'Unknown error'}');
        }
      } else {
        throw Exception('Lỗi ${response?.statusCode}: ${response?.body}');
      }
    } catch (e) {
      if (e.toString().contains('Không tìm thấy token') || e.toString().contains('hết hạn')) {
        rethrow;
      }
      throw Exception('Không tải được điểm rèn luyện: $e');
    }
  }

  /// Lấy điểm học phần
  static Future<List<dynamic>> getCourseGrades(int idSinhVien) async {
    try {
      final response = await AuthService.authenticatedRequestLichSinhVien(
        method: 'GET',
        endpoint: '/bang-diem-hoc-phan/$idSinhVien',
      );

      if (response != null && response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['data'] ?? [];
        } else {
          throw Exception('Lỗi: ${data['error'] ?? 'Unknown error'}');
        }
      } else {
        throw Exception('Lỗi ${response?.statusCode}: ${response?.body}');
      }
    } catch (e) {
      if (e.toString().contains('Không tìm thấy token') || e.toString().contains('hết hạn')) {
        rethrow;
      }
      throw Exception('Không tải được điểm học phần: $e');
    }
  }
}
