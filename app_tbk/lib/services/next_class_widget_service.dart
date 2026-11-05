import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:app_tbk/models/class_schedule.dart';

/// Đẩy buổi học hiện tại / tiếp theo ra widget màn hình chính (Android).
///
/// Cách dùng:
/// - Sau mỗi lần tải xong thời khóa biểu → [capNhat] với danh sách lớp học.
/// - Khi đăng xuất → [xoa] để widget không hiện dữ liệu cũ của tài khoản trước.
///
/// Widget phía Kotlin (NextClassWidgetProvider) chỉ đọc các key `nc_*` này
/// rồi tự tính lại nhãn "còn X giờ" mỗi 30 phút, nên không cần mở app
/// widget vẫn không bị đứng thời gian.
class NextClassWidgetService {
  static const _providerName = 'NextClassWidgetProvider';

  static Future<void> capNhat(List<LopHoc> lichHoc) async {
    try {
      final now = DateTime.now();
      _BuoiKeTiep? dangHoc;
      _BuoiKeTiep? sapToi;

      for (final lop in lichHoc) {
        final buoi = _buoiSapDienRa(lop, now);
        if (buoi == null) continue;
        if (!buoi.batDau.isAfter(now) && buoi.ketThuc.isAfter(now)) {
          if (dangHoc == null || buoi.batDau.isBefore(dangHoc.batDau)) {
            dangHoc = buoi;
          }
        } else if (buoi.batDau.isAfter(now)) {
          if (sapToi == null || buoi.batDau.isBefore(sapToi.batDau)) {
            sapToi = buoi;
          }
        }
      }

      final chon = dangHoc ?? sapToi;
      if (chon == null) {
        await HomeWidget.saveWidgetData<String>('nc_state', 'empty');
      } else {
        await HomeWidget.saveWidgetData<String>(
            'nc_state', dangHoc != null ? 'current' : 'next');
        await HomeWidget.saveWidgetData<String>('nc_subject', chon.lop.tenMon);
        await HomeWidget.saveWidgetData<String>(
            'nc_time', '${chon.lop.gioBd} – ${chon.lop.gioKt}');
        await HomeWidget.saveWidgetData<String>('nc_room', chon.lop.tenPhong);
        await HomeWidget.saveWidgetData<String>('nc_teacher', chon.lop.hoTen);
        await HomeWidget.saveWidgetData<String>(
            'nc_kind', chon.lop.nhomThi ? 'thi' : 'hoc');
        await HomeWidget.saveWidgetData<int>(
            'nc_start_ms', chon.batDau.millisecondsSinceEpoch);
        await HomeWidget.saveWidgetData<int>(
            'nc_end_ms', chon.ketThuc.millisecondsSinceEpoch);
      }
      await HomeWidget.updateWidget(
        name: _providerName,
        androidName: 'widget.NextClassWidgetProvider',
        qualifiedAndroidName:
            'com.example.app_tbk.widget.NextClassWidgetProvider',
      );
    } catch (e) {
      // Widget là tính năng phụ — lỗi ở đây không được làm hỏng luồng chính.
      debugPrint('NextClassWidgetService.capNhat: $e');
    }
  }

  /// Xóa dữ liệu widget (gọi khi đăng xuất).
  static Future<void> xoa() async {
    try {
      await HomeWidget.saveWidgetData<String>('nc_state', 'empty');
      await HomeWidget.saveWidgetData<String>('nc_subject', '');
      await HomeWidget.updateWidget(
        name: _providerName,
        androidName: 'widget.NextClassWidgetProvider',
        qualifiedAndroidName:
            'com.example.app_tbk.widget.NextClassWidgetProvider',
      );
    } catch (e) {
      debugPrint('NextClassWidgetService.xoa: $e');
    }
  }

  /// Tìm lần diễn ra gần nhất của 1 lớp (theo thứ hàng tuần, trong khoảng
  /// ngayBd → ngayKt) mà giờ kết thúc vẫn còn ở phía trước.
  static _BuoiKeTiep? _buoiSapDienRa(LopHoc lop, DateTime now) {
    final bd = _parseGio(lop.gioBd);
    final kt = _parseGio(lop.gioKt);
    if (bd == null || kt == null) return null;

    // THU server: 2 = Thứ 2 ... 8 = Chủ nhật → DateTime.weekday: 1..7
    final weekdayMucTieu = lop.thu - 1;
    if (weekdayMucTieu < 1 || weekdayMucTieu > 7) return null;

    final homNay = DateTime(now.year, now.month, now.day);
    final ngayBd = DateTime(lop.ngayBd.year, lop.ngayBd.month, lop.ngayBd.day);
    final ngayKt = DateTime(lop.ngayKt.year, lop.ngayKt.month, lop.ngayKt.day);

    var lech = (weekdayMucTieu - homNay.weekday) % 7;
    var ngay = homNay.add(Duration(days: lech));

    // Học kỳ chưa bắt đầu → nhảy tới lần diễn ra đầu tiên trong kỳ.
    while (ngay.isBefore(ngayBd)) {
      ngay = ngay.add(const Duration(days: 7));
    }

    // Thử tuần này, nếu đã qua giờ thì thử tuần sau.
    for (var i = 0; i < 2; i++) {
      if (!ngay.isBefore(ngayBd) && !ngay.isAfter(ngayKt)) {
        final batDau = ngay.add(Duration(hours: bd[0], minutes: bd[1]));
        final ketThuc = ngay.add(Duration(hours: kt[0], minutes: kt[1]));
        if (ketThuc.isAfter(now)) {
          return _BuoiKeTiep(lop, batDau, ketThuc);
        }
      }
      ngay = ngay.add(const Duration(days: 7));
    }
    return null;
  }

  static List<int>? _parseGio(String gio) {
    final parts = gio.trim().split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return [h, m];
  }
}

class _BuoiKeTiep {
  final LopHoc lop;
  final DateTime batDau;
  final DateTime ketThuc;
  const _BuoiKeTiep(this.lop, this.batDau, this.ketThuc);
}
