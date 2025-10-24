// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:local_auth/local_auth.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:app_tbk/screens/main_screen.dart';
//
// class LoginScreen extends StatefulWidget {
//   const LoginScreen({Key? key}) : super(key: key);
//
//   @override
//   State<LoginScreen> createState() => _LoginScreenState();
// }
//
// class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
//   final _formKey = GlobalKey<FormState>();
//   final _mssvController = TextEditingController();
//   final _passwordController = TextEditingController();
//   final LocalAuthentication _localAuth = LocalAuthentication();
//   final FlutterSecureStorage _storage = const FlutterSecureStorage();
//
//   bool _obscurePassword = true;
//   bool _isLoading = false;
//   bool _rememberMe = false;
//
//   // Biometric
//   bool _canCheckBiometrics = false;
//   bool _biometricEnabled = false;
//   List<BiometricType> _availableBiometrics = [];
//   String _biometricType = '';
//
//   late AnimationController _animationController;
//   late Animation<double> _fadeAnimation;
//   late Animation<Offset> _slideAnimation;
//
//   @override
//   void initState() {
//     super.initState();
//
//     // Animation
//     _animationController = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 1000),
//     );
//     _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
//       CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
//     );
//     _slideAnimation = Tween<Offset>(
//       begin: const Offset(0, 0.3),
//       end: Offset.zero,
//     ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
//     _animationController.forward();
//
//     // Kiểm tra biometric
//     _initBiometric();
//   }
//
//   @override
//   void dispose() {
//     _mssvController.dispose();
//     _passwordController.dispose();
//     _animationController.dispose();
//     super.dispose();
//   }
//
//   // ========== BIOMETRIC FUNCTIONS ==========
//
//   Future<void> _initBiometric() async {
//     await _checkBiometricSupport();
//     await _loadSavedCredentials();
//
//     // Tự động hiện biometric nếu đã bật và có thông tin đăng nhập
//     if (_biometricEnabled && _canCheckBiometrics) {
//       await Future.delayed(const Duration(milliseconds: 500));
//       _loginWithBiometric();
//     }
//   }
//
//   Future<void> _checkBiometricSupport() async {
//     try {
//       bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
//       bool isDeviceSupported = await _localAuth.isDeviceSupported();
//       List<BiometricType> availableBiometrics = await _localAuth.getAvailableBiometrics();
//
//       setState(() {
//         _canCheckBiometrics = canCheckBiometrics && isDeviceSupported;
//         _availableBiometrics = availableBiometrics;
//
//         if (availableBiometrics.contains(BiometricType.face)) {
//           _biometricType = 'Face ID';
//         } else if (availableBiometrics.contains(BiometricType.fingerprint)) {
//           _biometricType = 'Vân tay';
//         } else {
//           _biometricType = 'Sinh trắc học';
//         }
//       });
//
//       print('🔍 Biometric: $_canCheckBiometrics | Types: $availableBiometrics');
//     } catch (e) {
//       print('❌ Lỗi check biometric: $e');
//     }
//   }
//
//   Future<void> _loadSavedCredentials() async {
//     final prefs = await SharedPreferences.getInstance();
//     setState(() {
//       _biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
//     });
//
//     if (_biometricEnabled) {
//       String? savedMssv = await _storage.read(key: 'saved_mssv');
//       if (savedMssv != null) {
//         _mssvController.text = savedMssv;
//       }
//     }
//   }
//
//   Future<void> _loginWithBiometric() async {
//     try {
//       bool authenticated = await _localAuth.authenticate(
//         localizedReason: 'Xác thực để đăng nhập bằng $_biometricType',
//         options: const AuthenticationOptions(
//           stickyAuth: true,
//           biometricOnly: true,
//         ),
//       );
//
//       if (authenticated) {
//         setState(() => _isLoading = true);
//
//         String? savedMssv = await _storage.read(key: 'saved_mssv');
//         String? savedToken = await _storage.read(key: 'auth_token');
//
//         setState(() => _isLoading = false);
//
//         if (savedMssv != null && savedToken != null) {
//           // Giả lập verify token
//           await Future.delayed(const Duration(milliseconds: 500));
//           _navigateToMainScreen();
//         } else {
//           _showErrorSnackbar('Không tìm thấy thông tin đăng nhập đã lưu');
//         }
//       }
//     } catch (e) {
//       print('❌ Lỗi xác thực: $e');
//       setState(() => _isLoading = false);
//       _showErrorSnackbar('Xác thực thất bại: $e');
//     }
//   }
//
//   // ========== LOGIN FUNCTIONS ==========
//
//   Future<void> _handleLogin() async {
//     if (_formKey.currentState!.validate()) {
//       setState(() => _isLoading = true);
//
//       // Giả lập gọi API đăng nhập
//       await Future.delayed(const Duration(seconds: 2));
//
//       setState(() => _isLoading = false);
//
//       if (mounted) {
//         // Giả lập đăng nhập thành công
//         if (_mssvController.text == '19719' && _passwordController.text == '123456') {
//           await _saveLoginInfo();
//
//           // Hỏi có muốn bật biometric không (nếu chưa bật)
//           if (_rememberMe && _canCheckBiometrics && !_biometricEnabled) {
//             _showEnableBiometricDialog();
//           } else {
//             _navigateToMainScreen();
//           }
//         } else {
//           _showErrorDialog('MSSV hoặc mật khẩu không đúng!');
//         }
//       }
//     }
//   }
//
//   Future<void> _saveLoginInfo() async {
//     if (_rememberMe) {
//       await _storage.write(key: 'saved_mssv', value: _mssvController.text);
//       await _storage.write(key: 'auth_token', value: 'fake_token_${_mssvController.text}');
//       final prefs = await SharedPreferences.getInstance();
//       await prefs.setInt('login_timestamp', DateTime.now().millisecondsSinceEpoch);
//     }
//   }
//
//   Future<void> _enableBiometric() async {
//     try {
//       bool authenticated = await _localAuth.authenticate(
//         localizedReason: 'Xác thực để bật $_biometricType',
//         options: const AuthenticationOptions(
//           stickyAuth: true,
//           biometricOnly: true,
//         ),
//       );
//
//       if (authenticated) {
//         final prefs = await SharedPreferences.getInstance();
//         await prefs.setBool('biometric_enabled', true);
//         setState(() {
//           _biometricEnabled = true;
//         });
//         _showSuccessSnackbar('Đã bật đăng nhập bằng $_biometricType');
//       }
//     } catch (e) {
//       print('❌ Lỗi bật biometric: $e');
//       _showErrorSnackbar('Lỗi bật $_biometricType: $e');
//     }
//   }
//
//   void _showEnableBiometricDialog() {
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (context) => AlertDialog(
//         icon: Icon(
//           _getBiometricIcon(),
//           color: const Color(0xFF6366F1),
//           size: 64,
//         ),
//         title: Text('Bật đăng nhập bằng $_biometricType?'),
//         content: Text(
//           'Bạn có muốn sử dụng $_biometricType để đăng nhập nhanh hơn trong lần sau không?',
//           textAlign: TextAlign.center,
//         ),
//         actions: [
//           TextButton(
//             onPressed: () {
//               Navigator.pop(context);
//               _navigateToMainScreen();
//             },
//             child: const Text('Bỏ qua'),
//           ),
//           ElevatedButton(
//             onPressed: () async {
//               Navigator.pop(context);
//               await _enableBiometric();
//               _navigateToMainScreen();
//             },
//             style: ElevatedButton.styleFrom(
//               backgroundColor: const Color(0xFF6366F1),
//             ),
//             child: const Text('Bật ngay'),
//           ),
//         ],
//       ),
//     );
//   }
//
//   void _navigateToMainScreen() {
//     Navigator.pushReplacement(
//       context,
//       MaterialPageRoute(builder: (_) => const MainScreen()),
//     );
//   }
//
//   // ========== DIALOGS & SNACKBARS ==========
//
//   void _showErrorDialog(String message) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         icon: Icon(
//           Icons.error_outline_rounded,
//           color: Colors.red[400],
//           size: 64,
//         ),
//         title: const Text('Đăng nhập thất bại'),
//         content: Text(message),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('Đóng'),
//           ),
//         ],
//       ),
//     );
//   }
//
//   void _showSuccessSnackbar(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Row(
//           children: [
//             const Icon(Icons.check_circle, color: Colors.white),
//             const SizedBox(width: 12),
//             Expanded(child: Text(message)),
//           ],
//         ),
//         backgroundColor: Colors.green,
//         behavior: SnackBarBehavior.floating,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//       ),
//     );
//   }
//
//   void _showErrorSnackbar(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Row(
//           children: [
//             const Icon(Icons.error, color: Colors.white),
//             const SizedBox(width: 12),
//             Expanded(child: Text(message)),
//           ],
//         ),
//         backgroundColor: Colors.red,
//         behavior: SnackBarBehavior.floating,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//       ),
//     );
//   }
//
//   IconData _getBiometricIcon() {
//     if (_availableBiometrics.contains(BiometricType.face)) {
//       return Icons.face;
//     } else if (_availableBiometrics.contains(BiometricType.fingerprint)) {
//       return Icons.fingerprint;
//     } else {
//       return Icons.security;
//     }
//   }
//
//   // ========== UI BUILD ==========
//
//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final isDark = theme.brightness == Brightness.dark;
//     final size = MediaQuery.of(context).size;
//
//     return Scaffold(
//       body: SafeArea(
//         child: Center(
//           child: SingleChildScrollView(
//             child: Padding(
//               padding: const EdgeInsets.all(24.0),
//               child: FadeTransition(
//                 opacity: _fadeAnimation,
//                 child: SlideTransition(
//                   position: _slideAnimation,
//                   child: Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       _buildHeader(isDark, size),
//                       const SizedBox(height: 48),
//                       _buildLoginForm(theme, isDark, size),
//                       const SizedBox(height: 24),
//                       if (_biometricEnabled && _canCheckBiometrics)
//                         _buildBiometricButton(theme, isDark),
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget _buildHeader(bool isDark, Size size) {
//     return Column(
//       children: [
//         Container(
//           width: size.width > 600 ? 120 : 100,
//           height: size.width > 600 ? 120 : 100,
//           decoration: BoxDecoration(
//             gradient: const LinearGradient(
//               colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
//               begin: Alignment.topLeft,
//               end: Alignment.bottomRight,
//             ),
//             shape: BoxShape.circle,
//             boxShadow: [
//               BoxShadow(
//                 color: const Color(0xFF6366F1).withOpacity(0.3),
//                 blurRadius: 20,
//                 offset: const Offset(0, 10),
//               ),
//             ],
//           ),
//           child: Icon(
//             Icons.school_rounded,
//             size: size.width > 600 ? 60 : 50,
//             color: Colors.white,
//           ),
//         ),
//         const SizedBox(height: 24),
//         Text(
//           'Chào mừng trở lại!',
//           style: TextStyle(
//             fontSize: size.width > 600 ? 32 : 28,
//             fontWeight: FontWeight.bold,
//             color: isDark ? Colors.white : const Color(0xFF0F172A),
//           ),
//         ),
//         const SizedBox(height: 8),
//         Text(
//           'Đăng nhập để tiếp tục',
//           style: TextStyle(
//             fontSize: size.width > 600 ? 18 : 16,
//             color: isDark ? Colors.grey[400] : Colors.grey[600],
//           ),
//         ),
//       ],
//     );
//   }
//
//   Widget _buildLoginForm(ThemeData theme, bool isDark, Size size) {
//     final maxWidth = size.width > 600 ? 400.0 : double.infinity;
//
//     return Container(
//       constraints: BoxConstraints(maxWidth: maxWidth),
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         color: isDark ? Colors.grey[900]?.withOpacity(0.5) : Colors.white,
//         borderRadius: BorderRadius.circular(24),
//         border: Border.all(
//           color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
//           width: 1,
//         ),
//         boxShadow: [
//           BoxShadow(
//             color: isDark
//                 ? Colors.black.withOpacity(0.3)
//                 : Colors.grey.withOpacity(0.1),
//             blurRadius: 20,
//             offset: const Offset(0, 10),
//           ),
//         ],
//       ),
//       child: Form(
//         key: _formKey,
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             TextFormField(
//               controller: _mssvController,
//               keyboardType: TextInputType.number,
//               style: TextStyle(fontSize: size.width > 600 ? 18 : 16),
//               decoration: InputDecoration(
//                 labelText: 'Mã số sinh viên',
//                 hintText: 'Nhập MSSV của bạn',
//                 prefixIcon: Icon(
//                   Icons.person_outline_rounded,
//                   color: theme.colorScheme.primary,
//                 ),
//                 filled: true,
//                 fillColor: isDark
//                     ? Colors.grey[850]?.withOpacity(0.5)
//                     : Colors.grey[50],
//                 border: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(16),
//                   borderSide: BorderSide.none,
//                 ),
//                 enabledBorder: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(16),
//                   borderSide: BorderSide(
//                     color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
//                     width: 1,
//                   ),
//                 ),
//                 focusedBorder: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(16),
//                   borderSide: BorderSide(
//                     color: theme.colorScheme.primary,
//                     width: 2,
//                   ),
//                 ),
//                 contentPadding: const EdgeInsets.symmetric(
//                   horizontal: 20,
//                   vertical: 18,
//                 ),
//               ),
//               validator: (value) {
//                 if (value == null || value.isEmpty) {
//                   return 'Vui lòng nhập MSSV';
//                 }
//                 if (value.length < 5) {
//                   return 'MSSV phải có ít nhất 5 ký tự';
//                 }
//                 return null;
//               },
//             ),
//             const SizedBox(height: 20),
//             TextFormField(
//               controller: _passwordController,
//               obscureText: _obscurePassword,
//               style: TextStyle(fontSize: size.width > 600 ? 18 : 16),
//               decoration: InputDecoration(
//                 labelText: 'Mật khẩu',
//                 hintText: 'Nhập mật khẩu',
//                 prefixIcon: Icon(
//                   Icons.lock_outline_rounded,
//                   color: theme.colorScheme.primary,
//                 ),
//                 suffixIcon: IconButton(
//                   icon: Icon(
//                     _obscurePassword
//                         ? Icons.visibility_off_rounded
//                         : Icons.visibility_rounded,
//                     color: isDark ? Colors.grey[400] : Colors.grey[600],
//                   ),
//                   onPressed: () {
//                     setState(() => _obscurePassword = !_obscurePassword);
//                   },
//                 ),
//                 filled: true,
//                 fillColor: isDark
//                     ? Colors.grey[850]?.withOpacity(0.5)
//                     : Colors.grey[50],
//                 border: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(16),
//                   borderSide: BorderSide.none,
//                 ),
//                 enabledBorder: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(16),
//                   borderSide: BorderSide(
//                     color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
//                     width: 1,
//                   ),
//                 ),
//                 focusedBorder: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(16),
//                   borderSide: BorderSide(
//                     color: theme.colorScheme.primary,
//                     width: 2,
//                   ),
//                 ),
//                 contentPadding: const EdgeInsets.symmetric(
//                   horizontal: 20,
//                   vertical: 18,
//                 ),
//               ),
//               validator: (value) {
//                 if (value == null || value.isEmpty) {
//                   return 'Vui lòng nhập mật khẩu';
//                 }
//                 if (value.length < 6) {
//                   return 'Mật khẩu phải có ít nhất 6 ký tự';
//                 }
//                 return null;
//               },
//             ),
//             const SizedBox(height: 16),
//             Row(
//               children: [
//                 Transform.scale(
//                   scale: 0.9,
//                   child: Checkbox(
//                     value: _rememberMe,
//                     onChanged: (value) {
//                       setState(() => _rememberMe = value ?? false);
//                     },
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(4),
//                     ),
//                   ),
//                 ),
//                 Text(
//                   'Ghi nhớ đăng nhập',
//                   style: TextStyle(
//                     color: isDark ? Colors.grey[400] : Colors.grey[700],
//                     fontSize: size.width > 600 ? 16 : 14,
//                   ),
//                 ),
//                 const Spacer(),
//               ],
//             ),
//             const SizedBox(height: 24),
//             SizedBox(
//               height: size.width > 600 ? 60 : 56,
//               child: ElevatedButton(
//                 onPressed: _isLoading ? null : _handleLogin,
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: theme.colorScheme.primary,
//                   foregroundColor: Colors.white,
//                   shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(16),
//                   ),
//                   elevation: 0,
//                 ),
//                 child: _isLoading
//                     ? const SizedBox(
//                   height: 24,
//                   width: 24,
//                   child: CircularProgressIndicator(
//                     strokeWidth: 2.5,
//                     valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
//                   ),
//                 )
//                     : Row(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Text(
//                       'Đăng nhập',
//                       style: TextStyle(
//                         fontSize: size.width > 600 ? 18 : 16,
//                         fontWeight: FontWeight.bold,
//                         letterSpacing: 0.5,
//                       ),
//                     ),
//                     const SizedBox(width: 8),
//                     const Icon(Icons.arrow_forward_rounded),
//                   ],
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildBiometricButton(ThemeData theme, bool isDark) {
//     return Column(
//       children: [
//         Row(
//           children: [
//             Expanded(
//               child: Divider(
//                 color: isDark ? Colors.grey[800] : Colors.grey[300],
//               ),
//             ),
//             Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 16),
//               child: Text(
//                 'hoặc',
//                 style: TextStyle(
//                   color: isDark ? Colors.grey[500] : Colors.grey[600],
//                   fontSize: 14,
//                 ),
//               ),
//             ),
//             Expanded(
//               child: Divider(
//                 color: isDark ? Colors.grey[800] : Colors.grey[300],
//               ),
//             ),
//           ],
//         ),
//         const SizedBox(height: 24),
//         Container(
//           decoration: BoxDecoration(
//             shape: BoxShape.circle,
//             boxShadow: [
//               BoxShadow(
//                 color: theme.colorScheme.primary.withOpacity(0.3),
//                 blurRadius: 20,
//                 offset: const Offset(0, 10),
//               ),
//             ],
//           ),
//           child: Material(
//             color: isDark ? Colors.grey[850] : Colors.white,
//             shape: const CircleBorder(),
//             child: InkWell(
//               onTap: _isLoading ? null : _loginWithBiometric,
//               customBorder: const CircleBorder(),
//               child: Container(
//                 width: 72,
//                 height: 72,
//                 padding: const EdgeInsets.all(16),
//                 child: _isLoading
//                     ? const CircularProgressIndicator(strokeWidth: 2)
//                     : Icon(
//                   _getBiometricIcon(),
//                   size: 36,
//                   color: theme.colorScheme.primary,
//                 ),
//               ),
//             ),
//           ),
//         ),
//         const SizedBox(height: 12),
//         Text(
//           'Đăng nhập bằng $_biometricType',
//           style: TextStyle(
//             fontSize: 14,
//             color: isDark ? Colors.grey[400] : Colors.grey[600],
//             fontWeight: FontWeight.w500,
//           ),
//         ),
//       ],
//     );
//   }
// }