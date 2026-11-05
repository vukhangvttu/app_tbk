import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:app_tbk/features/auth/services/auth_service.dart';
import 'package:app_tbk/features/notification-setting/models/notification.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'notification_tracking_service.dart';

// Background handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('📱 Background Message: ${message.messageId}');

  final notificationId = NotificationTrackingService.extractNotificationId(message.data);
  if (notificationId != null) {
    await NotificationTrackingService.reportDelivered(notificationId);
  }
}


class SmartNotificationService {
  static final SmartNotificationService _instance = SmartNotificationService._internal();
  factory SmartNotificationService() => _instance;
  SmartNotificationService._internal();

  static SmartNotificationService get instance => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  // Giá trị mặc định - LUÔN TẮT khi chưa có settings từ API
  AppNotificationSettings get defaultSettings => AppNotificationSettings(
    enabled: false, // TẮT mặc định
    scheduleEnabled: true,
    scheduleHour: 8,
    scheduleMinute: 0,
    examEnabled: true,
    examHour: 8,
    examMinute: 0,
    reminderMinutes: 30,
    examReminderDays: 3,
    isDefaultSettings: true,
      attendanceInEnabled: true,
      attendanceInMinutes: 5,
      attendanceOutEnabled: true,
      attendanceOutMinutes: 5

  );

  Future<AppNotificationSettings?> getSettings(String mssv) async {
    try {
      // Sử dụng mssv được truyền vào thay vì lấy lại từ AuthService
      if (mssv.isEmpty) {
        debugPrint('ProfileService: MSSV không hợp lệ');
        return null;
      }

      final response = await AuthService.authenticatedRequestNotification(
        method: 'GET',
        endpoint: '/users/get-settings/$mssv',
      );

      // Kiểm tra response có null không
      if (response == null) {
        debugPrint('ProfileService: Không nhận được phản hồi từ server');
        return null;
      }

      // Parse JSON an toàn
      final Map<String, dynamic> jsonMap = jsonDecode(response.body);

      // Kiểm tra success
      final bool success = jsonMap['success'] == true;
      if (!success) {
        final message = jsonMap['message'] ?? 'Lấy cài đặt thất bại';
        debugPrint('ProfileService: $message');
        return null;
      }

      // Lấy data
      final dynamic data = jsonMap['data'];
      if (data == null || data is! Map<String, dynamic>) {
        debugPrint('ProfileService: Dữ liệu data không hợp lệ hoặc rỗng');
        return null;
      }

      // Parse thành NotificationSettings
      return AppNotificationSettings.fromJson(data);

    } catch (e) {
      debugPrint('ProfileService.fetchProfile Error: $e');
      // Không throw nữa → trả về null để UI xử lý gracefully
      return null;
    }
  }

  /// Lưu cài đặt thông báo – đồng nhất với toàn bộ dự án
  static Future<void> saveSettings(AppNotificationSettings settings) async {
    try {
      // 1. Lấy MSSV hiện tại (đã lưu khi login)
      final mssv = await AuthService.getSavedMssv();
      if (mssv == null || mssv.isEmpty) {
        throw Exception('Không tìm thấy MSSV của người dùng');
      }

      // 2. Lưu cục bộ trước (offline-first)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notification_settings', jsonEncode(settings.toJson()));
      debugPrint('NotificationService: Đã lưu cài đặt cục bộ');

      // 3. Chuẩn bị dữ liệu gửi lên server
      final Map<String, dynamic> payload = settings.toJson();
      payload['mssv'] = mssv; // backend yêu cầu trường mssv

      debugPrint('NotificationService: Đang gửi cài đặt lên server cho MSSV: $mssv');

      // 4. Gọi API bằng AuthService (tự động thêm token, baseURL, retry, v.v.)
      final response = await AuthService.authenticatedRequestNotification(
        method: 'PUT',
        endpoint: '/users/$mssv/settings', // Đúng route bạn đang dùng
        body: jsonEncode(payload),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Lưu cài đặt thông báo quá thời gian chờ');
        },
      );

      // 5. Kiểm tra response
      if (response == null) {
        debugPrint('NotificationService: Không nhận được phản hồi từ server');
        // Vẫn coi là thành công cục bộ → không rethrow để tránh làm hỏng UI
        return;
      }

      debugPrint('NotificationService: Save response ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
        final success = jsonResponse['success'] == true;

        if (success) {
          debugPrint('NotificationService: Lưu cài đặt lên server thành công');
        } else {
          final msg = jsonResponse['message'] ?? 'Unknown error';
          debugPrint('NotificationService: Server trả về success=false: $msg');
          // Không rethrow → vẫn giữ cài đặt cục bộ
        }
      } else {
        debugPrint('NotificationService: Lỗi HTTP ${response.statusCode}');
        // Không rethrow → người dùng vẫn dùng được cài đặt offline
      }
    } on TimeoutException catch (e) {
      debugPrint('NotificationService: Timeout khi lưu cài đặt: $e');
      // Không rethrow → vẫn lưu được local
    } catch (e) {
      debugPrint('NotificationService: Lỗi khi lưu cài đặt: $e');
      // Không rethrow để tránh crash UI
      // Người dùng vẫn có cài đặt cục bộ → trải nghiệm không bị gián đoạn
    }
  }
  // ==================== KHỞI TẠO ====================
  Future<void> initialize() async {
    try {
      print('🔥 Khởi tạo Smart Notification Service...');

      await Firebase.initializeApp();
      tz.initializeTimeZones();

      await _requestPermission();
      await _getFCMToken();
      await _setupLocalNotifications();
      _setupMessageHandlers();

      print('✅ Smart Notification Service ready!');
    } catch (e) {
      print('❌ Error initializing: $e');
    }
  }

  Future<void> _requestPermission() async {
    final NotificationSettings permissionSettings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (permissionSettings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ Notification permission granted');
    } else {
      print('⚠️ Notification permission denied');
    }
  }

  Future<void> _getFCMToken() async {
    _fcmToken = await _messaging.getToken();
    print('📱 FCM Token: $_fcmToken');

    _messaging.onTokenRefresh.listen((newToken) {
      _fcmToken = newToken;
      print('🔄 Token refreshed: $newToken');
    });
  }

  Future<void> _setupLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    // Create notification channels
    const List<AndroidNotificationChannel> channels = [
      AndroidNotificationChannel(
        'schedule_channel',
        'Lịch học',
        description: 'Thông báo nhắc nhở lịch học hàng ngày',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        'exam_channel',
        'Lịch thi',
        description: 'Thông báo nhắc nhở lịch thi quan trọng',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        'reminder_channel',
        'Nhắc nhở trước giờ',
        description: 'Nhắc nhở trước giờ học/thi',
        importance: Importance.high,
        playSound: true,
      ),
      AndroidNotificationChannel(
        'exam_advance_channel',
        'Nhắc trước kỳ thi',
        description: 'Nhắc nhở trước nhiều ngày kỳ thi',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    ];

    for (var channel in channels) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  void _setupMessageHandlers() {
    // Lưu ý: Các sự kiện tin nhắn FCM trực tiếp (foreground/background)
    // được xử lý duy nhất bởi SimpleFirebaseService để tránh hiển thị trùng lặp thông báo local.
  }

  void _handleNotificationTap(dynamic response) {
    String? payload;
    if (response is NotificationResponse) {
      if (response.payload == null || response.payload!.trim().isEmpty) return;
      payload = response.payload;
    } else if (response is RemoteMessage) {
      if (response.data.isEmpty && response.notification == null) return;
      payload = jsonEncode(response.data);
    }

    if (payload != null && payload.trim().isNotEmpty) {
      try {
        final data = jsonDecode(payload);
        if (data is Map<String, dynamic> && data.isNotEmpty) {
          print('👆 Notification tapped: ${data['type']}');
          final notificationId = NotificationTrackingService.extractNotificationId(data);
          if (notificationId != null) {
            NotificationTrackingService.reportOpened(notificationId);
          }
        }
      } catch (e) {
        print('Lỗi parse payload tap notification: $e');
      }
    }
  }

  Future<void> _checkInitialMessage() async {
    RemoteMessage? message = await _messaging.getInitialMessage();
    if (message != null) {
      final title = message.notification?.title ?? message.data['title'] ?? message.data['tieuDe'];
      final body = message.notification?.body ?? message.data['body'] ?? message.data['noiDung'];
      if ((title == null || title.toString().trim().isEmpty) &&
          (body == null || body.toString().trim().isEmpty) &&
          message.data.isEmpty) {
        return;
      }
      _handleNotificationTap(message);
    }
  }

  // ==================== SCHEDULE NOTIFICATIONS ====================

  Future<void> scheduleForClass({
    required int id,
    required String tenMon,
    required DateTime ngayHoc,
    required String gioHoc,
    required String phongHoc,
    required bool isExam,
    required String mssv, // Thêm tham số mssv bắt buộc
  }) async {
    final settings = await getSettings(mssv); // Truyền mssv vào getSettings

    // Nếu không lấy được settings, sử dụng defaultSettings
    final effectiveSettings = settings ?? defaultSettings;

    if (!effectiveSettings.enabled) return;
    if (isExam && !effectiveSettings.examEnabled) return;
    if (!isExam && !effectiveSettings.scheduleEnabled) return;

    // Parse giờ học (VD: "07:00")
    final timeParts = gioHoc.split(':');
    final classHour = int.tryParse(timeParts[0]) ?? 7;
    final classMinute = int.tryParse(timeParts[1]) ?? 0;

    if (isExam) {
      await _scheduleExamNotifications(
        id: id,
        tenMon: tenMon,
        ngayThi: ngayHoc,
        gioThi: gioHoc,
        phongThi: phongHoc,
        classHour: classHour,
        classMinute: classMinute,
        settings: effectiveSettings,
      );
    } else {
      await _scheduleClassNotifications(
        id: id,
        tenMon: tenMon,
        ngayHoc: ngayHoc,
        gioHoc: gioHoc,
        phongHoc: phongHoc,
        classHour: classHour,
        classMinute: classMinute,
        settings: effectiveSettings,
      );
    }
  }

  Future<void> _scheduleClassNotifications({
    required int id,
    required String tenMon,
    required DateTime ngayHoc,
    required String gioHoc,
    required String phongHoc,
    required int classHour,
    required int classMinute,
    required AppNotificationSettings settings,
  }) async {
    // 1. Thông báo hàng ngày
    DateTime dailyNotificationTime = DateTime(
      ngayHoc.year,
      ngayHoc.month,
      ngayHoc.day,
      settings.scheduleHour,
      settings.scheduleMinute,
    );

    if (dailyNotificationTime.isAfter(DateTime.now())) {
      await _scheduleNotification(
        id: id,
        title: '📘 Lịch học hôm nay',
        body: '$tenMon - $gioHoc tại $phongHoc',
        scheduledTime: dailyNotificationTime,
        channel: 'schedule_channel',
        payload: jsonEncode({
          'type': 'CLASS',
          'id': id,
          'tenMon': tenMon,
        }),
      );
      print('✅ Scheduled CLASS daily notification at ${settings.scheduleTimeString}');
    }

    // 2. Nhắc nhở trước giờ học
    if (settings.reminderMinutes > 0) {
      DateTime reminderTime = DateTime(
        ngayHoc.year,
        ngayHoc.month,
        ngayHoc.day,
        classHour,
        classMinute,
      ).subtract(Duration(minutes: settings.reminderMinutes));

      if (reminderTime.isAfter(DateTime.now())) {
        await _scheduleNotification(
          id: id + 100000,
          title: '⏰ Sắp đến giờ học',
          body: '$tenMon sẽ bắt đầu sau ${settings.reminderMinutes} phút',
          scheduledTime: reminderTime,
          channel: 'reminder_channel',
          payload: jsonEncode({
            'type': 'REMINDER',
            'id': id,
            'tenMon': tenMon,
          }),
        );
        print('✅ Scheduled CLASS reminder ${settings.reminderMinutes} mins before');
      }
    }
  }

  Future<void> _scheduleExamNotifications({
    required int id,
    required String tenMon,
    required DateTime ngayThi,
    required String gioThi,
    required String phongThi,
    required int classHour,
    required int classMinute,
    required AppNotificationSettings settings,
  }) async {
    // 1. Thông báo ngày thi
    DateTime examDayNotifTime = DateTime(
      ngayThi.year,
      ngayThi.month,
      ngayThi.day,
      settings.examHour,
      settings.examMinute,
    );

    if (examDayNotifTime.isAfter(DateTime.now())) {
      await _scheduleNotification(
        id: id,
        title: '🧾 Hôm nay bạn có thi',
        body: '$tenMon - $gioThi tại $phongThi',
        scheduledTime: examDayNotifTime,
        channel: 'exam_channel',
        payload: jsonEncode({
          'type': 'EXAM',
          'id': id,
          'tenMon': tenMon,
        }),
      );
      print('✅ Scheduled EXAM day notification at ${settings.examTimeString}');
    }

    // 2. Nhắc nhở trước giờ thi
    if (settings.reminderMinutes > 0) {
      DateTime examReminderTime = DateTime(
        ngayThi.year,
        ngayThi.month,
        ngayThi.day,
        classHour,
        classMinute,
      ).subtract(Duration(minutes: settings.reminderMinutes));

      if (examReminderTime.isAfter(DateTime.now())) {
        await _scheduleNotification(
          id: id + 100000,
          title: '⏰ Sắp đến giờ thi',
          body: '$tenMon sẽ bắt đầu sau ${settings.reminderMinutes} phút',
          scheduledTime: examReminderTime,
          channel: 'reminder_channel',
          payload: jsonEncode({
            'type': 'EXAM_REMINDER',
            'id': id,
            'tenMon': tenMon,
          }),
        );
        print('✅ Scheduled EXAM reminder ${settings.reminderMinutes} mins before');
      }
    }

    // 3. Nhắc nhở trước kỳ thi (nếu bật)
    if (settings.examReminderDays > 0) {
      for (int i = 1; i <= settings.examReminderDays; i++) {
        DateTime notifyAt = ngayThi.subtract(Duration(days: i));
        notifyAt = DateTime(
          notifyAt.year,
          notifyAt.month,
          notifyAt.day,
          settings.examHour,
          settings.examMinute,
        );

        if (notifyAt.isAfter(DateTime.now())) {
          await _scheduleNotification(
            id: id + 200000 + i,
            title: '📅 Sắp đến kỳ thi',
            body: 'Còn $i ngày nữa: $tenMon vào ${_formatDate(ngayThi)} tại $phongThi',
            scheduledTime: notifyAt,
            channel: 'exam_advance_channel',
            payload: jsonEncode({
              'type': 'EXAM_ADVANCE',
              'id': id,
              'tenMon': tenMon,
              'daysAhead': i,
            }),
          );
          print('✅ Scheduled advance exam reminder: $tenMon ($i days ahead)');
        }
      }
    }
  }

  Future<void> scheduleAdvanceExamReminder({
    required int id,
    required String tenMon,
    required DateTime ngayThi,
    required String phongThi,
    required int daysAhead,
    required DateTime notifyAt,
    required String mssv, // Thêm tham số mssv bắt buộc
  }) async {
    final settings = await getSettings(mssv); // Truyền mssv vào getSettings

    // Nếu không lấy được settings, sử dụng defaultSettings
    final effectiveSettings = settings ?? defaultSettings;

    if (!effectiveSettings.enabled || !effectiveSettings.examEnabled) return;

    if (notifyAt.isAfter(DateTime.now())) {
      await _scheduleNotification(
        id: id + 200000 + daysAhead,
        title: '📅 Sắp đến kỳ thi',
        body: 'Còn $daysAhead ngày nữa: $tenMon vào ${_formatDate(ngayThi)} tại $phongThi',
        scheduledTime: notifyAt,
        channel: 'exam_advance_channel',
        payload: jsonEncode({
          'type': 'EXAM_ADVANCE',
          'id': id,
          'tenMon': tenMon,
          'daysAhead': daysAhead,
        }),
      );
      print('✅ Scheduled advance exam reminder: $tenMon ($daysAhead days ahead)');
    }
  }

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String channel,
    String? payload,
  }) async {
    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(
      scheduledTime,
      tz.local,
    );

    await _localNotifications.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          _getChannelName(channel),
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF2196F3),
          playSound: true,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  String _getChannelName(String channel) {
    switch (channel) {
      case 'exam_channel':
        return 'Lịch thi';
      case 'exam_advance_channel':
        return 'Nhắc trước kỳ thi';
      case 'reminder_channel':
        return 'Nhắc nhở';
      default:
        return 'Lịch học';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> cancelAllNotifications() async {
    await _localNotifications.cancelAll();
    print('🗑️ All notifications cancelled');
  }

  Future<void> cancelNotificationForClass(int id) async {
    await _localNotifications.cancel(id);
    await _localNotifications.cancel(id + 100000);
    for (int i = 1; i <= 7; i++) {
      await _localNotifications.cancel(id + 200000 + i);
    }
    print('🗑️ Cancelled all notifications for class $id');
  }

  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _localNotifications.pendingNotificationRequests();
  }
}
