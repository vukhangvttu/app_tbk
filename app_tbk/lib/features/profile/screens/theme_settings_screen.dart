import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeSettingsScreen extends StatefulWidget {
  final ThemeMode? currentThemeMode;
  final Function(ThemeMode)? onThemeChanged;

  const ThemeSettingsScreen({
    super.key,
    this.currentThemeMode,
    this.onThemeChanged,
  });

  @override
  State<ThemeSettingsScreen> createState() => _ThemeSettingsScreenState();
}

class _ThemeSettingsScreenState extends State<ThemeSettingsScreen> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.currentThemeMode ?? ThemeMode.system;
  }

  Widget _buildThemeOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required ThemeMode mode,
  }) {
    final isSelected = _themeMode == mode;

    return RadioListTile<ThemeMode>(
      value: mode,
      groupValue: _themeMode,
      onChanged: (ThemeMode? value) async {
        if (value != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('themeMode', value.toString().split('.').last);
          setState(() {
            _themeMode = value;
          });
          if (widget.onThemeChanged != null) {
            widget.onThemeChanged!(value);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã chuyển sang chế độ $title'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      title: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(title),
        ],
      ),
      subtitle: Text(subtitle),
      selected: isSelected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chọn giao diện'),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 0,
      ),
      body: Container(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildThemeOption(
              title: 'Theo hệ thống',
              subtitle: 'Tự động thay đổi theo cài đặt thiết bị',
              icon: Icons.brightness_auto,
              mode: ThemeMode.system,
            ),
            _buildThemeOption(
              title: 'Sáng',
              subtitle: 'Giao diện sáng',
              icon: Icons.light_mode,
              mode: ThemeMode.light,
            ),
            _buildThemeOption(
              title: 'Tối',
              subtitle: 'Giao diện tối',
              icon: Icons.dark_mode,
              mode: ThemeMode.dark,
            ),
          ],
        ),
      ),
    );
  }
}