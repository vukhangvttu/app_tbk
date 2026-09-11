import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../security_checker_service.dart';
import '../models/event_model.dart';
import '../providers/checkin_provider.dart';
import '../widgets/face_camera_widget.dart';

class CheckInScreen extends StatefulWidget {
  const CheckInScreen({Key? key}) : super(key: key);

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  bool _showCamera = false;
  bool _isCheckingIn = false;

  @override
  void initState() {
    super.initState();
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   context.read<CheckInProvider>().loadEvents();
    // });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
       await _performSecurityCheck(); // kiểm tra root / mock location, v.v.
      if (mounted && _isSecure) {
        // Chỉ khởi tạo sinh trắc học khi thiết bị an toàn
        context.read<CheckInProvider>().loadEvents();
      }
    });
  }

  bool _isChecking = true;
  bool _isSecure = true;
  String _detectionDetails = '';
  final SafeDeviceExamples _securityChecker = SafeDeviceExamples();

  /// Thực hiện kiểm tra bảo mật ngay khi khởi động
  Future<void> _performSecurityCheck() async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));

      SecurityStatus result = await _securityChecker.comprehensiveCheck();

      setState(() {
        _isChecking = false;
        _isSecure = result.isSafe;
        _detectionDetails = result.reason;
      });

      if (!result.isSafe) {
        _showSecurityWarningDialog(context, _detectionDetails);

      }
    } catch (e) {
      setState(() {
        _isChecking = false;
        _isSecure = false;
        _detectionDetails = 'Error: $e';
      });
      _showSecurityWarningDialog(context, _detectionDetails);

    }
  }

  // Hiển thị dialog cảnh báo bảo mật
  void _showSecurityWarningDialog(BuildContext context, String detectionDetails) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            // didPop = true nếu pop thành công
            // result = giá trị trả về khi pop (nếu có)
            // Bạn có thể thêm xử lý ở đây nếu cần
          },
          child: AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.security, color: Colors.red[700], size: 30),
                const SizedBox(width: 10),
                Expanded( // 👈 thêm dòng này để Text co giãn không tràn
                  child: Text(
                    'Cảnh báo bảo mật',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 18,
                    ),
                    overflow: TextOverflow.ellipsis, // nếu vẫn dài thì sẽ hiện "..."
                    maxLines: 1, // hoặc có thể bỏ dòng này nếu muốn tự xuống hàng
                    softWrap: true,
                  ),
                ),
              ],
            ),

            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hệ thống phát hiện thiết bị của bạn có dấu hiệu không an toàn:',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.red.withOpacity(0.15) : Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.redAccent.withOpacity(0.4) : Colors.red[200]!,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          detectionDetails,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Ứng dụng sẽ tự động đóng khi bạn nhấn "OK".',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
            actions: [
              Center(
                child: ElevatedButton.icon(
                  onPressed: _closeApp,
                  icon: const Icon(Icons.exit_to_app, color: Colors.white),
                  label: const Text(
                    'OK',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                    padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _closeApp() {
    // Đóng app ngay lập tức
    if (Platform.isAndroid) {
      SystemNavigator.pop(); // Android
    } else if (Platform.isIOS) {
      exit(0); // iOS
    } else {
      exit(0);
    }
  }

  Future<void> _startCheckIn() async {
    final provider = context.read<CheckInProvider>();
    final permissions = await provider.checkPermissions();

    if (!permissions['camera']!) {
      _showError('Vui lòng cấp quyền Camera');
      return;
    }
    if (!permissions['location']!) {
      _showError('Vui lòng cấp quyền Vị trí');
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showLocationDialog();
      return;
    }

    setState(() => _showCamera = true);
  }

  void _showLocationDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.location_off, color: Colors.redAccent, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Bật vị trí',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gps_off, size: 72, color: Colors.redAccent.withOpacity(0.7)),
            const SizedBox(height: 16),
            Text(
              'Vị trí đang bị tắt.\nVui lòng bật GPS để check-in.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurface.withOpacity(0.9)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Hủy', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
            icon: const Icon(Icons.location_on),
            label: const Text('Bật GPS'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCapture(String base64Image, Uint8List imageBytes) async {
    setState(() {
      _showCamera = false;
      _isCheckingIn = true;
    });

    try {
      final provider = context.read<CheckInProvider>();
      final event = provider.selectedEvent;

      if (event == null) {
        _showError('Không tìm thấy sự kiện');
        return;
      }

      final locationResult = await provider.getCurrentLocation();
      if (!locationResult['success']) {
        _showError(locationResult['message']);
        setState(() => _isCheckingIn = false);
        return;
      }

      final checkInData = CheckInData(
        eventId: event.id,
        faceImageBase64: base64Image,
        latitude: locationResult['latitude'],
        longitude: locationResult['longitude'],
        timestamp: DateTime.now(),
      );

      // in gọn, an toàn:
      print('📦 Check-in: ${checkInData.eventId} - ${checkInData.latitude}, ${checkInData.longitude} - imgLen=${checkInData.faceImageBase64.length}');


      final response = await provider.submitCheckIn(checkInData);
      if (response.success) {
        provider.markAsCheckedIn(event.id);
        _showSuccess('Check-in thành công!');
      } else {
        _showError(response.message);
      }
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      setState(() => _isCheckingIn = false);
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        msg,
        style: const TextStyle(color: Colors.white), // 🔹 chữ trắng
      ),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 4),
    ),
  );


  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green, duration: const Duration(seconds: 3)),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_showCamera) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: FaceCameraWidget(
          onCapture: _handleCapture,
          onCancel: () => setState(() => _showCamera = false),
        ),
      );
    }

    if (_isCheckingIn) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 5),
              SizedBox(height: 24),
              Text('Đang xử lý check-in...', style: TextStyle(fontSize: 18)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-in Sự kiện', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [Colors.blue.shade900, Colors.purple.shade900]
                  : [Colors.blue.shade600, Colors.purple.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Consumer<CheckInProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return _buildErrorState(provider.error!, provider.loadEvents);
          }

          if (provider.events.isEmpty) {
            return const Center(child: Text('Không có sự kiện nào', style: TextStyle(fontSize: 18)));
          }

          final event = provider.selectedEvent ?? provider.events.first;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildEventCard(event, theme),
              const SizedBox(height: 24),
              _buildCountdownTimer(event, theme),
              const SizedBox(height: 32),
              _buildCheckInButton(event, theme),
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorState(String error, VoidCallback retry) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(CheckInEvent event, ThemeData theme) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final timeFormat = DateFormat('HH:mm');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: theme.brightness == Brightness.dark
              ? [Colors.grey.shade900, Colors.grey.shade800]
              : [Colors.white, Colors.grey.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.event_available, color: Colors.blue.shade700, size: 36),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(event.date),
                      style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              if (event.isCheckedIn)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Đã check-in',
                        style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const Divider(height: 32, thickness: 1),
          _buildInfoRow(Icons.access_time, 'Giờ check-in', '${timeFormat.format(event.checkInStartTime)} - ${timeFormat.format(event.checkInEndTime)}'),
          if (event.location != null) ...[
            const SizedBox(height: 12),
            _buildInfoRow(Icons.location_on, 'Địa điểm', event.location!),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 22, color: Colors.blue.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownTimer(CheckInEvent event, ThemeData theme) {
    if (event.canCheckIn) {
      return _buildStatusCard(
        'Sẵn sàng check-in',
        Icons.check_circle,
        Colors.green,
        theme,
      );
    }

    if (event.timeUntilCheckIn == Duration.zero) {
      return _buildStatusCard(
        'Đã hết giờ check-in',
        Icons.cancel,
        Colors.red,
        theme,
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          Text(
            'Check-in sau',
            style: TextStyle(fontSize: 15, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _CountdownDisplay(
            duration: event.timeUntilCheckIn,
            onFinished: () => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(String text, IconData icon, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckInButton(CheckInEvent event, ThemeData theme) {
    final canCheckIn = event.canCheckIn && !event.isCheckedIn;

    return SizedBox(
      height: 60,
      child: ElevatedButton.icon(
        onPressed: canCheckIn ? _startCheckIn : null,
        icon: const Icon(Icons.camera_alt, size: 26),
        label: Text(
          event.isCheckedIn
              ? 'Đã check-in'
              : canCheckIn
              ? 'Bắt đầu Check-in'
              : 'Chưa đến giờ',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: canCheckIn ? Colors.blueAccent : Colors.grey.shade400,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: canCheckIn ? 8 : 0,
          shadowColor: canCheckIn ? Colors.blueAccent.withOpacity(0.5) : null,
        ),
      ),
    );
  }
}

// === COUNTDOWN HIỆN ĐẠI ===
class _CountdownDisplay extends StatefulWidget {
  final Duration duration;
  final VoidCallback? onFinished;

  const _CountdownDisplay({
    required this.duration,
    this.onFinished,
  });

  @override
  State<_CountdownDisplay> createState() => _CountdownDisplayState();
}

class _CountdownDisplayState extends State<_CountdownDisplay> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.duration;
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _CountdownDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _remaining = widget.duration;
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remaining.inSeconds > 1) {
        setState(() {
          _remaining -= const Duration(seconds: 1);
        });
      } else {
        _timer?.cancel();
        setState(() {
          _remaining = Duration.zero;
        });
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            widget.onFinished?.call();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _remaining.inHours;
    final m = _remaining.inMinutes.remainder(60);
    final s = _remaining.inSeconds.remainder(60);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildDigit(h, 'GIỜ'),
        _buildSeparator(),
        _buildDigit(m, 'PHÚT'),
        _buildSeparator(),
        _buildDigit(s, 'GIÂY'),
      ],
    );
  }

  Widget _buildDigit(int value, String label) {
    return Column(
      children: [
        Container(
          width: 70,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade700, Colors.purple.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4)),
            ],
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildSeparator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text(':', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.blue)),
    );
  }
}