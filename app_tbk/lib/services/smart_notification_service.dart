import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// Background handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('📱 Background Message: ${message.messageId}');
}

class AppNotificationSettings {
  final bool enabled;
  final bool scheduleEnabled;
  final int scheduleHour;
  final int scheduleMinute;
  final bool examEnabled;
  final int examHour;
  final int examMinute;
  final int reminderMinutes;
  final int examReminderDays;
  final bool isDefaultSettings; // Thêm flag để đánh dấu là settings mặc định

  AppNotificationSettings({
    required this.enabled,
    required this.scheduleEnabled,
    required this.scheduleHour,
    required this.scheduleMinute,
    required this.examEnabled,
    required this.examHour,
    required this.examMinute,
    required this.reminderMinutes,
    required this.examReminderDays,
    this.isDefaultSettings = false,
  });

  String get scheduleTimeString =>
      '${scheduleHour.toString().padLeft(2, '0')}:${scheduleMinute.toString().padLeft(2, '0')}';
  String get examTimeString =>
      '${examHour.toString().padLeft(2, '0')}:${examMinute.toString().padLeft(2, '0')}';

  AppNotificationSettings copyWith({
    bool? enabled,
    bool? scheduleEnabled,
    int? scheduleHour,
    int? scheduleMinute,
    bool? examEnabled,
    int? examHour,
    int? examMinute,
    int? reminderMinutes,
    int? examReminderDays,
    bool? isDefaultSettings,
  }) {
    return AppNotificationSettings(
      enabled: enabled ?? this.enabled,
      scheduleEnabled: scheduleEnabled ?? this.scheduleEnabled,
      scheduleHour: scheduleHour ?? this.scheduleHour,
      scheduleMinute: scheduleMinute ?? this.scheduleMinute,
      examEnabled: examEnabled ?? this.examEnabled,
      examHour: examHour ?? this.examHour,
      examMinute: examMinute ?? this.examMinute,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      examReminderDays: examReminderDays ?? this.examReminderDays,
      isDefaultSettings: isDefaultSettings ?? this.isDefaultSettings,
    );
  }

  factory AppNotificationSettings.fromJson(Map<String, dynamic> json, {bool isDefault = false}) {
    return AppNotificationSettings(
      enabled: json['enabled'] ?? false,
      scheduleEnabled: json['scheduleEnabled'] ?? true,
      scheduleHour: json['scheduleHour'] ?? 8,
      scheduleMinute: json['scheduleMinute'] ?? 30,
      examEnabled: json['examEnabled'] ?? true,
      examHour: json['examHour'] ?? 6,
      examMinute: json['examMinute'] ?? 0,
      reminderMinutes: json['reminderMinutes'] ?? 30,
      examReminderDays: json['examReminderDays'] ?? 3,
      isDefaultSettings: isDefault,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'scheduleEnabled': scheduleEnabled,
      'scheduleHour': scheduleHour,
      'scheduleMinute': scheduleMinute,
      'examEnabled': examEnabled,
      'examHour': examHour,
      'examMinute': examMinute,
      'reminderMinutes': reminderMinutes,
      'examReminderDays': examReminderDays,
    };
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
    scheduleMinute: 30,
    examEnabled: true,
    examHour: 6,
    examMinute: 0,
    reminderMinutes: 30,
    examReminderDays: 3,
    isDefaultSettings: true,
  );

  Future<AppNotificationSettings> getSettings({String mssv = '7231620971'}) async {
    try {
      final response = await http.get(
        Uri.parse('http://192.168.1.120:8080/notification-service/api/users/get-settings/$mssv'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Request to get settings timed out');
        },
      );

      print('🔍 API get-settings response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;

        final bool success = jsonResponse['success'] ?? false;
        final dynamic data = jsonResponse['data'];

        if (success && data != null) {
          print('✅ User has saved settings from server');
          return AppNotificationSettings.fromJson(data, isDefault: false);
        } else {
          // API trả về success=false hoặc không có data
          print('⚠️ No user settings found, using default (disabled)');
          return defaultSettings;
        }
      } else {
        // Các lỗi HTTP khác
        print('⚠️ API error: ${response.statusCode}, using default (disabled)');
        return defaultSettings;
      }
    } catch (e) {
      print('❌ Error fetching settings: $e, using default (disabled)');
      return defaultSettings;
    }
  }


  Future<void> saveSettings(AppNotificationSettings settings, {String mssv = '7231620971'}) async {
    try {
      // Lưu cục bộ
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notification_settings', jsonEncode(settings.toJson()));
      print('💾 Saved settings locally: ${settings.toJson()}');

      // Gửi tới API
      final settingsData = settings.toJson();
      settingsData['mssv'] = mssv;

      final response = await http.put(
        Uri.parse('http://192.168.0.9:8080/notification-service/api/users/$mssv/settings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(settingsData),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Request to save settings timed out');
        },
      );

      print('🔍 API save-settings response: ${response.statusCode} - ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Failed to save settings to server: ${response.statusCode} - ${response.body}');
      }

      print('✅ Settings saved successfully to server');
    } catch (e) {
      print('❌ Error saving settings: $e');
      rethrow;
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
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    _checkInitialMessage();
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('📬 Foreground message: ${message.notification?.title}');

    await _localNotifications.show(
      message.notification.hashCode,
      message.notification?.title,
      message.notification?.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          message.data['channel'] ?? 'schedule_channel',
          message.data['channelName'] ?? 'Thông báo',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleNotificationTap(dynamic response) {
    String? payload;
    if (response is NotificationResponse) {
      payload = response.payload;
    } else if (response is RemoteMessage) {
      payload = jsonEncode(response.data);
    }

    if (payload != null) {
      final data = jsonDecode(payload);
      print('👆 Notification tapped: ${data['type']}');
      // TODO: Navigate to appropriate screen
    }
  }

  Future<void> _checkInitialMessage() async {
    RemoteMessage? message = await _messaging.getInitialMessage();
    if (message != null) {
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
  }) async {
    final settings = await getSettings();

    if (!settings.enabled) return;
    if (isExam && !settings.examEnabled) return;
    if (!isExam && !settings.scheduleEnabled) return;

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
        settings: settings,
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
        settings: settings,
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
  }) async {
    final settings = await getSettings();

    if (!settings.enabled || !settings.examEnabled) return;

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