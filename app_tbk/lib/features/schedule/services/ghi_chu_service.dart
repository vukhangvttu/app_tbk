import 'dart:convert';

import 'package:app_tbk/models/class_schedule.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../auth/services/auth_service.dart';

/// Ghi chú của sinh viên cho 1 buổi học (lưu trên BE, không lưu ở thiết bị).
class GhiChu {
  /// Khóa định danh buổi học — xem [GhiChuService.khoaBuoi].
  final String buoiKey;
  final DateTime? ngayHoc;
  final String gioBd;
  final String noiDung;
  final DateTime? capNhatLuc;

  const GhiChu({
    required this.buoiKey,
    this.ngayHoc,
    this.gioBd = '',
    required this.noiDung,
    this.capNhatLuc,
  });

  factory GhiChu.fromJson(Map<String, dynamic> json) {
    return GhiChu(
      buoiKey: (json['buoiKey'] ?? json['BUOIKEY'] ?? '').toString(),
      ngayHoc: _parseNgay(json['ngayHoc'] ?? json['NGAYHOC']),
      gioBd: (json['gioBd'] ?? json['GIOBD'] ?? '').toString(),
      noiDung: (json['noiDung'] ?? json['NOIDUNG'] ?? '').toString(),
      capNhatLuc: _parseThoiGian(
          json['updatedAt'] ?? json['capNhatLuc'] ?? json['UPDATEDAT']),
    );
  }

  static DateTime? _parseNgay(dynamic v) {
    if (v == null) return null;
    if (v is List && v.length >= 3) {
      try {
        return DateTime(v[0] as int, v[1] as int, v[2] as int);
      } catch (_) {
        return null;
      }
    }
    final str = v.toString().trim();
    if (str.isEmpty) return null;
    try {
      final cleaned = str.replaceAll('Z', '').replaceAll('z', '');
      final d = DateTime.parse(cleaned);
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseThoiGian(dynamic v) {
    if (v == null) return null;
    if (v is List && v.length >= 3) {
      try {
        final year = v[0] as int;
        final month = v[1] as int;
        final day = v[2] as int;
        final hour = v.length > 3 ? v[3] as int : 0;
        final minute = v.length > 4 ? v[4] as int : 0;
        final second = v.length > 5 ? v[5] as int : 0;
        return DateTime(year, month, day, hour, minute, second);
      } catch (_) {
        return null;
      }
    }
    final str = v.toString().trim();
    if (str.isEmpty) return null;
    try {
      final cleaned = str.replaceAll('Z', '').replaceAll('z', '');
      final parsed = DateTime.parse(cleaned);
      return parsed.isUtc
          ? DateTime(
              parsed.year,
              parsed.month,
              parsed.day,
              parsed.hour,
              parsed.minute,
              parsed.second,
              parsed.millisecond,
              parsed.microsecond,
            )
          : parsed;
    } catch (_) {
      return null;
    }
  }
}

/// API ghi chú buổi học — đi qua đúng pipeline của app
/// ([AuthService.authenticatedRequestLichSinhVien], envelope {success, data})
/// giống [ApiService.getThoiKhoaBieu].
///
/// Hợp đồng BE (base: /student-calendar/api/v1):
/// - GET    /ghi-chu/{buoiKey}   -> data: {buoiKey, ngayHoc, gioBd, noiDung, updatedAt} | null
/// - PUT    /ghi-chu/{buoiKey}   -> body {buoiKey, maNhom, tenMon, ngayHoc, gioBd, noiDung}
/// - GET    /ghi-chu/mon/{maNhom} -> data: [ {buoiKey, ngayHoc, gioBd, noiDung, updatedAt}, ... ]
class GhiChuService {
  GhiChuService._();

  static final _fmtNgay = DateFormat('yyyy-MM-dd');

  /// Khóa định danh 1 buổi học. Server hiện chưa cấp id buổi riêng nên
  /// tổng hợp từ nhóm + ngày học + giờ bắt đầu (đủ duy nhất cho 1 buổi).
  /// Khi BE có id buổi thật, chỉ cần sửa duy nhất hàm này.
  static String khoaBuoi(LopHoc lop) =>
      '${lop.maNhom}|${_fmtNgay.format(lop.ngayBd)}|${lop.gioBd}';

  static dynamic _docData(http.Response? res) {
    if (res == null) throw Exception('Không nhận được phản hồi từ máy chủ');
    if (res.statusCode != 200) throw Exception('Lỗi server: ${res.statusCode}');
    final body = jsonDecode(res.body);
    if (body is Map && body['success'] == true) return body['data'];
    throw Exception(
        'Lỗi: ${body is Map ? (body['error'] ?? 'Unknown error') : 'Dữ liệu không hợp lệ'}');
  }

  /// Ghi chú của 1 buổi học; null = chưa có ghi chú.
  static Future<GhiChu?> layGhiChu(LopHoc lop) async {
    final key = khoaBuoi(lop);
    final res = await AuthService.authenticatedRequestLichSinhVien(
      method: 'GET',
      endpoint: '/ghi-chu/${Uri.encodeComponent(key)}',
    );
    final data = _docData(res);
    if (data == null) return null;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      map['buoiKey'] ??= key;
      final g = GhiChu.fromJson(map);
      return g.noiDung.trim().isEmpty ? null : g;
    }
    return null;
  }

  /// Tạo mới / cập nhật ghi chú của 1 buổi học (upsert phía BE).
  static Future<void> luuGhiChu(LopHoc lop, String noiDung) async {
    final key = khoaBuoi(lop);
    final res = await AuthService.authenticatedRequestLichSinhVien(
      method: 'PUT',
      endpoint: '/ghi-chu/${Uri.encodeComponent(key)}',
      body: {
        'buoiKey': key,
        'maNhom': lop.tenNhom,
        'tenMon': lop.tenMon,
        'ngayHoc': _fmtNgay.format(lop.ngayBd),
        'gioBd': lop.gioBd,
        'noiDung': noiDung,
      },
    );
    _docData(res);
  }

  /// Toàn bộ ghi chú của 1 môn (theo nhóm) — dùng cho tab Lịch thi ôn tập.
  /// Nếu không truyền [mssv], hàm sẽ tự lấy MSSV đã lưu của người dùng hiện tại.
  /// Đã lọc ghi chú rỗng, xếp theo ngày buổi học tăng dần.
  static Future<List<GhiChu>> layTheoMon(String tenNhom) async {
    // final mssv = await AuthService.getSavedMssv() ?? '';
    final res = await AuthService.authenticatedRequestLichSinhVien(
      method: 'GET',
      endpoint: '/ghi-chu/mon/$tenNhom',
    );
    final data = _docData(res);
    if (data is! List) return const [];
    final ds = data
        .whereType<Map>()
        .map((e) => GhiChu.fromJson(Map<String, dynamic>.from(e)))
        .where((g) => g.noiDung.trim().isNotEmpty)
        .toList();
    ds.sort((a, b) => (a.ngayHoc ?? DateTime(2100))
        .compareTo(b.ngayHoc ?? DateTime(2100)));
    return ds;
  }
}
