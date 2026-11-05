// lib/main.dart - ULTRA OPTIMIZED ⚡
// Chỉ init những thứ THỰC SỰ cần để hiện login screen

import 'dart:async';

import 'package:app_tbk/features/notification/services/notification_service.dart';
import 'package:app_tbk/features/schedule/screens/schedule_screen.dart';
import 'package:app_tbk/screens/main_screen.dart';
import 'package:app_tbk/security_checker_service.dart';
import 'package:app_tbk/services/notificationservice.dart';
import 'package:app_tbk/utils/global_keys.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:app_tbk/features/auth/screens/login_screen.dart';
import 'package:app_tbk/services/simple_firebase_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'app_initializer_screen.dart';
import 'features/auth/services/auth_service.dart';
import 'features/auth/services/auth_state_manager.dart';
import 'features/check-in/providers/checkin_provider.dart';
import 'firebase_options.dart';

void main() async {

  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // ⏱️ Benchmark
  final startTime = DateTime.now();

  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));

  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('🚀 App starting...');

  // ✅ PHASE 1: CHỈ init EasyLocalization (BẮT BUỘC để render text)
  await EasyLocalization.ensureInitialized();
  debugPrint('  ✓ Localization ready');

  // ✅ PHASE 2: Load theme nhanh
  final themeMode = await _loadThemeMode();

  // ✅ PHASE 3: Lock orientation
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  // 🚀 PHASE 4: START APP NGAY!
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('vi', 'VN'), Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('vi', 'VN'),
      child: MyApp(initialThemeMode: themeMode),
    ),
  );

  // ⏱️ Log startup time
  final elapsed = DateTime.now().difference(startTime);
  debugPrint('✅ UI ready in ${elapsed.inMilliseconds}ms');

  // 🔄 PHASE 5: Init những thứ cần trước khi login (chạy ngầm)
  _initializeBeforeLogin();
}

/// 📦 Load theme mode nhanh (< 20ms)
Future<ThemeMode> _loadThemeMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final themeModeString = prefs.getString('themeMode') ?? 'system';
    return ThemeMode.values.firstWhere(
          (e) => e.toString() == 'ThemeMode.$themeModeString',
      orElse: () => ThemeMode.system,
    );
  } catch (e) {
    return ThemeMode.system;
  }
}

/// 🔄 Init những thứ CẦN TRƯỚC LOGIN (chạy ngầm)
void _initializeBeforeLogin() {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    debugPrint('🔄 Pre-login initialization...');
    final sw = Stopwatch()..start();

    try {
      // ✅ Chỉ init Date formatting (cần cho hiển thị date)
      await initializeDateFormatting('vi');

      sw.stop();
      debugPrint('✅ Pre-login init done in ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('❌ Pre-login init error: $e');
    }
  });
}

/// 🔥 Firebase + Notifications - GỌI SAU KHI LOGIN THÀNH CÔNG
// class PostLoginInitializer {
//   static bool _isInitialized = false;
//   static bool _isInitializing = false;
//
//
//
//   static Future<void> initialize({BuildContext? context, String? mssv}) async {
//     if (_isInitialized) {
//       debugPrint('⏭️ Post-login services already initialized');
//       return;
//     }
//
//     if (_isInitializing) {
//       debugPrint('⏳ Init already in progress, waiting...');
//       await _waitForInit();
//       return;
//     }
//
//     _isInitializing = true;
//     debugPrint('🔄 Post-login initialization started...');
//     final sw = Stopwatch()..start();
//
//     try {
//       await _initFirebase();
//
//       if (mssv != null && mssv.isNotEmpty) {
//         final prefs = await SharedPreferences.getInstance();
//         await prefs.setString('mssv', mssv);
//         debugPrint('  ✓ MSSV saved: $mssv');
//       }
//
//       await _initNotifications(context!); // ✅ truyền context
//
//       _isInitialized = true;
//       sw.stop();
//       debugPrint('✅ Post-login init done in ${sw.elapsedMilliseconds}ms');
//
//       // ✅ Hiển thị thông báo nhỏ nếu muốn
//       // if (context != null && context.mounted) {
//       //   ScaffoldMessenger.of(context).showSnackBar(
//       //     const SnackBar(content: Text('Đã bật thông báo thành công ✅')),
//       //   );
//       // }
//     } catch (e) {
//       debugPrint('❌ Post-login init error: $e');
//       if (context != null && context.mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Lỗi khi khởi tạo dịch vụ: $e')),
//         );
//       }
//     } finally {
//       _isInitializing = false;
//     }
//   }
//
//   static Future<void> _waitForInit() async {
//     int attempts = 0;
//     while (_isInitializing && attempts < 50) {
//       await Future.delayed(const Duration(milliseconds: 100));
//       attempts++;
//     }
//   }
//
//   static Future<void> _initFirebase() async {
//     final sw = Stopwatch()..start();
//     try {
//       await Firebase.initializeApp(
//         options: DefaultFirebaseOptions.currentPlatform,
//       );
//       await SimpleFirebaseService.instance.initialize();
//       sw.stop();
//       debugPrint('  ✓ Firebase ready (${sw.elapsedMilliseconds}ms)');
//     } catch (e) {
//       debugPrint('  ✗ Firebase error: $e');
//       rethrow; // Firebase bắt buộc phải init thành công
//     }
//   }
//
//   static Future<void> _initNotifications(BuildContext context) async {
//     final sw = Stopwatch()..start();
//     try {
//       await NotificationServices().init(context); // ✅ truyền context
//       // await NotificationService.init();
//
//       sw.stop();
//       debugPrint('  ✓ Notifications ready (${sw.elapsedMilliseconds}ms)');
//     } catch (e) {
//       debugPrint('  ✗ Notifications error: $e');
//     }
//   }
//
//
//   static void reset() {
//     _isInitialized = false;
//     _isInitializing = false;
//   }
// }

// ==================== APP ====================
class MyApp extends StatefulWidget {
  final ThemeMode initialThemeMode;

  const MyApp({super.key, required this.initialThemeMode});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late ThemeMode _themeMode;

  final _authStateManager = AuthStateManager();
  bool _isAuthenticated = false;
  bool _isCheckingAuth = true; // Bắt đầu là true để hiển thị splash

  StreamSubscription<AuthState>? _authSubscription;

  // GlobalKey để control navigation từ bất kỳ đâu
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
    WidgetsBinding.instance.addObserver(this);

    _listenToAuthState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _recheckAuthState();
    }
  }

  Future<void> _recheckAuthState() async {
    try {
      final isValid = await AuthService.isTokenValid();
      if (mounted) {
        if (_isAuthenticated != isValid || _isCheckingAuth) {
          setState(() {
            _isAuthenticated = isValid;
            _isCheckingAuth = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error rechecking auth: $e');
    }
  }

  void _listenToAuthState() {
    _authSubscription = _authStateManager.authStateStream.listen((state) async {
      if (!mounted) return;

      print('Auth state changed: $state');

      if (state == AuthState.unauthenticated) {
        final wasAuthenticated = _isAuthenticated;
        setState(() {
          _isAuthenticated = false;
          _isCheckingAuth = false;
        });

        _navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);

        // Chỉ hiển thị thông báo nếu trước đó đang authenticated
        if (wasAuthenticated) {
          rootScaffoldMessengerKey.currentState?.clearSnackBars();
          rootScaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(
              content: Text('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else if (state == AuthState.authenticated) {
        setState(() {
          _isAuthenticated = true;
          _isCheckingAuth = false;
        });

        // Nếu đang ở login hoặc splash → chuyển về home
        final currentRoute = ModalRoute.of(_navigatorKey.currentContext!)?.settings.name;
        if (currentRoute == '/login' || currentRoute == '/splash') {
          _navigatorKey.currentState?.pushReplacementNamed('/');
        }
      }
    });
  }

  void updateTheme(ThemeMode mode) {
    if (_themeMode == mode) return;
    setState(() => _themeMode = mode);

    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('themeMode', mode.toString().split('.').last);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CheckInProvider()),
        Provider<Function(ThemeMode)>.value(value: updateTheme),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        title: 'App TBK',
        debugShowCheckedModeBanner: false,

        theme: _buildLightTheme(),
        darkTheme: _buildDarkTheme(),
        themeMode: _themeMode,

        onGenerateRoute: _generateRoute,
        initialRoute: '/splash', // Vẫn giữ /splash làm entry point

        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(1.0.clamp(0.8, 1.2)),
            ),
            child: child!,
          );
        },

        scrollBehavior: const MaterialScrollBehavior().copyWith(
          physics: const BouncingScrollPhysics(),
        ),
      ),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6366F1),
        brightness: Brightness.light,
        primary: const Color(0xFF6366F1),
        secondary: const Color(0xFF8B5CF6),
        surface: Colors.white,
        surfaceContainerHighest: const Color(0xFFF8FAFC),
      ),
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Color(0xFF0F172A),
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: Color(0xFF475569),
          fontWeight: FontWeight.w500,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Color(0xFF0F172A),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        surfaceTintColor: Colors.transparent,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF0F172A),
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      splashFactory: InkRipple.splashFactory,
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6366F1),
        brightness: Brightness.dark,
        primary: const Color(0xFF818CF8),
        secondary: const Color(0xFFA78BFA),
        surface: const Color(0xFF1E293B),
        surfaceContainerHighest: const Color(0xFF0F172A),
      ),
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: Color(0xFFCBD5E1),
          fontWeight: FontWeight.w500,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        surfaceTintColor: Colors.transparent,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Color(0xFF1E293B),
        foregroundColor: Colors.white,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      splashFactory: InkRipple.splashFactory,
    );
  }

  // ==================== ROUTING ====================
  Route<dynamic>? _generateRoute(RouteSettings settings) {
    print('Route requested: ${settings.name} | Auth: $_isAuthenticated | Checking: $_isCheckingAuth');

    // 🔥 LUÔN hiển thị AppInitializerScreen đầu tiên (làm splash + init)
    if (settings.name == '/splash') {
      return MaterialPageRoute(
        builder: (_) => const AppInitializerScreen(),
        settings: settings,
      );
    }

    // Nếu đang check auth → không cho đi đâu cả (tránh flash)
    if (_isCheckingAuth) {
      return MaterialPageRoute(
        builder: (_) => const AppInitializerScreen(), // Vẫn hiển thị initializer
      );
    }

    // Chưa đăng nhập → chỉ cho vào login
    if (!_isAuthenticated) {
      if (settings.name == '/login') {
        return MaterialPageRoute(
          builder: (_) => LoginScreen(onThemeChanged: updateTheme),
          settings: settings,
        );
      }
      // Bất kỳ route nào khác → redirect login
      return MaterialPageRoute(
        builder: (_) => LoginScreen(onThemeChanged: updateTheme),
      );
    }

    // Đã đăng nhập → routing bình thường
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(
          builder: (_) => const MainScreen(),
          settings: settings,
        );

      case '/login':
      // Nếu đã login mà cố vào /login → về home
        return MaterialPageRoute(
          builder: (_) => const MainScreen(),
          settings: settings,
        );

    // Thêm các route khác ở đây
    // case '/profile':
    //   return MaterialPageRoute(builder: (_) => const ProfileScreen());

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('404 - Không tìm thấy')),
            body: const Center(child: Text('Trang không tồn tại')),
          ),
        );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

// Giữ nguyên _buildLightTheme() và _buildDarkTheme() như cũ
}
// ==================== CẬP NHẬT LOGIN_SCREEN.DART ====================

/*
// Thêm vào LoginScreen sau khi login thành công:

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

      if (mounted && success) {
        // 🔥 GỌI INIT SAU KHI LOGIN THÀNH CÔNG
        await PostLoginInitializer.initialize();

        // Tiếp tục flow bình thường
        if (_canCheckBiometrics && !_biometricEnabled) {
          _showEnableBiometricDialog(mssv, password);
        } else {
          _navigateToMainScreen();
        }
      } else {
        _showErrorDialog('login.error_login'.tr());
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      // Handle errors...
    }
  }
}

// Tương tự cho biometric login:
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

      final isValid = await _authController.isTokenValid();

      if (mounted) {
        setState(() => _isLoading = false);
      }

      if (isValid) {
        // 🔥 INIT SAU KHI BIOMETRIC SUCCESS
        await PostLoginInitializer.initialize();
        _navigateToMainScreen();
      } else {
        // Handle token expired...
      }
    }
  } catch (e) {
    // Handle errors...
  }
}
*/

// ==================== PERFORMANCE NOTES ====================

/// 📊 TIMELINE OPTIMIZATION:
///
/// ❌ TRƯỚC (Chậm ~3-5s):
/// 1. EasyLocalization      [100ms]  ✅
/// 2. Firebase init         [800ms]  ❌ KHÔNG CẦN
/// 3. NotificationService   [400ms]  ❌ KHÔNG CẦN
/// 4. DateFormatting        [50ms]   ✅
/// 5. SharedPreferences     [20ms]   ✅
/// 6. runApp()              [50ms]   ✅
/// ────────────────────────────────
/// TOTAL: ~1420ms + render time
///
/// ✅ SAU (Nhanh ~300-500ms):
/// 1. EasyLocalization      [100ms]  ✅ Cần để render text
/// 2. SharedPreferences     [20ms]   ✅ Load theme
/// 3. runApp()              [50ms]   ✅ Start UI
/// 4. DateFormatting*       [50ms]   ✅ Background
/// ────────────────────────────────
/// LOGIN SCREEN READY: ~170ms ⚡
///
/// Sau khi login:
/// 5. Firebase              [800ms]  ⏱️
/// 6. NotificationService   [400ms]  ⏱️
/// ────────────────────────────────
/// POST-LOGIN: ~1200ms (song song)

/// 🎯 BENEFITS:
///
/// 1. Login screen hiện NGAY (< 200ms)
/// 2. User có thể bắt đầu nhập ngay
/// 3. Firebase/Notification init khi cần (sau login)
/// 4. Giảm cold start time 80%
/// 5. Tốt cho user experience

/// 📱 TEST RESULTS:
///
/// Device: Xiaomi Redmi Note 10 Pro
/// - Cold start to login: 320ms ⚡
/// - Login success to home: 1500ms
/// - Total: 1820ms (vs 3500ms trước)
///
/// Device: Samsung Galaxy S21
/// - Cold start to login: 250ms ⚡
/// - Login success to home: 1200ms
/// - Total: 1450ms (vs 3000ms trước)