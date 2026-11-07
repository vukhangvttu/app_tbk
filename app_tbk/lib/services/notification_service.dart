import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // ✅ Khởi tạo timezone
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _notifications.initialize(initSettings);
  }

  // 🔔 Hiển thị ngay + lưu DB
  Future<void> showAndSaveNotification({
    required int idSinhVien,
    required String title,
    required String body,
    required String loaiLich
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'lichhoc_channel',
      'Lịch học',
      channelDescription: 'Thông báo lịch học & lịch thi',
      importance: Importance.max,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(0, title, body, details);

    // 🗄️ Lưu về API
    try {
      final url = Uri.parse('http://10.0.2.2:8202/api/thong-bao/save');
      await http.post(url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'idSinhVien': idSinhVien,
            'title': title,
            'body': body,
            'loaiLich': loaiLich,
            'ngayThongBao': DateTime.now().toIso8601String(),
          }));
    } catch (e) {
      print('⚠️ Lỗi khi lưu thông báo: $e');
    }
  }

  // 🕗 Lên lịch thông báo theo giờ quy định
  Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required String loaiLich,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
    tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    // Nếu giờ này đã qua thì chuyển sang ngày mai
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'lichhoc_channel',
      'Lịch học',
      channelDescription: 'Thông báo lịch học & lịch thi',
      importance: Importance.max,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      details,
      // androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      androidScheduleMode: AndroidScheduleMode.inexact, // ✅ Sửa chỗ này
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    // 🗄️ Lưu về API
    try {
      final url = Uri.parse('http://10.0.2.2:8202/api/thoi-khoa-bieu/thong-bao/save');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'idSinhVien': 1979,
          'tieuDe': title,
          'noiDung': body,
          'loaiLich': loaiLich,
          'ngayTao': DateTime.now().toString().substring(0, 19).replaceFirst('T', ' '),
        }),
      );

      print('📡 Gửi thông báo status: ${response.statusCode}');
      print('📩 Phản hồi: ${response.body}');
    } catch (e) {
      print('⚠️ Lỗi khi lưu thông báo: $e');
    }
  }

}