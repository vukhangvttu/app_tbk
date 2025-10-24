import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
        print('👆 User tap vào notification: ${response.payload}');
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'Thông báo quan trọng',
      description: 'Kênh thông báo cho lịch học và lịch thi',
      importance: Importance.high,
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
    // 1. Khi app đang MỞ (foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📬 Nhận notification khi app đang mở');
      print('   Title: ${message.notification?.title}');
      print('   Body: ${message.notification?.body}');

      _showLocalNotification(message);
    });

    // 2. Khi app đang ĐÓNG/BACKGROUND
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 3. Khi user TAP vào notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('👆 User tap vào notification');
      print('   Data: ${message.data}');

      _handleNotificationTap(message);
    });

    // 4. Kiểm tra notification khi app vừa mở
    _checkInitialMessage();
  }

  // ========== HIỂN THỊ LOCAL NOTIFICATION ==========
  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;

    if (notification == null) return;

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'Thông báo quan trọng',
          channelDescription: 'Kênh thông báo cho lịch học',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data.toString(),
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
      _handleNotificationTap(initialMessage);
    }
  }

  // ========== GỬI TEST NOTIFICATION ==========
  Future<void> sendTestNotification() async {
    print('📤 Gửi test notification...');
  }
}