import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';

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
  }

  // ========== BIOMETRIC FUNCTIONS ==========

  /// Khởi tạo và kiểm tra hỗ trợ sinh trắc học
  Future<void> initBiometric() async {
    try {
      // Kiểm tra thiết bị có hỗ trợ sinh trắc học không
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      canCheckBiometrics.value = canCheck && isSupported;

      // Lấy danh sách các loại sinh trắc học có sẵn
      final available = await _localAuth.getAvailableBiometrics();
      availableBiometrics.value = available;

      // Xác định loại sinh trắc học
      if (available.contains(BiometricType.face)) {
        biometricType.value = 'Face ID';
      } else if (available.contains(BiometricType.fingerprint)) {
        biometricType.value = 'Vân tay';
      } else if (available.contains(BiometricType.iris)) {
        biometricType.value = 'Mống mắt';
      } else {
        biometricType.value = 'Sinh trắc học';
      }

      // Kiểm tra trạng thái đã bật sinh trắc học chưa
      biometricEnabled.value = await AuthService.isBiometricEnabled();

      print('✅ Biometric initialized: ${biometricType
          .value}, Enabled: ${biometricEnabled.value}');
    } catch (e) {
      print('❌ Lỗi khởi tạo sinh trắc học: $e');
      canCheckBiometrics.value = false;
      biometricEnabled.value = false;
    }
  }

  /// Xác thực sinh trắc học (không đăng nhập, chỉ xác thực)
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

      print(authenticated
          ? '✅ Xác thực sinh trắc học thành công'
          : '❌ Xác thực sinh trắc học thất bại');
      return authenticated;
    } catch (e) {
      print('❌ Lỗi xác thực sinh trắc học: $e');
      return false;
    }
  }

  /// Kiểm tra có thể tự động đăng nhập bằng sinh trắc học không
  Future<bool> canAutoLoginWithBiometric() async {
    try {
      if (!biometricEnabled.value || !canCheckBiometrics.value) {
        print('❌ Sinh trắc học chưa được bật hoặc không hỗ trợ');
        return false;
      }

      final canAuto = await AuthService.canAutoLoginWithBiometric();
      print(canAuto
          ? '✅ Có thể tự động đăng nhập'
          : '❌ Không thể tự động đăng nhập (token hết hạn)');
      return canAuto;
    } catch (e) {
      print('❌ Lỗi kiểm tra auto login: $e');
      return false;
    }
  }

  /// Bật sinh trắc học (yêu cầu xác thực trước)
  Future<bool> enableBiometricWithAuth(String mssv, String password) async {
    try {
      if (!canCheckBiometrics.value) {
        print('❌ Thiết bị không hỗ trợ sinh trắc học');
        return false;
      }

      // Bước 1: Xác thực sinh trắc học
      final authenticated = await authenticateBiometric(
        reason: 'Xác thực để bật ${biometricType.value}',
      );

      if (!authenticated) {
        print('❌ Xác thực sinh trắc học thất bại');
        return false;
      }

      // Bước 2: Đăng nhập lại với rememberMe = true để lấy token dài hạn
      isLoading.value = true;
      final success = await AuthService.loginWithBiometric(mssv, password);
      isLoading.value = false;

      if (!success) {
        print('❌ Không thể lấy token dài hạn');
        return false;
      }

      // Bước 3: Lưu trạng thái sinh trắc học đã bật
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

  /// Tắt sinh trắc học
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

  /// Đăng nhập thông thường (Token ngắn hạn - 1 ngày)
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
      } else {
        print('❌ Đăng nhập thất bại - Sai thông tin đăng nhập');
      }

      return success;
    } catch (e) {
      print('❌ Lỗi đăng nhập: $e');
      rethrow; // Ném lại lỗi để screen xử lý
    } finally {
      isLoading.value = false;
    }
  }

  /// Đăng nhập với sinh trắc học (Token dài hạn - 30 ngày)
  Future<bool> loginWithBiometric(String mssv, String password) async {
    try {
      if (mssv.isEmpty || password.isEmpty) {
        throw Exception('MSSV và mật khẩu không được để trống');
      }

      isLoading.value = true;
      print('🔄 Đang đăng nhập với sinh trắc học - MSSV: $mssv');

      final success = await AuthService.loginWithBiometric(mssv, password);

      if (success) {
        print('✅ Đăng nhập sinh trắc học thành công (Token 30 ngày)');
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

  /// Đăng nhập tự động bằng sinh trắc học (khi mở app)
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
        await disableBiometric(); // Tắt sinh trắc học khi token hết hạn
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

  /// Lấy thông tin người dùng đã lưu
  Future<Map<String, String?>> getSavedUserInfo() async {
    try {
      final mssv = await AuthService.getSavedMssv();
      final idSinhVien = await AuthService.getIdSinhVien();
      final token = await AuthService.getToken();

      return {
        'mssv': mssv,
        'idSinhVien': idSinhVien,
        'token': token,
      };
    } catch (e) {
      print('❌ Lỗi lấy thông tin người dùng: $e');
      return {
        'mssv': null,
        'idSinhVien': null,
        'token': null,
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

      // Xóa trạng thái xác thực
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

  /// Validate MSSV
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

  /// Validate Password
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
