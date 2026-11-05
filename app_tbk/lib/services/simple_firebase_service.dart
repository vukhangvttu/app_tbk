import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';
import 'notification_tracking_service.dart';

// ========== HÀM XỬ LÝ BACKGROUND MESSAGES ==========
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('📱 Nhận được notification trong background: ${message.notification?.title}');
  print('📦 Dữ liệu Notification: ${message.notification?.toMap()}');
  print('📦 Dữ liệu Data Payload: ${message.data}');

  // Báo DELIVERED về Go Server khi nhận background notification
  final notificationId = NotificationTrackingService.extractNotificationId(message.data);
  if (notificationId != null) {
    await NotificationTrackingService.reportDelivered(notificationId);
  }

  // Lấy title và body từ notification hoặc data payload
  final title = (message.notification?.title ??
          message.data['title'] ??
          message.data['tieuDe'] ??
          message.data['tieu_de'] ??
          '').toString().trim();

  final body = (message.notification?.body ??
          message.data['body'] ??
          message.data['noiDung'] ??
          message.data['noi_dung'] ??
          '').toString().trim();

  // Bỏ qua nếu cả tiêu đề và nội dung đều rỗng (tránh hiển thị thông báo rỗng)
  if (title.isEmpty && body.isEmpty) {
    print('⚠️ Bỏ qua background notification rỗng');
    return;
  }

  // CHỈ hiển thị Local Notification nếu FCM message KHÔNG có notification object (tức là data-only payload).
  if (message.notification == null) {
    String soundId = message.data['sound'] ?? 'system';
    if (soundId.endsWith('.mp3')) soundId = soundId.substring(0, soundId.length - 4);
    if (soundId == 'default') soundId = 'system';

    final dedupKey = NotificationTrackingService.getDedupKey(message.data);
    final int notifIntId = dedupKey != null ? dedupKey.hashCode : message.hashCode;

    final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
    final channelId = soundId != 'system' ? 'custom_channel_$soundId' : 'high_importance_channel';

    final androidPlugin = localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    final channel = AndroidNotificationChannel(
      channelId,
      'Thông báo quan trọng',
      description: 'Kênh thông báo cho lịch học và lịch thi',
      importance: Importance.max,
      playSound: true,
      sound: soundId != 'system' ? RawResourceAndroidNotificationSound(soundId) : null,
      enableVibration: true,
    );

    await androidPlugin?.createNotificationChannel(channel);

    await localNotifications.show(
      notifIntId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Thông báo quan trọng',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          sound: soundId != 'system' ? RawResourceAndroidNotificationSound(soundId) : null,
          enableVibration: true,
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
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // StreamController để phát sự kiện khi nhận notification ở foreground
  final StreamController<RemoteMessage> _messageStreamController =
      StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get onMessageReceived => _messageStreamController.stream;

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
    if (_isInitialized) {
      print('⏭️ SimpleFirebaseService already initialized in this session');
      return;
    }

    try {
      print('🔥 Bắt đầu khởi tạo Firebase...');

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('✅ Firebase initialized');

      _messaging = FirebaseMessaging.instance;
      await _requestPermission();
      await _getFCMToken();
      await _setupLocalNotifications();
      _setupMessageHandlers();
      _isInitialized = true;
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

    // Đảm bảo hiển thị thông báo khi app đang ở foreground (kể cả trên iOS / Android)
    await _messaging!.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
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
      if (Platform.isIOS) {
        print('🍎 Waiting for APNs token on iOS...');
        String? apnsToken = await _messaging!.getAPNSToken();
        int retry = 0;
        while (apnsToken == null && retry < 10) {
          await Future.delayed(const Duration(seconds: 1));
          apnsToken = await _messaging!.getAPNSToken();
          retry++;
        }
        if (apnsToken != null) {
          print('✅ APNs token received: $apnsToken');
        } else {
          print('⚠️ APNs token is null on iOS. FCM token might fail.');
        }
      }

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
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('👆 User tap vào local notification: ${response.payload}');
        if (response.payload != null && response.payload!.trim().isNotEmpty) {
          try {
            final data = jsonDecode(response.payload!);
            if (data is Map<String, dynamic> && data.isNotEmpty) {
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

    // Đảm bảo xin quyền thông báo trên Android 13+ (API 33+)
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      
      const channel = AndroidNotificationChannel(
        'high_importance_channel',
        'Thông báo quan trọng',
        description: 'Kênh thông báo cho lịch học và lịch thi',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await androidPlugin.createNotificationChannel(channel);
    }

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

      // Phát sự kiện ra Stream để UI (NotificationHistoryScreen,...) tự động làm mới
      _messageStreamController.add(message);

      showLocalNotification(message);
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
  Future<void> showLocalNotification(RemoteMessage message) async {
    try {
      final dedupKey = NotificationTrackingService.getDedupKey(message.data);
      if (dedupKey != null && isAlreadyShown(message.data)) {
        print('⏭️ Bỏ qua Local Notification trùng lặp (dedupKey: $dedupKey)');
        return;
      }

      String title = (message.notification?.title ??
              message.data['title'] ??
              message.data['tieuDe'] ??
              message.data['tieu_de'] ??
              '').toString().trim();

      String body = (message.notification?.body ??
              message.data['body'] ??
              message.data['noiDung'] ??
              message.data['noi_dung'] ??
              '').toString().trim();

      // Nếu cả 2 đều rỗng thì bỏ qua
      if (title.isEmpty && body.isEmpty) {
        print('⚠️ Không có title/body để hiển thị notification (bỏ qua)');
        return;
      }

      // Đảm bảo không truyền chuỗi rỗng làm title/body
      if (title.isEmpty) title = 'Thông báo';
      if (body.isEmpty) body = 'Bạn có thông báo mới';

      String soundId = message.data['sound'] ?? message.notification?.android?.sound ?? 'system';
      if (soundId.endsWith('.mp3')) soundId = soundId.substring(0, soundId.length - 4);
      if (soundId == 'default') soundId = 'system';

      // Kiểm tra âm thanh tùy chỉnh hợp lệ trong res/raw/
      const validCustomSounds = {'sound_bell', 'sound_gentle', 'sound_energetic'};
      if (soundId != 'system' && !validCustomSounds.contains(soundId)) {
        soundId = 'system';
      }

      final String channelId = soundId != 'system' ? 'custom_channel_$soundId' : 'high_importance_channel';

      // Tạo ID thông báo dương (31-bit integer)
      final int rawHash = dedupKey != null
          ? dedupKey.hashCode
          : (message.messageId?.hashCode ?? message.hashCode);
      final int notifIntId = rawHash.abs() % 0x7FFFFFFF;

      // Đảm bảo kênh thông báo Android tồn tại trên thiết bị trước khi hiển thị
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      final channel = AndroidNotificationChannel(
        channelId,
        'Thông báo quan trọng',
        description: 'Kênh thông báo cho lịch học và lịch thi',
        importance: Importance.max,
        playSound: true,
        sound: soundId != 'system' ? RawResourceAndroidNotificationSound(soundId) : null,
        enableVibration: true,
      );

      await androidPlugin?.createNotificationChannel(channel);

      await _localNotifications.show(
        notifIntId,
        title,
        body,
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
      print('✅ Đã hiển thị Local Notification khi app đang mở: $title');
    } catch (e, stack) {
      print('❌ Lỗi khi hiển thị Local Notification: $e');
      print('   Stack: $stack');
    }
  }

  // Alias để giữ tương thích private call
  Future<void> _showLocalNotification(RemoteMessage message) => showLocalNotification(message);

  // ========== XỬ LÝ KHI TAP NOTIFICATION ==========
  void _handleNotificationTap(RemoteMessage message) {
    if (message.data.isEmpty && message.notification == null) return;
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
      final title = initialMessage.notification?.title ??
          initialMessage.data['title'] ??
          initialMessage.data['tieuDe'];
      final body = initialMessage.notification?.body ??
          initialMessage.data['body'] ??
          initialMessage.data['noiDung'];

      if ((title == null || title.toString().trim().isEmpty) &&
          (body == null || body.toString().trim().isEmpty) &&
          initialMessage.data.isEmpty) {
        print('ℹ️ Bỏ qua initial message rỗng');
        return;
      }

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