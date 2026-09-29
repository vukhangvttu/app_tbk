import 'dart:math';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'face_id_scanning_screen.dart';

class FaceIdSetupScreen extends StatefulWidget {
  const FaceIdSetupScreen({super.key});

  @override
  State<FaceIdSetupScreen> createState() => _FaceIdSetupScreenState();
}

class _FaceIdSetupScreenState extends State<FaceIdSetupScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _opacityAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleStartFaceId() async {
    final status = await Permission.camera.status;

    if (status.isGranted) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const FaceIdScanningScreen(),
        ),
      );
      return;
    }

    final result = await Permission.camera.request();

    if (!mounted) return;

    if (result.isGranted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const FaceIdScanningScreen(),
        ),
      );
    } else if (result.isPermanentlyDenied) {
      _showPermissionDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ứng dụng cần quyền camera để thiết lập Face ID.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          'Yêu cầu quyền Camera',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Để thực hiện thiết lập Face ID, ứng dụng cần truy cập camera. Vui lòng cấp quyền camera trong phần Cài đặt của thiết bị.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Cài đặt', style: TextStyle(color: Color(0xFF007AFF))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Navigation Header (Top cancel action)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  behavior: HitTestBehavior.opaque,
                  child: const Text(
                    'Hủy',
                    style: TextStyle(
                      color: Color(0xFF007AFF),
                      fontSize: 17,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),

            // Main Content Area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    // Face ID Graphic Container
                    FadeTransition(
                      opacity: _opacityAnimation,
                      child: SizedBox(
                        width: 280,
                        height: 280,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 48 Ticks Radial Outer Ring
                            CustomPaint(
                              size: const Size(280, 280),
                              painter: _FaceIdTicksPainter(),
                            ),
                            // Center Inner Face Circle
                            Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFD1D5DB),
                                  width: 3,
                                ),
                              ),
                              child: Center(
                                child: CustomPaint(
                                  size: const Size(80, 80),
                                  painter: _FaceIdGlyphPainter(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Instruction Text
                    const Text(
                      'Cách thiết lập Face ID',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: const Text(
                        'Đầu tiên, định vị khuôn mặt của bạn trong khung hình camera. Sau đó, di chuyển đầu của bạn theo hình tròn để hiển thị tất cả các góc cạnh trên khuôn mặt của bạn.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFEBEBF5),
                          fontSize: 16.5,
                          height: 1.38,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // Bottom Primary CTA Button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 370),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: Material(
                    color: const Color(0xFF007AFF),
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _handleStartFaceId,
                      child: const Center(
                        child: Text(
                          'Bắt đầu',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
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
}

class _FaceIdTicksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFFE5E7EB).withOpacity(0.88)
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double outerRadius = (size.width / 2) - 10;
    final double innerRadius = outerRadius - 14;

    const int totalTicks = 48;
    const double angleStep = (2 * pi) / totalTicks;

    for (int i = 0; i < totalTicks; i++) {
      final double angle = i * angleStep;
      final double dx1 = cx + innerRadius * sin(angle);
      final double dy1 = cy - innerRadius * cos(angle);
      final double dx2 = cx + outerRadius * sin(angle);
      final double dy2 = cy - outerRadius * cos(angle);

      canvas.drawLine(Offset(dx1, dy1), Offset(dx2, dy2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FaceIdGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFFD1D5DB)
      ..strokeWidth = 4.2 * (size.width / 80.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final double scale = size.width / 80.0;

    // Left Eye
    canvas.drawLine(
      Offset(26 * scale, 29 * scale),
      Offset(26 * scale, 36 * scale),
      paint,
    );

    // Right Eye
    canvas.drawLine(
      Offset(54 * scale, 29 * scale),
      Offset(54 * scale, 36 * scale),
      paint,
    );

    // Nose: M42 29 V43 H35
    final Path nosePath = Path()
      ..moveTo(42 * scale, 29 * scale)
      ..lineTo(42 * scale, 43 * scale)
      ..lineTo(35 * scale, 43 * scale);
    canvas.drawPath(nosePath, paint);

    // Smile: M30 51 C34 57 46 57 50 51
    final Path smilePath = Path()
      ..moveTo(30 * scale, 51 * scale)
      ..cubicTo(
        34 * scale,
        57 * scale,
        46 * scale,
        57 * scale,
        50 * scale,
        51 * scale,
      );
    canvas.drawPath(smilePath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
