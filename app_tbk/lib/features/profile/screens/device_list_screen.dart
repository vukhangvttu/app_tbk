// lib/features/profile/screens/device_list_screen.dart
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/device_session.dart';
import '../services/device_service.dart';

class DeviceListScreen extends StatefulWidget {
  final List<DeviceSession> devices;

  const DeviceListScreen({Key? key, required this.devices}) : super(key: key);

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  late List<DeviceSession> _devices;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _devices = widget.devices;
  }

  Future<void> _logoutDevice(DeviceSession device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận đăng xuất'),
        content: Text(
          'Bạn có chắc muốn đăng xuất khỏi thiết bị "${device.deviceName}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await DeviceService.logoutDevice(device.deviceId);

      setState(() {
        _devices.removeWhere((d) => d.deviceId == device.deviceId);
        _isLoading = false;
      });

      _showSuccess('Đã đăng xuất thiết bị thành công');
    } catch (e) {
      setState(() => _isLoading = false);
      _showError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _logoutAllOthers() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận đăng xuất'),
        content: const Text(
          'Bạn có chắc muốn đăng xuất khỏi TẤT CẢ các thiết bị khác?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Đăng xuất tất cả', style: TextStyle(color: Colors.white), ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await DeviceService.logoutAllOtherDevices();

      setState(() {
        _devices.removeWhere((d) => !d.isCurrentDevice);
        _isLoading = false;
      });

      _showSuccess('Đã đăng xuất tất cả thiết bị khác');
    } catch (e) {
      setState(() => _isLoading = false);
      _showError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'mobile':
        return Icons.phone_android_rounded;
      case 'tablet':
        return Icons.tablet_rounded;
      case 'desktop':
        return Icons.computer_rounded;
      case 'web':
        return Icons.language_rounded;
      default:
        return Icons.devices_rounded;
    }
  }

  String _getOSIcon(String os) {
    final osLower = os.toLowerCase();
    if (osLower.contains('android')) return '🤖';
    if (osLower.contains('ios')) return '🍎';
    if (osLower.contains('windows')) return '🪟';
    if (osLower.contains('mac')) return '💻';
    if (osLower.contains('linux')) return '🐧';
    return '📱';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2);

    final currentDevice = _devices.firstWhere(
          (d) => d.isCurrentDevice,
      orElse: () => _devices.first,
    );
    final otherDevices = _devices.where((d) => !d.isCurrentDevice).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thiết bị đăng nhập'),
        elevation: 0,
        actions: [
          if (otherDevices.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Đăng xuất tất cả thiết bị khác',
              onPressed: _isLoading ? null : _logoutAllOthers,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current Device
          Text(
            'Thiết bị hiện tại',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _buildDeviceCard(currentDevice, primaryColor, isDark, isCurrent: true),

          // Other Devices
          if (otherDevices.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Thiết bị khác (${otherDevices.length})',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            ...otherDevices.map((device) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildDeviceCard(device, primaryColor, isDark),
            )),
          ],

          // Empty state
          if (otherDevices.isEmpty) ...[
            const SizedBox(height: 32),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.devices_rounded,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Không có thiết bị khác',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceCard(
      DeviceSession device,
      Color primaryColor,
      bool isDark, {
        bool isCurrent = false,
      }) {
    final now = DateTime.now();
    final isExpired = device.expiresAt.isBefore(now);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrent
            ? BorderSide(color: primaryColor, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getDeviceIcon(device.deviceType),
                    color: primaryColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              device.deviceName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Hiện tại',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_getOSIcon(device.os)} ${device.os} ${device.osVersion}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Details
            _buildInfoRow(
              Icons.access_time_rounded,
              'Đăng nhập',
              _formatDateTime(device.loginAt),
              isDark,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.update_rounded,
              'Hoạt động',
              _formatDateTime(device.lastActiveAt),
              isDark,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.event_busy_rounded,
              'Hết hạn',
              _formatDateTime(device.expiresAt),
              isDark,
              isExpired: isExpired,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.location_on_outlined,
              'IP',
              device.ipAddress,
              isDark,
            ),

            // Logout button
            if (!isCurrent) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _logoutDevice(device),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Đăng xuất thiết bị'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
      IconData icon,
      String label,
      String value,
      bool isDark, {
        bool isExpired = false,
      }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isExpired
              ? Colors.red
              : (isDark ? Colors.grey[500] : Colors.grey[600]),
        ),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isExpired
                  ? Colors.red
                  : (isDark ? Colors.white : Colors.black87),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Vừa xong';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} phút trước';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} giờ trước';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else {
      return DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
    }
  }
}