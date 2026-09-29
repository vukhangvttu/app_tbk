import 'dart:io';

import 'package:app_tbk/config/api_constants.dart';
import 'package:app_tbk/core/errors/exceptions.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:app_tbk/features/auth/controllers/login_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:app_tbk/screens/main_screen.dart';
import 'package:get/get.dart' hide Trans;
import '../../../security_checker_service.dart';
import '../services/auth_service.dart';
import '../services/post_login_initializer.dart';
import 'forgotpassword/forgot_password_screen.dart';
import 'register_screen.dart'; // ✅ IMPORT REGISTER SCREEN
import 'package:google_sign_in/google_sign_in.dart';

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
    // Thực hiện kiểm tra bảo mật trước
    // WidgetsBinding.instance.addPostFrameCallback((_) async {
    //    await _performSecurityCheck(); // kiểm tra root / mock location, v.v.
    //   if (mounted && _isSecure) {
    //     // Chỉ khởi tạo sinh trắc học khi thiết bị an toàn
    //     await _initBiometric();
    //   }
    // });
  }

  @override
  void dispose() {
    _mssvController.dispose();
    _passwordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }


  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: ApiConstants.googleServerClientId,
  );

  bool _isGoogleLoading = false;

  Future<void> _handleGoogleLogin() async {
    if (!await AuthService.hasInternetConnection()) {
      _showErrorDialog('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
      return;
    }

    setState(() => _isGoogleLoading = true);
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        // Người dùng hủy
        setState(() => _isGoogleLoading = false);
        return;
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      final String? idToken = auth.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw Exception('Không lấy được token từ Google. Vui lòng kiểm tra lại kết nối mạng.');
      }

      // Gửi idToken lên backend để xác thực + đổi lấy JWT nội bộ
      final success = await _authController.loginWithGoogle(idToken);

      if (mounted) setState(() => _isGoogleLoading = false);

      if (success) {
        final mssv = await AuthService.getSavedMssv() ?? '';
        if (mounted) {
          PostLoginInitializer.quickInit(
            context: context,
            mssv: mssv,
          );
          _navigateToMainScreen();
        }
      } else {
        if (mounted) {
          _showErrorDialog('Đăng nhập Google thất bại. Tài khoản có thể chưa được liên kết.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
        final errorMsg = e.toString();
        if (e is NoInternetException ||
            errorMsg.contains('Không có kết nối') ||
            errorMsg.contains('SocketException') ||
            errorMsg.contains('ClientException') ||
            errorMsg.contains('network_error') ||
            errorMsg.contains('Internet')) {
          _showErrorDialog('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
        } else if (e is GoogleAccountNotLinkedException || errorMsg.contains('chưa được liên kết')) {
          _showErrorDialog('Email Google chưa được liên kết với tài khoản sinh viên.');
        } else {
          _showErrorDialog(errorMsg.replaceAll('Exception: ', ''));
        }
      }
    }
  }



  // ========== BIOMETRIC FUNCTIONS ==========

  Future<void> _initBiometric() async {
    await _checkBiometricSupport();
    await _loadSavedCredentials();

    // ✅ Kiểm tra token hợp lệ trước khi cho phép đăng nhập sinh trắc học
    if (_biometricEnabled && _canCheckBiometrics) {
      final isTokenValid = await _authController.isTokenValid();

      if (isTokenValid) {
        // Token còn hạn -> có thể tự động đăng nhập
        await Future.delayed(const Duration(milliseconds: 300));
        _loginWithBiometric();
      } else {
        // ✅ Token hết hạn -> tắt biometric và yêu cầu đăng nhập lại
        debugPrint('❌ Không thể tự động đăng nhập (token hết hạn)');
        await _authController.disableBiometric();
        if (mounted) {
          setState(() {
            _biometricEnabled = false;
          });
        }
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
      debugPrint('❌ Lỗi check biometric: $e');
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

      if (!authenticated) {
        debugPrint('❌ Xác thực sinh trắc học thất bại hoặc bị hủy');
        return;
      }

      if (!mounted) return;

      setState(() => _isLoading = true);

      // ✅ Kiểm tra token còn hạn không
      final isValid = await _authController.isTokenValid();

      if (mounted) {
        setState(() => _isLoading = false);
      }

      if (isValid) {
        // 🔥 Token còn hạn -> init services và chuyển màn hình
        // await PostLoginInitializer.initialize().then((_) {
        //   debugdebugPrint('✅ Post-login services ready (biometric)');
        // }).catchError((e) {
        //   debugdebugPrint('❌ Post-login init error: $e');
        // });

        _navigateToMainScreen();
      } else {
        // ❌ Token hết hạn -> tắt biometric
        if (mounted) {
          debugPrint('❌ Token đã hết hạn - Tắt sinh trắc học');
          await _authController.disableBiometric();
          setState(() => _biometricEnabled = false);

          _showSnackbar(
              'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại bằng mật khẩu.', isError: false
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi đăng nhập sinh trắc học: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackbar('❌ Lỗi đăng nhập sinh trắc học: $e', isError: true);
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
            // PostLoginInitializer.initialize(context: context, mssv: mssv).then((_) {
            //   debugdebugPrint('✅ Post-login services ready');
            // }).catchError((e) {
            //   debugdebugPrint('❌ Post-login init error: $e');
            // });

            PostLoginInitializer.quickInit(
              context: context,
              mssv: mssv,
            );

            // ✅ Hỏi có muốn bật biometric không (nếu chưa bật)
            // if (_canCheckBiometrics && !_biometricEnabled) {
            //   _showEnableBiometricDialog(mssv, password);
            // } else {
            //   _navigateToMainScreen();
            // }
            _navigateToMainScreen();
          } else {
            _showErrorDialog('login.error_login'.tr());
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        if (e is Exception) {
          final errorMsg = e.toString();

          if (errorMsg.contains('401')) {
            // ❌ Sai thông tin đăng nhập
            _showErrorDialog('Thông tin đăng nhập không chính xác');
          } else if (errorMsg.contains('timeout')) {
            _showErrorDialog('Kết nối máy chủ quá thời gian phản hồi, vui lòng thử lại.');
          } else if (e is NoInternetException ||
              errorMsg.contains('kết nối') ||
              errorMsg.contains('SocketException') ||
              errorMsg.contains('ClientException') ||
              errorMsg.contains('Internet')) {
            _showErrorDialog('Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
          } else {
            _showErrorDialog('Lỗi không xác định: ${errorMsg.replaceAll('Exception: ', '')}');
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
          _showSnackbar('', isError: false);
        } else {
          if (mounted) {
            _showSnackbar('', isError: true);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackbar('', isError: true);
      }
    }
  }

  void _showEnableBiometricDialog(String mssv, String password) {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        contentPadding: EdgeInsets.zero,
        content: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🎨 Header gradient
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6366F1),
                      const Color(0xFF8B5CF6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getBiometricIcon(),
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Bật đăng nhập nhanh',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sử dụng $_biometricType',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),

              // 📝 Content
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lợi ích khi bật:',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildBenefitItem(
                      isDark,
                      Icons.flash_on,
                      'Đăng nhập nhanh chóng',
                      'Không cần nhập mật khẩu mỗi lần',
                    ),
                    const SizedBox(height: 10),

                    _buildBenefitItem(
                      isDark,
                      Icons.security,
                      'An toàn tuyệt đối',
                      'Dữ liệu được mã hóa bảo mật',
                    ),
                    const SizedBox(height: 10),

                    _buildBenefitItem(
                      isDark,
                      Icons.timer,
                      'Hiệu lực 30 ngày',
                      'Tự động đăng nhập trong 30 ngày',
                    ),

                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.blue[900]?.withOpacity(0.2)
                            : Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? Colors.blue[700]!.withOpacity(0.3)
                              : Colors.blue[200]!,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: isDark ? Colors.blue[300] : Colors.blue[700],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Bạn có thể tắt tính năng này bất cứ lúc nào trong Cài đặt',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.blue[200] : Colors.blue[800],
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 🔘 Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _navigateToMainScreen();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(
                            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                          ),
                        ),
                        child: Text(
                          'Bỏ qua',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _enableBiometric(mssv, password);
                          _navigateToMainScreen();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_getBiometricIcon(), size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Bật ngay',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitItem(bool isDark, IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: const Color(0xFF6366F1),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
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
    // await PostLoginInitializer.initialize()
    //     .timeout(const Duration(seconds: 3))
    //     .catchError((e) {
    //   debugdebugPrint('⚠️ Post-login init timeout or error: $e');
    // });

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

  void _showSnackbar(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFE53935) : const Color(0xFF43A047),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: Duration(seconds: isError ? 4 : 2),
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await SystemNavigator.pop();
      },
      child: Scaffold(
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
                          const SizedBox(height: 12),
                          _buildLoginForm(theme, isDark, size),
                          _buildGoogleLoginSection(theme, isDark),
                          const SizedBox(height: 12),
                          // _buildRegisterLink(isDark), // ✅ THÊM NÚT ĐĂNG KÝ
                          // const SizedBox(height: 1),
                          // _buildBiometricSection(theme, isDark),


                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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

            const SizedBox(height: 12),

            // ✅ THÊM NÚT QUÊN MẬT KHẨU
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ForgotPasswordScreen(),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Quên mật khẩu?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.lightBlue[300] : const Color(0xFF6366F1),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

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

  Widget _buildGoogleLoginSection(ThemeData theme, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Divider(color: isDark ? Colors.grey[800] : Colors.grey[300])),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Hoặc',
                style: TextStyle(
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(child: Divider(color: isDark ? Colors.grey[800] : Colors.grey[300])),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: OutlinedButton(
            onPressed: _isGoogleLoading ? null : _handleGoogleLogin,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              side: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
            child: _isGoogleLoading
                ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.network(
                  'https://www.google.com/favicon.ico',
                  height: 20,
                  width: 20,
                  errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 24),
                ),
                const SizedBox(width: 10),
                Text(
                  'Đăng nhập Email sinh viên',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ✅ THÊM WIDGET NÚT ĐĂNG KÝ
  Widget _buildRegisterLink(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Chưa có tài khoản? ',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const RegisterScreen(),
              ),
            );
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(
            'Đăng ký ngay',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.lightBlue[300] : const Color(0xFF6366F1),
            ),
          ),
        ),
      ],
    );
  }
}
