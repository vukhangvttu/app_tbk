// // lib/services/notification_scheduler.dart
// import 'dart:async';
// import 'dart:convert';
// import 'dart:ui';
// import 'package:flutter/material.dart';
// import 'package:flutter_background_service/flutter_background_service.dart';
// import 'package:flutter_background_service_android/flutter_background_service_android.dart';
// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'smart_notification_service.dart';
//
// /// Service quản lý việc schedule thông báo tự động
// /// Chạy background service kiểm tra lịch học/thi mỗi ngày
// class NotificationScheduler {
//   static const String _apiBaseUrl = 'http://192.168.0.9:8202';
//   static final FlutterBackgroundService _backgroundService = FlutterBackgroundService();
//
//   /// Khởi tạo background service
//   static Future<void> initialize() async {
//     try {
//       await _initializeService();
//       print('📅 NotificationScheduler initialized with flutter_background_service');
//     } catch (e) {
//       print('❌ Error initializing scheduler: $e');
//     }
//   }
//
//   /// Cấu hình background service
//   static Future<void> _initializeService() async {
//     final service = FlutterBackgroundService();
//
//     // Tạo notification channel cho service
//     const AndroidNotificationChannel channel = AndroidNotificationChannel(
//       'notification_scheduler_channel',
//       'Notification Scheduler',
//       description: 'Background service đồng bộ lịch học/thi',
//       importance: Importance.low,
//     );
//
//     final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
//     FlutterLocalNotificationsPlugin();
//
//     await flutterLocalNotificationsPlugin
//         .resolvePlatformSpecificImplementation<
//         AndroidFlutterLocalNotificationsPlugin>()
//         ?.createNotificationChannel(channel);
//
//     await service.configure(
//       iosConfiguration: IosConfiguration(
//         autoStart: true,
//         onForeground: onStart,
//         onBackground: onIosBackground,
//       ),
//       androidConfiguration: AndroidConfiguration(
//         onStart: onStart,
//         autoStart: true,
//         isForegroundMode: false, // Chạy background
//         autoStartOnBoot: true,
//         notificationChannelId: 'notification_scheduler_channel',
//         initialNotificationTitle: 'Lịch học thông minh',
//         initialNotificationContent: 'Đang đồng bộ lịch học...',
//         foregroundServiceNotificationId: 888,
//       ),
//     );
//
//     // Start service
//     await service.startService();
//   }
//
//   /// iOS background handler
//   @pragma('vm:entry-point')
//   static Future<bool> onIosBackground(ServiceInstance service) async {
//     WidgetsFlutterBinding.ensureInitialized();
//     DartPluginRegistrant.ensureInitialized();
//     return true;
//   }
//
//   /// Main background task
//   @pragma('vm:entry-point')
//   static void onStart(ServiceInstance service) async {
//     DartPluginRegistrant.ensureInitialized();
//
//     if (service is AndroidServiceInstance) {
//       service.on('setAsForeground').listen((event) {
//         service.setAsForegroundService();
//       });
//
//       service.on('setAsBackground').listen((event) {
//         service.setAsBackgroundService();
//       });
//     }
//
//     service.on('stopService').listen((event) {
//       service.stopSelf();
//     });
//
//     // Timer chạy mỗi 24 giờ (00:05 sáng)
//     Timer.periodic(const Duration(hours: 24), (timer) async {
//       print('⏰ Background task triggered at ${DateTime.now()}');
//
//       // Kiểm tra xem có phải 00:05 không
//       final now = DateTime.now();
//       if (now.hour == 0 && now.minute >= 0 && now.minute <= 10) {
//         await _syncNotifications();
//       }
//     });
//
//     // Sync ngay khi khởi động (để test)
//     await _syncNotifications();
//
//     // Listener để sync thủ công từ UI
//     service.on('syncNow').listen((event) async {
//       print('🔄 Manual sync triggered');
//       await _syncNotifications();
//       service.invoke('syncCompleted');
//     });
//   }
//
//   /// CORE LOGIC: Đồng bộ thông báo
//   static Future<void> _syncNotifications() async {
//     try {
//       print('🔍 Starting notification sync...');
//
//       // Lấy settings
//       final prefs = await SharedPreferences.getInstance();
//       final notifEnabled = prefs.getBool('notifications_enabled') ?? true;
//
//       if (!notifEnabled) {
//         print('⏸️ Notifications disabled');
//         return;
//       }
//
//       // Lấy idSinhVien
//       final idSinhVien = prefs.getInt('idSinhVien');
//       if (idSinhVien == null) {
//         print('❌ No student ID found');
//         return;
//       }
//
//       print('📚 Fetching schedules for student: $idSinhVien');
//
//       // Lấy lịch hôm nay
//       final todaySchedules = await _fetchTodaySchedule(idSinhVien);
//
//       if (todaySchedules.isEmpty) {
//         print('📭 No schedules for today');
//         return;
//       }
//
//       print('✅ Found ${todaySchedules.length} items');
//
//       // Schedule notifications
//       final settings = await _getSettings();
//
//       for (final schedule in todaySchedules) {
//         final isExam = schedule['NHOMTHI'] == true;
//
//         if (isExam && settings['examEnabled']) {
//           await _scheduleExamNotification(schedule, settings, idSinhVien);
//         } else if (!isExam && settings['scheduleEnabled']) {
//           await _scheduleClassNotification(schedule, settings, idSinhVien);
//         }
//       }
//
//       // Schedule thông báo nhắc thi trước
//       if (settings['examEnabled'] && settings['examReminderDays'] > 0) {
//         await _scheduleUpcomingExamReminders(settings, idSinhVien);
//       }
//
//       print('✅ Sync completed successfully');
//     } catch (e) {
//       print('❌ Error syncing: $e');
//     }
//   }
//
//   /// Lấy settings từ SharedPreferences
//   static Future<Map<String, dynamic>> _getSettings() async {
//     final prefs = await SharedPreferences.getInstance();
//     return {
//       'enabled': prefs.getBool('notifications_enabled') ?? true,
//       'scheduleEnabled': prefs.getBool('schedule_notif_enabled') ?? true,
//       'examEnabled': prefs.getBool('exam_notif_enabled') ?? true,
//       'scheduleHour': prefs.getInt('schedule_hour') ?? 7,
//       'scheduleMinute': prefs.getInt('schedule_minute') ?? 0,
//       'examHour': prefs.getInt('exam_hour') ?? 6,
//       'examMinute': prefs.getInt('exam_minute') ?? 0,
//       'reminderMinutes': prefs.getInt('reminder_minutes') ?? 30,
//       'examReminderDays': prefs.getInt('exam_reminder_days') ?? 3,
//     };
//   }
//
//   /// Gọi API lấy lịch theo ngày
//   static Future<List<Map<String, dynamic>>> _fetchTodaySchedule(int idSinhVien) async {
//     try {
//       final now = DateTime.now();
//       final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
//
//       final response = await http.get(
//         Uri.parse('$_apiBaseUrl/api/thoi-khoa-bieu/lich-hoc-lich-thi/theo-ngay?idSinhVien=$idSinhVien&date=$dateStr'),
//         headers: {'Content-Type': 'application/json'},
//       ).timeout(const Duration(seconds: 10));
//
//       if (response.statusCode == 200) {
//         final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
//         return data.cast<Map<String, dynamic>>();
//       }
//       return [];
//     } catch (e) {
//       print('❌ API error: $e');
//       return [];
//     }
//   }
//
//   /// Gọi API lấy lịch của ngày cụ thể
//   static Future<List<Map<String, dynamic>>> _fetchScheduleByDate(
//       int idSinhVien,
//       DateTime date,
//       ) async {
//     try {
//       final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
//
//       final response = await http.get(
//         Uri.parse('$_apiBaseUrl/api/thoi-khoa-bieu/lich-hoc-lich-thi/theo-ngay?idSinhVien=$idSinhVien&date=$dateStr'),
//         headers: {'Content-Type': 'application/json'},
//       ).timeout(const Duration(seconds: 10));
//
//       if (response.statusCode == 200) {
//         final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
//         return data.cast<Map<String, dynamic>>();
//       }
//       return [];
//     } catch (e) {
//       print('❌ API error: $e');
//       return [];
//     }
//   }
//
//   /// Schedule thông báo cho lịch học
//   static Future<void> _scheduleClassNotification(
//       Map<String, dynamic> schedule,
//       Map<String, dynamic> settings,
//       int idSinhVien,
//       ) async {
//     try {
//       final tenMon = schedule['TENMON'] ?? 'Lớp học';
//       final gioHoc = schedule['GIOBD'] ?? '07:00';
//       final phongHoc = schedule['TENPHONG'] ?? '';
//
//       final parts = gioHoc.split(':');
//       final now = DateTime.now();
//       final classTime = DateTime(
//         now.year,
//         now.month,
//         now.day,
//         int.parse(parts[0]),
//         int.parse(parts[1]),
//       );
//
//       if (classTime.isAfter(DateTime.now())) {
//         final uniqueId = _generateNotificationId(idSinhVien, schedule['MANHOM'] ?? 0, false);
//
//         await SmartNotificationService.instance.scheduleForClass(
//           id: uniqueId,
//           tenMon: tenMon,
//           ngayHoc: classTime,
//           gioHoc: gioHoc,
//           phongHoc: phongHoc,
//           isExam: false,
//         );
//
//         print('   ⏰ Scheduled class: $tenMon at $gioHoc');
//       }
//     } catch (e) {
//       print('❌ Error scheduling class: $e');
//     }
//   }
//
//   /// Schedule thông báo cho lịch thi
//   static Future<void> _scheduleExamNotification(
//       Map<String, dynamic> exam,
//       Map<String, dynamic> settings,
//       int idSinhVien,
//       ) async {
//     try {
//       final tenMon = exam['TENMON'] ?? 'Kỳ thi';
//       final gioThi = exam['GIOBD'] ?? '07:00';
//       final phongThi = exam['TENPHONG'] ?? '';
//
//       final parts = gioThi.split(':');
//       final now = DateTime.now();
//       final examTime = DateTime(
//         now.year,
//         now.month,
//         now.day,
//         int.parse(parts[0]),
//         int.parse(parts[1]),
//       );
//
//       if (examTime.isAfter(DateTime.now())) {
//         final uniqueId = _generateNotificationId(idSinhVien, exam['MANHOM'] ?? 0, true);
//
//         await SmartNotificationService.instance.scheduleForClass(
//           id: uniqueId,
//           tenMon: tenMon,
//           ngayHoc: examTime,
//           gioHoc: gioThi,
//           phongHoc: phongThi,
//           isExam: true,
//         );
//
//         print('   📝 Scheduled exam: $tenMon at $gioThi');
//       }
//     } catch (e) {
//       print('❌ Error scheduling exam: $e');
//     }
//   }
//
//   /// Schedule thông báo nhắc thi trước
//   static Future<void> _scheduleUpcomingExamReminders(
//       Map<String, dynamic> settings,
//       int idSinhVien,
//       ) async {
//     try {
//       final today = DateTime.now();
//       final daysAhead = settings['examReminderDays'] as int;
//       final futureDate = today.add(Duration(days: daysAhead));
//
//       final upcomingSchedules = await _fetchScheduleByDate(idSinhVien, futureDate);
//       final upcomingExams = upcomingSchedules.where((s) => s['NHOMTHI'] == true).toList();
//
//       for (final exam in upcomingExams) {
//         final tenMon = exam['TENMON'] ?? 'Kỳ thi';
//         final gioThi = exam['GIOBD'] ?? '07:00';
//         final phongThi = exam['TENPHONG'] ?? '';
//
//         final parts = gioThi.split(':');
//         final examTime = DateTime(
//           futureDate.year,
//           futureDate.month,
//           futureDate.day,
//           int.parse(parts[0]),
//           int.parse(parts[1]),
//         );
//
//         final reminderTime = DateTime(
//           today.year,
//           today.month,
//           today.day,
//           settings['examHour'] as int,
//           settings['examMinute'] as int,
//         );
//
//         if (reminderTime.isAfter(DateTime.now())) {
//           final uniqueId = _generateNotificationId(idSinhVien, exam['MANHOM'] ?? 0, true) + 100000;
//
//           await SmartNotificationService.instance.scheduleAdvanceExamReminder(
//             id: uniqueId,
//             tenMon: tenMon,
//             ngayThi: examTime,
//             phongThi: phongThi,
//             daysAhead: daysAhead,
//             notifyAt: reminderTime,
//           );
//
//           print('   🔔 Scheduled advance reminder: $tenMon');
//         }
//       }
//     } catch (e) {
//       print('❌ Error scheduling advance reminders: $e');
//     }
//   }
//
//   /// Tạo unique ID
//   static int _generateNotificationId(int idSinhVien, int maNhom, bool isExam) {
//     final now = DateTime.now();
//     final timeHash = now.hour * 100 + now.minute;
//     return (idSinhVien % 1000) * 1000000 +
//         (maNhom % 10000) * 100 +
//         timeHash +
//         (isExam ? 50000 : 0);
//   }
//
//   // ==================== PUBLIC METHODS ====================
//
//   /// Sync thủ công (gọi từ UI)
//   static Future<void> syncNow() async {
//     final service = FlutterBackgroundService();
//     if (await service.isRunning()) {
//       service.invoke('syncNow');
//       print('🔄 Sync request sent to background service');
//     } else {
//       print('⚠️ Background service is not running');
//       await _syncNotifications();
//     }
//   }
//
//   /// Dừng background service
//   static Future<void> stop() async {
//     final service = FlutterBackgroundService();
//     service.invoke('stopService');
//     print('⏹️ Background service stopped');
//   }
//
//   /// Khởi động lại service
//   static Future<void> restart() async {
//     await stop();
//     await Future.delayed(const Duration(seconds: 1));
//     await initialize();
//     print('🔄 Background service restarted');
//   }
//
//   /// Kiểm tra service có đang chạy không
//   static Future<bool> isRunning() async {
//     return await FlutterBackgroundService().isRunning();
//   }
// }