import 'package:easy_localization/easy_localization.dart';
import 'package:app_tbk/features/notification/screens/notification_history_screen.dart';
import 'package:app_tbk/features/profile/screens/profile_screen.dart';
import 'package:app_tbk/features/schedule/screens/schedule_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'notification_screen.dart';

class MainScreen extends StatefulWidget {
  final Function(ThemeMode)? onThemeChanged;
  final ThemeMode? currentThemeMode;

  const MainScreen({super.key, this.onThemeChanged, this.currentThemeMode});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _chiSoDuocChon = 0;
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.currentThemeMode ?? ThemeMode.system;
    _loadThemeMode();
  }

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cập nhật khi theme thay đổi từ bên ngoài
    if (widget.currentThemeMode != null && widget.currentThemeMode != _themeMode) {
      setState(() {
        _themeMode = widget.currentThemeMode!;
      });
    }
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeString = prefs.getString('themeMode') ?? 'system';
    final loadedTheme = ThemeMode.values.firstWhere(
          (e) => e.toString() == 'ThemeMode.$themeModeString',
      orElse: () => ThemeMode.system,
    );

    if (mounted) {
      setState(() {
        _themeMode = loadedTheme;
      });
    }
  }

  // ✅ Hàm này sẽ được gọi từ ProfileScreen
  Future<void> _updateThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode.toString().split('.').last);

    setState(() {
      _themeMode = mode;
    });

    // ✅ QUAN TRỌNG: Gọi callback để cập nhật theme trong MyApp
    if (widget.onThemeChanged != null) {
      widget.onThemeChanged!(mode);
    }
  }

  void _khiChon(int chiSo) {
    setState(() {
      _chiSoDuocChon = chiSo;
    });
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Tạo list widget trong build method và truyền callback + key để force rebuild
    final List<Widget> _cacWidget = [
      ScheduleScreen(key: ValueKey(_themeMode)), // ✅ Thêm key để rebuild khi theme thay đổi
      NotificationHistoryScreen(key: ValueKey(_themeMode)), // ✅ Thêm key để rebuild khi theme thay đổi
      ProfileScreen(
        key: ValueKey(_themeMode), // ✅ Thêm key
        onThemeChanged: _updateThemeMode,
        currentThemeMode: _themeMode,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _chiSoDuocChon,
        children: _cacWidget,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _chiSoDuocChon,
        selectedItemColor: const Color(0xFF6366F1),
        unselectedItemColor: Colors.grey,
        onTap: _khiChon,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        items: [
          BottomNavigationBarItem(
            icon: Icon(
              _chiSoDuocChon == 0
                  ? Icons.home
                  : Icons.home_outlined,
            ),
            label: 'home.title'.tr(),
          ),
          BottomNavigationBarItem(
            icon: Icon(
              _chiSoDuocChon == 1
                  ? Icons.notifications_active
                  : Icons.notifications_outlined,
            ),
            label: 'notification.title'.tr(),
          ),
          BottomNavigationBarItem(
            icon: Icon(
              _chiSoDuocChon == 2
                  ? Icons.person
                  : Icons.person_outline,
            ),
            label: 'profile.title'.tr(),
          ),
        ],
      ),
    );
  }
}