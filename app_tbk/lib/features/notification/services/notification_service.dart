// lib/services/notification_service.dart

import 'dart:convert';
import 'dart:ui';
import 'package:app_tbk/config/api_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/notification_history.dart';

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();
  static final _historyDb = NotificationHistoryDatabase.instance;


  static Future<void> init() async {
    // Khởi tạo timezone
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: android,
      iOS: ios,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    await _createNotificationChannels();
    print('✅ Notification Service initialized');
  }

  // ==================== CREATE CHANNELS ====================

  static Future<void> _createNotificationChannels() async {
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return;

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'lichhoc_channel',
        'Lịch học',
        description: 'Thông báo lịch học hàng ngày',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'lichthi_channel',
        'Lịch thi',
        description: 'Thông báo lịch thi quan trọng',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'nhacnho_channel',
        'Nhắc nhở',
        description: 'Nhắc nhở trước giờ học/thi',
        importance: Importance.high,
        playSound: true,
      ),
    );
  }

  // ==================== HANDLE TAP ====================

  static Future<void> _onNotificationTapped(
      NotificationResponse response
      ) async {
    print('👆 Notification tapped: ${response.payload}');

    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        if (data['historyId'] != null) {
          await _historyDb.markAsRead(data['historyId']);
        }
      } catch (e) {
        print('❌ Error handling notification tap: $e');
      }
    }
  }

  // ==================== SHOW & SAVE ====================

  Future<void> showAndSaveNotification({
    required int idSinhVien,
    required String title,
    required String body,
    required String loaiLich,
    Map<String, dynamic>? extraData,
  }) async {
    final channelId = _getChannelId(loaiLich);
    final channelName = _getChannelName(loaiLich);
    final channelColor = _getChannelColor(loaiLich);

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Thông báo $channelName',
      importance: loaiLich == 'LICHTHI' ? Importance.max : Importance.high,
      priority: loaiLich == 'LICHTHI' ? Priority.max : Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(channelColor),
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Lưu vào LOCAL DB
    int? historyId;
    try {
      final notification = NotificationHistory(
        title: title,
        body: body,
        type: _mapLoaiLichToType(loaiLich),
        sentAt: DateTime.now(),
        payload: {
          'idSinhVien': idSinhVien.toString(),
          'loaiLich': loaiLich,
          ...?extraData,
        },
      );

      historyId = await _historyDb.insert(notification);
      print('💾 Saved to local DB with ID: $historyId');
    } catch (e) {
      print('⚠️ Error saving to local DB: $e');
    }

    // Hiển thị notification
    final payload = jsonEncode({
      'historyId': historyId,
      'idSinhVien': idSinhVien,
      'loaiLich': loaiLich,
      'type': _mapLoaiLichToType(loaiLich),
      ...?extraData,
    });

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
      payload: payload,
    );

    // Lưu về API (async)
    _saveToApi(
      idSinhVien: idSinhVien,
      title: title,
      body: body,
      loaiLich: loaiLich,
    ).catchError((error) {
      print('⚠️ Lỗi khi lưu về API: $error');
    });
  }

  // ==================== SCHEDULE DAILY ====================

  Future<void> scheduleDailyNotification({
    required int id,
    required int idSinhVien,
    required String title,
    required String body,
    required String loaiLich,
    required int hour,
    required int minute,
    Map<String, dynamic>? extraData,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final channelId = _getChannelId(loaiLich);
    final channelName = _getChannelName(loaiLich);
    final channelColor = _getChannelColor(loaiLich);

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Thông báo $channelName',
      importance: loaiLich == 'LICHTHI' ? Importance.max : Importance.high,
      priority: loaiLich == 'LICHTHI' ? Priority.max : Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(channelColor),
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Lưu vào LOCAL DB
    int? historyId;
    try {
      final notification = NotificationHistory(
        title: title,
        body: body,
        type: _mapLoaiLichToType(loaiLich),
        sentAt: scheduled,
        payload: {
          'idSinhVien': idSinhVien.toString(),
          'loaiLich': loaiLich,
          'scheduled': 'true',
          ...?extraData,
        },
      );

      historyId = await _historyDb.insert(notification);
      print('💾 Scheduled notification saved to DB: $historyId');
    } catch (e) {
      print('⚠️ Error saving scheduled notification: $e');
    }

    final payload = jsonEncode({
      'historyId': historyId,
      'idSinhVien': idSinhVien,
      'loaiLich': loaiLich,
      'type': _mapLoaiLichToType(loaiLich),
      'scheduled': 'true',
      ...?extraData,
    });

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );

    print('⏰ Scheduled notification at $hour:$minute for ID: $id');

    _saveScheduledToApi(
      idSinhVien: idSinhVien,
      title: title,
      body: body,
      loaiLich: loaiLich,
    ).catchError((error) {
      print('⚠️ Lỗi khi lưu scheduled notification về API: $error');
    });
  }

  // ==================== SCHEDULE ONE-TIME ====================

  Future<void> scheduleOneTimeNotification({
    required int id,
    required int idSinhVien,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String loaiLich = 'NHACNHO',
    Map<String, dynamic>? extraData,
  }) async {
    final scheduled = tz.TZDateTime.from(scheduledTime, tz.local);

    if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) {
      print('⏭️ Skipping past notification');
      return;
    }

    final channelId = _getChannelId(loaiLich);
    final channelName = _getChannelName(loaiLich);
    final channelColor = _getChannelColor(loaiLich);

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(channelColor),
    );

    final details = NotificationDetails(android: androidDetails);

    try {
      final notification = NotificationHistory(
        title: title,
        body: body,
        type: _mapLoaiLichToType(loaiLich),
        sentAt: scheduledTime,
        payload: {
          'idSinhVien': idSinhVien.toString(),
          'loaiLich': loaiLich,
          ...?extraData,
        },
      );

      await _historyDb.insert(notification);
    } catch (e) {
      print('⚠️ Error saving reminder: $e');
    }

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );

    print('⏰ One-time notification scheduled at $scheduledTime');
  }

  // ==================== CANCEL ====================

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
    print('🗑️ Cancelled notification ID: $id');
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
    print('🗑️ Cancelled all notifications');
  }

  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }

  // ==================== HELPERS ====================

  static String _getChannelId(String loaiLich) {
    switch (loaiLich.toUpperCase()) {
      case 'LICHTHI':
        return 'lichthi_channel';
      case 'NHACNHO':
        return 'nhacnho_channel';
      case 'LICHHOC':
      default:
        return 'lichhoc_channel';
    }
  }

  static String _getChannelName(String loaiLich) {
    switch (loaiLich.toUpperCase()) {
      case 'LICHTHI':
        return 'Lịch thi';
      case 'NHACNHO':
        return 'Nhắc nhở';
      case 'LICHHOC':
      default:
        return 'Lịch học';
    }
  }

  static int _getChannelColor(String loaiLich) {
    switch (loaiLich.toUpperCase()) {
      case 'LICHTHI':
        return 0xFFFF9800;
      case 'NHACNHO':
        return 0xFF4CAF50;
      case 'LICHHOC':
      default:
        return 0xFF2196F3;
    }
  }

  static String _mapLoaiLichToType(String loaiLich) {
    switch (loaiLich.toUpperCase()) {
      case 'LICHTHI':
        return 'EXAM';
      case 'NHACNHO':
        return 'REMINDER';
      case 'LICHHOC':
      default:
        return 'CLASS';
    }
  }

  // ==================== API CALLS ====================

  static Future<void> _saveToApi({
    required int idSinhVien,
    required String title,
    required String body,
    required String loaiLich,
  }) async {
    try {
      // ✅ Lấy headers có Bearer token
      final headers = await ApiGetToken.getAuthHeaders();

      final url = Uri.parse('${ApiConstants.baseUrl}/thong-bao/save');

      // ✅ Gửi request với headers chuẩn
      final response = await http.post(
        url,
        headers: headers, // DÙNG headers đã có token
        body: jsonEncode({
          'idSinhVien': idSinhVien,
          'title': title,
          'body': body,
          'loaiLich': loaiLich,
          'ngayThongBao': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Saved to API successfully');
      } else {
        print('⚠️ API error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ Error saving to API: $e');
      rethrow;
    }
  }


  static Future<void> _saveScheduledToApi({
    required int idSinhVien,
    required String title,
    required String body,
    required String loaiLich,
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.baseUrl}/thoi-khoa-bieu/thong-bao/save',
      );

      // ✅ Lấy headers có Bearer token
      final headers = await ApiGetToken.getAuthHeaders();

      final requestBody = {
        'idSinhVien': idSinhVien,
        'tieuDe': title,
        'noiDung': body,
        'loaiLich': loaiLich,
        'ngayTao': DateTime.now()
            .toString()
            .substring(0, 19)
            .replaceFirst('T', ' '),
      };

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      print('📡 [API] Save scheduled: ${response.statusCode}');
      if (response.statusCode == 200) {
        print('✅ Lưu thông báo lịch học thành công.');
      } else {
        print('⚠️ Lỗi khi lưu lịch (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('❌ Lỗi khi gửi thông báo lịch lên API: $e');
      rethrow;
    }
  }

  // ==================== HISTORY MANAGEMENT (PUBLIC METHODS) ====================

  /// Lấy tất cả lịch sử thông báo
  Future<List<NotificationHistory>> getNotificationHistory({int? limit}) async {
    return await _historyDb.getAll(limit: limit);
  }

  /// Lấy lịch sử theo loại
  Future<List<NotificationHistory>> getHistoryByType(String type) async {
    return await _historyDb.getByType(type);
  }

  /// Lấy số thông báo chưa đọc
  Future<int> getUnreadCount() async {
    return await _historyDb.getUnreadCount();
  }

  /// Đánh dấu 1 notification đã đọc
  Future<void> markNotificationAsRead(int id) async {
    await _historyDb.markAsRead(id);
  }

  /// Đánh dấu tất cả đã đọc
  Future<void> markAllNotificationsAsRead() async {
    await _historyDb.markAllAsRead();
  }

  /// Xóa 1 notification
  Future<void> deleteNotification(int id) async {
    await _historyDb.delete(id);
  }

  /// Xóa tất cả lịch sử
  Future<void> clearNotificationHistory() async {
    await _historyDb.deleteAll();
  }

  /// Xóa thông báo cũ hơn X ngày
  Future<void> cleanOldNotifications({int days = 30}) async {
    await _historyDb.deleteOlderThan(days);
  }

  /// Lấy thống kê
  Future<Map<String, int>> getNotificationStatistics() async {
    return await _historyDb.getStatistics();
  }

  // ==================== BACKWARD COMPATIBILITY ====================

  /// Alias methods để tương thích với code cũ
  Future<List<NotificationHistory>> getHistory({int? limit}) async {
    return await getNotificationHistory(limit: limit);
  }

  Future<void> markAsRead(int historyId) async {
    await markNotificationAsRead(historyId);
  }

  Future<void> cleanOldHistory({int days = 30}) async {
    await cleanOldNotifications(days: days);
  }

  Future<void> clearAllHistory() async {
    await clearNotificationHistory();
  }

  Future<Map<String, int>> getStatistics() async {
    return await getNotificationStatistics();
  }
}