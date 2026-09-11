import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../../../config/api_constants.dart';
import '../../auth/services/auth_service.dart';
import '../models/profile.dart';

class ProfileService {
  /// Lấy thông tin profile theo userId
  static Future<UserProfile?> fetchProfile(BuildContext context) async {
    final userId = await AuthService.getUserId() ?? '';
    if (userId.isEmpty) throw Exception('Không tìm thấy userId');

    final response = await AuthService.authenticatedRequestLichSinhVien(
      method: 'GET',
      endpoint: '/user-profile/$userId',
    );

    if (response == null) {
      throw Exception('Không nhận được phản hồi từ máy chủ.');
    }

    if (response.statusCode == 200) {
      final dynamic jsonData = jsonDecode(response.body);

      final data = jsonData['data'];

      // Nếu API trả về object thay vì array
      if (jsonData is Map<String, dynamic>) {
         if(data != null) {
           return UserProfile.fromJson(data);
         } else
           return null;

      }

      // Nếu API trả về array, lấy phần tử đầu tiên
      if (jsonData is List && jsonData.isNotEmpty) {
        return UserProfile.fromJson(jsonData[0]);
      }

      throw Exception('Dữ liệu trả về không hợp lệ');
    } else {
      throw Exception('Server trả về mã lỗi ${response.statusCode}');
    }
  }


  // Thêm vào class AuthService
  static Future<Map<String, String>> getAuthHeaders() async {
    final token = await AuthService.getAccessToken(); // ← Đây là hàm bạn đã có rồi
    if (token == null) return {};

    return {
      'Authorization': 'Bearer $token',
    };
  }

  /// Cập nhật thông tin profile
  static Future<void> updateProfile({
    required BuildContext context,
    required String hoTen,
    required String ngaySinh,
    required String gioiTinh,
    required String mssv,
    required String email,
    required String sdt,
    required String lop,
    required String khoaHoc,
    File? avatarFile,
  }) async {
    final userId = await AuthService.getUserId() ?? '';
    if (userId.isEmpty) throw Exception('Không tìm thấy userId');

    // Nếu có file ảnh, upload trước
    String? avatarUrl;
    if (avatarFile != null) {
      final int fileSize = await avatarFile.length(); // bytes
      final double fileSizeMB = fileSize / (1024 * 1024); // chuyển sang MB

      if (fileSizeMB > 5.0) { // Giới hạn 5MB

        throw Exception('Ảnh quá lớn. Vui lòng chọn ảnh nhỏ hơn 1MB');
      }

      avatarUrl = await _uploadAvatar(userId, avatarFile);
    }

    // Chuẩn bị dữ liệu cập nhật
    final Map<String, dynamic> updateData = {
      'ho_ten': hoTen,
      'ngay_sinh': ngaySinh,
      'gioi_tinh': gioiTinh,
      'mssv': mssv,
      'email': email + '@stu.vttu.edu.vn',
      'sdt': sdt,
      'lop': lop,
      'khoa_hoc': khoaHoc,
    };

    // Thêm avatarUrl nếu có
    if (avatarUrl != null) {
      updateData['avatar_url'] = avatarUrl;
    }

    final response = await AuthService.authenticatedRequestLichSinhVien(
      method: 'PUT', // hoặc 'PATCH' tùy API của bạn
      endpoint: '/user-profile/$userId',
      body: (updateData),
    );

    if (response == null) {
      throw Exception('Không nhận được phản hồi từ máy chủ.');
    }

    if (response.statusCode != 200 && response.statusCode != 204) {
      final errorMessage = response.body.isNotEmpty
          ? jsonDecode(response.body)['message'] ?? 'Cập nhật thất bại'
          : 'Cập nhật thất bại';
      throw Exception(errorMessage);
    }
  }

  /// Upload avatar lên server
  /// Upload avatar lên server (theo cùng cấu trúc với updateProfile)
  static Future<String> _uploadAvatar(String userId, File imageFile) async {
    try {
      // Gửi multipart request qua AuthService
      final response = await AuthService.authenticatedRequestLichSinhVien(
        method: 'POST',
        endpoint: '/upload-avatar/$userId',
        isMultipart: true,
        // 👈 thêm flag này để hàm AuthService biết là multipart
        files: {
          'avatar': imageFile, // 👈 key 'avatar' giống backend nhận
        },
      );

      if (response == null) {
        throw Exception('Không nhận được phản hồi từ máy chủ.');
      }

      if (response.statusCode != 200) {
        final errorMessage = response.body.isNotEmpty
            ? jsonDecode(response.body)['message'] ?? 'Upload ảnh thất bại'
            : 'Upload ảnh thất bại';
        throw Exception(errorMessage);
      }

      final jsonData = jsonDecode(response.body);
      return jsonData['avatarUrl'] ?? jsonData['url'] ?? '';
    } catch (e) {
      throw Exception('Lỗi khi upload ảnh: $e');
    }
  }

  static String mapCategoryToEnglish(String vietnamese) {
    switch (vietnamese) {
      case 'Góp ý chung':
        return 'other';
      case 'Báo lỗi':
        return 'bug';
      case 'Yêu cầu tính năng':
        return 'feature';
      case 'Cải thiện UI/UX':
        return 'improvement';
      case 'Khác':
        return 'other';
      default:
        return 'other';
    }
  }

  /// Gửi phản hồi từ người dùng
  /// Sử dụng AuthService.authenticatedRequestLichSinhVien để đảm bảo đồng bộ với các request khác
  static Future<void> submitFeedback({
    required String loaiPhanHoi,
    required String noiDung,
    List<File> hinhAnh = const [],
  }) async {
    final fields = <String, String>{
      'feedback_type': mapCategoryToEnglish(loaiPhanHoi),
      'content': noiDung,
    };

    final files = <String, List<File>>{};
    if (hinhAnh.isNotEmpty) {
      files['hinhanh'] = hinhAnh;
    }

    final response = await AuthService.authenticatedMultipartRequest(
      method: 'POST',
      endpoint: '/feedback',
      fields: fields,
      files: files,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return;
    }

    String errorMessage = 'Không thể gửi phản hồi';
    try {
      final json = jsonDecode(response.body);
      errorMessage = json['message'] ?? json['error'] ?? errorMessage;
    } catch (_) {}

    throw Exception('$errorMessage (Mã: ${response.statusCode})');
  }



}





// Model UserProfile
// class UserProfile {
//   final String? hoTen;
//   final String? ngaySinh;
//   final String? gioiTinh;
//   final String? mssv;
//   final String? email;
//   final String? sdt;
//   final String? lop;
//   final String? khoaHoc;
//   final String? avatarUrl;
//
//   UserProfile({
//     this.hoTen,
//     this.ngaySinh,
//     this.gioiTinh,
//     this.mssv,
//     this.email,
//     this.sdt,
//     this.lop,
//     this.khoaHoc,
//     this.avatarUrl,
//   });
//
//   factory UserProfile.fromJson(Map<String, dynamic> json) {
//     return UserProfile(
//       hoTen: json['ho_ten'] as String?,
//       ngaySinh: json['ngay_sinh'] as String?,
//       gioiTinh: json['gioi_tinh'] as String?,
//       mssv: json['mssv'] as String?,
//       email: json['email'] as String?,
//       sdt: json['sdt'] as String?,
//       lop: json['lop'] as String?,
//       khoaHoc: json['khoa_hoc'] as String?,
//       avatarUrl: json['avatar_url'] as String?,
//     );
//   }
//
//   Map<String, dynamic> toJson() {
//     return {
//       'hoTen': hoTen,
//       'ngaySinh': ngaySinh,
//       'gioiTinh': gioiTinh,
//       'mssv': mssv,
//       'email': email,
//       'sdt': sdt,
//       'lop': lop,
//       'khoaHoc': khoaHoc,
//       'avatarUrl': avatarUrl,
//     };
//   }
// }