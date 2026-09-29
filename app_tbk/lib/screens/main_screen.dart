// import 'package:easy_localization/easy_localization.dart';
// import 'package:app_tbk/features/notification/screens/notification_history_screen.dart';
// import 'package:app_tbk/features/profile/screens/profile_screen.dart';
// import 'package:app_tbk/features/schedule/screens/schedule_screen.dart';
// import 'package:flutter/material.dart';
// import 'package:shared_preferences/shared_preferences.dart';
//
// import '../features/attendance/screens/attendance_history_screen.dart';
//
// class MainScreen extends StatefulWidget {
//   final Function(ThemeMode)? onThemeChanged;
//   final ThemeMode? currentThemeMode;
//
//   const MainScreen({super.key, this.onThemeChanged, this.currentThemeMode});
//
//   @override
//   State<MainScreen> createState() => _MainScreenState();
// }
//
// class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
//   int _chiSoDuocChon = 0;
//   late ThemeMode _themeMode;
//   late AnimationController _animationController;
//   late Animation<Offset> _slideAnimation;
//   int _previousIndex = 0;
//
//   @override
//   void initState() {
//     super.initState();
//     _themeMode = widget.currentThemeMode ?? ThemeMode.system;
//     _loadThemeMode();
//
//     // Initialize animation controller
//     _animationController = AnimationController(
//       duration: const Duration(milliseconds: 400),
//       vsync: this,
//     );
//
//     _slideAnimation = Tween<Offset>(
//       begin: Offset.zero,
//       end: Offset.zero,
//     ).animate(CurvedAnimation(
//       parent: _animationController,
//       curve: Curves.easeInOutCubic,
//     ));
//   }
//
//   @override
//   void dispose() {
//     _animationController.dispose();
//     super.dispose();
//   }
//
//   @override
//   void didUpdateWidget(MainScreen oldWidget) {
//     super.didUpdateWidget(oldWidget);
//     // Cập nhật khi theme thay đổi từ bên ngoài
//     if (widget.currentThemeMode != null && widget.currentThemeMode != _themeMode) {
//       setState(() {
//         _themeMode = widget.currentThemeMode!;
//       });
//     }
//   }
//
//   Future<void> _loadThemeMode() async {
//     final prefs = await SharedPreferences.getInstance();
//     final themeModeString = prefs.getString('themeMode') ?? 'system';
//     final loadedTheme = ThemeMode.values.firstWhere(
//           (e) => e.toString() == 'ThemeMode.$themeModeString',
//       orElse: () => ThemeMode.system,
//     );
//
//     if (mounted) {
//       setState(() {
//         _themeMode = loadedTheme;
//       });
//     }
//   }
//
//   // ✅ Hàm này sẽ được gọi từ ProfileScreen
//   Future<void> _updateThemeMode(ThemeMode mode) async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setString('themeMode', mode.toString().split('.').last);
//
//     setState(() {
//       _themeMode = mode;
//     });
//
//     // ✅ QUAN TRỌNG: Gọi callback để cập nhật theme trong MyApp
//     if (widget.onThemeChanged != null) {
//       widget.onThemeChanged!(mode);
//     }
//   }
//
//   void _khiChon(int chiSo) {
//     if (_chiSoDuocChon != chiSo) {
//       // Determine slide direction
//       final isMovingRight = chiSo > _chiSoDuocChon;
//
//       setState(() {
//         _previousIndex = _chiSoDuocChon;
//         _chiSoDuocChon = chiSo;
//       });
//
//       // Setup animation
//       _slideAnimation = Tween<Offset>(
//         begin: isMovingRight ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0),
//         end: Offset.zero,
//       ).animate(CurvedAnimation(
//         parent: _animationController,
//         curve: Curves.easeInOutCubic,
//       ));
//
//       // Run animation
//       _animationController.forward(from: 0.0);
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     // ✅ Tạo list widget trong build method và truyền callback + key để force rebuild
//     final List<Widget> _cacWidget = [
//       ScheduleScreen(key: ValueKey(_themeMode)), // ✅ Thêm key để rebuild khi theme thay đổi
//       AttendanceHistoryScreen(key: ValueKey(_themeMode)),
//       NotificationHistoryScreen(key: ValueKey(_themeMode)), // ✅ Thêm key để rebuild khi theme thay đổi
//       ProfileScreen(
//         key: ValueKey(_themeMode), // ✅ Thêm key
//         onThemeChanged: _updateThemeMode,
//         currentThemeMode: _themeMode,
//       ),
//     ];
//
//     return Scaffold(
//       body: AnimatedBuilder(
//         animation: _animationController,
//         builder: (context, child) {
//           return SlideTransition(
//             position: _slideAnimation,
//             child: IndexedStack(
//               index: _chiSoDuocChon,
//               children: _cacWidget,
//             ),
//           );
//         },
//       ),
//       bottomNavigationBar: BottomNavigationBar(
//         currentIndex: _chiSoDuocChon,
//         selectedItemColor: const Color(0xFF6366F1),
//         unselectedItemColor: Colors.grey,
//         onTap: _khiChon,
//         type: BottomNavigationBarType.fixed,
//         elevation: 8,
//         items: [
//           BottomNavigationBarItem(
//             icon: AnimatedSwitcher(
//               duration: const Duration(milliseconds: 300),
//               transitionBuilder: (Widget child, Animation<double> animation) {
//                 return ScaleTransition(
//                   scale: animation,
//                   child: child,
//                 );
//               },
//               child: Icon(
//                 _chiSoDuocChon == 0
//                     ? Icons.calendar_today
//                     : Icons.calendar_today_outlined,
//                 key: ValueKey<bool>(_chiSoDuocChon == 0),
//               ),
//             ),
//             label: 'home.title'.tr(),
//           ),
//           // ✅ Tab mới cho lịch sử điểm danh
//           BottomNavigationBarItem(
//             icon: AnimatedSwitcher(
//               duration: const Duration(milliseconds: 300),
//               transitionBuilder: (Widget child, Animation<double> animation) {
//                 return ScaleTransition(
//                   scale: animation,
//                   child: child,
//                 );
//               },
//               child: Icon(
//                 _chiSoDuocChon == 1
//                     ? Icons.fingerprint
//                     : Icons.fingerprint_outlined,
//                 key: ValueKey<bool>(_chiSoDuocChon == 1),
//               ),
//             ),
//             label: 'Điểm danh',
//           ),
//           BottomNavigationBarItem(
//             icon: AnimatedSwitcher(
//               duration: const Duration(milliseconds: 300),
//               transitionBuilder: (Widget child, Animation<double> animation) {
//                 return ScaleTransition(
//                   scale: animation,
//                   child: child,
//                 );
//               },
//               child: Icon(
//                 _chiSoDuocChon == 2
//                     ? Icons.notifications_active
//                     : Icons.notifications_outlined,
//                 key: ValueKey<bool>(_chiSoDuocChon == 2),
//               ),
//             ),
//             label: 'notification.title'.tr(),
//           ),
//           BottomNavigationBarItem(
//             icon: AnimatedSwitcher(
//               duration: const Duration(milliseconds: 300),
//               transitionBuilder: (Widget child, Animation<double> animation) {
//                 return ScaleTransition(
//                   scale: animation,
//                   child: child,
//                 );
//               },
//               child: Icon(
//                 _chiSoDuocChon == 3
//                     ? Icons.person
//                     : Icons.person_outline,
//                 key: ValueKey<bool>(_chiSoDuocChon == 3),
//               ),
//             ),
//             label: 'profile.title'.tr(),
//           ),
//         ],
//       ),
//     );
//   }
// }

import 'package:app_tbk/features/check-in/screens/checkin_screen.dart';
import 'package:app_tbk/features/summary_list/screens/attendance_management_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:app_tbk/features/notification/screens/notification_history_screen.dart';
import 'package:app_tbk/features/profile/screens/profile_screen.dart';
import 'package:app_tbk/features/schedule/screens/schedule_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/attendance/screens/attendance_history_screen.dart';
import 'package:badges/badges.dart' as badges;

import '../features/notification/services/notification_service.dart';

class MainScreen extends StatefulWidget {
  final Function(ThemeMode)? onThemeChanged;
  final ThemeMode? currentThemeMode;

  const MainScreen({super.key, this.onThemeChanged, this.currentThemeMode});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  int _chiSoDuocChon = 0; // BẮT ĐẦU TỪ 0 → home.title

  int _unreadCount = 0;
  bool _isLoading = true;

  late ThemeMode _themeMode;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;


  // GlobalKey để điều khiển NotificationHistoryScreen
  final GlobalKey<NotificationHistoryScreenState> _notificationKey =
  GlobalKey<NotificationHistoryScreenState>();

  final GlobalKey<AttendanceHistoryScreenState> _attendanceKey =
  GlobalKey<AttendanceHistoryScreenState>();

  final GlobalKey<ProfileScreenState> _profileKey = GlobalKey<ProfileScreenState>();

  @override
  void initState() {
    super.initState();
    _themeMode = widget.currentThemeMode ?? ThemeMode.system;
    _loadThemeMode();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    ));

    _loadUnreadCount();
    // KHÔNG LOAD NOTIFICATION Ở ĐÂY → chỉ load khi vào tab
  }


  Future<void> _loadUnreadCount() async {
    try {
      final count = await NotificationHistoryService.getUnreadCount(context);
      if (mounted) {
        setState(() {
          _unreadCount = count;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading unread count: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Gọi lại khi chuyển tab về thông báo hoặc sau khi mark as read/delete
  void _refreshUnreadCount() => _loadUnreadCount();


  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  Future<void> _updateThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode.toString().split('.').last);

    setState(() {
      _themeMode = mode;
    });

    widget.onThemeChanged?.call(mode);
  }

  void _khiChon(int chiSo) {
    if (_chiSoDuocChon == chiSo) return;

    final isMovingRight = chiSo > _chiSoDuocChon;

    setState(() {
      // _previousIndex = _chiSoDuocChon;
      _chiSoDuocChon = chiSo;
    });

    _animationController.forward(from: 0.0).then((_) {
      if (!mounted) return;

      switch (chiSo) {
        case 1:
          print('HIỆU ỨNG XONG → BẮT ĐẦU LOAD TAB 1');
          _attendanceKey.currentState?.loadTab(1);
          break;
        case 2:
          print('HIỆU ỨNG XONG → BẮT ĐẦU LOAD TAB 2');
          _notificationKey.currentState?.loadTab(0);
          _refreshUnreadCount();
          break;
        case 3:
          print('HIỆU ỨNG XONG → BẮT ĐẦU LOAD TAB 3');
          _profileKey.currentState?.loadTab(0);
          break;
      }
    });


    // Cập nhật animation
    _slideAnimation = Tween<Offset>(
      begin: isMovingRight ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _cacWidget = [
      ScheduleScreen(key: ValueKey(_themeMode)),
      // AttendanceHistoryScreen(
      //   key: _attendanceKey,
      //   onTabSelected: (index) {
      //     _attendanceKey.currentState?.loadTab(index);
      //   },
      // ),
      AttendanceManagementScreen(
        key: ValueKey(_themeMode),

      ),
      NotificationHistoryScreen(
        key: _notificationKey,
        onTabSelected: (index) {
          _notificationKey.currentState?.loadTab(index);
        },
        onNotificationChanged: _refreshUnreadCount,
      ),
      ProfileScreen(
        key:
          _profileKey,
          onTabSelected: (index) {
            _profileKey.currentState?.loadTab(index);
          },
        onThemeChanged: _updateThemeMode,
        currentThemeMode: _themeMode,
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await SystemNavigator.pop();
      },
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return SlideTransition(
              position: _slideAnimation,
              child: IndexedStack(
                index: _chiSoDuocChon,
                children: _cacWidget,
              ),
            );
          },
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
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: Icon(
                  _chiSoDuocChon == 0 ? Icons.calendar_today : Icons.calendar_today_outlined,
                  key: ValueKey(_chiSoDuocChon == 0),
                ),
              ),
              label: 'home.title'.tr(),
            ),
            BottomNavigationBarItem(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: Icon(
                  _chiSoDuocChon == 1 ? Icons.list_alt : Icons.list_alt_outlined,
                  key: ValueKey(_chiSoDuocChon == 1),
                ),
              ),
              label: 'Chức năng',
            ),
            BottomNavigationBarItem(
              icon: badges.Badge(
                badgeStyle: badges.BadgeStyle(
                  badgeColor: Colors.red.shade300,
                  elevation: 3,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                ),
                badgeContent: Text(
                  _unreadCount > 99 ? '99+' : _unreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                badgeAnimation: const badges.BadgeAnimation.scale(
                  animationDuration: Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                ),
                showBadge: _unreadCount > 0,
                position: badges.BadgePosition.topEnd(top: -5, end: -10),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    _chiSoDuocChon == 2 ? Icons.notifications_active : Icons.notifications_outlined,
                    key: ValueKey(_chiSoDuocChon == 2),
                  ),
                ),
              ),
              label: 'notification.title'.tr(),
            ),
            BottomNavigationBarItem(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: Icon(
                  _chiSoDuocChon == 3 ? Icons.person : Icons.person_outline,
                  key: ValueKey(_chiSoDuocChon == 3),
                ),
              ),
              label: 'profile.title'.tr(),
            ),
          ],
        ),
      ),
    );
  }
}