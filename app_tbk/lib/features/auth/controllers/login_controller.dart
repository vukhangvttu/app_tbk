import 'dart:async';

import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/auth_state_manager.dart';

class LoginController extends GetxController {
  final LocalAuthentication _localAuth = LocalAuthentication();

  // ========== OBSERVABLES ==========
  var isLoading = false.obs;
  var biometricType = ''.obs;
  var canCheckBiometrics = false.obs;
  var biometricEnabled = false.obs;
  var availableBiometrics = <BiometricType>[].obs;

  @override
  void onInit() {
    super.onInit();
    initBiometric();
    // Không tự động chạy _startTokenRefreshTimer() khi chưa login
  }

  @override
  void onClose() {
    _tokenRefreshTimer?.cancel();
    super.onClose();
  }

  // ========== TOKEN REFRESH TIMER ==========
  Timer? _tokenRefreshTimer;

  /// Tự động kiểm tra và refresh token mỗi 5 phút (chỉ chạy khi đã đăng nhập)
  void _startTokenRefreshTimer() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (timer) async {
        if (AuthStateManager().currentState != AuthState.authenticated) {
          timer.cancel();
          return;
        }
        final isValid = await AuthService.isTokenValid();
        if (!isValid) {
          print('⚠️ Token không hợp lệ - Dừng timer');
          timer.cancel();
        }
      },
    );
  }

  // ========== BIOMETRIC FUNCTIONS ==========

  Future<void> initBiometric() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      canCheckBiometrics.value = canCheck && isSupported;

      final available = await _localAuth.getAvailableBiometrics();
      availableBiometrics.value = available;

      if (available.contains(BiometricType.face)) {
        biometricType.value = 'Face ID';
      } else if (available.contains(BiometricType.fingerprint)) {
        biometricType.value = 'Vân tay';
      } else if (available.contains(BiometricType.iris)) {
        biometricType.value = 'Mống mắt';
      } else {
        biometricType.value = 'Sinh trắc học';
      }

      biometricEnabled.value = await AuthService.isBiometricEnabled();

      print('✅ Biometric initialized: ${biometricType.value}, Enabled: ${biometricEnabled.value}');
    } catch (e) {
      print('❌ Lỗi khởi tạo sinh trắc học: $e');
      canCheckBiometrics.value = false;
      biometricEnabled.value = false;
    }
  }

  Future<bool> authenticateBiometric({String? reason}) async {
    try {
      if (!canCheckBiometrics.value) {
        print('❌ Thiết bị không hỗ trợ sinh trắc học');
        return false;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: reason ?? 'Xác thực để tiếp tục',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      print(authenticated ? '✅ Xác thực sinh trắc học thành công' : '❌ Xác thực sinh trắc học thất bại');
      return authenticated;
    } catch (e) {
      print('❌ Lỗi xác thực sinh trắc học: $e');
      return false;
    }
  }

  Future<bool> canAutoLoginWithBiometric() async {
    try {
      if (!biometricEnabled.value || !canCheckBiometrics.value) {
        print('❌ Sinh trắc học chưa được bật hoặc không hỗ trợ');
        return false;
      }

      final canAuto = await AuthService.canAutoLoginWithBiometric();
      print(canAuto ? '✅ Có thể tự động đăng nhập' : '❌ Không thể tự động đăng nhập (token hết hạn)');
      return canAuto;
    } catch (e) {
      print('❌ Lỗi kiểm tra auto login: $e');
      return false;
    }
  }

  Future<bool> enableBiometricWithAuth(String mssv, String password) async {
    try {
      if (!canCheckBiometrics.value) {
        print('❌ Thiết bị không hỗ trợ sinh trắc học');
        return false;
      }

      // Xác thực sinh trắc học
      final authenticated = await authenticateBiometric(
        reason: 'Xác thực để bật ${biometricType.value}',
      );

      if (!authenticated) {
        print('❌ Xác thực sinh trắc học thất bại');
        return false;
      }

      // Đăng nhập lại để lấy tokens mới
      isLoading.value = true;
      final success = await AuthService.loginWithBiometric(mssv, password);
      isLoading.value = false;

      if (!success) {
        print('❌ Không thể lấy tokens');
        return false;
      }

      // Lưu trạng thái sinh trắc học
      await AuthService.enableBiometric(true);
      biometricEnabled.value = true;

      print('✅ Đã bật sinh trắc học thành công');
      return true;
    } catch (e) {
      print('❌ Lỗi bật sinh trắc học: $e');
      isLoading.value = false;
      return false;
    }
  }

  Future<void> disableBiometric() async {
    try {
      await AuthService.enableBiometric(false);
      biometricEnabled.value = false;
      print('✅ Đã tắt sinh trắc học');
    } catch (e) {
      print('❌ Lỗi tắt sinh trắc học: $e');
    }
  }

  // ========== LOGIN FUNCTIONS ==========

  /// Đăng nhập bằng Google
  Future<bool> loginWithGoogle(String idToken) async {
    try {
      if (idToken.isEmpty) {
        throw Exception('idToken không được để trống');
      }

      isLoading.value = true;
      print('🔄 Đang đăng nhập với Google...');

      final success = await AuthService.loginWithGoogle(idToken);

      if (success) {
        print('✅ Đăng nhập Google thành công');
        _startTokenRefreshTimer();
      } else {
        print('❌ Đăng nhập Google thất bại');
      }

      return success;
    } catch (e) {
      print('❌ Lỗi đăng nhập Google: $e');
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  /// Đăng nhập thông thường
  Future<bool> login(String mssv, String password) async {
    try {
      if (mssv.isEmpty || password.isEmpty) {
        throw Exception('MSSV và mật khẩu không được để trống');
      }

      isLoading.value = true;
      print('🔄 Đang đăng nhập với MSSV: $mssv');

      final success = await AuthService.login(mssv, password);

      if (success) {
        print('✅ Đăng nhập thành công');
        _startTokenRefreshTimer(); // Bắt đầu auto refresh
      } else {
        print('❌ Đăng nhập thất bại - Sai thông tin đăng nhập');
      }

      return success;
    } catch (e) {
      print('❌ Lỗi đăng nhập: $e');
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  /// Đăng nhập với sinh trắc học
  Future<bool> loginWithBiometric(String mssv, String password) async {
    try {
      if (mssv.isEmpty || password.isEmpty) {
        throw Exception('MSSV và mật khẩu không được để trống');
      }

      isLoading.value = true;
      print('🔄 Đang đăng nhập với sinh trắc học - MSSV: $mssv');

      final success = await AuthService.loginWithBiometric(mssv, password);

      if (success) {
        print('✅ Đăng nhập sinh trắc học thành công');
        _startTokenRefreshTimer();
      } else {
        print('❌ Đăng nhập sinh trắc học thất bại');
      }

      return success;
    } catch (e) {
      print('❌ Lỗi đăng nhập sinh trắc học: $e');
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  /// Đăng nhập tự động bằng sinh trắc học
  Future<bool> autoLoginWithBiometric() async {
    try {
      if (!biometricEnabled.value || !canCheckBiometrics.value) {
        print('❌ Sinh trắc học chưa được bật hoặc không hỗ trợ');
        return false;
      }

      // Kiểm tra token còn hạn không
      final canAuto = await canAutoLoginWithBiometric();
      if (!canAuto) {
        print('❌ Token đã hết hạn - Cần đăng nhập lại');
        await disableBiometric();
        return false;
      }

      // Xác thực sinh trắc học
      final authenticated = await authenticateBiometric(
        reason: 'Xác thực để đăng nhập bằng ${biometricType.value}',
      );

      if (!authenticated) {
        print('❌ Xác thực sinh trắc học thất bại');
        return false;
      }

      // Đánh dấu đã xác thực trong session
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometric_authenticated', true);

      print('✅ Đăng nhập tự động thành công');
      _startTokenRefreshTimer();
      return true;
    } catch (e) {
      print('❌ Lỗi đăng nhập tự động: $e');
      return false;
    }
  }

  // ========== TOKEN MANAGEMENT ==========

  /// Kiểm tra token có còn hợp lệ không
  Future<bool> isTokenValid() async {
    try {
      final isValid = await AuthService.isTokenValid();
      print(isValid ? '✅ Token còn hợp lệ' : '❌ Token đã hết hạn');
      return isValid;
    } catch (e) {
      print('❌ Lỗi kiểm tra token: $e');
      return false;
    }
  }

  /// Refresh access token thủ công
  Future<bool> refreshToken() async {
    try {
      isLoading.value = true;
      print('🔄 Đang refresh access token...');

      final success = await AuthService.refreshAccessToken();

      if (success) {
        print('✅ Refresh token thành công');
      } else {
        print('❌ Refresh token thất bại - Cần đăng nhập lại');
      }

      return success;
    } catch (e) {
      print('❌ Lỗi refresh token: $e');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /// Lấy thông tin người dùng đã lưu
  Future<Map<String, String?>> getSavedUserInfo() async {
    try {
      final mssv = await AuthService.getSavedMssv();
      final idSinhVien = await AuthService.getIdSinhVien();
      final accessToken = await AuthService.getAccessToken();
      final refreshToken = await AuthService.getRefreshToken();

      return {
        'mssv': mssv,
        'idSinhVien': idSinhVien,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
      };
    } catch (e) {
      print('❌ Lỗi lấy thông tin người dùng: $e');
      return {
        'mssv': null,
        'idSinhVien': null,
        'accessToken': null,
        'refreshToken': null,
      };
    }
  }

  // ========== LOGOUT ==========

  /// Đăng xuất
  Future<void> logout() async {
    try {
      isLoading.value = true;
      print('🔄 Đang đăng xuất...');

      await AuthService.logout();
      biometricEnabled.value = false;
      _tokenRefreshTimer?.cancel();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('biometric_authenticated');

      print('✅ Đăng xuất thành công');
    } catch (e) {
      print('❌ Lỗi đăng xuất: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // ========== VALIDATION ==========

  String? validateMssv(String? value) {
    if (value == null || value.isEmpty) {
      return 'MSSV không được để trống';
    }
    if (value.length < 5) {
      return 'MSSV phải có ít nhất 5 ký tự';
    }
    if (value.length > 15) {
      return 'MSSV không được quá 15 ký tự';
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Mật khẩu không được để trống';
    }
    if (value.length < 6) {
      return 'Mật khẩu phải có ít nhất 6 ký tự';
    }
    if (value.length > 20) {
      return 'Mật khẩu không được quá 20 ký tự';
    }
    return null;
  }
}