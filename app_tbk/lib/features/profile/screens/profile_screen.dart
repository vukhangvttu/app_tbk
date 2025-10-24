import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:app_tbk/features/auth/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:app_tbk/screens/notifications_settings_screen.dart';
import 'package:get/get.dart' hide Trans;
import '../../auth/controllers/login_controller.dart';
import '../../auth/services/auth_service.dart'; // Thêm import này

class ProfileScreen extends StatefulWidget {
  final Function(ThemeMode)? onThemeChanged;
  final ThemeMode? currentThemeMode;

  const ProfileScreen({
    super.key,
    this.onThemeChanged,
    this.currentThemeMode,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _biometricEnabled = false;
  bool _canCheckBiometrics = false;
  List<BiometricType> _availableBiometrics = [];
  String _biometricType = '';

  // Thông tin user mẫu - thay bằng dữ liệu thực tế
  final String _userName = 'Nguyễn Văn A';
  final String _mssv = '7231620971';
  final String _email = '7231620971@student.vttu.edu.vn';
  final String _phone = '0123456789';
  final String _lop = 'CNTT K16';

  // Theme mode local state
  ThemeMode _themeMode = ThemeMode.system;

  final LoginController _authController = Get.put(LoginController());


  @override
  void initState() {
    super.initState();
    _checkBiometricSupport();
    _loadBiometricSetting();
    // _loadThemeMode();
  }

  // Kiểm tra thiết bị có hỗ trợ sinh trắc học không
  Future<void> _checkBiometricSupport() async {
    try {
      bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      bool isDeviceSupported = await _localAuth.isDeviceSupported();
      List<BiometricType> availableBiometrics = await _localAuth.getAvailableBiometrics();

      setState(() {
        _canCheckBiometrics = canCheckBiometrics && isDeviceSupported;
        _availableBiometrics = availableBiometrics;

        if (availableBiometrics.contains(BiometricType.face)) {
          _biometricType = 'Face ID';
        } else if (availableBiometrics.contains(BiometricType.fingerprint)) {
          _biometricType = 'Vân tay';
        } else if (availableBiometrics.contains(BiometricType.iris)) {
          _biometricType = 'Mống mắt';
        } else {
          _biometricType = 'Sinh trắc học';
        }
      });

      print('🔍 Biometric Support Check:');
      print('  - canCheckBiometrics: $canCheckBiometrics');
      print('  - isDeviceSupported: $isDeviceSupported');
      print('  - Available types: $availableBiometrics');
    } catch (e) {
      print('❌ Lỗi kiểm tra sinh trắc học: $e');
      setState(() {
        _canCheckBiometrics = false;
        _availableBiometrics = [];
        _biometricType = 'Sinh trắc học';
      });
    }
  }

  // Load cài đặt sinh trắc học từ SharedPreferences
  Future<void> _loadBiometricSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    });
  }

  // Lưu cài đặt sinh trắc học
  Future<void> _saveBiometricSetting(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', enabled);
  }

  // Xác thực sinh trắc học
  Future<bool> _authenticateWithBiometrics() async {
    try {
      bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Xác thực để bật/tắt đăng nhập bằng $_biometricType',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      return authenticated;
    } on PlatformException catch (e) {
      print('Lỗi xác thực: $e');
      _showErrorDialog('Lỗi xác thực: ${e.message}');
      return false;
    }
  }

  // Dialog yêu cầu mật khẩu
  Future<bool> _showPasswordDialog(isBiometricEnabled) async {
    final TextEditingController passwordController = TextEditingController();
    String? errorMessage; // Lưu thông báo lỗi để hiển thị trên giao diện
    // Lấy trạng thái biometric từ SharedPreferences
    final prefs = await SharedPreferences.getInstance();


    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Xác thực mật khẩu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  errorText: errorMessage, // Hiển thị thông báo lỗi
                  errorMaxLines: 3, // Đảm bảo thông báo lỗi dài được hiển thị đầy đủ
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                final username = await AuthService.getSavedMssv();
                if (username == null || username.isEmpty) {
                  throw Exception('Không tìm thấy thông tin sinh viên');
                }

                String password = passwordController.text;

                setState(() {
                  errorMessage = null; // Xóa lỗi cũ trước khi gọi API
                });

                try {
                  bool isValid;
                  if (isBiometricEnabled) {
                    isValid = await _authController.loginWithBiometric(username, password);
                  } else {
                    isValid = await _authController.login(username, password);
                  }

                  if (isValid) {
                    // Lưu trạng thái biometric nếu xác thực thành công
                    await prefs.setBool('biometric_enabled', true);
                    print('Lưu biometric_enabled: true'); // Debug
                    Navigator.pop(context, true);
                  } else {
                    setState(() {
                      errorMessage = 'Mật khẩu không đúng';
                    });
                  }
                } catch (e) {
                  print('Lỗi trong _showPasswordDialog: $e'); // Debug lỗi
                  String message = 'Lỗi không xác định';
                  try {
                    // Parse lỗi từ chuỗi: "Exception: Lỗi server: 401 - {...}"
                    final errorStr = e.toString();
                    final jsonStart = errorStr.indexOf('{');
                    if (jsonStart != -1) {
                      final jsonStr = errorStr.substring(jsonStart);
                      final errorJson = jsonDecode(jsonStr) as Map<String, dynamic>;
                      final errorCode = errorJson['code'] as int?;
                      final errorMsg = errorJson['message'] as String?;

                      // Ánh xạ mã lỗi với thông báo
                      switch (errorCode) {
                        case 1003:
                          message = 'Xác thực thất bại: Người dùng chưa được xác thực';
                          break;
                        case 1004:
                          message = 'Mật khẩu không hợp lệ';
                          break;
                        case 1005:
                          message = 'Tài khoản bị khóa';
                          break;
                        default:
                          message = errorMsg ?? 'Lỗi không xác định';
                      }
                    } else {
                      message = 'Lỗi server không xác định';
                    }
                  } catch (parseError) {
                    print('Lỗi parse JSON: $parseError'); // Debug lỗi parse
                    message = 'Lỗi: $e';
                  }

                  setState(() {
                    errorMessage = message; // Cập nhật thông báo lỗi
                  });
                }
              },
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );

    return result ?? false;
  }
  // Toggle sinh trắc học
  Future<void> _toggleBiometric(bool value) async {
    if (!_canCheckBiometrics || _availableBiometrics.isEmpty) {
      _showBiometricSetupDialog();
      return;
    }

    if (value) {
      // Bật sinh trắc học
      bool passwordVerified = await _showPasswordDialog(value);
      if (!passwordVerified) return;

      bool authenticated = await _authenticateWithBiometrics();
      if (authenticated) {

         await _saveBiometricSetting(true);

        setState(() {
          _biometricEnabled = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Đã bật đăng nhập bằng $_biometricType')),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } else {
      // Tắt sinh trắc học
      bool authenticated = await _authenticateWithBiometrics();
      if (authenticated) {
        await _saveBiometricSetting(false);

        // ✅ QUAN TRỌNG: Reset trạng thái xác thực khi tắt
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('biometric_authenticated');

        setState(() {
          _biometricEnabled = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.cancel, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Đã tắt đăng nhập bằng $_biometricType')),
                ],
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    }
  }
  void _showBiometricSetupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.fingerprint_outlined,
          color: Colors.orange[400],
          size: 64,
        ),
        title: const Text('Thiết lập sinh trắc học'),
        content: const Text(
          'Thiết bị của bạn chưa hỗ trợ hoặc chưa cài đặt sinh trắc học.\n\n'
              '📱 Hướng dẫn:\n\n'
              'Android:\n'
              '1. Vào Cài đặt > Bảo mật\n'
              '2. Chọn "Vân tay" hoặc "Face Unlock"\n'
              '3. Đăng ký sinh trắc học\n'
              '4. Quay lại app này\n\n'
              'iOS:\n'
              '1. Vào Cài đặt > Face ID & Passcode\n'
              '2. Hoặc Touch ID & Passcode\n'
              '3. Đăng ký sinh trắc học\n\n'
              '⚠️ Lưu ý: Emulator không hỗ trợ sinh trắc học thực. Vui lòng test trên thiết bị thật.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.error_outline,
          color: Colors.red[400],
          size: 48,
        ),
        title: const Text('Thông báo'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('theme.title'.tr()),
          contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 20),
          content: SizedBox(
            width: double.maxFinite, // Đảm bảo AlertDialog sử dụng chiều rộng tối đa hợp lý
            // height: 2, // Giới hạn chiều cao của content
            child: ListView(
              shrinkWrap: true, // Đảm bảo ListView chỉ chiếm không gian cần thiết
              children: [
                _buildThemeOption(
                  title: 'theme.system'.tr(),
                  subtitle: 'theme.system_subtitle'.tr(),
                  icon: Icons.brightness_auto,
                  mode: ThemeMode.system,
                ),
                _buildThemeOption(
                  title: 'theme.light'.tr(),
                  subtitle: 'theme.light_subtitle'.tr(),
                  icon: Icons.light_mode,
                  mode: ThemeMode.light,
                ),
                _buildThemeOption(
                  title: 'theme.dark'.tr(),
                  subtitle: 'theme.dark_subtitle'.tr(),
                  icon: Icons.dark_mode,
                  mode: ThemeMode.dark,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Hủy'.tr()),
            ),
          ],
        );
      },
    );
  }

  Widget _buildThemeOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required ThemeMode mode,
  }) {
    final isSelected = _themeMode == mode;

    return RadioListTile<ThemeMode>(
      value: mode,
      groupValue: _themeMode,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (ThemeMode? value) async {
        if (value != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('themeMode', value.toString().split('.').last);
          setState(() => _themeMode = value);
          widget.onThemeChanged?.call(value);
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã chuyển sang chế độ $title'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      title: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      selected: isSelected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(theme, isDark),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildProfileHeader(theme, isDark),
                const SizedBox(height: 24),
                _buildInfoSection(theme, isDark),
                const SizedBox(height: 16),
                _buildSecuritySection(theme, isDark),
                const SizedBox(height: 16),
                _buildSettingsSection(theme, isDark),
                const SizedBox(height: 16),
                _buildActionsSection(theme, isDark),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(ThemeData theme, bool isDark) {
    return SliverAppBar(
      expandedHeight: 60,
      floating: false,
      pinned: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        title:  Text(
          'profile.title_1'.tr(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: false,
        titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
      ),
      // actions: [
      //   IconButton(
      //     icon: const Icon(Icons.edit_outlined),
      //     onPressed: () {
      //       // TODO: Navigate to edit profile
      //     },
      //   ),
      // ],
    );
  }

  Widget _buildProfileHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _userName[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _userName,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'MSSV: $_mssv',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(ThemeData theme, bool isDark) {
    return _buildSection(
      theme,
      isDark,
      title: 'profile.student_info'.tr(),
      icon: Icons.person_outline,
      children: [
        _buildInfoTile(
          icon: Icons.badge_outlined,
          title: 'profile.mssv'.tr(),
          value: _mssv,
          isDark: isDark,
        ),
        _buildInfoTile(
          icon: Icons.email_outlined,
          title: 'profile.email'.tr(),
          value: _email,
          isDark: isDark,
        ),
        _buildInfoTile(
          icon: Icons.phone_outlined,
          title: 'profile.phone'.tr(),
          value: _phone,
          isDark: isDark,
        ),
        _buildInfoTile(
          icon: Icons.class_outlined,
          title: 'profile.class'.tr(),
          value: _lop,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildSecuritySection(ThemeData theme, bool isDark) {
    String typeKey;

    switch (_biometricType) {
      case 'fingerprint':
        typeKey = "profile.biometric_type.fingerprint".tr();
        break;
      case 'face':
        typeKey = "profile.biometric_type.face".tr();
        break;
      default:
        typeKey = "profile.biometric_type.biometric".tr();
    }


    return _buildSection(
      theme,
      isDark,
      title: 'profile.security'.tr(),
      icon: Icons.security_outlined,
      children: [
        _buildSwitchTile(
          icon: _getBiometricIcon(),
          title: "profile.biometric_login".tr(namedArgs: {'type': typeKey}),
          subtitle: _canCheckBiometrics && _availableBiometrics.isNotEmpty
              ? "profile.biometric_subtitle".tr(namedArgs: {'type': typeKey})
              : "profile.biometric_not_supported".tr(),
          value: _biometricEnabled,
          onChanged: _canCheckBiometrics && _availableBiometrics.isNotEmpty
              ? _toggleBiometric
              : null,
          isDark: isDark,
        ),
        _buildActionTile(
          icon: Icons.lock_outline,
          title: 'profile.change_password'.tr(),
          subtitle: 'profile.change_password_subtitle'.tr(),
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text('⚙️ ' + 'profile.feature_in_development'.tr()),
                content: Text('profile.feature_in_development_description'.tr()),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('OK'),
                  ),
                ],
              ),
            );
          },
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildSettingsSection(ThemeData theme, bool isDark) {
    return _buildSection(
      theme,
      isDark,
      title: 'profile.settings'.tr(),
      icon: Icons.settings_outlined,
      children: [
        _buildActionTile(
          icon: _getThemeIcon(),
          title: 'profile.theme'.tr(),
          subtitle: _getThemeModeName(),
          onTap: _showThemeDialog,
          isDark: isDark,
          trailing: Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
        ),
        _buildActionTile(
          icon: Icons.notifications_outlined,
          title: 'profile.notifications'.tr(),
          subtitle: 'profile.notifications_subtitle'.tr(),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const NotificationSettingsScreen()),
            );
          },
          isDark: isDark,
          trailing: Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
        ),
        _buildActionTile(
          icon: Icons.language_outlined,
          title: 'profile.language'.tr(),
          subtitle: _getLanguageName(), // ✅ Hiển thị ngôn ngữ hiện tại
          onTap: _showLanguageDialog, // ✅ Mở dialog chọn ngôn ngữ
          isDark: isDark,
        ),
      ],
    );
  }


  String _getLanguageName() {
    final locale = context.locale;
    if (locale.languageCode == 'vi') {
      return 'profile.vietnamese'.tr(); // "Tiếng Việt"
    } else if (locale.languageCode == 'en') {
      return 'profile.english'.tr(); // "English"
    }
    return 'profile.vietnamese'.tr();
  }


  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('language.title'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<Locale>(
              title: Text('profile.vietnamese'.tr()),
              value: Locale('vi', 'VN'),
              groupValue: context.locale,
              onChanged: (value) async {
                await context.setLocale(value!);
                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'language.changed'.tr(namedArgs: {'language': 'Tiếng Việt'}),
                    ),
                  ),
                );
              },
            ),
            RadioListTile<Locale>(
              title: Text('profile.english'.tr()),
              value: Locale('en', 'US'),
              groupValue: context.locale,
              onChanged: (value) async {
                await context.setLocale(value!);
                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'language.changed'.tr(namedArgs: {'language': 'English'}),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsSection(ThemeData theme, bool isDark) {
    return _buildSection(
      theme,
      isDark,
      title: 'profile.other'.tr(),
      icon: Icons.more_horiz,
      children: [
        _buildActionTile(
          icon: Icons.feedback,
          title: 'profile.feedback'.tr(),
          subtitle: 'profile.sendfeedback'.tr(),
          onTap: () {},
          isDark: isDark,
        ),
        _buildActionTile(
          icon: Icons.info_outline,
          title: 'profile.about'.tr(),
          subtitle: 'profile.about_subtitle'.tr(),
          onTap: () {},
          isDark: isDark,
        ),
        _buildActionTile(
          icon: Icons.logout,
          title: 'profile.logout'.tr(),
          subtitle: 'profile.logout_subtitle'.tr(),
          onTap: _showLogoutDialog,
          isDark: isDark,
          iconColor: Colors.red,
        ),
      ],
    );
  }

  Widget _buildSection(
      ThemeData theme,
      bool isDark, {
        required String title,
        required IconData icon,
        required List<Widget> children,
      }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
    required bool isDark,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.grey[800]?.withValues(alpha:  0.5)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      subtitle: Text(
        value,
        maxLines: 1, // Giới hạn hiển thị 1 dòng
        overflow: TextOverflow.ellipsis, // Hiển thị dấu "..."
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool)? onChanged,
    required bool isDark,
  }) {
    final isDisabled = onChanged == null;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDisabled
              ? (isDark ? Colors.grey[900] : Colors.grey[200])
              : (isDark
              ? Colors.grey[800]?.withOpacity(0.5)
              : Colors.grey[100]),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isDisabled
              ? (isDark ? Colors.grey[700] : Colors.grey[400])
              : (isDark ? Colors.grey[400] : Colors.grey[600]),
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isDisabled
              ? (isDark ? Colors.grey[600] : Colors.grey[400])
              : (isDark ? Colors.white : const Color(0xFF0F172A)),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: isDark ? Colors.grey[500] : Colors.grey[600],
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
    Widget? trailing,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor != null
              ? iconColor.withOpacity(0.1)
              : (isDark
              ? Colors.grey[800]?.withOpacity(0.5)
              : Colors.grey[100]),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: iconColor ?? (isDark ? Colors.grey[400] : Colors.grey[600]),
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: iconColor ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: isDark ? Colors.grey[500] : Colors.grey[600],
        ),
      ),
      trailing: trailing ??
          Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
      onTap: onTap,
    );
  }

  IconData _getBiometricIcon() {
    if (_availableBiometrics.contains(BiometricType.face)) {
      return Icons.face;
    } else if (_availableBiometrics.contains(BiometricType.fingerprint)) {
      return Icons.fingerprint;
    } else {
      return Icons.security;
    }
  }

  IconData _getThemeIcon() {
    switch (_themeMode) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
      default:
        return Icons.brightness_auto;
    }
  }

  String _getThemeModeName() {
    switch (_themeMode) {
      case ThemeMode.light:
        return 'theme.light'.tr();
      case ThemeMode.dark:
        return 'theme.dark'.tr();
      case ThemeMode.system:
      default:
        return 'theme.system'.tr();
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.logout,
          color: Colors.red,
          size: 48,
        ),
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Xóa thông tin đăng nhập
              await _storage.delete(key: 'saved_mssv');
              await _storage.delete(key: 'auth_token');
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('biometric_enabled');
              await prefs.remove('login_timestamp');

              // ✅ QUAN TRỌNG: Reset trạng thái xác thực sinh trắc học
              await prefs.remove('biometric_authenticated');

              // Cập nhật state
              setState(() {
                _biometricEnabled = false;
              });

              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => LoginScreen()),
              );

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Đã đăng xuất thành công'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }


}