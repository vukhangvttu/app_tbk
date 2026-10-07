import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../auth/services/auth_service.dart';
import '../screens/notification_history_screen.dart'; // Đảm bảo import model đúng

class NotificationHistoryService {
  /// Lấy MSSV từ AuthService (chung cho tất cả hàm)
  static Future<String> _getMssv() async {
    final mssv = await AuthService.getSavedMssv() ?? '';
    if (mssv.isEmpty) {
      throw Exception('Không tìm thấy MSSV. Vui lòng đăng nhập lại.');
    }
    return mssv;
  }

  /// Timeout chung
  static const Duration _timeout = Duration(seconds: 20);

  /// Giải mã JSON an toàn, tránh văng FormatException do HTML error page hoặc rác
  static dynamic _safeJsonDecode(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  /// 1. Lấy danh sách thông báo theo MSSV (Có hỗ trợ phân trang)
  /// GET /notification-history/:mssv
  static Future<Map<String, dynamic>> fetchNotifications(
    BuildContext context, {
    int page = 1,
    int limit = 20,
    int? beforeId,
    int? afterId,
  }) async {
    final mssv = await _getMssv();

    String queryParams = '?page=$page&limit=$limit';
    if (beforeId != null) queryParams += '&before_id=$beforeId';
    if (afterId != null) queryParams += '&after_id=$afterId';

    var response = await AuthService.authenticatedRequestNotification(
      method: 'GET',
      endpoint: '/notification-history/$mssv$queryParams',
    ).timeout(
      _timeout,
      onTimeout: () => throw TimeoutException('Kết nối quá hạn (20s). Vui lòng thử lại.'),
    );

    // Thử các endpoint dự phòng nếu bị 404/405
    if (response != null && (response.statusCode == 404 || response.statusCode == 405)) {
      response = await AuthService.authenticatedRequestNotification(
        method: 'GET',
        endpoint: '/notification_history/$mssv$queryParams',
      ).timeout(_timeout);
    }

    if (response != null && (response.statusCode == 404 || response.statusCode == 405)) {
      response = await AuthService.authenticatedRequestNotification(
        method: 'GET',
        endpoint: '/notifications/$mssv$queryParams',
      ).timeout(_timeout);
    }

    if (response == null) {
      throw Exception('Không nhận được phản hồi từ server.');
    }

    if (response.statusCode == 200) {
      final decoded = _safeJsonDecode(response.body);
      if (decoded == null) {
        throw Exception('Dữ liệu phản hồi từ máy chủ không đúng định dạng JSON.');
      }

      dynamic rawData;
      bool hasMore = false;

      if (decoded is Map<String, dynamic>) {
        if (decoded['success'] == false) {
          throw Exception(decoded['message'] ?? 'Lỗi không xác định từ server');
        }
        rawData = decoded['data'] ?? decoded['notifications'] ?? decoded['result'];
        
        if (decoded['pagination'] != null) {
          hasMore = decoded['pagination']['has_more'] == true;
        }
      } else if (decoded is List) {
        rawData = decoded;
      }

      if (rawData == null || rawData is! List) {
        return {'data': <NotificationHistory>[], 'has_more': false};
      }

      final List<dynamic> jsonData = rawData;
      final notifications = jsonData
          .map((json) => NotificationHistory.fromJson(Map<String, dynamic>.from(json)))
          .toList();

      // Sắp xếp mới nhất trước
      notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      // Nếu backend cũ không trả về pagination, ta tự suy luận
      if (decoded is Map<String, dynamic> && decoded['pagination'] == null) {
         hasMore = notifications.length >= limit;
      }

      return {
        'data': notifications,
        'has_more': hasMore,
      };
    } else {
      final decoded = _safeJsonDecode(response.body);
      if (decoded is Map && decoded['message'] != null) {
        throw Exception(decoded['message']);
      }
      throw Exception('Lỗi máy chủ (${response.statusCode})');
    }
  }

  /// 2. Lấy tổng hợp thống kê thông báo (unread & total)
  /// GET /notification-history/:mssv/summary
  static Future<Map<String, int>> getNotificationStats(BuildContext context) async {
    final mssv = await _getMssv();

    var response = await AuthService.authenticatedRequestNotification(
      method: 'GET',
      endpoint: '/notification-history/$mssv/summary',
    ).timeout(_timeout);

    if (response != null && (response.statusCode == 404 || response.statusCode == 405)) {
      response = await AuthService.authenticatedRequestNotification(
        method: 'GET',
        endpoint: '/notification-history/$mssv/unread-count',
      ).timeout(_timeout);
    }

    if (response == null) throw Exception('Không nhận được phản hồi từ server.');

    if (response.statusCode == 200) {
      final decoded = _safeJsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['success'] == false) return {'unread': 0, 'total': 0};
        final data = decoded['data'];
        if (data == null) return {'unread': 0, 'total': 0};

        if (data is Map) {
          int unread = (data['unread_count'] ?? data['unreadCount'] ?? data['unread'] ?? 0) as int;
          int total = (data['total_count'] ?? data['totalCount'] ?? data['total'] ?? 0) as int;
          return {'unread': unread, 'total': total};
        }
        if (data is int) return {'unread': data, 'total': 0};
      } else if (decoded is int) {
        return {'unread': decoded, 'total': 0};
      }
      return {'unread': 0, 'total': 0};
    } else {
      return {'unread': 0, 'total': 0};
    }
  }

  /// Lấy số lượng thông báo chưa đọc (giữ lại cho tương thích)
  /// GET /notification-history/:mssv/unread-count
  static Future<int> getUnreadCount(BuildContext context) async {
    final stats = await getNotificationStats(context);
    return stats['unread'] ?? 0;
  }

  /// 3. Đánh dấu tất cả thông báo là đã đọc
  /// PATCH /notification-history/:mssv/mark-all-read
  static Future<void> markAllAsRead(BuildContext context) async {
    final mssv = await _getMssv();

    var response = await AuthService.authenticatedRequestNotification(
      method: 'PATCH',
      endpoint: '/notification-history/$mssv/mark-all-read',
    ).timeout(_timeout);

    if (response != null && (response.statusCode == 404 || response.statusCode == 405)) {
      response = await AuthService.authenticatedRequestNotification(
        method: 'PUT',
        endpoint: '/notification_history/$mssv/read-all',
      ).timeout(_timeout);
    }

    if (response == null) throw Exception('Không nhận được phản hồi từ server.');

    if (response.statusCode != 200) {
      final decoded = _safeJsonDecode(response.body);
      final errorMsg = (decoded is Map && decoded['message'] != null)
          ? decoded['message'].toString()
          : 'Không thể đánh dấu đã đọc';
      throw Exception(errorMsg);
    }
  }

  /// 4. Đánh dấu một thông báo cụ thể là đã đọc
  /// PATCH /notification-history/:mssv/mark-read/:id
  static Future<void> markAsRead(BuildContext context, int notificationId) async {
    final mssv = await _getMssv();

    var response = await AuthService.authenticatedRequestNotification(
      method: 'PATCH',
      endpoint: '/notification-history/$mssv/mark-read/$notificationId',
    ).timeout(_timeout);

    if (response != null && (response.statusCode == 404 || response.statusCode == 405)) {
      response = await AuthService.authenticatedRequestNotification(
        method: 'PUT',
        endpoint: '/notification_history/$mssv/read/$notificationId',
      ).timeout(_timeout);
    }

    if (response == null) throw Exception('Không nhận được phản hồi từ server.');

    if (response.statusCode != 200) {
      final decoded = _safeJsonDecode(response.body);
      final errorMsg = (decoded is Map && decoded['message'] != null)
          ? decoded['message'].toString()
          : 'Không thể đánh dấu thông báo đã đọc';
      throw Exception(errorMsg);
    }
  }

  /// 5. Xóa một thông báo cụ thể
  /// DELETE /notification-history/:mssv/delete/:id
  static Future<void> deleteNotification(BuildContext context, int notificationId) async {
    final mssv = await _getMssv();

    var response = await AuthService.authenticatedRequestNotification(
      method: 'DELETE',
      endpoint: '/notification-history/$mssv/delete/$notificationId',
    ).timeout(_timeout);

    if (response != null && (response.statusCode == 404 || response.statusCode == 405)) {
      response = await AuthService.authenticatedRequestNotification(
        method: 'DELETE',
        endpoint: '/notification_history/$mssv/$notificationId',
      ).timeout(_timeout);
    }

    if (response != null && (response.statusCode == 404 || response.statusCode == 405)) {
      response = await AuthService.authenticatedRequestNotification(
        method: 'DELETE',
        endpoint: '/notification-history/$mssv/$notificationId',
      ).timeout(_timeout);
    }

    if (response == null) throw Exception('Không nhận được phản hồi từ server.');

    if (response.statusCode != 204 && response.statusCode != 200) {
      final decoded = _safeJsonDecode(response.body);
      final errorMsg = (decoded is Map && decoded['message'] != null)
          ? decoded['message'].toString()
          : 'Không thể xóa thông báo';
      throw Exception(errorMsg);
    }
  }

  /// 6. Xóa tất cả thông báo của user
  /// DELETE /notification-history/:mssv/delete-all
  static Future<void> deleteAllNotifications(BuildContext context) async {
    final mssv = await _getMssv();

    var response = await AuthService.authenticatedRequestNotification(
      method: 'DELETE',
      endpoint: '/notification-history/$mssv/delete-all',
    ).timeout(_timeout);

    if (response != null && (response.statusCode == 404 || response.statusCode == 405)) {
      response = await AuthService.authenticatedRequestNotification(
        method: 'DELETE',
        endpoint: '/notification_history/$mssv',
      ).timeout(_timeout);
    }

    if (response != null && (response.statusCode == 404 || response.statusCode == 405)) {
      response = await AuthService.authenticatedRequestNotification(
        method: 'DELETE',
        endpoint: '/notification-history/$mssv',
      ).timeout(_timeout);
    }

    if (response == null) throw Exception('Không nhận được phản hồi từ server.');

    if (response.statusCode != 204 && response.statusCode != 200) {
      final decoded = _safeJsonDecode(response.body);
      final errorMsg = (decoded is Map && decoded['message'] != null)
          ? decoded['message'].toString()
          : 'Không thể xóa tất cả thông báo';
      throw Exception(errorMsg);
    }
  }
}

//
// import 'dart:convert';
// import 'dart:ui';
// import 'package:app_tbk/config/api_constants.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:http/http.dart' as http;
// import 'package:timezone/data/latest.dart' as tz;
// import 'package:timezone/timezone.dart' as tz;
// import '../models/notification_history.dart';
//
// class NotificationService {
//   static final _notifications = FlutterLocalNotificationsPlugin();
//   static final _historyDb = NotificationHistoryDatabase.instance;
//
//
//   static Future<void> init() async {
//     // Khởi tạo timezone
//     tz.initializeTimeZones();
//     tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
//
//     const android = AndroidInitializationSettings('@mipmap/ic_launcher');
//     const ios = DarwinInitializationSettings(
//       requestAlertPermission: true,
//       requestBadgePermission: true,
//       requestSoundPermission: true,
//     );
//
//     const initSettings = InitializationSettings(
//       android: android,
//       iOS: ios,
//     );
//
//     await _notifications.initialize(
//       initSettings,
//       onDidReceiveNotificationResponse: _onNotificationTapped,
//     );
//
//     await _createNotificationChannels();
//     print('✅ Notification Service initialized');
//   }
//
//   // ==================== CREATE CHANNELS ====================
//
//   static Future<void> _createNotificationChannels() async {
//     final androidPlugin = _notifications
//         .resolvePlatformSpecificImplementation<
//         AndroidFlutterLocalNotificationsPlugin>();
//
//     if (androidPlugin == null) return;
//
//     await androidPlugin.createNotificationChannel(
//       const AndroidNotificationChannel(
//         'lichhoc_channel',
//         'Lịch học',
//         description: 'Thông báo lịch học hàng ngày',
//         importance: Importance.high,
//         playSound: true,
//         enableVibration: true,
//       ),
//     );
//
//     await androidPlugin.createNotificationChannel(
//       const AndroidNotificationChannel(
//         'lichthi_channel',
//         'Lịch thi',
//         description: 'Thông báo lịch thi quan trọng',
//         importance: Importance.max,
//         playSound: true,
//         enableVibration: true,
//       ),
//     );
//
//     await androidPlugin.createNotificationChannel(
//       const AndroidNotificationChannel(
//         'nhacnho_channel',
//         'Nhắc nhở',
//         description: 'Nhắc nhở trước giờ học/thi',
//         importance: Importance.high,
//         playSound: true,
//       ),
//     );
//   }
//
//   // ==================== HANDLE TAP ====================
//
//   static Future<void> _onNotificationTapped(
//       NotificationResponse response
//       ) async {
//     print('👆 Notification tapped: ${response.payload}');
//
//     if (response.payload != null) {
//       try {
//         final data = jsonDecode(response.payload!);
//         if (data['historyId'] != null) {
//           await _historyDb.markAsRead(data['historyId']);
//         }
//       } catch (e) {
//         print('❌ Error handling notification tap: $e');
//       }
//     }
//   }
//
//   // ==================== SHOW & SAVE ====================
//
//   Future<void> showAndSaveNotification({
//     required int idSinhVien,
//     required String title,
//     required String body,
//     required String loaiLich,
//     Map<String, dynamic>? extraData,
//   }) async {
//     final channelId = _getChannelId(loaiLich);
//     final channelName = _getChannelName(loaiLich);
//     final channelColor = _getChannelColor(loaiLich);
//
//     final androidDetails = AndroidNotificationDetails(
//       channelId,
//       channelName,
//       channelDescription: 'Thông báo $channelName',
//       importance: loaiLich == 'LICHTHI' ? Importance.max : Importance.high,
//       priority: loaiLich == 'LICHTHI' ? Priority.max : Priority.high,
//       icon: '@mipmap/ic_launcher',
//       color: Color(channelColor),
//       playSound: true,
//       enableVibration: true,
//     );
//
//     const iosDetails = DarwinNotificationDetails(
//       presentAlert: true,
//       presentBadge: true,
//       presentSound: true,
//     );
//
//     final details = NotificationDetails(
//       android: androidDetails,
//       iOS: iosDetails,
//     );
//
//     // Lưu vào LOCAL DB
//     int? historyId;
//     try {
//       final notification = NotificationHistory(
//         title: title,
//         body: body,
//         type: _mapLoaiLichToType(loaiLich),
//         sentAt: DateTime.now(),
//         payload: {
//           'idSinhVien': idSinhVien.toString(),
//           'loaiLich': loaiLich,
//           ...?extraData,
//         },
//       );
//
//       historyId = await _historyDb.insert(notification);
//       print('💾 Saved to local DB with ID: $historyId');
//     } catch (e) {
//       print('⚠️ Error saving to local DB: $e');
//     }
//
//     // Hiển thị notification
//     final payload = jsonEncode({
//       'historyId': historyId,
//       'idSinhVien': idSinhVien,
//       'loaiLich': loaiLich,
//       'type': _mapLoaiLichToType(loaiLich),
//       ...?extraData,
//     });
//
//     await _notifications.show(
//       DateTime.now().millisecondsSinceEpoch % 100000,
//       title,
//       body,
//       details,
//       payload: payload,
//     );
//
//     // Lưu về API (async)
//     _saveToApi(
//       idSinhVien: idSinhVien,
//       title: title,
//       body: body,
//       loaiLich: loaiLich,
//     ).catchError((error) {
//       print('⚠️ Lỗi khi lưu về API: $error');
//     });
//   }
//
//   // ==================== SCHEDULE DAILY ====================
//
//   Future<void> scheduleDailyNotification({
//     required int id,
//     required int idSinhVien,
//     required String title,
//     required String body,
//     required String loaiLich,
//     required int hour,
//     required int minute,
//     Map<String, dynamic>? extraData,
//   }) async {
//     final now = tz.TZDateTime.now(tz.local);
//     var scheduled = tz.TZDateTime(
//       tz.local,
//       now.year,
//       now.month,
//       now.day,
//       hour,
//       minute,
//     );
//
//     if (scheduled.isBefore(now)) {
//       scheduled = scheduled.add(const Duration(days: 1));
//     }
//
//     final channelId = _getChannelId(loaiLich);
//     final channelName = _getChannelName(loaiLich);
//     final channelColor = _getChannelColor(loaiLich);
//
//     final androidDetails = AndroidNotificationDetails(
//       channelId,
//       channelName,
//       channelDescription: 'Thông báo $channelName',
//       importance: loaiLich == 'LICHTHI' ? Importance.max : Importance.high,
//       priority: loaiLich == 'LICHTHI' ? Priority.max : Priority.high,
//       icon: '@mipmap/ic_launcher',
//       color: Color(channelColor),
//       playSound: true,
//       enableVibration: true,
//     );
//
//     const iosDetails = DarwinNotificationDetails(
//       presentAlert: true,
//       presentBadge: true,
//       presentSound: true,
//     );
//
//     final details = NotificationDetails(
//       android: androidDetails,
//       iOS: iosDetails,
//     );
//
//     // Lưu vào LOCAL DB
//     int? historyId;
//     try {
//       final notification = NotificationHistory(
//         title: title,
//         body: body,
//         type: _mapLoaiLichToType(loaiLich),
//         sentAt: scheduled,
//         payload: {
//           'idSinhVien': idSinhVien.toString(),
//           'loaiLich': loaiLich,
//           'scheduled': 'true',
//           ...?extraData,
//         },
//       );
//
//       historyId = await _historyDb.insert(notification);
//       print('💾 Scheduled notification saved to DB: $historyId');
//     } catch (e) {
//       print('⚠️ Error saving scheduled notification: $e');
//     }
//
//     final payload = jsonEncode({
//       'historyId': historyId,
//       'idSinhVien': idSinhVien,
//       'loaiLich': loaiLich,
//       'type': _mapLoaiLichToType(loaiLich),
//       'scheduled': 'true',
//       ...?extraData,
//     });
//
//     await _notifications.zonedSchedule(
//       id,
//       title,
//       body,
//       scheduled,
//       details,
//       androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
//       uiLocalNotificationDateInterpretation:
//       UILocalNotificationDateInterpretation.absoluteTime,
//       matchDateTimeComponents: DateTimeComponents.time,
//       payload: payload,
//     );
//
//     print('⏰ Scheduled notification at $hour:$minute for ID: $id');
//
//     _saveScheduledToApi(
//       idSinhVien: idSinhVien,
//       title: title,
//       body: body,
//       loaiLich: loaiLich,
//     ).catchError((error) {
//       print('⚠️ Lỗi khi lưu scheduled notification về API: $error');
//     });
//   }
//
//   // ==================== SCHEDULE ONE-TIME ====================
//
//   Future<void> scheduleOneTimeNotification({
//     required int id,
//     required int idSinhVien,
//     required String title,
//     required String body,
//     required DateTime scheduledTime,
//     String loaiLich = 'NHACNHO',
//     Map<String, dynamic>? extraData,
//   }) async {
//     final scheduled = tz.TZDateTime.from(scheduledTime, tz.local);
//
//     if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) {
//       print('⏭️ Skipping past notification');
//       return;
//     }
//
//     final channelId = _getChannelId(loaiLich);
//     final channelName = _getChannelName(loaiLich);
//     final channelColor = _getChannelColor(loaiLich);
//
//     final androidDetails = AndroidNotificationDetails(
//       channelId,
//       channelName,
//       importance: Importance.high,
//       priority: Priority.high,
//       icon: '@mipmap/ic_launcher',
//       color: Color(channelColor),
//     );
//
//     final details = NotificationDetails(android: androidDetails);
//
//     try {
//       final notification = NotificationHistory(
//         title: title,
//         body: body,
//         type: _mapLoaiLichToType(loaiLich),
//         sentAt: scheduledTime,
//         payload: {
//           'idSinhVien': idSinhVien.toString(),
//           'loaiLich': loaiLich,
//           ...?extraData,
//         },
//       );
//
//       await _historyDb.insert(notification);
//     } catch (e) {
//       print('⚠️ Error saving reminder: $e');
//     }
//
//     await _notifications.zonedSchedule(
//       id,
//       title,
//       body,
//       scheduled,
//       details,
//       androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
//       uiLocalNotificationDateInterpretation:
//       UILocalNotificationDateInterpretation.absoluteTime,
//     );
//
//     print('⏰ One-time notification scheduled at $scheduledTime');
//   }
//
//   // ==================== CANCEL ====================
//
//   Future<void> cancelNotification(int id) async {
//     await _notifications.cancel(id);
//     print('🗑️ Cancelled notification ID: $id');
//   }
//
//   Future<void> cancelAllNotifications() async {
//     await _notifications.cancelAll();
//     print('🗑️ Cancelled all notifications');
//   }
//
//   Future<List<PendingNotificationRequest>> getPendingNotifications() async {
//     return await _notifications.pendingNotificationRequests();
//   }
//
//   // ==================== HELPERS ====================
//
//   static String _getChannelId(String loaiLich) {
//     switch (loaiLich.toUpperCase()) {
//       case 'LICHTHI':
//         return 'lichthi_channel';
//       case 'NHACNHO':
//         return 'nhacnho_channel';
//       case 'LICHHOC':
//       default:
//         return 'lichhoc_channel';
//     }
//   }
//
//   static String _getChannelName(String loaiLich) {
//     switch (loaiLich.toUpperCase()) {
//       case 'LICHTHI':
//         return 'Lịch thi';
//       case 'NHACNHO':
//         return 'Nhắc nhở';
//       case 'LICHHOC':
//       default:
//         return 'Lịch học';
//     }
//   }
//
//   static int _getChannelColor(String loaiLich) {
//     switch (loaiLich.toUpperCase()) {
//       case 'LICHTHI':
//         return 0xFFFF9800;
//       case 'NHACNHO':
//         return 0xFF4CAF50;
//       case 'LICHHOC':
//       default:
//         return 0xFF2196F3;
//     }
//   }
//
//   static String _mapLoaiLichToType(String loaiLich) {
//     switch (loaiLich.toUpperCase()) {
//       case 'LICHTHI':
//         return 'EXAM';
//       case 'NHACNHO':
//         return 'REMINDER';
//       case 'LICHHOC':
//       default:
//         return 'CLASS';
//     }
//   }
//
//   // ==================== API CALLS ====================
//
//   static Future<void> _saveToApi({
//     required int idSinhVien,
//     required String title,
//     required String body,
//     required String loaiLich,
//   }) async {
//     try {
//       // ✅ Lấy headers có Bearer token
//       final headers = await ApiGetToken.getAuthHeaders();
//
//       final url = Uri.parse('${ApiConstants.baseUrl}/thong-bao/save');
//
//       // ✅ Gửi request với headers chuẩn
//       final response = await http.post(
//         url,
//         headers: headers, // DÙNG headers đã có token
//         body: jsonEncode({
//           'idSinhVien': idSinhVien,
//           'title': title,
//           'body': body,
//           'loaiLich': loaiLich,
//           'ngayThongBao': DateTime.now().toIso8601String(),
//         }),
//       );
//
//       if (response.statusCode == 200) {
//         print('✅ Saved to API successfully');
//       } else {
//         print('⚠️ API error ${response.statusCode}: ${response.body}');
//       }
//     } catch (e) {
//       print('❌ Error saving to API: $e');
//       rethrow;
//     }
//   }
//
//
//   static Future<void> _saveScheduledToApi({
//     required int idSinhVien,
//     required String title,
//     required String body,
//     required String loaiLich,
//   }) async {
//     try {
//       final url = Uri.parse(
//         '${ApiConstants.baseUrl}/thoi-khoa-bieu/thong-bao/save',
//       );
//
//       // ✅ Lấy headers có Bearer token
//       final headers = await ApiGetToken.getAuthHeaders();
//
//       final requestBody = {
//         'idSinhVien': idSinhVien,
//         'tieuDe': title,
//         'noiDung': body,
//         'loaiLich': loaiLich,
//         'ngayTao': DateTime.now()
//             .toString()
//             .substring(0, 19)
//             .replaceFirst('T', ' '),
//       };
//
//       final response = await http.post(
//         url,
//         headers: headers,
//         body: jsonEncode(requestBody),
//       );
//
//       print('📡 [API] Save scheduled: ${response.statusCode}');
//       if (response.statusCode == 200) {
//         print('✅ Lưu thông báo lịch học thành công.');
//       } else {
//         print('⚠️ Lỗi khi lưu lịch (${response.statusCode}): ${response.body}');
//       }
//     } catch (e) {
//       print('❌ Lỗi khi gửi thông báo lịch lên API: $e');
//       rethrow;
//     }
//   }
//
//   // ==================== HISTORY MANAGEMENT (PUBLIC METHODS) ====================
//
//   /// Lấy tất cả lịch sử thông báo
//   Future<List<NotificationHistory>> getNotificationHistory({int? limit}) async {
//     return await _historyDb.getAll(limit: limit);
//   }
//
//   /// Lấy lịch sử theo loại
//   Future<List<NotificationHistory>> getHistoryByType(String type) async {
//     return await _historyDb.getByType(type);
//   }
//
//   /// Lấy số thông báo chưa đọc
//   Future<int> getUnreadCount() async {
//     return await _historyDb.getUnreadCount();
//   }
//
//   /// Đánh dấu 1 notification đã đọc
//   Future<void> markNotificationAsRead(int id) async {
//     await _historyDb.markAsRead(id);
//   }
//
//   /// Đánh dấu tất cả đã đọc
//   Future<void> markAllNotificationsAsRead() async {
//     await _historyDb.markAllAsRead();
//   }
//
//   /// Xóa 1 notification
//   Future<void> deleteNotification(int id) async {
//     await _historyDb.delete(id);
//   }
//
//   /// Xóa tất cả lịch sử
//   Future<void> clearNotificationHistory() async {
//     await _historyDb.deleteAll();
//   }
//
//   /// Xóa thông báo cũ hơn X ngày
//   Future<void> cleanOldNotifications({int days = 30}) async {
//     await _historyDb.deleteOlderThan(days);
//   }
//
//   /// Lấy thống kê
//   Future<Map<String, int>> getNotificationStatistics() async {
//     return await _historyDb.getStatistics();
//   }
//
//   // ==================== BACKWARD COMPATIBILITY ====================
//
//   /// Alias methods để tương thích với code cũ
//   Future<List<NotificationHistory>> getHistory({int? limit}) async {
//     return await getNotificationHistory(limit: limit);
//   }
//
//   Future<void> markAsRead(int historyId) async {
//     await markNotificationAsRead(historyId);
//   }
//
//   Future<void> cleanOldHistory({int days = 30}) async {
//     await cleanOldNotifications(days: days);
//   }
//
//   Future<void> clearAllHistory() async {
//     await clearNotificationHistory();
//   }
//
//   Future<Map<String, int>> getStatistics() async {
//     return await getNotificationStatistics();
//   }
// }