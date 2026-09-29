import 'dart:convert';

import 'package:app_tbk/core/errors/exceptions.dart';
import '../../auth/services/auth_service.dart';


class AttendanceHistoryService {
  /// Lấy lịch sử điểm danh theo sinh viên
  /// API hỗ trợ các tham số: TuNgay, DenNgay, SoNgay
  static Future<List<dynamic>> getAttendanceHistory(
    String idSinhVien, {
    String? tuNgay,
    String? denNgay,
    int? soNgay = 14,
  }) async {
    try {
      final queryParams = <String, String>{};

      if (tuNgay != null && tuNgay.isNotEmpty) {
        queryParams['TuNgay'] = tuNgay;
      }
      if (denNgay != null && denNgay.isNotEmpty) {
        queryParams['DenNgay'] = denNgay;
      }

      // Nếu không có TuNgay và DenNgay thì truyền SoNgay (mặc định 14)
      if ((tuNgay == null || tuNgay.isEmpty) &&
          (denNgay == null || denNgay.isEmpty) &&
          soNgay != null) {
        queryParams['SoNgay'] = soNgay.toString();
      }

      final uri = Uri(
        path: '/lich-su-diem-danh/$idSinhVien',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final endpoint = uri.toString();

      // 🟦 Gọi API có xác thực token
      final response = await AuthService.authenticatedRequestLichSinhVien(
        method: 'GET',
        endpoint: endpoint,
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
      // 🧠 Nếu lỗi liên quan đến mạng hoặc token
      if (e is NoInternetException ||
          e.toString().contains('Không có kết nối') ||
          e.toString().contains('Không tìm thấy token') ||
          e.toString().contains('hết hạn')) {
        rethrow; // Cho phép UI xử lý logout, refresh token hoặc thông báo mất mạng
      }
      throw Exception('Không tải được lịch sử điểm danh: $e');
    }
  }

}





