import 'dart:io';

import 'package:app_tbk/config/api_constants.dart';
import 'package:app_tbk/core/errors/exceptions.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:app_tbk/features/auth/controllers/login_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:app_tbk/screens/main_screen.dart';
import 'package:get/get.dart' hide Trans;
import '../services/auth_service.dart';
import '../services/post_login_initializer.dart';
import 'package:app_tbk/features/version/services/app_version_service.dart';
import 'forgotpassword/forgot_password_screen.dart';
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
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: ApiConstants.googleServerClientId,
  );

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  // Biometric (chỉ còn luồng tự động đăng nhập; nút bật/tắt thủ công
  // nằm ở màn hình Cài đặt, không còn ở đây)
  bool _canCheckBiometrics = false;
  bool _biometricEnabled = false;
  List<BiometricType> _availableBiometrics = [];
  String _biometricType = '';

  @override
  void initState() {
    super.initState();
    // Dialog cần context đã mount xong → chạy sau frame đầu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppVersionService.checkAndShowUpdateDialog(context);
    });
    _initBiometric();
  }

  @override
  void dispose() {
    _mssvController.dispose();
    _passwordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleLogin() async {
    if (!await AuthService.hasInternetConnection()) {
      _showErrorDialog(
          'Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
      return;
    }

    setState(() => _isGoogleLoading = true);
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        // Người dùng hủy
        if (mounted) setState(() => _isGoogleLoading = false);
        return;
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      final String? idToken = auth.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw Exception(
            'Không lấy được token từ Google. Vui lòng kiểm tra lại kết nối mạng.');
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
          _showErrorDialog(
              'Đăng nhập Google thất bại. Tài khoản có thể chưa được liên kết.');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGoogleLoading = false);
      final errorMsg = e.toString();
      if (e is NoInternetException ||
          errorMsg.contains('Không có kết nối') ||
          errorMsg.contains('SocketException') ||
          errorMsg.contains('ClientException') ||
          errorMsg.contains('network_error') ||
          errorMsg.contains('Internet')) {
        _showErrorDialog(
            'Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
      } else if (e is GoogleAccountNotLinkedException ||
          errorMsg.contains('chưa được liên kết')) {
        _showErrorDialog('Email Google chưa được liên kết với tài khoản sinh viên.');
      } else {
        _showErrorDialog(errorMsg.replaceAll('Exception: ', ''));
      }
    }
  }

  // ========== BIOMETRIC (tự động) ==========

  Future<void> _initBiometric() async {
    await _checkBiometricSupport();
    await _loadSavedCredentials();

    // Chỉ tự động đăng nhập khi token còn hạn
    if (_biometricEnabled && _canCheckBiometrics) {
      final isTokenValid = await _authController.isTokenValid();

      if (isTokenValid) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) _loginWithBiometric();
      } else {
        // Token hết hạn -> tắt biometric, yêu cầu đăng nhập lại
        debugPrint('❌ Không thể tự động đăng nhập (token hết hạn)');
        await _authController.disableBiometric();
        if (mounted) {
          setState(() => _biometricEnabled = false);
        }
      }
    }
  }

  Future<void> _checkBiometricSupport() async {
    try {
      // Chạy song song 3 check thay vì tuần tự
      final results = await Future.wait([
        _localAuth.canCheckBiometrics,
        _localAuth.isDeviceSupported(),
        _localAuth.getAvailableBiometrics(),
      ]);

      final canCheckBiometrics = results[0] as bool;
      final isDeviceSupported = results[1] as bool;
      final availableBiometrics = results[2] as List<BiometricType>;

      if (!mounted) return;
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
    } catch (e) {
      debugPrint('❌ Lỗi check biometric: $e');
    }
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMssv = await _storage.read(key: 'saved_mssv');
    if (!mounted) return;
    setState(() {
      _biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
      if (savedMssv != null) _mssvController.text = savedMssv;
    });
  }

  Future<void> _loginWithBiometric() async {
    try {
      final authenticated = await _localAuth.authenticate(
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

      final isValid = await _authController.isTokenValid();

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (isValid) {
        _navigateToMainScreen();
      } else {
        debugPrint('❌ Token đã hết hạn - Tắt sinh trắc học');
        await _authController.disableBiometric();
        if (mounted) {
          setState(() => _biometricEnabled = false);
          _showSnackbar(
            'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại bằng mật khẩu.',
            isError: false,
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

  // ========== LOGIN ==========

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    // Cho phép trình quản lý mật khẩu lưu thông tin đăng nhập
    TextInput.finishAutofillContext();

    setState(() => _isLoading = true);

    final mssv = _mssvController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final success = await _authController.login(mssv, password);

      if (mounted) setState(() => _isLoading = false);
      if (!mounted) return;

      if (success) {
        PostLoginInitializer.quickInit(
          context: context,
          mssv: mssv,
        );
        _navigateToMainScreen();
      } else {
        _showErrorDialog('login.error_login'.tr());
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (!mounted) return;

      final errorMsg = e.toString();
      if (errorMsg.contains('401')) {
        _showErrorDialog('Thông tin đăng nhập không chính xác');
      } else if (errorMsg.contains('timeout')) {
        _showErrorDialog(
            'Kết nối máy chủ quá thời gian phản hồi, vui lòng thử lại.');
      } else if (e is NoInternetException ||
          errorMsg.contains('kết nối') ||
          errorMsg.contains('SocketException') ||
          errorMsg.contains('ClientException') ||
          errorMsg.contains('Internet')) {
        _showErrorDialog(
            'Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.');
      } else {
        _showErrorDialog(
            'Lỗi không xác định: ${errorMsg.replaceAll('Exception: ', '')}');
      }
    }
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
            Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
                child:
                Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
        backgroundColor:
        isError ? const Color(0xFFE53935) : const Color(0xFF43A047),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  // ========== UI ==========

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
                          _FadeSlide(
                              index: 0, child: _buildHeader(isDark, size)),
                          const SizedBox(height: 12),
                          _FadeSlide(
                              index: 1,
                              child: _buildLoginForm(theme, isDark, size)),
                          _FadeSlide(
                              index: 2,
                              child:
                              _buildGoogleLoginSection(theme, isDark)),
                          const SizedBox(height: 12),
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
      // AutofillGroup: cho phép trình quản lý mật khẩu điền & lưu thông tin
      child: AutofillGroup(
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
                autofillHints: const [AutofillHints.username],
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
                autofillHints: const [AutofillHints.password],
                onEditingComplete: () => TextInput.finishAutofillContext(),
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
                    padding:
                    const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'login.forgot_password'.tr(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.lightBlue[300]
                          : const Color(0xFF6366F1),
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
                      valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.white),
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
      ),
    );
  }

  Widget _buildGoogleLoginSection(ThemeData theme, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: Divider(
                    color: isDark ? Colors.grey[800] : Colors.grey[300])),
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
            Expanded(
                child: Divider(
                    color: isDark ? Colors.grey[800] : Colors.grey[300])),
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
                // Logo Google bundle trong app (không phụ thuộc mạng).
                // Nếu chưa có file assets/images/google_logo.png thì
                // errorBuilder sẽ hiện icon dự phòng.
                Image.asset(
                  'assets/images/google_logo.png',
                  height: 20,
                  width: 20,
                  errorBuilder: (_, __, ___) =>
                  const Icon(Icons.g_mobiledata, size: 24),
                ),
                const SizedBox(width: 10),
                Text(
                  'login.google_button'.tr(),
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
}

/// Mờ dần + trượt lên khi các khối màn hình đăng nhập xuất hiện
class _FadeSlide extends StatelessWidget {
  final int index;
  final Widget child;
  const _FadeSlide({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (index * 100).clamp(0, 400)),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
