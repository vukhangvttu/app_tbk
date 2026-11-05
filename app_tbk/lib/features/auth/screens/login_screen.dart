import 'dart:async';
import 'dart:io';

import 'package:app_tbk/config/api_constants.dart';
import 'package:app_tbk/core/errors/exceptions.dart';
import 'package:app_tbk/features/auth/controllers/login_controller.dart';
import 'package:app_tbk/features/version/services/app_version_service.dart';
import 'package:app_tbk/screens/main_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart' hide Trans;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/post_login_initializer.dart';
import 'forgotpassword/forgot_password_screen.dart';

// Màu thương hiệu: chỉ dùng cho gradient / điểm nhấn.
// Các màu còn lại lấy từ Theme.colorScheme để tự hài hòa với dark mode.
const _brandA = Color(0xFF6366F1);
const _brandB = Color(0xFF8B5CF6);

class LoginScreen extends StatefulWidget {
  final Function(ThemeMode)? onThemeChanged;
  const LoginScreen({super.key, this.onThemeChanged});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mssvController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mssvFocus = FocusNode();
  final _passwordFocus = FocusNode();

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

  // Biometric
  bool _canCheckBiometrics = false;
  bool _biometricEnabled = false;
  List<BiometricType> _availableBiometrics = [];
  String _biometricType = '';

  bool get _busy => _isLoading || _isGoogleLoading;
  bool get _canUseBiometric => _canCheckBiometrics && _biometricEnabled;

  @override
  void initState() {
    super.initState();
    // Không dùng context trực tiếp trong initState -> đợi frame đầu tiên.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppVersionService.checkAndShowUpdateDialog(context);
      _initBiometric();
    });
  }

  @override
  void dispose() {
    _mssvController.dispose();
    _passwordController.dispose();
    _mssvFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // ========== BIOMETRIC ==========

  Future<void> _initBiometric() async {
    await _checkBiometricSupport();
    await _loadSavedCredentials();

    // Token hết hạn -> tắt biometric, yêu cầu đăng nhập lại bằng mật khẩu.
    if (_biometricEnabled && _canCheckBiometrics) {
      final isTokenValid = await _authController.isTokenValid();
      if (!isTokenValid) {
        await _authController.disableBiometric();
        if (mounted) setState(() => _biometricEnabled = false);
      }
    }
  }

  Future<void> _checkBiometricSupport() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      final available = await _localAuth.getAvailableBiometrics();

      if (!mounted) return;
      setState(() {
        _canCheckBiometrics = canCheck && supported;
        _availableBiometrics = available;
        if (available.contains(BiometricType.face)) {
          _biometricType = 'Face ID';
        } else if (available.contains(BiometricType.fingerprint)) {
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
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMssv = await _storage.read(key: 'saved_mssv');
      if (!mounted) return;
      setState(() {
        _biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
        if (savedMssv != null) _mssvController.text = savedMssv;
      });
    } catch (e) {
      debugPrint('❌ Lỗi khi tải thông tin đăng nhập: $e');
      try {
        await _storage.deleteAll();
      } catch (_) {}
    }
  }

  Future<void> _loginWithBiometric() async {
    if (_busy) return;
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Xác thực để đăng nhập bằng $_biometricType',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (!authenticated || !mounted) return;

      setState(() => _isLoading = true);
      final isValid = await _authController.isTokenValid();
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (isValid) {
        _navigateToMainScreen();
      } else {
        await _authController.disableBiometric();
        if (!mounted) return;
        setState(() => _biometricEnabled = false);
        _showSnackbar(
          'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại bằng mật khẩu.',
          isError: false,
        );
      }
    } catch (e) {
      debugPrint('❌ Lỗi đăng nhập sinh trắc học: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackbar('Không thể xác thực sinh trắc học. Vui lòng thử lại.',
          isError: true);
    }
  }

  // ========== LOGIN ==========

  Future<void> _handleLogin() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.lightImpact();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final mssv = _mssvController.text.trim();
    // Không trim mật khẩu: mật khẩu có thể chứa khoảng trắng đầu/cuối.
    final password = _passwordController.text;

    try {
      final success = await _authController.login(mssv, password);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        TextInput.finishAutofillContext(); // cho phép lưu mật khẩu
        PostLoginInitializer.quickInit(context: context, mssv: mssv);
        _navigateToMainScreen();
      } else {
        HapticFeedback.mediumImpact();
        _showSnackbar('login.error_login'.tr(), isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      HapticFeedback.mediumImpact();
      _showSnackbar(_friendlyError(e), isError: true);
    }
  }

  Future<void> _handleGoogleLogin() async {
    if (_busy) return;

    if (!await AuthService.hasInternetConnection()) {
      if (mounted) _showSnackbar(_noInternetMsg, isError: true);
      return;
    }

    setState(() => _isGoogleLoading = true);
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        // Người dùng hủy
        if (mounted) setState(() => _isGoogleLoading = false);
        return;
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception(
            'Không lấy được token từ Google. Vui lòng kiểm tra lại kết nối mạng.');
      }

      // Gửi idToken lên backend để xác thực + đổi lấy JWT nội bộ
      final success = await _authController.loginWithGoogle(idToken);
      if (!mounted) return;
      setState(() => _isGoogleLoading = false);

      if (success) {
        final mssv = await AuthService.getSavedMssv() ?? '';
        if (!mounted) return;
        PostLoginInitializer.quickInit(context: context, mssv: mssv);
        _navigateToMainScreen();
      } else {
        HapticFeedback.mediumImpact();
        _showSnackbar(
          'Đăng nhập Google thất bại. Tài khoản có thể chưa được liên kết.',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGoogleLoading = false);
      HapticFeedback.mediumImpact();
      _showSnackbar(_friendlyError(e), isError: true);
    }
  }

  static const _noInternetMsg =
      'Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.';

  /// Gom toàn bộ việc map lỗi -> thông báo về một chỗ.
  /// Tốt nhất là để LoginController ném exception có kiểu, ở đây chỉ `is`.
  String _friendlyError(Object e) {
    final msg = e.toString();

    if (e is NoInternetException ||
        e is SocketException ||
        msg.contains('Không có kết nối') ||
        msg.contains('SocketException') ||
        msg.contains('ClientException') ||
        msg.contains('network_error') ||
        msg.contains('Internet')) {
      return _noInternetMsg;
    }
    if (e is TimeoutException || msg.contains('timeout')) {
      return 'Kết nối máy chủ quá thời gian phản hồi, vui lòng thử lại.';
    }
    if (e is GoogleAccountNotLinkedException ||
        msg.contains('chưa được liên kết')) {
      return 'Email Google chưa được liên kết với tài khoản sinh viên.';
    }
    if (msg.contains('401')) {
      return 'Thông tin đăng nhập không chính xác';
    }
    return msg.replaceAll('Exception: ', '');
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

  // ========== FEEDBACK ==========

  void _showSnackbar(String message, {required bool isError}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: isError ? scheme.onError : Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: isError ? scheme.onError : Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? scheme.error : const Color(0xFF43A047),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  IconData get _biometricIcon {
    if (_availableBiometrics.contains(BiometricType.face)) return Icons.face;
    if (_availableBiometrics.contains(BiometricType.fingerprint)) {
      return Icons.fingerprint;
    }
    return Icons.security;
  }

  // ========== UI ==========

  InputDecoration _inputDecoration(
      ColorScheme scheme, {
        required String label,
        required String hint,
        required IconData icon,
        Widget? suffix,
      }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: scheme.primary, size: 22),
      suffixIcon: suffix,
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(scheme.outlineVariant),
      enabledBorder: border(scheme.outlineVariant),
      focusedBorder: border(scheme.primary, 2),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        resizeToAvoidBottomInset: false, // Giữ cố định khung hình & nền khi bàn phím hiện lên
        body: Stack(
          children: [
            const Positioned.fill(child: _BackgroundDecor()),
            SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusScope.of(context).unfocus(),
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _FadeSlideIn(
                              child: _buildHeader(scheme, size),
                            ),
                            const SizedBox(height: 24),
                            _FadeSlideIn(
                              delayMs: 100,
                              child: _buildLoginCard(scheme),
                            ),
                            _FadeSlideIn(
                              delayMs: 200,
                              child: _buildGoogleSection(scheme),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme, Size size) {
    final small = size.height < 700;
    final logoSize = small ? 80.0 : 92.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_brandA, _brandB],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _brandA.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Icon(Icons.school_rounded,
              size: logoSize * 0.5, color: Colors.white),
        ),
        const SizedBox(height: 20),
        Text(
          'login.welcome'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: small ? 24 : 28,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'login.subtitle'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: small ? 14 : 15,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _mssvController,
                focusNode: _mssvFocus,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                style: const TextStyle(fontSize: 16),
                decoration: _inputDecoration(
                  scheme,
                  label: 'login.mssv'.tr(),
                  hint: 'login.mssv_hint'.tr(),
                  icon: Icons.person_outline_rounded,
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
                focusNode: _passwordFocus,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _handleLogin(),
                style: const TextStyle(fontSize: 16),
                decoration: _inputDecoration(
                  scheme,
                  label: 'login.password'.tr(),
                  hint: 'login.password_hint'.tr(),
                  icon: Icons.lock_outline_rounded,
                  suffix: IconButton(
                    tooltip: _obscurePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: scheme.onSurfaceVariant,
                      size: 22,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'login.password_required'.tr();
                  }
                  if (value.length < 6) return 'login.password_min'.tr();
                  if (value.length > 20) return 'login.password_max'.tr();
                  return null;
                },
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ForgotPasswordScreen(),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Quên mật khẩu?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _GradientButton(
                      height: 54,
                      onPressed: _busy ? null : _handleLogin,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _isLoading
                            ? const SizedBox(
                          key: ValueKey('loading'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                            : Row(
                          key: const ValueKey('label'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'login.login_button'.tr(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded,
                                size: 20, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_canUseBiometric) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 54,
                      height: 54,
                      child: OutlinedButton(
                        onPressed: _busy ? null : _loginWithBiometric,
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(color: scheme.outlineVariant),
                        ),
                        child: Icon(_biometricIcon,
                            size: 28, color: scheme.primary),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleSection(ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Divider(color: scheme.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Hoặc',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
            Expanded(child: Divider(color: scheme.outlineVariant)),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton(
            onPressed: _busy ? null : _handleGoogleLogin,
            style: OutlinedButton.styleFrom(
              backgroundColor: scheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _isGoogleLoading
                  ? const SizedBox(
                key: ValueKey('g-loading'),
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : Row(
                key: const ValueKey('g-label'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _GoogleMark(),
                  const SizedBox(width: 12),
                  Text(
                    'Đăng nhập Email sinh viên',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ========== SMALL WIDGETS ==========

/// Nền trang trí: const + RepaintBoundary nên không bị vẽ lại khi bàn phím/hiệu ứng thay đổi.
class _BackgroundDecor extends StatelessWidget {
  const _BackgroundDecor();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final a = isDark ? 0.14 : 0.12;

    return RepaintBoundary(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -70,
              right: -70,
              child: _blob(240, _brandA.withValues(alpha: a)),
            ),
            Positioned(
              bottom: -100,
              left: -90,
              child: _blob(300, _brandB.withValues(alpha: a * 0.9)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
    ),
  );
}

/// Hiệu ứng xuất hiện: mờ dần + trượt nhẹ từ dưới lên (Chỉ chạy 1 lần duy nhất khi mở màn hình, không bị re-animate khi bật bàn phím).
class _FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const _FadeSlideIn({required this.child, this.delayMs = 0});

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    final durationMs = 500 + widget.delayMs;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );

    final startRatio = (widget.delayMs / durationMs).clamp(0.0, 0.9);
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(startRatio, 1.0, curve: Curves.easeOutCubic),
    );

    _opacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curve);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 24),
      end: Offset.zero,
    ).animate(curve);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _opacityAnim.value,
        child: Transform.translate(
          offset: _slideAnim.value,
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Nút gradient có ripple và trạng thái disabled.
class _GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final double height;
  const _GradientButton({
    required this.onPressed,
    required this.child,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.7,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_brandA, _brandB],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: enabled
                ? [
              BoxShadow(
                color: _brandA.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ]
                : null,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Logo "G" đa sắc vẽ bằng code (không tải mạng).
/// Muốn chuẩn thương hiệu: thay bằng SvgPicture.asset('assets/icons/google.svg').
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => const SweepGradient(
        colors: [
          Color(0xFF4285F4), // xanh dương
          Color(0xFF34A853), // xanh lá
          Color(0xFFFBBC05), // vàng
          Color(0xFFEA4335), // đỏ
          Color(0xFF4285F4),
        ],
        stops: [0.0, 0.3, 0.5, 0.75, 1.0],
      ).createShader(rect),
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          height: 1,
          color: Colors.white,
        ),
      ),
    );
  }
}