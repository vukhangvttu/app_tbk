import 'dart:async';
import 'dart:io';
import 'package:app_tbk/core/errors/exceptions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/auth/services/auth_service.dart';
import '../utils/global_keys.dart';
import 'notification_tracking_service.dart';
import 'simple_firebase_service.dart';

class NotificationServices {
  static final NotificationServices _instance = NotificationServices._internal();
  factory NotificationServices() => _instance;
  NotificationServices._internal();

  bool _isInitialized = false;
  BuildContext? _context;

  // ✅ Trạng thái đăng ký token (phục vụ retry khi APNs/FCM chưa sẵn sàng)
  bool _listenersRegistered = false;
  bool _tokenSaved = false;
  bool _tokenRetryScheduled = false;

  // ✅ Shared Preferences keys
  static const String _keyLastFcmToken = 'last_fcm_token';
  static const String _keyLastDeviceId = 'last_device_id';
  static const String _keyLastMssv = 'last_mssv';

  /// ✅ Init notification service (CHỈ GỌI SAU KHI FIREBASE READY)
  Future<void> init(BuildContext context) async {
    _context = context;

    final prefs = await SharedPreferences.getInstance();
    final String? mssv = await AuthService.getSavedMssv() ?? prefs.getString('mssv');

    if (_isInitialized) {
      print('⏭️ NotificationServices already initialized');
      // Đã init nhưng lần trước chưa lưu được token (APNs/FCM chưa sẵn sàng)
      // → thử đăng ký lại thay vì bỏ qua hẳn
      if (!_tokenSaved && mssv != null && mssv.isNotEmpty) {
        print('🔁 Retrying FCM token registration...');
        final ok = await _fetchAndSaveToken(mssv);
        if (!ok) _scheduleTokenRetry(mssv);
      }
      return;
    }

    try {
      print('🔔 Initializing NotificationServices...');
      if (mssv == null || mssv.isEmpty) {
        print('⚠️ MSSV not found, skipping FCM token registration');
        // KHÔNG đánh dấu _isInitialized: để lần init sau (khi đã có MSSV) chạy tiếp được
        return;
      }

      // ✅ Request permission
      await _requestPermission();

      // ✅ Đăng ký listeners đúng 1 lần — TRƯỚC khi lấy token,
      // để token về muộn (onTokenRefresh) vẫn được lưu lên server
      if (!_listenersRegistered) {
        _listenersRegistered = true;

        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
          print('🔄 FCM Token refreshed: $newToken');

          final prefs = await SharedPreferences.getInstance();
          final currentMssv = await AuthService.getSavedMssv() ?? prefs.getString('mssv') ?? '';

          final currentDeviceInfo = await DeviceHelper.getDeviceInfo();
          final currentDeviceId = currentDeviceInfo['device_id'] ?? 'unknown_device';

          if (currentMssv.isNotEmpty) {
            final ok = await saveFcmTokenToServer(currentMssv, newToken, currentDeviceId);
            if (ok) _tokenSaved = true;
            await _cacheTokenInfo(prefs, currentMssv, newToken, currentDeviceId);
          }
        }).onError((err) {
          print('❌ Error on token refresh: $err');
        });

        // ✅ Listen for foreground messages
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          print('📬 Received foreground message in NotificationServices: ${message.notification?.title}');
          final notificationId = NotificationTrackingService.extractNotificationId(message.data);
          if (notificationId != null) {
            NotificationTrackingService.reportDelivered(notificationId);
          }
        });
      }

      // ✅ Lấy FCM token + gửi lên server (có chờ APNs và retry bên trong)
      final saved = await _fetchAndSaveToken(mssv);
      if (!saved) {
        // Chưa lưu được (thường do APNs token chưa về kịp trên iOS)
        // → hẹn thử lại ở nền, đừng để cả phiên mất đăng ký token
        _scheduleTokenRetry(mssv);
      }

      _isInitialized = true;
      print('✅ NotificationServices initialized');
    } catch (e, stackTrace) {
      print('❌ Error initializing NotificationServices: $e');
      print('Stack trace: $stackTrace');
      // KHÔNG đánh dấu _isInitialized khi lỗi: lần init kế tiếp phải chạy lại được
    }
  }

  /// ⏳ Chờ APNs token trên iOS (tối đa ~30s). Android bỏ qua, trả về true ngay.
  Future<bool> _waitForApnsToken() async {
    if (!Platform.isIOS) return true;

    print('🍎 Waiting for APNs token on iOS...');
    String? apnsToken = await FirebaseMessaging.instance.getAPNSToken();
    int retryCount = 0;
    while (apnsToken == null && retryCount < 30) {
      await Future.delayed(const Duration(seconds: 1));
      apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      retryCount++;
      print('  ⏳ Retrying APNs token ($retryCount/30)...');
    }

    if (apnsToken == null) {
      print('⚠️ APNs token is null on iOS. FCM token fetch might fail.');
      return false;
    }

    print('✅ APNs Token received: $apnsToken');
    return true;
  }

  /// 📱 Lấy FCM token có retry.
  /// Trên iOS, getToken() gọi quá sớm sẽ VĂNG lỗi apns-token-not-set (không phải timeout)
  /// nên phải bắt lỗi và thử lại, không chỉ bọc .timeout().
  Future<String?> _getTokenWithRetry() async {
    for (int attempt = 1; attempt <= 5; attempt++) {
      try {
        final token = await FirebaseMessaging.instance.getToken()
            .timeout(const Duration(seconds: 15), onTimeout: () {
          print('⏱️ FCM token timeout (attempt $attempt)');
          return null;
        });
        if (token != null && token.isNotEmpty) {
          return token;
        }
        print('⚠️ FCM token null/empty (attempt $attempt)');
      } catch (e) {
        print('⚠️ getToken attempt $attempt failed: $e');
      }

      if (attempt < 5) {
        await Future.delayed(Duration(seconds: attempt * 3));
      }
    }
    return null;
  }

  /// 🚀 Lấy FCM token rồi gửi lên server. Trả về true nếu server đã lưu (HTTP 200).
  Future<bool> _fetchAndSaveToken(String mssv) async {
    // Chờ APNs trước (iOS). Nếu APNs chưa về vẫn thử getToken (đã có retry),
    // nhưng KHÔNG coi là xong — nơi gọi sẽ hẹn retry tiếp khi hàm này trả false.
    await _waitForApnsToken();

    final fcmToken = await _getTokenWithRetry();
    if (fcmToken == null || fcmToken.isEmpty) {
      print('⚠️ FCM Token is null after retries.');
      return false;
    }

    print('📱 Current FCM Token: $fcmToken');

    // ✅ Get real device info from AuthService
    final deviceInfo = await DeviceHelper.getDeviceInfo();
    String deviceId = deviceInfo['device_id'] ?? 'unknown_device';

    // ✅ Luôn cập nhật Token lên Go Server khi init để đảm bảo DB luôn có Token mới nhất
    print('🔄 Updating FCM Token to server for MSSV $mssv...');
    final ok = await saveFcmTokenToServer(mssv, fcmToken, deviceId);

    final prefs = await SharedPreferences.getInstance();
    await _cacheTokenInfo(prefs, mssv, fcmToken, deviceId);

    if (ok) {
      _tokenSaved = true;
    }
    return ok;
  }

  /// 🔁 Hẹn thử lại đăng ký token ở nền (mỗi 20s, tối đa 5 lần)
  /// khi lần đầu thất bại — cứu trường hợp APNs/FCM sẵn sàng muộn trên iOS.
  void _scheduleTokenRetry(String mssv) {
    if (_tokenRetryScheduled || _tokenSaved) return;
    _tokenRetryScheduled = true;

    () async {
      for (int i = 1; i <= 5 && !_tokenSaved; i++) {
        await Future.delayed(const Duration(seconds: 20));
        if (_tokenSaved) break;
        print('🔁 Token registration retry $i/5...');
        try {
          await _fetchAndSaveToken(mssv);
        } catch (e) {
          print('⚠️ Token registration retry $i error: $e');
        }
      }
      _tokenRetryScheduled = false;
    }();
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

  /// Trả về true CHỈ khi server trả HTTP 200 (đã lưu token thật).
  Future<bool> saveFcmTokenToServer(String mssv, String fcmToken, String deviceId) async {
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
        return true;
      } else {
        print('❌ Failed to save FCM token: ${response?.statusCode}');
        print('   Response: ${response?.body}');
        return false;
      }
    } on NoInternetException {
      print('🌐 Offline mode: Không thể gửi FCM token lên server do mất mạng - sẽ thử lại khi có mạng.');
      return false;
    } catch (e) {
      print('❌ Error saving FCM token: $e');
      return false;
    }
  }

  /// ✅ Update MSSV và refresh token (gọi sau khi login)
  Future<void> updateMssv(String mssv) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mssv', mssv);

      // ✅ Force update vì MSSV thay đổi — dùng chung luồng chờ APNs + retry
      // (bản cũ gọi thẳng getToken(): trên iOS lúc vừa login APNs chưa sẵn sàng
      // nên văng lỗi apns-token-not-set và mất luôn lần lưu này)
      print('🔄 MSSV updated - forcing token refresh');
      final ok = await _fetchAndSaveToken(mssv);
      if (!ok) _scheduleTokenRetry(mssv);
    } catch (e) {
      print('❌ Error updating MSSV: $e');
    }
  }

  /// ✅ Clear token khi logout
  Future<void> clearToken() async {
    try {
      _tokenSaved = false;
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