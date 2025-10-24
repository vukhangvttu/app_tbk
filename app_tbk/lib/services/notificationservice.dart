import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../utils/global_keys.dart';


class NotificationServices {
  static final NotificationServices _instance = NotificationServices
      ._internal();

  factory NotificationServices() => _instance;

  NotificationServices._internal();

  bool _isInitialized = false;
  BuildContext? _context;

  /// ✅ Init notification service (CHỈ GỌI SAU KHI FIREBASE READY)
  Future<void> init(BuildContext context) async {
    if (_isInitialized) {
      print('⏭️ NotificationServices already initialized');
      return;
    }

    _context = context;

    try {
      print('🔔 Initializing NotificationServices...');

      final prefs = await SharedPreferences.getInstance();
      final String? mssv = prefs.getString('mssv');

      if (mssv == null || mssv.isEmpty) {
        print('⚠️ MSSV not found, skipping FCM token registration');
        _isInitialized = true;
        return;
      }

      await _requestPermission();

      final fcmToken = await FirebaseMessaging.instance.getToken()
          .timeout(const Duration(seconds: 10), onTimeout: () {
        print('⏱️ FCM token timeout');
        return null;
      });

      if (fcmToken != null && fcmToken.isNotEmpty) {
        print('✅ Initial FCM Token: ${fcmToken.substring(0, 20)}...');
        await saveFcmTokenToServer(mssv, fcmToken);
      } else {
        print('❌ Failed to get FCM token');
        _showError('Không thể lấy FCM token, nên không thể nhận thông báo.');
      }

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        print('🔄 FCM Token refreshed: ${newToken.substring(0, 20)}...');
        saveFcmTokenToServer(mssv, newToken);
      }).onError((err) {
        print('❌ Error on token refresh: $err');
      });

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📬 Received foreground message: ${message.notification?.title}');
      });

      _isInitialized = true;
      print('✅ NotificationServices initialized');
    } catch (e, stackTrace) {
      print('❌ Error initializing NotificationServices: $e');
      print('Stack trace: $stackTrace');
      _showError('Không thể khởi tạo thông báo: $e');
      _isInitialized = true;
    }
  }

  Future<void> _requestPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ Notification permission granted');
      } else {
        _showError('Ứng dụng chưa được cấp quyền thông báo.');
      }
    } catch (e) {
      print('⚠️ Error requesting permission: $e');
    }
  }

  Future<void> saveFcmTokenToServer(String mssv, String fcmToken) async {
    try {
      print('💾 Saving FCM token for MSSV: $mssv');

      final response = await http.post(
        Uri.parse(
            'http://192.168.1.120:8080/notification-service/api/users/$mssv/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fcmToken': fcmToken}),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timeout');
        },
      );

      if (response.statusCode == 200) {
        print('✅ FCM token saved successfully');
      } else {
        print('❌ Failed to save FCM token: ${response.statusCode}');
        print('Response: ${response.body}');
        _showError('Không thể lưu FCM token nên không thể nhận thông báo.');
      }
    } catch (e) {
      print('❌ Error saving FCM token: $e');
      _showError('Không thể lưu FCM token nên không thể nhận thông báo.');
    }
  }

  /// ✅ Update MSSV và refresh token (gọi sau khi login)
  Future<void> updateMssv(String mssv) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mssv', mssv);

      // Lấy lại token và save
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await saveFcmTokenToServer(mssv, fcmToken);
      }
    } catch (e) {
      print('❌ Error updating MSSV: $e');
    }
  }

  /// ✅ Clear token khi logout
  Future<void> clearToken() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('mssv');
      print('✅ FCM token cleared');
    } catch (e) {
      print('❌ Error clearing token: $e');
    }
  }

  /// ✅ Hiển thị thông báo lỗi (SnackBar hoặc Dialog)
  void _showError(String message) {
    print('⚠️ Show global SnackBar: $message');

    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) {
      print('⚠️ ScaffoldMessenger chưa sẵn sàng, bỏ qua lỗi.');
      return;
    }

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.red[400],
        duration: const Duration(seconds: 15),
        dismissDirection: DismissDirection.up,
      ),
    );
  }
}


// ==================== CÁCH SỬ DỤNG ====================

/*
// 1. Trong PostLoginInitializer (main.dart):

static Future<void> _initNotifications() async {
  final sw = Stopwatch()..start();
  try {
    await Future.wait([
      NotificationServices().init(),  // ✅ Gọi sau khi Firebase ready
      NotificationService.init(),
    ]);
    sw.stop();
    debugPrint('  ✓ Notifications ready (${sw.elapsedMilliseconds}ms)');
  } catch (e) {
    debugPrint('  ✗ Notifications error: $e');
  }
}

// 2. Trong LoginScreen sau khi login success:

Future<void> _handleLogin() async {
  // ... login code ...

  if (success) {
    // Lưu MSSV vào SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mssv', mssv);

    // Init Firebase + Notifications
    await PostLoginInitializer.initialize();

    // Navigate...
  }
}

// 3. Khi logout:

Future<void> logout() async {
  await NotificationServices().clearToken();
  // ... other logout code ...
}
*/

// ==================== DEBUG TIPS ====================

/*
// Nếu vẫn không hoạt động, kiểm tra:

1. Firebase đã init chưa?
   ✓ Gọi Firebase.initializeApp() trước NotificationServices().init()

2. MSSV có trong SharedPreferences chưa?
   ✓ await prefs.setString('mssv', mssv) sau login

3. FCM token có được tạo không?
   ✓ Check console logs: "Initial FCM Token: ..."

4. Network có hoạt động không?
   ✓ Ping http://192.168.1.120:8080

5. Android: google-services.json đã thêm chưa?
   ✓ android/app/google-services.json

6. iOS: GoogleService-Info.plist đã thêm chưa?
   ✓ ios/Runner/GoogleService-Info.plist

7. Permissions đã được grant chưa?
   ✓ Check Settings → Apps → Your App → Notifications

8. Test trên thiết bị thật (không phải emulator)
   ✓ FCM có thể không hoạt động tốt trên emulator
*/