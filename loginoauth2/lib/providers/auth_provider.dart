import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Quản lý phiên đăng nhập.
///
/// Đăng nhập bằng Email/OAuth2 được hiện thực qua Google Sign-In
/// (chuẩn OAuth 2.0). Sau khi đăng nhập thành công, thông tin email
/// + tên hiển thị của người dùng được lưu lại để dùng ở màn hình chính.
///
/// GHI CHÚ CẤU HÌNH THỰC TẾ:
/// - Android: thêm SHA-1 vào Firebase / Google Cloud Console và tệp
///   google-services.json vào android/app/.
/// - iOS: thêm CLIENT_ID vào ios/Runner/Info.plist (REVERSED_CLIENT_ID)
///   và GoogleService-Info.plist vào ios/Runner/.
class AuthProvider extends ChangeNotifier {
  static const _prefsEmailKey = 'auth_email';
  static const _prefsNameKey = 'auth_name';
  static const _prefsPhotoKey = 'auth_photo';

  // Thay thế bằng Web Client ID bạn lấy được ở Bước 4B trên Google Cloud Console
  static const String _webClientId = '848526078075-2slsgsopp84r6ku42jmadaho5pmgphbr.apps.googleusercontent.com';


  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: _webClientId, // Thêm Web Client ID vào đây
    scopes: ['email', 'profile'],
  );

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AuthStatus get status => _status;
  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  AuthProvider() {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_prefsEmailKey);
    if (email != null) {
      _currentUser = AppUser(
        displayName: prefs.getString(_prefsNameKey) ?? email.split('@').first,
        email: email,
        photoUrl: prefs.getString(_prefsPhotoKey),
      );
      _status = AuthStatus.authenticated;
    } else {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<void> _persistSession(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsEmailKey, user.email);
    await prefs.setString(_prefsNameKey, user.displayName);
    if (user.photoUrl != null) {
      await prefs.setString(_prefsPhotoKey, user.photoUrl!);
    }
  }

  /// Đăng nhập bằng Google (OAuth2) — dùng email Google của người dùng
  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // ================= LẤY TOKEN Ở ĐÂY =================
      final GoogleSignInAuthentication auth = await account.authentication;

      final String? accessToken = auth.accessToken; // Access Token dùng gọi Google API trực tiếp
      final String? idToken = auth.idToken;         // ID Token (JWT) dùng gửi lên Backend server xác thực

      print('Access Token: $accessToken');
      print('ID Token: $idToken');
      // ====================================================

      final user = AppUser(
        displayName: account.displayName ?? account.email.split('@').first,
        email: account.email,
        photoUrl: account.photoUrl,
      );

      await _persistSession(user);

      _currentUser = user;
      _status = AuthStatus.authenticated;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Đăng nhập thất bại: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Đăng nhập bằng email/mật khẩu thường (demo, thay bằng API backend thật)
  Future<bool> signInWithEmail(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 900)); // giả lập gọi API

    if (email.isEmpty || !email.contains('@')) {
      _errorMessage = 'Email không hợp lệ';
      _isLoading = false;
      notifyListeners();
      return false;
    }
    if (password.length < 6) {
      _errorMessage = 'Mật khẩu phải từ 6 ký tự trở lên';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    final user = AppUser(
      displayName: email.split('@').first,
      email: email,
    );
    await _persistSession(user);

    _currentUser = user;
    _status = AuthStatus.authenticated;
    _isLoading = false;
    notifyListeners();
    return true;
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Bỏ qua nếu phiên hiện tại không phải Google
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsEmailKey);
    await prefs.remove(_prefsNameKey);
    await prefs.remove(_prefsPhotoKey);

    _currentUser = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
