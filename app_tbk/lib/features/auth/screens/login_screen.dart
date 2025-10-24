import 'package:easy_localization/easy_localization.dart';
import 'package:app_tbk/features/auth/controllers/login_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:app_tbk/screens/main_screen.dart';
import 'package:get/get.dart' hide Trans;
import 'package:app_tbk/main.dart';

class LoginScreen extends StatefulWidget {
  final Function(ThemeMode)? onThemeChanged;
  const LoginScreen({Key? key, this.onThemeChanged}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mssvController = TextEditingController();
  final _passwordController = TextEditingController();

  final _scrollController = ScrollController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  final LoginController _authController = Get.put(LoginController());

  bool _obscurePassword = true;
  bool _isLoading = false;

  // Biometric
  bool _canCheckBiometrics = false;
  bool _biometricEnabled = false;
  List<BiometricType> _availableBiometrics = [];
  String _biometricType = '';

  @override
  void initState() {
    super.initState();
    _initBiometric();
  }

  @override
  void dispose() {
    _mssvController.dispose();
    _passwordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ========== BIOMETRIC FUNCTIONS ==========

  Future<void> _initBiometric() async {
    await _checkBiometricSupport();
    await _loadSavedCredentials();

    // ✅ Kiểm tra có thể tự động đăng nhập bằng biometric không
    if (_biometricEnabled && _canCheckBiometrics) {
      final canAutoLogin = await _authController.canAutoLoginWithBiometric();

      if (canAutoLogin) {
        // Tự động hiện prompt biometric
        await Future.delayed(const Duration(milliseconds: 300));
        _loginWithBiometric();
      }
    }
  }

  Future<void> _checkBiometricSupport() async {
    try {
      bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      bool isDeviceSupported = await _localAuth.isDeviceSupported();
      List<BiometricType> availableBiometrics = await _localAuth.getAvailableBiometrics();

      if (mounted) {
        setState(() {
          _canCheckBiometrics = canCheckBiometrics && isDeviceSupported;
          _availableBiometrics = availableBiometrics;

          if (availableBiometrics.contains(BiometricType.face)) {
            _biometricType = 'Face ID';
          } else if (availableBiometrics.contains(BiometricType.fingerprint)) {
            _biometricType = 'Vân tay';
          } else {
            _biometricType = 'Sinh trắc học';
          }
        });
      }
    } catch (e) {
      print('❌ Lỗi check biometric: $e');
    }
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
      });
    }


      String? savedMssv = await _storage.read(key: 'saved_mssv');
      if (savedMssv != null && mounted) {
        _mssvController.text = savedMssv;
      }

  }

  Future<void> _loginWithBiometric() async {
    try {
      bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Xác thực để đăng nhập bằng $_biometricType',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated && mounted) {
        setState(() => _isLoading = true);

        // ✅ Kiểm tra token còn hạn không
        final isValid = await _authController.isTokenValid();

        if (mounted) {
          setState(() => _isLoading = false);
        }

        if (isValid) {
          // 🔥 INIT SERVICES SAU KHI BIOMETRIC SUCCESS
          PostLoginInitializer.initialize().then((_) {
            debugPrint('✅ Post-login services ready (biometric)');
          }).catchError((e) {
            debugPrint('❌ Post-login init error: $e');
          });


          _navigateToMainScreen();
        } else {
          if (mounted) {
            _showErrorSnackbar('Token đã hết hạn. Vui lòng đăng nhập lại.');
            // ❌ Tắt biometric nếu token hết hạn
            await _authController.disableBiometric();
            setState(() => _biometricEnabled = false);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackbar('Xác thực thất bại: $e');
      }
    }
  }

  // ========== LOGIN FUNCTIONS ==========
  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      FocusScope.of(context).unfocus();

      setState(() => _isLoading = true);

      final mssv = _mssvController.text.trim();
      final password = _passwordController.text.trim();

      try {
        final success = await _authController.login(mssv, password);

        if (mounted) {
          setState(() => _isLoading = false);
        }

        if (mounted) {
          if (success) {

            // 🔥 INIT FIREBASE + NOTIFICATIONS SAU KHI LOGIN THÀNH CÔNG
            // ✅ QUAN TRỌNG: Truyền MSSV vào để lưu trước khi init NotificationServices
            PostLoginInitializer.initialize(context: context, mssv: mssv).then((_) {
              debugPrint('✅ Post-login services ready');
            }).catchError((e) {
              debugPrint('❌ Post-login init error: $e');
              // App vẫn hoạt động bình thường
            });

            // ✅ Hỏi có muốn bật biometric không (nếu chưa bật)
            if (_canCheckBiometrics && !_biometricEnabled) {
              _showEnableBiometricDialog(mssv, password);
            } else {
              _navigateToMainScreen();
            }
          } else {
            _showErrorDialog('login.error_login'.tr());
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        if (e is Exception) {
          if (e.toString().contains('timeout')) {
            _showErrorDialog('login.time_out'.tr());
          } else if (e.toString().contains('kết nối')) {
            _showErrorDialog('login.network'.tr());
          } else {
            _showErrorDialog('login.unknown: $e'.tr());
          }
        }
      }
    }
  }

  Future<void> _enableBiometric(String mssv, String password) async {
    try {
      bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Xác thực để bật $_biometricType',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated && mounted) {
        setState(() => _isLoading = true);

        // ✅ Gọi API lại với rememberMe = true để lấy token dài hạn
        final success = await _authController.loginWithBiometric(mssv, password);

        if (mounted) {
          setState(() => _isLoading = false);
        }

        if (success) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('biometric_enabled', true);
          setState(() {
            _biometricEnabled = true;
          });
          _showSuccessSnackbar('Đã bật đăng nhập bằng $_biometricType');
        } else {
          if (mounted) {
            _showErrorSnackbar('Không thể bật $_biometricType');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackbar('Lỗi bật $_biometricType: $e');
      }
    }
  }

  void _showEnableBiometricDialog(String mssv, String password) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(
          _getBiometricIcon(),
          color: const Color(0xFF6366F1),
          size: 64,
        ),
        title: Text('Bật đăng nhập bằng $_biometricType?'),
        content: Text(
          'Bạn có muốn sử dụng $_biometricType để đăng nhập nhanh hơn trong lần sau không?\n\n'
              'Khi bật, bạn sẽ không cần nhập mật khẩu trong vòng 30 ngày.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToMainScreen();
            },
            child: const Text('Bỏ qua'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _enableBiometric(mssv, password);
              _navigateToMainScreen();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            child: const Text('Bật ngay'),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToMainScreen() async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final themeModeString = prefs.getString('themeMode') ?? 'system';
    final currentTheme = ThemeMode.values.firstWhere(
          (e) => e.toString() == 'ThemeMode.$themeModeString',
      orElse: () => ThemeMode.system,
    );

    if (!mounted) return;

    // Đợi services ready (hoặc timeout sau 3s)
    await PostLoginInitializer.initialize()
        .timeout(const Duration(seconds: 3))
        .catchError((e) {
      debugPrint('⚠️ Post-login init timeout or error: $e');
      // Continue anyway
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MainScreen(
          onThemeChanged: widget.onThemeChanged,
          currentThemeMode: currentTheme,
        ),
      ),
    );
  }

  // ========== DIALOGS & SNACKBARS ==========

  void _showErrorDialog(String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.error_outline_rounded,
          color: Colors.red[400],
          size: 64,
        ),
        title: Text('login.login_failed'.tr()),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('common.close'.tr()),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
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

  // ========== UI BUILD ==========

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          height: size.height,
          color: theme.scaffoldBackgroundColor,
          child: SafeArea(
            child: Stack(
              children: [
                // Background decoration
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: size.height * 0.4,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: isKeyboardVisible ? 0.3 : 0.6,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            theme.scaffoldBackgroundColor.withOpacity(0),
                            isDark
                                ? const Color(0xFF6366F1).withOpacity(0.03)
                                : const Color(0xFF6366F1).withOpacity(0.05),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Decorative circles
                if (!isKeyboardVisible) ...[
                  Positioned(
                    top: -50,
                    right: -50,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF6366F1).withOpacity(0.1),
                            const Color(0xFF6366F1).withOpacity(0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -80,
                    left: -80,
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF8B5CF6).withOpacity(0.08),
                            const Color(0xFF8B5CF6).withOpacity(0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                // Content chính
                Positioned.fill(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: 24,
                      bottom: isKeyboardVisible ? keyboardHeight + 16 : 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHeader(isDark, size),
                        const SizedBox(height: 32),
                        _buildLoginForm(theme, isDark, size),
                        const SizedBox(height: 24),
                        _buildBiometricSection(theme, isDark),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, Size size) {
    final isSmallScreen = size.height < 700;
    final logoSize = isSmallScreen ? 80.0 : 90.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Icon(
            Icons.school_rounded,
            size: logoSize * 0.5,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'login.welcome'.tr(),
          style: TextStyle(
            fontSize: isSmallScreen ? 24 : 28,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'login.subtitle'.tr(),
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 15,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm(ThemeData theme, bool isDark, Size size) {
    final maxWidth = size.width > 600 ? 400.0 : double.infinity;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900]?.withValues(alpha: 0.5) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.grey.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _mssvController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                labelText: 'login.mssv'.tr(),
                hintText: 'login.mssv_hint'.tr(),
                prefixIcon: Icon(
                  Icons.person_outline_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                filled: true,
                fillColor: isDark
                    ? Colors.grey[850]?.withOpacity(0.5)
                    : Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'login.validation.mssv_required'.tr();
                }
                if (value.length < 5) {
                  return 'login.validation.mssv_min'.tr();
                }
                if (value.length > 15) {
                  return 'login.validation.mssv_max'.tr();
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handleLogin(),
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                labelText: 'login.password'.tr(),
                hintText: 'login.password_hint'.tr(),
                prefixIcon: Icon(
                  Icons.lock_outline_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    size: 22,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
                filled: true,
                fillColor: isDark
                    ? Colors.grey[850]?.withOpacity(0.5)
                    : Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'login.password_required'.tr();
                }
                if (value.length < 6) {
                  return 'login.password_min'.tr();
                }
                if (value.length > 20) {
                  return 'login.password_max'.tr();
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            // ❌ BỎ CHECKBOX "REMEMBER ME"

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'login.login_button'.tr(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBiometricSection(ThemeData theme, bool isDark) {
    final canUseBiometric = _canCheckBiometrics && _biometricEnabled;

    final typeKey = _biometricType.toLowerCase();
    String localizedType;

    switch (typeKey) {
      case 'face':
        localizedType = 'biometric.face'.tr();
        break;
      case 'fingerprint':
        localizedType = 'biometric.fingerprint'.tr();
        break;
      case 'iris':
        localizedType = 'biometric.iris'.tr();
        break;
      default:
        localizedType = 'biometric.generic'.tr();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: isDark ? Colors.grey[800] : Colors.grey[300])),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'login.or'.tr(),
                style: TextStyle(
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(child: Divider(color: isDark ? Colors.grey[800] : Colors.grey[300])),
          ],
        ),
        const SizedBox(height: 20),

        Material(
          color: canUseBiometric
              ? (isDark ? Colors.grey[850] : Colors.white)
              : (isDark ? Colors.grey[850]?.withOpacity(0.3) : Colors.grey[100]),
          shape: const CircleBorder(),
          elevation: canUseBiometric ? 4 : 0,
          shadowColor: canUseBiometric
              ? theme.colorScheme.primary.withOpacity(0.3)
              : Colors.transparent,
          child: InkWell(
            onTap: canUseBiometric && !_isLoading ? _loginWithBiometric : null,
            customBorder: const CircleBorder(),
            child: Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(14),
              child: _isLoading && canUseBiometric
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : Icon(
                _getBiometricIcon(),
                size: 32,
                color: canUseBiometric
                    ? theme.colorScheme.primary
                    : (isDark ? Colors.grey[700] : Colors.grey[400]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        Text(
          'login.biometric_login'.tr(namedArgs: {'type': localizedType}),
          style: TextStyle(
            fontSize: 13,
            color: canUseBiometric
                ? (isDark ? Colors.grey[400] : Colors.grey[600])
                : (isDark ? Colors.grey[600] : Colors.grey[500]),
            fontWeight: canUseBiometric ? FontWeight.w500 : FontWeight.normal,
          ),
        ),

        if (!canUseBiometric) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.orange[900]?.withOpacity(0.2)
                  : Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.orange[800]!.withOpacity(0.3)
                    : Colors.orange[200]!,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: isDark ? Colors.orange[400] : Colors.orange[700],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _canCheckBiometrics
                        ? 'login.biometric_not_enabled'.tr()
                        : 'login.biometric_not_supported'.tr(),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.orange[300] : Colors.orange[800],
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}