import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_tracking_service.dart';

// ========== HÀM XỬ LÝ BACKGROUND MESSAGES ==========
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyBo1emgmzYTujE6mg6meIT-nB26Vr9g9o0',
      appId: '1:73761905325:android:3a5882bcd0b655945ec424',
      messagingSenderId: '73761905325',
      projectId: 'app-tbk-3a077',
      storageBucket: 'app-tbk-3a077.firebasestorage.app',
    ),
  );
  print('📱 Nhận được notification trong background: ${message.notification?.title}');
  print('📦 Dữ liệu Notification: ${message.notification?.toMap()}');
  print('📦 Dữ liệu Data Payload: ${message.data}');

  // Báo DELIVERED về Go Server khi nhận background notification
  final notificationId = NotificationTrackingService.extractNotificationId(message.data);
  if (notificationId != null) {
    await NotificationTrackingService.reportDelivered(notificationId);
  }

  // CHỈ hiển thị Local Notification nếu FCM message KHÔNG có notification object (tức là data-only payload).
  // Nếu FCM message có notification object, Android FCM SDK đã TỰ ĐỘNG hiển thị thông báo trên thanh trạng thái.
  if (message.notification == null) {
    String soundId = message.data['sound'] ?? 'system';
    if (soundId.endsWith('.mp3')) soundId = soundId.substring(0, soundId.length - 4);
    if (soundId == 'default') soundId = 'system';

    final dedupKey = NotificationTrackingService.getDedupKey(message.data);
    final int notifIntId = dedupKey != null ? dedupKey.hashCode : message.hashCode;

    final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
    final channelId = soundId != 'system' ? 'custom_channel_$soundId' : 'high_importance_channel';

    await localNotifications.show(
      notifIntId,
      message.data['title'] ?? message.data['tieuDe'] ?? message.data['tieu_de'] ?? 'Thông báo',
      message.data['body'] ?? message.data['noiDung'] ?? message.data['noi_dung'] ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Thông báo',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          sound: soundId != 'system' ? RawResourceAndroidNotificationSound(soundId) : null,
        ),
      ),
    );
  }
}

// ========== CLASS QUẢN LÝ FIREBASE ==========
class SimpleFirebaseService {
  // Singleton pattern
  static final SimpleFirebaseService _instance = SimpleFirebaseService._internal();
  static SimpleFirebaseService get instance => _instance;
  SimpleFirebaseService._internal();

  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  // Set theo dõi các notification / event đã hiển thị local notification để chống trùng lặp
  static final Set<String> _shownDedupKeys = {};

  static bool isAlreadyShown(Map<String, dynamic> data) {
    final dedupKey = NotificationTrackingService.getDedupKey(data);
    if (dedupKey == null) return false;
    if (_shownDedupKeys.contains(dedupKey)) return true;
    _shownDedupKeys.add(dedupKey);
    if (_shownDedupKeys.length > 200) {
      _shownDedupKeys.remove(_shownDedupKeys.first);
    }
    return false;
  }

  // ========== KHỞI TẠO FIREBASE ==========
  Future<void> initialize() async {
    try {
      print('🔥 Bắt đầu khởi tạo Firebase...');

      // Khởi tạo Firebase với FirebaseOptions thủ công
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyBo1emgmzYTujE6mg6meIT-nB26Vr9g9o0',
          appId: '1:73761905325:android:3a5882bcd0b655945ec424',
          messagingSenderId: '73761905325',
          projectId: 'app-tbk-3a077',
          storageBucket: 'app-tbk-3a077.firebasestorage.app',
        ),
      );
      print('✅ Firebase initialized');

      _messaging = FirebaseMessaging.instance;
      await _requestPermission();
      await _getFCMToken();
      await _setupLocalNotifications();
      _setupMessageHandlers();
      print('✅ Firebase Service hoàn tất!');
    } catch (e) {
      print('❌ Lỗi khởi tạo Firebase: $e');
    }
  }
  // ========== XIN QUYỀN THÔNG BÁO ==========
  Future<void> _requestPermission() async {
    print('📱 Xin quyền thông báo...');

    NotificationSettings settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ User cho phép thông báo');
    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      print('⚠️ User cho phép tạm thời');
    } else {
      print('❌ User từ chối thông báo');
    }
  }

  // ========== LẤY FCM TOKEN ==========
  Future<void> _getFCMToken() async {
    try {
      _fcmToken = await _messaging!.getToken();
      print('📱 FCM Token: $_fcmToken');

      // Lắng nghe khi token thay đổi
      _messaging!.onTokenRefresh.listen((newToken) {
        print('🔄 Token mới: $newToken');
        _fcmToken = newToken;
      });
    } catch (e) {
      print('❌ Lỗi lấy FCM token: $e');
    }
  }

  // ========== SETUP LOCAL NOTIFICATIONS ==========
  Future<void> _setupLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
    DarwinInitializationSettings(
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
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('👆 User tap vào local notification: ${response.payload}');
        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            final data = jsonDecode(response.payload!);
            if (data is Map<String, dynamic>) {
              final notificationId = NotificationTrackingService.extractNotificationId(data);
              if (notificationId != null) {
                NotificationTrackingService.reportOpened(notificationId);
              }
            }
          } catch (e) {
            print('Lỗi parse payload tap local notification: $e');
          }
        }
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'Thông báo quan trọng',
      description: 'Kênh thông báo cho lịch học và lịch thi',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    print('✅ Local Notifications setup xong');
  }

  // ========== LẮNG NGHE MESSAGES ==========
  void _setupMessageHandlers() {
    // 1. Khi app đang MỞ (foreground -> DELIVERED)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📬 Nhận notification khi app đang mở');
      print('   Notification Title: ${message.notification?.title}');
      print('   Notification Body: ${message.notification?.body}');
      print('   Data Payload: ${message.data}');

      final notificationId = NotificationTrackingService.extractNotificationId(message.data);
      if (notificationId != null) {
        NotificationTrackingService.reportDelivered(notificationId);
      }

      _showLocalNotification(message);
    });

    // 2. Khi app đang ĐÓNG/BACKGROUND
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 3. Khi user TAP vào notification (OPENED)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('👆 User tap vào notification');
      print('   Data: ${message.data}');

      final notificationId = NotificationTrackingService.extractNotificationId(message.data);
      if (notificationId != null) {
        NotificationTrackingService.reportOpened(notificationId);
      }

      _handleNotificationTap(message);
    });

    // 4. Kiểm tra notification khi app vừa mở
    _checkInitialMessage();
  }

  // ========== HIỂN THỊ LOCAL NOTIFICATION ==========
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final dedupKey = NotificationTrackingService.getDedupKey(message.data);
    if (dedupKey != null && isAlreadyShown(message.data)) {
      print('⏭️ Bỏ qua Local Notification trùng lặp (dedupKey: $dedupKey)');
      return;
    }

    String? title = message.notification?.title ?? 
        message.data['title']?.toString() ?? 
        message.data['tieuDe']?.toString() ?? 
        message.data['tieu_de']?.toString();

    String? body = message.notification?.body ?? 
        message.data['body']?.toString() ?? 
        message.data['noiDung']?.toString() ?? 
        message.data['noi_dung']?.toString();

    if (title == null && body == null) {
      print('⚠️ Không có title/body để hiển thị notification');
      return;
    }

    String soundId = message.data['sound'] ?? message.notification?.android?.sound ?? 'system';
    if (soundId.endsWith('.mp3')) soundId = soundId.substring(0, soundId.length - 4);
    if (soundId == 'default') soundId = 'system';

    final String channelId = soundId != 'system' ? 'custom_channel_$soundId' : 'high_importance_channel';

    final int notifIntId = dedupKey != null
        ? dedupKey.hashCode
        : (message.messageId?.hashCode ?? message.hashCode);

    await _localNotifications.show(
      notifIntId,
      title ?? 'Thông báo',
      body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Thông báo quan trọng',
          channelDescription: 'Kênh thông báo cho lịch học',
          importance: Importance.max,
          priority: Priority.max,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          sound: soundId != 'system' ? RawResourceAndroidNotificationSound(soundId) : null,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: soundId != 'system' ? '$soundId.mp3' : null,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  // ========== XỬ LÝ KHI TAP NOTIFICATION ==========
  void _handleNotificationTap(RemoteMessage message) {
    String? type = message.data['type'];

    print('🔔 Notification type: $type');

    switch (type) {
      case 'LICH_HOC':
        print('→ Chuyển đến màn hình lịch học');
        break;
      case 'LICH_THI':
        print('→ Chuyển đến màn hình lịch thi');
        break;
      case 'DIEM':
        print('→ Chuyển đến màn hình điểm');
        break;
      default:
        print('→ Mở app bình thường');
    }
  }

  // ========== KIỂM TRA NOTIFICATION KHI APP VỪA MỞ ==========
  Future<void> _checkInitialMessage() async {
    RemoteMessage? initialMessage = await _messaging!.getInitialMessage();

    if (initialMessage != null) {
      print('🚀 App được mở từ notification');
      final notificationId = NotificationTrackingService.extractNotificationId(initialMessage.data);
      if (notificationId != null) {
        NotificationTrackingService.reportOpened(notificationId);
      }
      _handleNotificationTap(initialMessage);
    }
  }

  // ========== GỬI TEST NOTIFICATION ==========
  Future<void> sendTestNotification() async {
    print('📤 Gửi test notification...');
  }
}