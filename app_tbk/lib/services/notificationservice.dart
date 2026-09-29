import 'dart:async';
import 'package:app_tbk/core/errors/exceptions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/auth/services/auth_service.dart';
import '../utils/global_keys.dart';
import 'notification_tracking_service.dart';

class NotificationServices {
  static final NotificationServices _instance = NotificationServices._internal();
  factory NotificationServices() => _instance;
  NotificationServices._internal();

  bool _isInitialized = false;
  BuildContext? _context;

  // ✅ Shared Preferences keys
  static const String _keyLastFcmToken = 'last_fcm_token';
  static const String _keyLastDeviceId = 'last_device_id';
  static const String _keyLastMssv = 'last_mssv';

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

      // ✅ Request permission
      await _requestPermission();

      // ✅ Get FCM token
      final fcmToken = await FirebaseMessaging.instance.getToken()
          .timeout(const Duration(seconds: 10), onTimeout: () {
        print('⏱️ FCM token timeout');
        return null;
      });

      if (fcmToken == null || fcmToken.isEmpty) {
        throw Exception('FCM token is empty or null');
      }

      print('📱 Current FCM Token: $fcmToken');

      // ✅ Get real device info from AuthService
      final deviceInfo = await DeviceHelper.getDeviceInfo();
      String deviceId = deviceInfo['device_id'] ?? 'unknown_device';

      // ✅ Luôn cập nhật Token lên Go Server khi init để đảm bảo DB luôn có Token mới nhất
      print('🔄 Updating FCM Token to server for MSSV $mssv...');
      await saveFcmTokenToServer(mssv, fcmToken, deviceId);
      await _cacheTokenInfo(prefs, mssv, fcmToken, deviceId);

      // ✅ Listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        print('🔄 FCM Token refreshed: $newToken');

        final prefs = await SharedPreferences.getInstance();
        final currentMssv = await AuthService.getSavedMssv() ?? prefs.getString('mssv') ?? '';

        final currentDeviceInfo = await DeviceHelper.getDeviceInfo();
        final currentDeviceId = currentDeviceInfo['device_id'] ?? 'unknown_device';

        if (currentMssv.isNotEmpty) {
          await saveFcmTokenToServer(currentMssv, newToken, currentDeviceId);
          await _cacheTokenInfo(prefs, currentMssv, newToken, currentDeviceId);
        }
      }).onError((err) {
        print('❌ Error on token refresh: $err');
      });

      // ✅ Listen for foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📬 Received foreground message: ${message.notification?.title}');
        final notificationId = NotificationTrackingService.extractNotificationId(message.data);
        if (notificationId != null) {
          NotificationTrackingService.reportDelivered(notificationId);
        }
      });

      _isInitialized = true;
      print('✅ NotificationServices initialized');
    } catch (e, stackTrace) {
      print('❌ Error initializing NotificationServices: $e');
      print('Stack trace: $stackTrace');
      _isInitialized = true;
    }
  }

  /// ✅ Kiểm tra xem có cần update token không
  Future<bool> _shouldUpdateToken({
    required SharedPreferences prefs,
    required String mssv,
    required String fcmToken,
    required String deviceId,
  }) async {
    final lastMssv = prefs.getString(_keyLastMssv);
    final lastToken = prefs.getString(_keyLastFcmToken);
    final lastDeviceId = prefs.getString(_keyLastDeviceId);

    // ✅ Trường hợp CẦN update:
    // 1. Chưa từng lưu token (first time)
    if (lastToken == null || lastToken.isEmpty) {
      print('  → First time setup');
      return true;
    }

    // 2. MSSV thay đổi (user khác login)
    if (lastMssv != mssv) {
      print('  → MSSV changed: $lastMssv → $mssv');
      return true;
    }

    // 3. FCM token thay đổi
    if (lastToken != fcmToken) {
      print('  → Token changed');
      return true;
    }

    // 4. Device ID thay đổi (reinstall app)
    if (lastDeviceId != deviceId) {
      print('  → Device ID changed');
      return true;
    }

    // ✅ Không cần update
    return false;
  }

  /// ✅ Cache token info vào SharedPreferences
  Future<void> _cacheTokenInfo(
      SharedPreferences prefs,
      String mssv,
      String fcmToken,
      String deviceId,
      ) async {
    await prefs.setString(_keyLastMssv, mssv);
    await prefs.setString(_keyLastFcmToken, fcmToken);
    await prefs.setString(_keyLastDeviceId, deviceId);
    print('💾 Cached token info');
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
        print('⚠️ Notification permission denied');
      }
    } catch (e) {
      print('⚠️ Error requesting permission: $e');
    }
  }

  Future<void> saveFcmTokenToServer(String mssv, String fcmToken, String deviceId) async {
    final url = '/users/$mssv/token';

    try {
      print('🌐 POST $url');
      print('   Body: {fcmToken: $fcmToken, deviceId: $deviceId}');

      final response = await AuthService.authenticatedRequestNotification(
        method: 'POST',
        endpoint: url,
        body: {
          'fcmToken': fcmToken,
          'fcm_token': fcmToken,
          'token': fcmToken,
          'deviceId': deviceId,
          'device_id': deviceId,
        },
      );

      if (response?.statusCode == 200) {
        print('✅ FCM token saved successfully');
      } else {
        print('❌ Failed to save FCM token: ${response?.statusCode}');
        print('   Response: ${response?.body}');
      }
    } on NoInternetException {
      print('🌐 Offline mode: Không thể gửi FCM token lên server do mất mạng - sẽ thử lại khi có mạng.');
    } catch (e) {
      print('❌ Error saving FCM token: $e');
    }
  }

  /// ✅ Update MSSV và refresh token (gọi sau khi login)
  Future<void> updateMssv(String mssv) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mssv', mssv);

      final deviceInfo = await DeviceHelper.getDeviceInfo();
      String deviceId = deviceInfo['device_id'];

      // ✅ Force update vì MSSV thay đổi
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        print('🔄 MSSV updated - forcing token refresh');
        await saveFcmTokenToServer(mssv, fcmToken, deviceId);
        await _cacheTokenInfo(prefs, mssv, fcmToken, deviceId);
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

      // ✅ Xóa cache để lần login sau sẽ gọi API
      await prefs.remove(_keyLastFcmToken);
      await prefs.remove(_keyLastDeviceId);
      await prefs.remove(_keyLastMssv);

      print('✅ FCM token cleared (cache cleared for next login)');
    } catch (e) {
      print('❌ Error clearing token: $e');
    }
  }

  /// ✅ Hiển thị thông báo lỗi
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

  /// ✅ Debug: Xem token cache hiện tại
  Future<void> debugPrintTokenCache() async {
    final prefs = await SharedPreferences.getInstance();
    print('═══════════════════════════════════════');
    print('📋 Token Cache Debug:');
    print('   MSSV: ${prefs.getString(_keyLastMssv) ?? "null"}');
    print('   Token: ${prefs.getString(_keyLastFcmToken) ?? "null"}');
    print('   Device: ${prefs.getString(_keyLastDeviceId) ?? "null"}');
    print('═══════════════════════════════════════');
  }
}


// ==================== CÁCH SỬ DỤNG ====================

/*
// 1. Đăng nhập lần đầu (hoặc sau khi xóa app):
//    → Gọi API lưu token ✅

// 2. Đăng nhập lại (token chưa thay đổi):
//    → KHÔNG gọi API ⏭️

// 3. Xóa app và cài lại:
//    → Cache bị xóa → Gọi API lại ✅

// 4. Token tự động refresh:
//    → Chỉ gọi API nếu token thực sự thay đổi ✅

// 5. Logout:
//    → Xóa cache → Lần login sau sẽ gọi API ✅
*/

// ==================== DEBUG ====================

/*
// Để debug, thêm vào màn hình nào đó:

ElevatedButton(
  onPressed: () async {
    await NotificationServices().debugPrintTokenCache();
  },
  child: Text('Debug Token Cache'),
)
*/