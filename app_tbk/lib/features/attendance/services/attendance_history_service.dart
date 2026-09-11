import 'dart:convert';

import '../../auth/services/auth_service.dart';


class AttendanceHistoryService {
  /// Lấy lịch sử điểm danh theo sinh viên
  static Future<List<dynamic>> getAttendanceHistory(String idSinhVien) async {
    try {
      // 🟦 Gọi API có xác thực token
      final response = await AuthService.authenticatedRequestLichSinhVien(
        method: 'GET',
        endpoint: '/lich-su-diem-danh/$idSinhVien',
      );

      // 🟢 Kiểm tra phản hồi
      if (response?.statusCode == 200) {
        final body = json.decode(response!.body);

        // Nếu API trả về đúng cấu trúc {"success": true, "count": ..., "data": [...]}
        if (body is Map<String, dynamic>) {
          if (body['success'] == true && body['data'] is List) {
            return body['data'];
          } else {
            throw Exception("Phản hồi API không đúng định dạng mong đợi");
          }
        } else {
          throw Exception("Dữ liệu trả về không phải Map hợp lệ");
        }
      } else {
        // 🔴 Lỗi khác từ server
        throw Exception('Lỗi ${response?.statusCode}: ${response!.body}');
      }
    } catch (e) {
      // 🧠 Nếu lỗi liên quan đến token (hết hạn hoặc không có)
      if (e.toString().contains('Không tìm thấy token') ||
          e.toString().contains('hết hạn')) {
        rethrow; // Cho phép UI xử lý logout hoặc refresh token
      }
      throw Exception('Không tải được lịch sử điểm danh: $e');
    }
  }

}





