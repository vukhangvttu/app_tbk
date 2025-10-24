// // lib/services/firebase_service.dart
// import 'dart:async';
// import 'dart:convert';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:firebase_remote_config/firebase_remote_config.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:http/http.dart' as http;
//
// // Top-level function để xử lý background messages
// @pragma('vm:entry-point')
// Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
//   await Firebase.initializeApp();
//   print('📱 Background Message: ${message.messageId}');
//   // Xử lý notification trong background
//   await FirebaseService.instance.handleBackgroundMessage(message);
// }
//
// class FirebaseService {
//   static final FirebaseService _instance = FirebaseService._internal();
//   static FirebaseService get instance => _instance;
//
//   FirebaseService._internal();
//
//   final FirebaseMessaging _messaging = FirebaseMessaging.instance;
//   final FlutterLocalNotificationsPlugin _localNotifications =
//   FlutterLocalNotificationsPlugin();
//   FirebaseRemoteConfig? _remoteConfig;
//
//   String? _fcmToken;
//   String? get fcmToken => _fcmToken;
//
//   // Stream controller để lắng nghe các sự kiện
//   final StreamController<RemoteMessage> _messageStreamController =
//   StreamController.broadcast();
//   Stream<RemoteMessage> get onMessageReceived => _messageStreamController.stream;
//
//   // ==================== KHỞI TẠO FIREBASE ====================
//
//   Future<void> initialize() async {
//     try {
//       // 1. Khởi tạo Firebase
//       await Firebase.initializeApp();
//       print('✅ Firebase initialized');
//
//       // 2. Khởi tạo FCM
//       await _initializeFCM();
//
//       // 3. Khởi tạo Remote Config
//       await _initializeRemoteConfig();
//
//       // 4. Khởi tạo Local Notifications
//       await _initializeLocalNotifications();
//
//       print('✅ Firebase Service fully initialized');
//     } catch (e) {
//       print('❌ Error initializing Firebase: $e');
//     }
//   }
//
//   // ==================== FCM SETUP ====================
//
//   Future<void> _initializeFCM() async {
//     // Yêu cầu quyền thông báo
//     NotificationSettings settings = await _messaging.requestPermission(
//       alert: true,
//       announcement: false,
//       badge: true,
//       carPlay: false,
//       criticalAlert: false,
//       provisional: false,
//       sound: true,
//     );
//
//     if (settings.authorizationStatus == AuthorizationStatus.authorized) {
//       print('✅ User granted notification permission');
//
//       // Lấy FCM token
//       _fcmToken = await _messaging.getToken();
//       print('📱 FCM Token: $_fcmToken');
//
//       // Lưu token vào SharedPreferences
//       await _saveFCMToken(_fcmToken);
//
//       // Gửi token lên server
//       await _sendTokenToServer(_fcmToken);
//
//       // Lắng nghe token refresh
//       _messaging.onTokenRefresh.listen((newToken) {
//         _fcmToken = newToken;
//         _saveFCMToken(newToken);
//         _sendTokenToServer(newToken);
//       });
//
//       // Setup message handlers
//       _setupMessageHandlers();
//     } else {
//       print('⚠️ User declined notification permission');
//     }
//   }
//
//   Future<void> _saveFCMToken(String? token) async {
//     if (token != null) {
//       final prefs = await SharedPreferences.getInstance();
//       await prefs.setString('fcm_token', token);
//     }
//   }
//
//   Future<void> _sendTokenToServer(String? token) async {
//     if (token == null) return;
//
//     try {
//       // Gửi token lên server của bạn
//       final response = await http.post(
//         Uri.parse('http://113.164.79.241:8202/api/fcm/register'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'token': token,
//           'idSinhVien': 19719, // Lấy từ user session
//           'platform': 'android', // hoặc 'ios'
//           'timestamp': DateTime.now().toIso8601String(),
//         }),
//       );
//
//       if (response.statusCode == 200) {
//         print('✅ Token sent to server successfully');
//       }
//     } catch (e) {
//       print('❌ Error sending token to server: $e');
//     }
//   }
//
//   void _setupMessageHandlers() {
//     // 1. Foreground messages (app đang mở)
//     FirebaseMessaging.onMessage.listen((RemoteMessage message) {
//       print('📬 Foreground Message: ${message.notification?.title}');
//       _handleForegroundMessage(message);
//       _messageStreamController.add(message);
//     });
//
//     // 2. Background messages (app trong background)
//     FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
//
//     // 3. Message opened app (click vào notification)
//     FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
//       print('🔔 Notification opened app: ${message.notification?.title}');
//       _handleNotificationTap(message);
//     });
//
//     // 4. Terminated state (app bị tắt hoàn toàn)
//     _handleTerminatedMessage();
//   }
//
//   Future<void> _handleForegroundMessage(RemoteMessage message) async {
//     // Hiển thị local notification khi app đang mở
//     RemoteNotification? notification = message.notification;
//     AndroidNotification? android = message.notification?.android;
//
//     if (notification != null && android != null) {
//       await _localNotifications.show(
//         notification.hashCode,
//         notification.title,
//         notification.body,
//         NotificationDetails(
//           android: AndroidNotificationDetails(
//             'high_importance_channel',
//             'Thông báo quan trọng',
//             channelDescription: 'Kênh thông báo cho lịch học và lịch thi',
//             importance: Importance.high,
//             priority: Priority.high,
//             icon: '@mipmap/ic_launcher',
//             color: const Color(0xFF2196F3),
//             playSound: true,
//             enableVibration: true,
//           ),
//           iOS: const DarwinNotificationDetails(
//             presentAlert: true,
//             presentBadge: true,
//             presentSound: true,
//           ),
//         ),
//         payload: jsonEncode(message.data),
//       );
//     }
//   }
//
//   Future<void> handleBackgroundMessage(RemoteMessage message) async {
//     // Xử lý logic khi nhận notification trong background
//     print('📱 Processing background message: ${message.data}');
//
//     // Lưu vào local database nếu cần
//     final prefs = await SharedPreferences.getInstance();
//     List<String> notifications = prefs.getStringList('notifications') ?? [];
//     notifications.add(jsonEncode({
//       'title': message.notification?.title,
//       'body': message.notification?.body,
//       'data': message.data,
//       'timestamp': DateTime.now().toIso8601String(),
//     }));
//     await prefs.setStringList('notifications', notifications);
//   }
//
//   void _handleNotificationTap(RemoteMessage message) {
//     // Xử lý khi user click vào notification
//     String? type = message.data['type'];
//
//     switch (type) {
//       case 'LICH_HOC':
//       // Navigate to schedule screen
//         print('Navigate to: Lịch học');
//         break;
//       case 'LICH_THI':
//       // Navigate to exam schedule
//         print('Navigate to: Lịch thi');
//         break;
//       case 'THONG_BAO':
//       // Navigate to notifications
//         print('Navigate to: Thông báo');
//         break;
//       case 'DIEM':
//       // Navigate to grades
//         print('Navigate to: Điểm số');
//         break;
//       default:
//         print('Unknown notification type: $type');
//     }
//   }
//
//   Future<void> _handleTerminatedMessage() async {
//     RemoteMessage? initialMessage = await _messaging.getInitialMessage();
//     if (initialMessage != null) {
//       print('🚀 App opened from terminated state');
//       _handleNotificationTap(initialMessage);
//     }
//   }
//
//   // ==================== LOCAL NOTIFICATIONS ====================
//
//   Future<void> _initializeLocalNotifications() async {
//     const AndroidInitializationSettings initializationSettingsAndroid =
//     AndroidInitializationSettings('@mipmap/ic_launcher');
//
//     final DarwinInitializationSettings initializationSettingsIOS =
//     DarwinInitializationSettings(
//       requestAlertPermission: true,
//       requestBadgePermission: true,
//       requestSoundPermission: true,
//       onDidReceiveLocalNotification: (id, title, body, payload) async {
//         // Handle iOS foreground notification
//       },
//     );
//
//     final InitializationSettings initializationSettings = InitializationSettings(
//       android: initializationSettingsAndroid,
//       iOS: initializationSettingsIOS,
//     );
//
//     await _localNotifications.initialize(
//       initializationSettings,
//       onDidReceiveNotificationResponse: (NotificationResponse response) async {
//         // Xử lý khi user tap vào local notification
//         if (response.payload != null) {
//           Map<String, dynamic> data = jsonDecode(response.payload!);
//           print('Local notification tapped: $data');
//         }
//       },
//     );
//
//     // Create notification channel cho Android
//     const AndroidNotificationChannel channel = AndroidNotificationChannel(
//       'high_importance_channel',
//       'Thông báo quan trọng',
//       description: 'Kênh thông báo cho lịch học và lịch thi',
//       importance: Importance.high,
//     );
//
//     await _localNotifications
//         .resolvePlatformSpecificImplementation<
//         AndroidFlutterLocalNotificationsPlugin>()
//         ?.createNotificationChannel(channel);
//   }
//
//   // ==================== REMOTE CONFIG ====================
//
//   Future<void> _initializeRemoteConfig() async {
//     try {
//       _remoteConfig = FirebaseRemoteConfig.instance;
//
//       // Cấu hình settings
//       await _remoteConfig!.setConfigSettings(RemoteConfigSettings(
//         fetchTimeout: const Duration(seconds: 10),
//         minimumFetchInterval: const Duration(hours: 1), // Production: 12 hours
//       ));
//
//       // Set default values
//       await _remoteConfig!.setDefaults({
//         'api_base_url': 'http://113.164.79.241:8202',
//         'enable_notifications': true,
//         'notification_time_hour': 8,
//         'notification_time_minute': 55,
//         'app_version_min': '1.0.0',
//         'maintenance_mode': false,
//         'maintenance_message': 'Hệ thống đang bảo trì',
//         'show_ads': false,
//         'refresh_interval_minutes': 30,
//         'enable_auto_refresh': true,
//         'max_cache_days': 7,
//         'theme_primary_color': '#2196F3',
//         'feature_flags': jsonEncode({
//           'enable_dark_mode': true,
//           'enable_biometric': false,
//           'enable_chat': false,
//         }),
//       });
//
//       // Fetch và activate
//       await _remoteConfig!.fetchAndActivate();
//
//       // Listen for updates (Realtime)
//       _remoteConfig!.onConfigUpdated.listen((event) async {
//         await _remoteConfig!.activate();
//         print('🔄 Remote Config updated');
//       });
//
//       print('✅ Remote Config initialized');
//     } catch (e) {
//       print('❌ Error initializing Remote Config: $e');
//     }
//   }
//
//   // ==================== REMOTE CONFIG GETTERS ====================
//
//   String getApiBaseUrl() {
//     return _remoteConfig?.getString('api_base_url') ??
//         'http://113.164.79.241:8202';
//   }
//
//   bool isNotificationsEnabled() {
//     return _remoteConfig?.getBool('enable_notifications') ?? true;
//   }
//
//   int getNotificationHour() {
//     return _remoteConfig?.getInt('notification_time_hour') ?? 8;
//   }
//
//   int getNotificationMinute() {
//     return _remoteConfig?.getInt('notification_time_minute') ?? 55;
//   }
//
//   bool isMaintenanceMode() {
//     return _remoteConfig?.getBool('maintenance_mode') ?? false;
//   }
//
//   String getMaintenanceMessage() {
//     return _remoteConfig?.getString('maintenance_message') ??
//         'Hệ thống đang bảo trì';
//   }
//
//   bool shouldShowAds() {
//     return _remoteConfig?.getBool('show_ads') ?? false;
//   }
//
//   int getRefreshInterval() {
//     return _remoteConfig?.getInt('refresh_interval_minutes') ?? 30;
//   }
//
//   bool isAutoRefreshEnabled() {
//     return _remoteConfig?.getBool('enable_auto_refresh') ?? true;
//   }
//
//   Map<String, dynamic> getFeatureFlags() {
//     try {
//       String flagsJson = _remoteConfig?.getString('feature_flags') ?? '{}';
//       return jsonDecode(flagsJson);
//     } catch (e) {
//       return {};
//     }
//   }
//
//   bool isFeatureEnabled(String featureName) {
//     Map<String, dynamic> flags = getFeatureFlags();
//     return flags[featureName] ?? false;
//   }
//
//   String getThemePrimaryColor() {
//     return _remoteConfig?.getString('theme_primary_color') ?? '#2196F3';
//   }
//
//   // ==================== TOPIC SUBSCRIPTION ====================
//
//   Future<void> subscribeToTopic(String topic) async {
//     try {
//       await _messaging.subscribeToTopic(topic);
//       print('✅ Subscribed to topic: $topic');
//     } catch (e) {
//       print('❌ Error subscribing to topic: $e');
//     }
//   }
//
//   Future<void> unsubscribeFromTopic(String topic) async {
//     try {
//       await _messaging.unsubscribeFromTopic(topic);
//       print('✅ Unsubscribed from topic: $topic');
//     } catch (e) {
//       print('❌ Error unsubscribing from topic: $e');
//     }
//   }
//
//   // Subscribe theo idSinhVien và các topics khác
//   Future<void> subscribeToUserTopics(int idSinhVien) async {
//     await subscribeToTopic('user_$idSinhVien');
//     await subscribeToTopic('all_students');
//     await subscribeToTopic('schedule_updates');
//   }
//
//   // ==================== SEND NOTIFICATION TO SERVER ====================
//
//   Future<void> sendNotificationToUser({
//     required int idSinhVien,
//     required String title,
//     required String body,
//     Map<String, dynamic>? data,
//   }) async {
//     try {
//       await http.post(
//         Uri.parse('${getApiBaseUrl()}/api/fcm/send'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'idSinhVien': idSinhVien,
//           'title': title,
//           'body': body,
//           'data': data ?? {},
//         }),
//       );
//     } catch (e) {
//       print('❌ Error sending notification: $e');
//     }
//   }
//
//   // ==================== CLEANUP ====================
//
//   void dispose() {
//     _messageStreamController.close();
//   }
// }