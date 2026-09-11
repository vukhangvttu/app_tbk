// lib/core/initializers/post_login_initializer.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../firebase_options.dart';
import '../../../services/notificationservice.dart';
import '../../../services/simple_firebase_service.dart';

class PostLoginInitializer {
  static bool _isInitialized = false;
  static bool _isInitializing = false;
  static bool _hasShownSuccessMessage = false; // ← Mới: chỉ hiện thông báo 1 lần

  static const String _prefKeyInitialized = 'post_login_services_initialized';
  static const String _prefKeyShownMessage = 'post_login_shown_notification_message';

  /// ✅ Quick init - Không block UI
  static Future<void> quickInit({
    required BuildContext context,
    String? mssv,
  }) async {
    // Nếu đã init thành công trong session này → skip hoàn toàn
    if (_isInitialized) {
      debugPrint('⏭️ Services already initialized in this session');
      return;
    }

    // Nếu đang init → chờ
    if (_isInitializing) {
      debugPrint('⏳ Init in progress...');
      return;
    }

    _isInitializing = true;
    debugPrint('🚀 Starting post-login initialization');

    // Lưu MSSV
    if (mssv != null && mssv.isNotEmpty) {
      await _saveMSSV(mssv);
    }

    // Kiểm tra xem đã từng init thành công trong phiên đăng nhập này chưa
    final prefs = await SharedPreferences.getInstance();
    final bool alreadyInitialized = prefs.getBool(_prefKeyInitialized) ?? false;
    final bool alreadyShownMessage = prefs.getBool(_prefKeyShownMessage) ?? false;

    _hasShownSuccessMessage = alreadyShownMessage;

    if (alreadyInitialized) {
      debugPrint('✅ Services were initialized before (from previous session) - skipping heavy init');
      _isInitialized = true;
      _isInitializing = false;
      return;
    }

    // Chưa từng init → chạy đầy đủ
    await _initServicesInBackground(context, prefs);
  }

  static Future<void> _saveMSSV(String mssv) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mssv', mssv);
      debugPrint('  ✓ MSSV saved: $mssv');
    } catch (e) {
      debugPrint('  ✗ Save MSSV error: $e');
    }
  }

  static Future<void> _initServicesInBackground(BuildContext context, SharedPreferences prefs) async {
    final sw = Stopwatch()..start();

    try {
      await _initFirebase();
      await _initNotifications(context);

      _isInitialized = true;
      sw.stop();
      debugPrint('✅ Services fully initialized in ${sw.elapsedMilliseconds}ms');

      // Lưu trạng thái đã init thành công
      await prefs.setBool(_prefKeyInitialized, true);

      // Chỉ hiện thông báo nếu chưa từng hiện trong phiên này
      if (context.mounted && !_hasShownSuccessMessage) {
        _hasShownSuccessMessage = true;
        await prefs.setBool(_prefKeyShownMessage, true);
        _showQuietSuccess(context);
      }
    } catch (e) {
      sw.stop();
      debugPrint('❌ Init error (${sw.elapsedMilliseconds}ms): $e');

      if (context.mounted && !_hasShownSuccessMessage) {
        _hasShownSuccessMessage = true;
        _showQuietError(context, e.toString());
      }

      // Retry sau 5s
      Future.delayed(const Duration(seconds: 5), () {
        if (!_isInitialized && context.mounted) {
          debugPrint('🔄 Retrying initialization...');
          _isInitializing = false;
          _initServicesInBackground(context, prefs);
        }
      });
    } finally {
      _isInitializing = false;
    }
  }

  // Các hàm _initFirebase, _initNotifications giữ nguyên
  static Future<void> _initFirebase() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await SimpleFirebaseService.instance.initialize();
      debugPrint('  ✓ Firebase ready');
    } catch (e) {
      debugPrint('  ✗ Firebase error: $e');
      rethrow;
    }
  }

  static Future<void> _initNotifications(BuildContext context) async {
    try {
      await NotificationServices().init(context);
      debugPrint('  ✓ Notifications ready');
    } catch (e) {
      debugPrint('  ✗ Notifications error: $e');
      rethrow;
    }
  }

  static void _showQuietSuccess(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Đã kích hoạt thông báo', style: TextStyle(color: Colors.white)),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static void _showQuietError(BuildContext context, String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text('Không thể bật thông báo. Đang thử lại...', maxLines: 2)),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
      ),
    );
  }

  // Các hàm khác giữ nguyên
  static Future<void> ensureInitialized(BuildContext context) async { /* ... */ }

  static bool get isInitialized => _isInitialized;

  /// ✅ Reset khi logout
  static Future<void> reset() async {
    _isInitialized = false;
    _isInitializing = false;
    _hasShownSuccessMessage = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyInitialized);
    await prefs.remove(_prefKeyShownMessage);

    debugPrint('🔄 Post-login services reset');
  }


}