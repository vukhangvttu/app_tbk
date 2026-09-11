// // lib/services/schedule_notification_manager.dart
// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import 'package:intl/intl.dart';
// import '../models/class_schedule.dart';
// import 'smart_notification_service.dart';
//
// class ScheduleNotificationManager {
//   static final ScheduleNotificationManager _instance =
//   ScheduleNotificationManager._internal();
//   static ScheduleNotificationManager get instance => _instance;
//   ScheduleNotificationManager._internal();
//
//   final _notificationService = SmartNotificationService.instance;
//
//   // API base URL
//   final String apiBaseUrl = 'http://113.164.79.241:8202';
//
//   // Cache lịch học
//   List<LopHoc> _cachedSchedule = [];
//   DateTime? _lastFetch;
//
//   /// Lấy lịch học từ API và schedule notifications
//   Future<void> syncScheduleAndNotifications({
//     required int idSinhVien,
//     required int hocKy,
//     required String namHoc,
//   }) async {
//     try {
//       print('🔄 Đồng bộ lịch học và notifications...');
//
//       // 1. Lấy lịch học từ API
//       final schedule = await _fetchSchedule(idSinhVien, hocKy, namHoc);
//
//       if (schedule.isEmpty) {
//         print('⚠️ Không có lịch học nào');
//         return;
//       }
//
//       _cachedSchedule = schedule;
//       _lastFetch = DateTime.now();
//
//       // 2. Lọc lịch trong tương lai
//       final upcomingClasses = _filterUpcomingClasses(schedule);
//
//       print('📅 Tìm thấy ${upcomingClasses.length} lịch học trong tương lai');
//
//       // 3. Schedule notifications cho từng lịch
//       int scheduledCount = 0;
//       for (var lop in upcomingClasses) {
//         final success = await _scheduleNotificationForClass(lop);
//         if (success) scheduledCount++;
//       }
//
//       print('✅ Đã schedule $scheduledCount notifications');
//
//     } catch (e) {
//       print('❌ Lỗi đồng bộ: $e');
//     }
//   }
//
//   /// Lấy lịch học từ API
//   Future<List<LopHoc>> _fetchSchedule(
//       int idSinhVien,
//       int hocKy,
//       String namHoc,
//       ) async {
//     final url = Uri.parse(
//       '$apiBaseUrl/api/lich-hoc/thoi-khoa-bieu?idSinhVien=$idSinhVien&hocKy=$hocKy&namHoc=$namHoc',
//     );
//
//     final response = await http.get(url).timeout(
//       const Duration(seconds: 15),
//     );
//
//     if (response.statusCode == 200) {
//       final List<dynamic> data = jsonDecode(response.body);
//
//       return data.map((json) {
//         return LopHoc(
//           tenMon: json['TENMON'] ?? '',
//           thu: json['THU'] ?? 2,
//           gioBd: json['GIOBD'] ?? '',
//           gioKt: json['GIOKT'] ?? '',
//           hoTen: json['HOTEN'] ?? '',
//           tenPhong: json['TENPHONG'] ?? '',
//           maNhom: json['manhom'] ?? 0,
//           soTiet: json['SOTIET'] ?? 0,
//           phanBo: json['PHANBO'] ?? '',
//           ngayBd: _parseDate(json['NGAYBD']),
//           ngayKt: _parseDate(json['NGAYKT']),
//           nhomThi: json['NHOMTHI'] ?? false,
//         );
//       }).toList();
//     } else {
//       throw Exception('Failed to fetch schedule: ${response.statusCode}');
//     }
//   }
//
//   DateTime _parseDate(String? dateStr) {
//     if (dateStr == null || dateStr.isEmpty) {
//       return DateTime.now();
//     }
//
//     try {
//       final utcDate = DateTime.parse(dateStr);
//       final localDate = utcDate.toLocal();
//       return DateTime(localDate.year, localDate.month, localDate.day);
//     } catch (e) {
//       try {
//         return DateFormat('dd/MM/yyyy').parse(dateStr);
//       } catch (e) {
//         return DateTime.now();
//       }
//     }
//   }
//
//   /// Lọc các lịch học trong tương lai (từ hôm nay trở đi)
//   List<LopHoc> _filterUpcomingClasses(List<LopHoc> schedule) {
//     final now = DateTime.now();
//     final today = DateTime(now.year, now.month, now.day);
//
//     return schedule.where((lop) {
//       // Lấy ngày học (loại bỏ giờ)
//       final classDate = DateTime(
//         lop.ngayBd.year,
//         lop.ngayBd.month,
//         lop.ngayBd.day,
//       );
//
//       // Chỉ lấy lịch từ hôm nay trở đi
//       return !classDate.isBefore(today);
//     }).toList();
//   }
//
//   /// Lọc lịch học theo ngày cụ thể
//   List<LopHoc> getClassesForDate(DateTime date) {
//     final targetDate = DateTime(date.year, date.month, date.day);
//
//     return _cachedSchedule.where((lop) {
//       final classDate = DateTime(
//         lop.ngayBd.year,
//         lop.ngayBd.month,
//         lop.ngayBd.day,
//       );
//       return classDate.isAtSameMomentAs(targetDate);
//     }).toList();
//   }
//
//   /// Kiểm tra xem ngày có lịch học không
//   bool hasClassOnDate(DateTime date) {
//     return getClassesForDate(date).isNotEmpty;
//   }
//
//   /// Schedule notification cho 1 lớp học
//   Future<bool> _scheduleNotificationForClass(LopHoc lop) async {
//     try {
//       await _notificationService.scheduleForClass(
//         id: lop.maNhom,
//         tenMon: lop.tenMon,
//         ngayHoc: lop.ngayBd,
//         gioHoc: lop.gioBd,
//         phongHoc: lop.tenPhong,
//         isExam: lop.nhomThi,
//       );
//       return true;
//     } catch (e) {
//       print('❌ Lỗi schedule notification cho ${lop.tenMon}: $e');
//       return false;
//     }
//   }
//
//   /// Refresh notifications khi settings thay đổi
//   Future<void> refreshNotifications({
//     required int idSinhVien,
//     required int hocKy,
//     required String namHoc,
//   }) async {
//     // Cancel tất cả notifications cũ
//     await _notificationService.cancelAllNotifications();
//
//     // Sync lại
//     await syncScheduleAndNotifications(
//       idSinhVien: idSinhVien,
//       hocKy: hocKy,
//       namHoc: namHoc,
//     );
//   }
//
//   /// Kiểm tra và schedule notification cho tuần tới
//   Future<void> scheduleUpcomingWeek({
//     required int idSinhVien,
//     required int hocKy,
//     required String namHoc,
//   }) async {
//     try {
//       final schedule = await _fetchSchedule(idSinhVien, hocKy, namHoc);
//
//       // Lọc lịch trong 7 ngày tới
//       final now = DateTime.now();
//       final nextWeek = now.add(const Duration(days: 7));
//
//       final upcomingWeek = schedule.where((lop) {
//         return lop.ngayBd.isAfter(now) && lop.ngayBd.isBefore(nextWeek);
//       }).toList();
//
//       print('📅 Lên lịch ${upcomingWeek.length} thông báo cho tuần tới');
//
//       for (var lop in upcomingWeek) {
//         await _scheduleNotificationForClass(lop);
//       }
//     } catch (e) {
//       print('❌ Lỗi schedule tuần tới: $e');
//     }
//   }
//
//   /// Lấy thống kê notifications
//   Future<NotificationStats> getStats() async {
//     final pending = await _notificationService.getPendingNotifications();
//     final settings = await _notificationService.getSettings();
//
//     // Đếm số lịch học trong tương lai
//     final upcomingClasses = _filterUpcomingClasses(_cachedSchedule);
//     final upcomingExams = upcomingClasses.where((c) => c.nhomThi).length;
//
//     return NotificationStats(
//       totalScheduled: pending.length,
//       upcomingClasses: upcomingClasses.length - upcomingExams,
//       upcomingExams: upcomingExams,
//       notificationsEnabled: settings.enabled,
//       lastSync: _lastFetch,
//     );
//   }
//
//   /// Lấy lịch gần nhất
//   LopHoc? getNextClass() {
//     final now = DateTime.now();
//     final upcoming = _cachedSchedule.where((lop) {
//       return lop.ngayBd.isAfter(now);
//     }).toList()
//       ..sort((a, b) => a.ngayBd.compareTo(b.ngayBd));
//
//     return upcoming.isNotEmpty ? upcoming.first : null;
//   }
//
//   /// Hủy notification khi lịch thay đổi
//   Future<void> cancelNotificationForClass(int maNhom) async {
//     await _notificationService.cancelNotificationForClass(maNhom);
//   }
// }
//
// // ==================== NOTIFICATION STATS MODEL ====================
// class NotificationStats {
//   final int totalScheduled;
//   final int upcomingClasses;
//   final int upcomingExams;
//   final bool notificationsEnabled;
//   final DateTime? lastSync;
//
//   NotificationStats({
//     required this.totalScheduled,
//     required this.upcomingClasses,
//     required this.upcomingExams,
//     required this.notificationsEnabled,
//     this.lastSync,
//   });
// }