import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPermissionsScreen extends StatefulWidget {
  const AppPermissionsScreen({super.key});

  @override
  State<AppPermissionsScreen> createState() => _AppPermissionsScreenState();
}

class _AppPermissionsScreenState extends State<AppPermissionsScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  PermissionStatus _cameraStatus = PermissionStatus.denied;
  PermissionStatus _locationStatus = PermissionStatus.denied;
  PermissionStatus _notificationStatus = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    setState(() => _isLoading = true);
    try {
      final camera = await Permission.camera.status;
      final location = await Permission.location.status;
      final notification = await Permission.notification.status;

      if (mounted) {
        setState(() {
          _cameraStatus = camera;
          _locationStatus = location;
          _notificationStatus = notification;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _requestPermission(Permission permission) async {
    final status = await permission.status;

    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }

    final result = await permission.request();
    if (result.isPermanentlyDenied) {
      if (mounted) {
        _showGoToSettingsDialog();
      }
    } else {
      _checkPermissions();
    }
  }

  Future<void> _requestAllPermissions() async {
    setState(() => _isLoading = true);
    try {
      await [
        Permission.camera,
        Permission.location,
        Permission.notification,
      ].request();
    } catch (_) {}
    await _checkPermissions();
  }

  void _showGoToSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cần cấp quyền trong Cài đặt'),
        content: const Text(
          'Quyền này đã bị từ chối vĩnh viễn. Vui lòng mở Cài đặt ứng dụng trên thiết bị để bật thủ công.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Mở Cài đặt'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Quyền truy cập ứng dụng',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeaderCard(isDark),
                const SizedBox(height: 20),
                _buildPermissionTile(
                  icon: Icons.camera_alt_outlined,
                  iconColor: Colors.blue,
                  title: 'Quyền Máy ảnh (Camera)',
                  subtitle: 'Dùng cho chức năng nhận diện khuôn mặt điểm danh',
                  status: _cameraStatus,
                  onTap: () => _requestPermission(Permission.camera),
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildPermissionTile(
                  icon: Icons.location_on_outlined,
                  iconColor: Colors.redAccent,
                  title: 'Quyền Vị trí (GPS)',
                  subtitle: 'Dùng để xác thực vị trí điểm danh trong bán kính trường học',
                  status: _locationStatus,
                  onTap: () => _requestPermission(Permission.location),
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildPermissionTile(
                  icon: Icons.notifications_active_outlined,
                  iconColor: Colors.orange,
                  title: 'Quyền Thông báo',
                  subtitle: 'Nhận thông báo nhắc lịch học, lịch thi và cảnh báo',
                  status: _notificationStatus,
                  onTap: () => _requestPermission(Permission.notification),
                  isDark: isDark,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _requestAllPermissions,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.primaryColor,
                      side: BorderSide(color: theme.primaryColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.touch_app_outlined),
                    label: const Text(
                      'Yêu cầu kích hoạt tất cả quyền',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: openAppSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text(
                      'Mở Cài đặt hệ thống iPhone',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeaderCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.blue.withValues(alpha: 0.3) : Colors.blue.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.shield_outlined,
            size: 36,
            color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Lưu ý iOS: Camera và Vị trí chỉ tự động xuất hiện trong "Cài đặt iPhone -> App Tbk" sau khi ứng dụng bật pop-up xin quyền ít nhất 1 lần.',
              style: TextStyle(
                fontSize: 13.0,
                height: 1.4,
                color: isDark ? Colors.grey.shade300 : Colors.blue.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required PermissionStatus status,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final bool isGranted = status.isGranted;
    final bool isPermanentlyDenied = status.isPermanentlyDenied;

    String statusText = 'Chưa cấp quyền';
    Color statusColor = Colors.orange;

    if (isGranted) {
      statusText = 'Đã cho phép';
      statusColor = Colors.green;
    } else if (isPermanentlyDenied) {
      statusText = 'Bị từ chối';
      statusColor = Colors.red;
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: isDark ? 0.2 : 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        trailing: Transform.scale(
          scale: 0.85,
          child: Switch(
            value: isGranted,
            activeColor: Colors.green,
            onChanged: (_) => onTap(),
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
