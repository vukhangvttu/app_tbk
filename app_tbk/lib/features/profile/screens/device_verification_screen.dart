// lib/features/profile/screens/device_verification_screen.dart
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/device_service.dart';
import 'device_list_screen.dart';

class DeviceVerificationScreen extends StatefulWidget {
  const DeviceVerificationScreen({Key? key}) : super(key: key);

  @override
  State<DeviceVerificationScreen> createState() => _DeviceVerificationScreenState();
}

class _DeviceVerificationScreenState extends State<DeviceVerificationScreen> {
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _showOtpField = false;
  bool _obscurePassword = true;
  String? _userEmail;

  @override
  void dispose() {
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyPassword() async {
    if (_passwordController.text.trim().isEmpty) {
      _showError('Vui lòng nhập mật khẩu');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await DeviceService.requestDeviceListOTP(
        password: _passwordController.text.trim(),
      );

      setState(() {
        _showOtpField = true;
        _userEmail = result['email'];
        _isLoading = false;
      });

      _showSuccess('Mã OTP đã được gửi đến email ${_maskEmail(_userEmail!)}');
    } catch (e) {
      setState(() => _isLoading = false);
      _showError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _verifyOTP() async {
    if (_otpController.text.trim().isEmpty) {
      _showError('Vui lòng nhập mã OTP');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final devices = await DeviceService.verifyOTPAndGetDevices(
        otp: _otpController.text.trim(),
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DeviceListScreen(devices: devices),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;

    final username = parts[0];
    final domain = parts[1];

    if (username.length <= 2) return email;

    final visible = username.substring(0, 2);
    final masked = '*' * (username.length - 2);

    return '$visible$masked@$domain';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(
          color: Colors.white,       // text trắng
          fontWeight: FontWeight.w500,
        ),),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,style: const TextStyle(
          color: Colors.white,       // text trắng
          fontWeight: FontWeight.w500,
        ),),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Xác thực bảo mật'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.security_rounded,
                size: 64,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              'Xác thực danh tính',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              _showOtpField
                  ? 'Nhập mã OTP đã được gửi đến email của bạn'
                  : 'Vui lòng xác nhận mật khẩu để xem danh sách thiết bị',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Password Field
            if (!_showOtpField) ...[
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  hintText: 'Nhập mật khẩu của bạn',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                enabled: !_isLoading,
                onSubmitted: (_) => _verifyPassword(),
              ),
              const SizedBox(height: 24),

              // Verify Password Button
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyPassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Text(
                    'Xác nhận',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],

            // OTP Field
            if (_showOtpField) ...[
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Mã OTP',
                  hintText: '000000',
                  prefixIcon: const Icon(Icons.pin_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  counterText: '',
                ),
                enabled: !_isLoading,
                onSubmitted: (_) => _verifyOTP(),
              ),
              const SizedBox(height: 16),

              // Email hint
              if (_userEmail != null)
                Text(
                  'Mã đã được gửi đến: ${_maskEmail(_userEmail!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 24),

              // Verify OTP Button
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOTP,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Text(
                    'Xác nhận OTP',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Resend OTP
              TextButton(
                onPressed: _isLoading ? null : _verifyPassword,
                child: Text(
                  'Gửi lại mã OTP',
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}