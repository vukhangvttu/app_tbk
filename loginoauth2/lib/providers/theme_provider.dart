import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quản lý trạng thái Theme (Sáng / Tối) toàn cục.
/// Trạng thái được lưu lại bằng SharedPreferences để giữ nguyên
/// lựa chọn của người dùng sau khi tắt app.
class ThemeProvider extends ChangeNotifier {
  static const _prefsKey = 'is_dark_mode';

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  ThemeProvider() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_prefsKey) ?? false;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  /// Đảo trạng thái theme và lưu lại lựa chọn
  Future<void> toggleTheme() async {
    _themeMode =
        _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, _themeMode == ThemeMode.dark);
  }
}
