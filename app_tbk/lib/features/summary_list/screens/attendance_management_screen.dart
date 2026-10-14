import 'package:app_tbk/features/attendance/screens/attendance_history_screen.dart';
import 'package:app_tbk/features/check-in/screens/checkin_screen.dart';
import 'package:app_tbk/features/absence-warning/screens/absence_warning_screen.dart';
import 'package:app_tbk/features/training_point/screens/training_point_screen.dart';
import 'package:app_tbk/features/course_grade/screens/course_grade_screen.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class AttendanceManagementScreen extends StatefulWidget {
  const AttendanceManagementScreen({Key? key}) : super(key: key);

  @override
  State<AttendanceManagementScreen> createState() => _AttendanceManagementScreenState();
}

class _AttendanceManagementScreenState extends State<AttendanceManagementScreen> {
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
    } else if (screen == 'absence_warning') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const AbsenceWarningScreen(),
        ),
      );
    } else if (screen == 'training_point') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const TrainingPointScreen(),
        ),
      );
    } else if (screen == 'course_grade') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const CourseGradeScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text(
          'Danh sách chức năng',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        elevation: 0,
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 16),
                _buildSection(
                  theme,
                  isDark,
                  title: 'Quản lý học tập & Sự kiện',
                  icon: Icons.school_outlined,
                  children: [
                    _buildActionTile(
                      icon: Icons.warning_amber_rounded,
                      title: 'absence_warning.title'.tr(),
                      subtitle: 'Xem cảnh báo môn học có nguy cơ cấm thi',
                      onTap: () => _navigateTo('absence_warning'),
                      isDark: isDark,
                      iconColor: Colors.orange,
                    ),
                    _buildActionTile(
                      icon: Icons.history_outlined,
                      title: 'Điểm danh',
                      subtitle: 'Xem lịch sử điểm danh',
                      onTap: () => _navigateTo('attendance'),
                      isDark: isDark,
                      iconColor: Colors.blue,
                    ),
                    _buildActionTile(
                      icon: Icons.score_outlined,
                      title: 'Điểm học phần',
                      subtitle: 'Xem điểm các môn học',
                      onTap: () => _navigateTo('course_grade'),
                      isDark: isDark,
                      iconColor: Colors.indigo,
                    ),
                    _buildActionTile(
                      icon: Icons.star_outline_rounded,
                      title: 'Điểm rèn luyện',
                      subtitle: 'Xem lịch sử điểm rèn luyện',
                      onTap: () => _navigateTo('training_point'),
                      isDark: isDark,
                      iconColor: Colors.purple,
                    ),
                    _buildActionTile(
                      icon: Icons.camera_alt_outlined,
                      title: 'Check-in',
                      subtitle: 'Check-in sự kiện',
                      onTap: () => _navigateTo('checkin'),
                      isDark: isDark,
                      iconColor: Colors.green,
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    ThemeData theme,
    bool isDark, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor != null
              ? iconColor.withValues(alpha: 0.1)
              : (isDark
                  ? Colors.grey.shade800.withValues(alpha: 0.5)
                  : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: iconColor ?? (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
      ),
      onTap: onTap,
    );
  }
}
