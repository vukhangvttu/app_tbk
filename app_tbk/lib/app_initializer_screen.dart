// lib/screens/app_initializer_screen.dart
import 'package:app_tbk/screens/main_screen.dart';
import 'package:flutter/material.dart';
import 'package:app_tbk/features/auth/services/auth_service.dart';
import 'package:app_tbk/features/auth/services/post_login_initializer.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'features/auth/screens/login_screen.dart';


class AppInitializerScreen extends StatefulWidget {
  const AppInitializerScreen({super.key});

  @override
  State<AppInitializerScreen> createState() => _AppInitializerScreenState();
}

class _AppInitializerScreenState extends State<AppInitializerScreen> {
  bool _isInitializing = true;
  String _statusMessage = 'Đang khởi động ứng dụng...';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _statusMessage = 'Đang kiểm tra phiên đăng nhập...';
      });

      // Kiểm tra token có hợp lệ không (tự động refresh nếu cần)
      final bool isLoggedIn = await AuthService.isTokenValid();

      if (!mounted) return;

      if (isLoggedIn) {
        setState(() {
          _statusMessage = 'Đang tải dữ liệu cá nhân...';
        });

        // Lấy MSSV từ secure storage
        final String? mssv = await AuthService.getSavedMssv();

        if (mssv != null && mssv.isNotEmpty) {
          setState(() {
            _statusMessage = 'Đang kích hoạt thông báo và dịch vụ...';
          });

          // 🔥 QUAN TRỌNG: Chỉ gọi quickInit khi đã xác nhận đăng nhập
          await PostLoginInitializer.quickInit(
            context: context,
            mssv: mssv,
          );

          // Optional: Đợi một chút để đảm bảo init xong (nếu cần lazy load)
          // await PostLoginInitializer.ensureInitialized(context);
        } else {
          debugPrint('⚠️ Đã login nhưng không tìm thấy MSSV → Đăng xuất buộc');
          await AuthService.logout();
        }

        if (!mounted) return;

        // Chuyển sang MainScreen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      } else {
        // Chưa đăng nhập → Chuyển sang Login
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (e) {
      debugPrint('❌ Lỗi khởi động app: $e');

      if (!mounted) return;

      setState(() {
        _statusMessage = 'Lỗi kết nối. Đang chuyển đến đăng nhập...';
      });

      // Dù lỗi vẫn chuyển về login để người dùng thử lại
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor, // hoặc màu nền app của bạn
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo app (thay bằng asset của bạn)
            Image.asset(
              'assets/images/logo-vttu.png', // ← Đảm bảo có file này
              width: 120,
              height: 120,
              errorBuilder: (_, __, ___) => Icon(
                Icons.school,
                size: 100,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 40),

            // Loading indicator
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              strokeWidth: 3,
            ),
            const SizedBox(height: 24),

            // Thông báo trạng thái
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _statusMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 80),

            // Version nhỏ ở dưới (tùy chọn)
            FutureBuilder<String>(
              future: () async {
                final info = await PackageInfo.fromPlatform();
                return 'v${info.version}';
              }(),
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? '',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}