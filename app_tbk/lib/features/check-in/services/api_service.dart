import 'dart:convert';
import 'dart:io';
import 'package:app_tbk/core/errors/exceptions.dart';
import 'package:http/http.dart' as http;
import '../models/event_model.dart';

class ApiService {
  // Thay đổi URL này thành API server của bạn
  static const String baseUrl = 'https://your-api-server.com/api';

  // Lấy danh sách sự kiện
  Future<List<CheckInEvent>> getEvents() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/events'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => CheckInEvent.fromJson(json)).toList();
      } else {
        throw Exception('Không thể tải danh sách sự kiện');
      }
    } on SocketException catch (_) {
      throw NoInternetException('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
    } catch (e) {
      print('Lỗi lấy sự kiện: $e');
      rethrow;
    }
  }

  // Gửi dữ liệu check-in
  Future<CheckInResponse> submitCheckIn(CheckInData data) async {

    print('🏃 DATA: ${data}');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/checkin'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        return CheckInResponse(
          success: true,
          message: responseData['message'] ?? 'Check-in thành công',
        );
      } else if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        return CheckInResponse(
          success: false,
          message: errorData['message'] ?? 'Dữ liệu không hợp lệ',
        );
      } else if (response.statusCode == 401) {
        return CheckInResponse(
          success: false,
          message: 'Vị trí không hợp lệ hoặc ngoài phạm vi cho phép',
        );
      } else if (response.statusCode == 422) {
        return CheckInResponse(
          success: false,
          message: 'Khuôn mặt không hợp lệ hoặc quá mờ',
        );
      } else {
        return CheckInResponse(
          success: false,
          message: 'Lỗi server. Vui lòng thử lại sau',
        );
      }
    } catch (e) {
      print('Lỗi submit check-in: $e');
      return CheckInResponse(
        success: false,
        message: 'Không thể kết nối đến server. Vui lòng kiểm tra kết nối mạng',
      );
    }
  }

  // Xác thực khuôn mặt
  Future<bool> validateFaceImage(String base64Image) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/validate-face'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'image': base64Image}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['isValid'] ?? false;
      }
      return false;
    } catch (e) {
      print('Lỗi xác thực khuôn mặt: $e');
      return false;
    }
  }
}

class CheckInResponse {
  final bool success;
  final String message;

  CheckInResponse({
    required this.success,
    required this.message,
  });
}