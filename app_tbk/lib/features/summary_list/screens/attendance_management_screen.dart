import 'package:app_tbk/features/attendance/screens/attendance_history_screen.dart';
import 'package:app_tbk/features/check-in/screens/checkin_screen.dart';
import 'package:flutter/material.dart';

class AttendanceManagementScreen extends StatefulWidget {
  const AttendanceManagementScreen({Key? key}) : super(key: key);

  @override
  State<AttendanceManagementScreen> createState() => _AttendanceManagementScreenState();
}

class _AttendanceManagementScreenState extends State<AttendanceManagementScreen> {
  String? _selectedScreen;

  void _navigateTo(String screen) {
    if (screen == 'attendance') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AttendanceHistoryScreen(
            onTabSelected: (index) {},
          ),
        ),
      );
    } else if (screen == 'checkin') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const CheckInScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Danh sách chức năng', style: TextStyle(fontWeight: FontWeight.bold)),

        elevation: 0,

      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Điểm danh
            _buildMenuItem(
              context: context,
              icon: Icons.history_outlined,
              title: 'Điểm danh',
              subtitle: 'Xem lịch sử điểm danh',
              onTap: () => _navigateTo('attendance'),
              isDark: isDark,
            ),
            const SizedBox(height: 16),

            // Check-in
            _buildMenuItem(
              context: context,
              icon: Icons.camera_alt_outlined,
              title: 'Check-in',
              subtitle: 'Check-in sự kiện',
              onTap: () => _navigateTo('checkin'),
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800.withValues(alpha: 0.8) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha : 0.1) : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha:  0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 32,
                    color: const Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(width: 16),

                // Text content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Arrow icon
                Icon(
                  Icons.chevron_right,
                  color: isDark ? Colors.white38 : Colors.grey.shade400,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}