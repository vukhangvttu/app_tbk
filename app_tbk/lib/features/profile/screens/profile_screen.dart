import 'dart:io';

import 'package:app_tbk/features/notification-setting/screens/notification_screen.dart';
import 'package:app_tbk/features/profile/models/profile.dart' as model;
import 'package:app_tbk/features/profile/screens/device_verification_screen.dart';
import 'package:app_tbk/features/profile/services/profile_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:app_tbk/features/auth/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:app_tbk/screens/notifications_settings_screen.dart';
import '../../../config/api_constants.dart';
import '../../auth/services/auth_service.dart';
import 'about_screen.dart';
import 'app_permissions_screen.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';
import 'face_id_setup_screen.dart';
import 'feeback_screen.dart';

class ProfileScreen extends StatefulWidget {
  final Function(int)? onTabSelected;
  final Function(ThemeMode)? onThemeChanged;
  final ThemeMode? currentThemeMode;

  const ProfileScreen({
    this.onTabSelected,
    super.key,
    this.onThemeChanged,
    this.currentThemeMode,
  });

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String _userId = '';

  // Thêm timestamp để force reload avatar
  int _avatarTimestamp = DateTime.now().millisecondsSinceEpoch;

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _daTaiThanhCong = false;

  late Future<Map<String, String>> _authHeadersFuture;

  ThemeMode _themeMode = ThemeMode.system;

  model.UserProfile _profile = model.UserProfile(
    id: '',
    userId: '',
    hoTen: 'Nguyễn Văn A',
    mssv: '0123456789',
    email: '0123456789@student.vttu.edu.vn',
    sdt: '0123456789',
    lop: '...',
    ngaySinh: '01/01/2000',
    gioiTinh: 'male',
    khoa: '',
    khoaHoc: '',
    avatarUrl: null,
  );

  @override
  void initState() {
    super.initState();
    _themeMode = widget.currentThemeMode ?? ThemeMode.system;
    _authHeadersFuture = ProfileService.getAuthHeaders();
    // FIX QUAN TRỌNG: bản cũ không gọi hàm load ở đây → màn hình treo skeleton mãi
    _loadProfile();
  }

  /// Được MainScreen gọi qua GlobalKey khi tab Cá nhân được chọn.
  /// Tải profile nếu chưa có dữ liệu; đã tải rồi thì bỏ qua để khỏi nhấp nháy.
  void loadTab(int tabIndex) {
    if (!_daTaiThanhCong && mounted) {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final profile = await ProfileService.fetchProfile(context);

      debugPrint('avatarUrl: ${profile?.avatarUrl}');

      if (!mounted) return;
      if (profile != null) {
        final userId = await AuthService.getUserId() ?? '';
        if (!mounted) return;
        setState(() {
          _profile = profile;
          _userId = userId;
          _isLoading = false;
          _hasError = false;
          _daTaiThanhCong = true;
          // Update timestamp để force reload avatar
          _avatarTimestamp = DateTime.now().millisecondsSinceEpoch;
          _authHeadersFuture = ProfileService.getAuthHeaders();
        });
      } else {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _daTaiThanhCong = false;
          _errorMessage = 'profile.load_error_default'.tr();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _daTaiThanhCong = false;
        _errorMessage = e.toString();
      });
    }
  }

  // Phóng to ảnh toàn màn hình
  void _showFullScreenImage(BuildContext context) {
    final String avatarEndpoint =
        '${ApiConstants.baseUrl}/upload/avatar/original-url/$_userId?t=$_avatarTimestamp';

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: FutureBuilder<Map<String, String>>(
            future: _authHeadersFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  return InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 10.0,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: CachedNetworkImage(
                        imageUrl: avatarEndpoint,
                        httpHeaders: snapshot.data,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(
                            Icons.person_rounded,
                            size: 100,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showThemeDialog() {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('theme.title'.tr()),
          contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 20),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                _buildThemeOption(
                  dialogContext: dialogContext,
                  messenger: messenger,
                  title: 'theme.system'.tr(),
                  subtitle: 'theme.system_subtitle'.tr(),
                  icon: Icons.brightness_auto,
                  mode: ThemeMode.system,
                ),
                _buildThemeOption(
                  dialogContext: dialogContext,
                  messenger: messenger,
                  title: 'theme.light'.tr(),
                  subtitle: 'theme.light_subtitle'.tr(),
                  icon: Icons.light_mode,
                  mode: ThemeMode.light,
                ),
                _buildThemeOption(
                  dialogContext: dialogContext,
                  messenger: messenger,
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
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('profile.cancel'.tr()),
            ),
          ],
        );
      },
    );
  }

  Widget _buildThemeOption({
    required BuildContext dialogContext,
    required ScaffoldMessengerState messenger,
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
          if (!mounted) return;
          setState(() => _themeMode = value);
          widget.onThemeChanged?.call(value);
          Navigator.pop(dialogContext);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'profile.theme_changed'.tr(namedArgs: {'mode': title}),
              ),
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
      backgroundColor:
      isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: _isLoading
          ? Shimmer.fromColors(
        baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
        child: _buildTabSkeleton(),
      )
          : _hasError
          ? _buildErrorView(isDark)
          : CustomScrollView(
        slivers: [
          _buildAppBar(theme, isDark),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _AnimatedItem(
                    index: 0,
                    child: _buildProfileHeader(theme, isDark)),
                _AnimatedItem(
                    index: 1,
                    child: _buildInfoSection(theme, isDark)),
                const SizedBox(height: 16),
                _AnimatedItem(
                    index: 2,
                    child: _buildSecuritySection(theme, isDark)),
                const SizedBox(height: 16),
                _AnimatedItem(
                    index: 3,
                    child: _buildSettingsSection(theme, isDark)),
                const SizedBox(height: 16),
                _AnimatedItem(
                    index: 4,
                    child: _buildActionsSection(theme, isDark)),
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
      automaticallyImplyLeading: false,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      floating: false,
      pinned: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      title: Text(
        'profile.title_1'.tr(),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 22,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const EditProfileScreen(),
              ),
            );

            if (result == true && mounted) {
              _loadProfile();
            }
          },
        ),
      ],
    );
  }

  Widget _buildProfileHeader(ThemeData theme, bool isDark) {
    final hasAvatar = _profile.mssv.isNotEmpty && _userId.isNotEmpty;
    final String avatarEndpoint =
        '${ApiConstants.baseUrl}/upload/avatar/thumb-url/$_userId?t=$_avatarTimestamp';

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Avatar với GestureDetector để zoom
          GestureDetector(
            onTap: hasAvatar ? () => _showFullScreenImage(context) : null,
            child: Container(
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
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipOval(
                child: hasAvatar
                    ? FutureBuilder<Map<String, String>>(
                  future: _authHeadersFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    return CachedNetworkImage(
                      imageUrl: avatarEndpoint,
                      httpHeaders: snapshot.data,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      errorWidget: (context, url, error) {
                        debugPrint('Lỗi load avatar: $error');
                        return _buildInitialAvatar(theme);
                      },
                    );
                  },
                )
                    : _buildInitialAvatar(theme),
              ),
            ),
          ),

          const SizedBox(height: 16),

          Text(
            _profile.hoTen,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),

          const SizedBox(height: 4),

          Text(
            'MSSV: ${_profile.mssv}',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialAvatar(ThemeData theme) {
    return Center(
      child: Text(
        _profile.hoTen.isNotEmpty ? _profile.hoTen[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
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
          icon: Icons.email_outlined,
          title: 'profile.email'.tr(),
          value: _profile.email,
          isDark: isDark,
        ),
        _buildInfoTile(
          icon: Icons.calendar_today_outlined,
          title: 'profile.ngaysinh'.tr(),
          value: _profile.ngaySinh,
          isDark: isDark,
        ),
        _buildInfoTile(
          icon: Icons.wc_outlined,
          title: 'profile.gender'.tr(),
          value: _profile.gioiTinh == 'male'
              ? 'profile.male'.tr()
              : 'profile.female'.tr(),
          isDark: isDark,
        ),
        _buildInfoTile(
          icon: Icons.phone_outlined,
          title: 'profile.phone'.tr(),
          value: _profile.sdt,
          isDark: isDark,
        ),
        _buildInfoTile(
          icon: Icons.class_outlined,
          title: 'profile.class'.tr(),
          value: '${_profile.lop} ${_profile.khoaHoc}',
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildSecuritySection(ThemeData theme, bool isDark) {
    return _buildSection(
      theme,
      isDark,
      title: 'profile.security'.tr(),
      icon: Icons.security_outlined,
      children: [
        _buildActionTile(
          icon: Icons.lock_outline,
          title: 'profile.change_password'.tr(),
          subtitle: 'profile.change_password_subtitle'.tr(),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ChangePasswordScreen(),
              ),
            );
          },
          isDark: isDark,
        ),
        _buildActionTile(
          icon: Icons.devices_rounded,
          title: 'profile.device'.tr(),
          subtitle: 'profile.device_subtitle'.tr(),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const DeviceVerificationScreen(),
              ),
            );
          },
          isDark: isDark,
        ),
        _buildActionTile(
          icon: Icons.face_rounded,
          title: 'profile.face_id'.tr(),
          subtitle: 'profile.face_id_subtitle'.tr(),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const FaceIdSetupScreen(),
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
              MaterialPageRoute(
                  builder: (context) => const NotificationSettingsScreen()),
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
          icon: Icons.security_rounded,
          title: 'Quyền ứng dụng',
          subtitle: 'Quản lý quyền Vị trí, Máy ảnh & Thông báo',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AppPermissionsScreen(),
              ),
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
          subtitle: _getLanguageName(),
          onTap: _showLanguageDialog,
          isDark: isDark,
        ),
      ],
    );
  }

  String _getLanguageName() {
    final locale = context.locale;
    if (locale.languageCode == 'vi') {
      return 'profile.vietnamese'.tr();
    } else if (locale.languageCode == 'en') {
      return 'profile.english'.tr();
    }
    return 'profile.vietnamese'.tr();
  }

  void _showLanguageDialog() {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('language.title'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<Locale>(
              title: Text('profile.vietnamese'.tr()),
              value: const Locale('vi', 'VN'),
              groupValue: context.locale,
              onChanged: (value) async {
                if (value == null) return;
                Navigator.pop(dialogContext);
                await context.setLocale(value);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'language.changed'
                          .tr(namedArgs: {'language': 'Tiếng Việt'}),
                    ),
                  ),
                );
              },
            ),
            RadioListTile<Locale>(
              title: Text('profile.english'.tr()),
              value: const Locale('en', 'US'),
              groupValue: context.locale,
              onChanged: (value) async {
                if (value == null) return;
                Navigator.pop(dialogContext);
                await context.setLocale(value);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'language.changed'
                          .tr(namedArgs: {'language': 'English'}),
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
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const FeedbackScreen()),
            );
          },
          isDark: isDark,
        ),
        _buildActionTile(
          icon: Icons.info_outline,
          title: 'profile.about'.tr(),
          subtitle: 'profile.about_subtitle'.tr(),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AboutAppScreen()),
            );
          },
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
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.grey.withValues(alpha: 0.1),
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
      dense: true,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.grey[800]?.withValues(alpha: 0.5)
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
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

  IconData _getThemeIcon() {
    switch (_themeMode) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
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
        return 'theme.system'.tr();
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.logout,
          color: Colors.red,
          size: 48,
        ),
        title: Text('profile.logout_title'.tr()),
        content: Text('profile.logout_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('profile.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () async {
              await AuthService.logout();

              if (!mounted) return;
              Navigator.pop(dialogContext);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('profile.logout_title'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(isDark ? 0.2 : 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(isDark ? 0.3 : 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_off_rounded,
                    color: Colors.red,
                    size: 48,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'profile.load_error_title'.tr(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage.isNotEmpty
                          ? _errorMessage
                          : 'profile.load_error_default'.tr(),
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loadProfile,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded,
                    size: 22, color: Colors.white),
                label: Text(
                  'profile.retry'.tr(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTabSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 50,
          pinned: true,
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Container(width: 120, height: 20, color: baseColor),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(width: 32, height: 32, color: baseColor),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: baseColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(width: 180, height: 24, color: baseColor),
                    const SizedBox(height: 8),
                    Container(width: 120, height: 16, color: highlightColor),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSkeletonSection(
                titleWidth: 140,
                iconColor: baseColor,
                rows: 5,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _buildSkeletonSection(
                titleWidth: 100,
                iconColor: baseColor,
                rows: 2,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _buildSkeletonSection(
                titleWidth: 90,
                iconColor: baseColor,
                rows: 3,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _buildSkeletonSection(
                titleWidth: 60,
                iconColor: baseColor,
                rows: 3,
                isDark: isDark,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonSection({
    required double titleWidth,
    required Color iconColor,
    required int rows,
    required bool isDark,
  }) {
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(width: 20, height: 20, color: iconColor),
                const SizedBox(width: 8),
                Container(width: titleWidth, height: 16, color: base),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.grey),
          ...List.generate(
              rows,
                  (index) => ListTile(
                leading: Container(width: 40, height: 40, color: base),
                title: Container(width: 100, height: 16, color: base),
                subtitle: Container(
                    width: double.infinity,
                    height: 14,
                    color: highlight),
                trailing: Icon(Icons.arrow_forward_ios,
                    size: 16, color: highlight),
              )),
        ],
      ),
    );
  }
}

/// Animation mờ dần + trượt lên khi section xuất hiện
class _AnimatedItem extends StatelessWidget {
  final int index;
  final Widget child;
  const _AnimatedItem({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 250 + (index * 80).clamp(0, 400)),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
