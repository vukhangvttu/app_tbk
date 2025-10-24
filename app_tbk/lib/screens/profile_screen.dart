import 'package:app_tbk/features/auth/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:app_tbk/screens/notifications_settings_screen.dart'; // Thêm import này

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

  @override
  void initState() {
    super.initState();
    _checkBiometricSupport();
    _loadBiometricSetting();
    _loadThemeMode();
  }

  // Load theme mode từ SharedPreferences nếu không được truyền vào
  Future<void> _loadThemeMode() async {
    if (widget.currentThemeMode == null) {
      final prefs = await SharedPreferences.getInstance();
      final themeModeString = prefs.getString('themeMode') ?? 'system';
      setState(() {
        _themeMode = ThemeMode.values.firstWhere(
              (e) => e.toString() == 'ThemeMode.$themeModeString',
          orElse: () => ThemeMode.system,
        );
      });
    } else {
      setState(() {
        _themeMode = widget.currentThemeMode!;
      });
    }
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
  Future<bool> _showPasswordDialog() async {
    final TextEditingController passwordController = TextEditingController();
    bool passwordError = false;

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
                  errorText: passwordError ? 'Mật khẩu không đúng' : null,
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
                // Giả lập xác thực mật khẩu
                bool isValid = passwordController.text == '123456';
                if (isValid) {
                  Navigator.pop(context, true);
                } else {
                  setState(() {
                    passwordError = true;
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
      // Yêu cầu nhập mật khẩu trước khi bật sinh trắc học
      bool passwordVerified = await _showPasswordDialog();
      if (!passwordVerified) return;

      bool authenticated = await _authenticateWithBiometrics();
      if (authenticated) {
        // Lưu thông tin đăng nhập vào secure storage
        await _storage.write(key: 'saved_mssv', value: _mssv);
        await _storage.write(key: 'auth_token', value: 'fake_token_$_mssv');
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
      bool authenticated = await _authenticateWithBiometrics();
      if (authenticated) {
        await _saveBiometricSetting(false);
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
          title: const Text('Chọn giao diện'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildThemeOption(
                title: 'Theo hệ thống',
                subtitle: 'Tự động thay đổi theo cài đặt thiết bị',
                icon: Icons.brightness_auto,
                mode: ThemeMode.system,
              ),
              _buildThemeOption(
                title: 'Sáng',
                subtitle: 'Giao diện sáng',
                icon: Icons.light_mode,
                mode: ThemeMode.light,
              ),
              _buildThemeOption(
                title: 'Tối',
                subtitle: 'Giao diện tối',
                icon: Icons.dark_mode,
                mode: ThemeMode.dark,
              ),
            ],
          ),
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
      onChanged: (ThemeMode? value) async {
        if (value != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('themeMode', value.toString().split('.').last);
          setState(() {
            _themeMode = value;
          });
          if (widget.onThemeChanged != null) {
            widget.onThemeChanged!(value);
          }
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
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(title),
        ],
      ),
      subtitle: Text(subtitle),
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
      expandedHeight: 100,
      floating: false,
      pinned: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        title: const Text(
          'Thông tin cá nhân',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
        titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          onPressed: () {
            // TODO: Navigate to edit profile
          },
        ),
      ],
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
      title: 'Thông tin sinh viên',
      icon: Icons.person_outline,
      children: [
        _buildInfoTile(
          icon: Icons.badge_outlined,
          title: 'Mã số sinh viên',
          value: _mssv,
          isDark: isDark,
        ),
        _buildInfoTile(
          icon: Icons.email_outlined,
          title: 'Email',
          value: _email,
          isDark: isDark,
        ),
        _buildInfoTile(
          icon: Icons.phone_outlined,
          title: 'Số điện thoại',
          value: _phone,
          isDark: isDark,
        ),
        _buildInfoTile(
          icon: Icons.class_outlined,
          title: 'Lớp',
          value: _lop,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildSecuritySection(ThemeData theme, bool isDark) {
    return _buildSection(
      theme,
      isDark,
      title: 'Bảo mật',
      icon: Icons.security_outlined,
      children: [
        _buildSwitchTile(
          icon: _getBiometricIcon(),
          title: 'Đăng nhập bằng $_biometricType',
          subtitle: _canCheckBiometrics && _availableBiometrics.isNotEmpty
              ? 'Sử dụng $_biometricType để đăng nhập nhanh'
              : 'Thiết bị không hỗ trợ',
          value: _biometricEnabled,
          onChanged: _canCheckBiometrics && _availableBiometrics.isNotEmpty
              ? _toggleBiometric
              : null,
          isDark: isDark,
        ),
        _buildActionTile(
          icon: Icons.lock_outline,
          title: 'Đổi mật khẩu',
          subtitle: 'Thay đổi mật khẩu đăng nhập',
          onTap: () {
            // TODO: Navigate to change password
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
      title: 'Cài đặt',
      icon: Icons.settings_outlined,
      children: [
        _buildActionTile(
          icon: _getThemeIcon(),
          title: 'Giao diện',
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
          title: 'Thông báo',
          subtitle: 'Quản lý thông báo',
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
          title: 'Ngôn ngữ',
          subtitle: 'Tiếng Việt',
          onTap: () {
            // TODO: Navigate to language settings
          },
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildActionsSection(ThemeData theme, bool isDark) {
    return _buildSection(
      theme,
      isDark,
      title: 'Khác',
      icon: Icons.more_horiz,
      children: [
        _buildActionTile(
          icon: Icons.help_outline,
          title: 'Trợ giúp',
          subtitle: 'Câu hỏi thường gặp',
          onTap: () {},
          isDark: isDark,
        ),
        _buildActionTile(
          icon: Icons.info_outline,
          title: 'Về ứng dụng',
          subtitle: 'Phiên bản 1.0.0',
          onTap: () {},
          isDark: isDark,
        ),
        _buildActionTile(
          icon: Icons.logout,
          title: 'Đăng xuất',
          subtitle: 'Thoát khỏi tài khoản',
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
              ? Colors.grey[800]?.withOpacity(0.5)
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
        return 'Sáng';
      case ThemeMode.dark:
        return 'Tối';
      case ThemeMode.system:
      default:
        return 'Theo hệ thống';
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

              // Cập nhật state
              setState(() {
                _biometricEnabled = false;
              });

              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) =>  LoginScreen()),
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