// import 'dart:async';
// import 'dart:convert';
// import 'package:easy_localization/easy_localization.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import '../features/auth/services/auth_service.dart';
// import '../services/smart_notification_service.dart';
// import '../widgets/save_button_styles.dart';
//
// class NotificationSettingsScreen extends StatefulWidget {
//   const NotificationSettingsScreen({Key? key}) : super(key: key);
//
//   @override
//   State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
// }
//
// class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
//   final _service = SmartNotificationService.instance;
//   AppNotificationSettings? _settings;
//   bool _loading = true;
//   bool _isLoading = false;
//   bool _hasUnsavedChanges = false;
//   String? _fcmToken;
//   bool _hasFcmToken = false;
//
//   @override
//   void initState() {
//     super.initState();
//     _initializeScreen();
//   }
//
//   Future<void> _initializeScreen() async {
//     await _checkFcmToken();
//     if (_hasFcmToken) {
//       await _loadSettings();
//     } else {
//       setState(() {
//         _loading = false;
//       });
//     }
//   }
//
//   Future<void> _checkFcmToken() async {
//     try {
//       _fcmToken = await FirebaseMessaging.instance.getToken();
//       print('🔍 FCM Token: $_fcmToken');
//
//       setState(() {
//         _hasFcmToken = _fcmToken != null && _fcmToken!.isNotEmpty;
//       });
//
//       if (!_hasFcmToken) {
//         print('⚠️ FCM Token không tồn tại');
//       } else {
//         print('✅ FCM Token hợp lệ');
//       }
//     } catch (e) {
//       print('❌ Error getting FCM token: $e');
//       setState(() {
//         _hasFcmToken = false;
//       });
//     }
//   }
//
//   Future<void> _loadSettings() async {
//     try {
//       final mssv = await AuthService.getSavedMssv() ?? '0';
//       final settings = await _service.getSettings(mssv: mssv);
//       if (mounted) {
//         setState(() {
//           _settings = settings;
//           _loading = false;
//           _hasUnsavedChanges = false;
//         });
//
//         if (settings.isDefaultSettings) {
//           print('⚠️ Using default settings (notifications disabled)');
//         } else {
//           print('✅ Loaded user settings from server');
//         }
//       }
//     } catch (e) {
//       print('❌ Error loading settings: $e');
//       if (mounted) {
//         setState(() {
//           _settings = _service.defaultSettings;
//           _loading = false;
//           _hasUnsavedChanges = false;
//         });
//       }
//     }
//   }
//
//   void _onSettingsChanged(AppNotificationSettings newSettings) {
//     if (!_hasFcmToken) return;
//
//     setState(() {
//       _settings = newSettings;
//       _hasUnsavedChanges = true;
//     });
//   }
//
//   void _showNotificationDialog(String title, String message, {bool isSuccess = true}) {
//     if (!mounted) return;
//
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
//
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: Text(title),
//         content: Text(message),
//         backgroundColor: isSuccess
//             ? (isDarkMode ? Colors.grey[900] : Colors.grey[50])
//             : (isDarkMode ? Colors.red[900] : Colors.red[50]),
//         titleTextStyle: TextStyle(
//           color: isDarkMode ? Colors.white : Colors.black,
//           fontSize: 18,
//           fontWeight: FontWeight.bold,
//         ),
//         contentTextStyle: TextStyle(
//           color: isDarkMode ? Colors.white70 : Colors.black87,
//           fontSize: 16,
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.of(context).pop(),
//             child: Text(
//               'common.close'.tr(),
//               style: TextStyle(
//                   color: isDarkMode ? Colors.blue[300] : Colors.blue
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Future<void> _saveSettings() async {
//     if (!_hasFcmToken) {
//       _showNotificationDialog(
//         'notification_settings.error_title'.tr(),
//         'FCM Token không tồn tại. Vui lòng khởi động lại ứng dụng.',
//         isSuccess: false,
//       );
//       return;
//     }
//
//     if (_settings == null) {
//       print('Error: _settings is null');
//       _showNotificationDialog(
//         'notification_settings.error_title'.tr(),
//         'notification_settings.error_settings_null'.tr(),
//         isSuccess: false,
//       );
//       return;
//     }
//
//     setState(() {
//       _isLoading = true;
//     });
//
//     try {
//       print('💾 Saving settings...');
//
//       final mssv = await AuthService.getSavedMssv();
//       if (mssv == null || mssv.isEmpty) {
//         throw Exception('Không tìm thấy thông tin sinh viên');
//       }
//
//       final settingsData = {
//         'mssv': mssv,
//         'fcmToken': _fcmToken,
//         'enabled': _settings!.enabled,
//         'scheduleEnabled': _settings!.scheduleEnabled,
//         'scheduleHour': _settings!.scheduleHour,
//         'scheduleMinute': _settings!.scheduleMinute,
//         'examEnabled': _settings!.examEnabled,
//         'examHour': _settings!.examHour,
//         'examMinute': _settings!.examMinute,
//         'reminderMinutes': _settings!.reminderMinutes,
//         'examReminderDays': _settings!.examReminderDays,
//       };
//       print('📤 Sending settings to server: $settingsData');
//
//       final response = await http
//           .put(
//         Uri.parse('http://192.168.1.120:8080/notification-service/api/users/$mssv/settings'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode(settingsData),
//       )
//           .timeout(
//         const Duration(seconds: 15),
//         onTimeout: () {
//           throw TimeoutException('notification_settings.timeout_error'.tr());
//         },
//       );
//
//       print('📥 API response status: ${response.statusCode}');
//       if (response.statusCode == 200) {
//         setState(() {
//           _settings = _settings!.copyWith(isDefaultSettings: false);
//           _hasUnsavedChanges = false;
//         });
//
//         _showNotificationDialog(
//           'notification_settings.success_title'.tr(),
//           'notification_settings.save_success'.tr(),
//         );
//         print('✅ Settings saved successfully');
//       } else {
//         throw Exception('Failed to save settings: ${response.statusCode} - ${response.body}');
//       }
//     } catch (error) {
//       print('❌ Error saving settings: $error');
//       _showNotificationDialog(
//         'notification_settings.error_title'.tr(),
//         error is TimeoutException
//             ? 'notification_settings.timeout_error'.tr()
//             : 'notification_settings.error_save'.tr(namedArgs: {'error': error.toString()}),
//         isSuccess: false,
//       );
//     } finally {
//       if (mounted) {
//         setState(() {
//           _isLoading = false;
//         });
//       }
//     }
//   }
//
//   Future<void> _selectScheduleTime() async {
//     if (!_hasFcmToken || _settings == null) return;
//
//     final TimeOfDay? picked = await showTimePicker(
//       context: context,
//       initialTime: TimeOfDay(
//         hour: _settings!.scheduleHour,
//         minute: _settings!.scheduleMinute,
//       ),
//       helpText: 'notification_settings.pick_schedule_time'.tr(),
//       builder: (context, child) {
//         return Theme(
//           data: Theme.of(context).copyWith(
//             timePickerTheme: TimePickerThemeData(
//               backgroundColor: Theme.of(context).cardColor,
//             ),
//           ),
//           child: child!,
//         );
//       },
//     );
//
//     if (picked != null && mounted) {
//       _onSettingsChanged(_settings!.copyWith(
//         scheduleHour: picked.hour,
//         scheduleMinute: picked.minute,
//       ));
//     }
//   }
//
//   Future<void> _selectExamTime() async {
//     if (!_hasFcmToken || _settings == null) return;
//
//     final TimeOfDay? picked = await showTimePicker(
//       context: context,
//       initialTime: TimeOfDay(
//         hour: _settings!.examHour,
//         minute: _settings!.examMinute,
//       ),
//       helpText: 'notification_settings.pick_exam_time'.tr(),
//       builder: (context, child) {
//         return Theme(
//           data: Theme.of(context).copyWith(
//             timePickerTheme: TimePickerThemeData(
//               backgroundColor: Theme.of(context).cardColor,
//             ),
//           ),
//           child: child!,
//         );
//       },
//     );
//
//     if (picked != null && mounted) {
//       _onSettingsChanged(_settings!.copyWith(
//         examHour: picked.hour,
//         examMinute: picked.minute,
//       ));
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     if (_loading) {
//       return Scaffold(
//         appBar: AppBar(title: Text('notification_settings.title'.tr())),
//         body: const Center(child: CircularProgressIndicator()),
//       );
//     }
//
//     // Nếu không có FCM Token, hiển thị thông báo lỗi
//     if (!_hasFcmToken) {
//       return Scaffold(
//         appBar: AppBar(
//           title: Text('notification_settings.title'.tr()),
//           elevation: 0,
//         ),
//         body: Center(
//           child: Padding(
//             padding: const EdgeInsets.all(24),
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Icon(
//                   Icons.error_outline,
//                   size: 80,
//                   color: Colors.red[300],
//                 ),
//                 const SizedBox(height: 24),
//                 Text(
//                   'FCM Token không tồn tại',
//                   style: TextStyle(
//                     fontSize: 20,
//                     fontWeight: FontWeight.bold,
//                     color: Theme.of(context).textTheme.titleLarge?.color,
//                   ),
//                   textAlign: TextAlign.center,
//                 ),
//                 const SizedBox(height: 16),
//                 Text(
//                   'Không thể sử dụng tính năng thông báo. Vui lòng:\n\n'
//                       '• Kiểm tra kết nối internet\n'
//                       '• Cấp quyền thông báo cho ứng dụng\n'
//                       '• Khởi động lại ứng dụng',
//                   style: TextStyle(
//                     fontSize: 16,
//                     color: Theme.of(context).textTheme.bodyMedium?.color,
//                   ),
//                   textAlign: TextAlign.center,
//                 ),
//                 const SizedBox(height: 32),
//                 ElevatedButton.icon(
//                   onPressed: () async {
//                     setState(() {
//                       _loading = true;
//                     });
//                     await _initializeScreen();
//                   },
//                   icon: const Icon(Icons.refresh),
//                   label: const Text('Thử lại'),
//                   style: ElevatedButton.styleFrom(
//                     padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       );
//     }
//
//     // Nếu settings chưa load xong
//     if (_settings == null) {
//       return Scaffold(
//         appBar: AppBar(title: Text('notification_settings.title'.tr())),
//         body: const Center(child: CircularProgressIndicator()),
//       );
//     }
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('notification_settings.title'.tr()),
//         elevation: 0,
//       ),
//       body: ListView(
//         padding: const EdgeInsets.all(16),
//         children: [
//           _buildMainSwitch(),
//           const SizedBox(height: 24),
//           _buildSectionTitle('notification_settings.schedule_section'.tr()),
//           _buildTypeCard(
//             title: 'notification_settings.enable_schedule'.tr(),
//             subtitle: 'notification_settings.enable_schedule_sub'.tr(),
//             icon: Icons.school,
//             color: Colors.blue,
//             value: _settings!.scheduleEnabled,
//             onChanged: _settings!.enabled
//                 ? (value) {
//               _onSettingsChanged(_settings!.copyWith(scheduleEnabled: value));
//             }
//                 : null,
//           ),
//           const SizedBox(height: 12),
//           _buildScheduleTimeCard(),
//           const SizedBox(height: 12),
//           _buildReminderCard(),
//           const SizedBox(height: 32),
//           _buildSectionTitle('notification_settings.exam_section'.tr()),
//           _buildTypeCard(
//             title: 'notification_settings.enable_exam'.tr(),
//             subtitle: 'notification_settings.enable_exam_sub'.tr(),
//             icon: Icons.assignment,
//             color: Colors.orange,
//             value: _settings!.examEnabled,
//             onChanged: _settings!.enabled
//                 ? (value) {
//               _onSettingsChanged(_settings!.copyWith(examEnabled: value));
//             }
//                 : null,
//           ),
//           const SizedBox(height: 12),
//           _buildExamTimeCard(),
//           const SizedBox(height: 12),
//           _buildExamAdvanceReminderCard(),
//           const SizedBox(height: 32),
//           GradientSaveButton(
//             onPressed: _hasUnsavedChanges ? () => _saveSettings() : () {},
//             title: 'notification_settings.save_button'.tr(),
//             subtitle: _hasUnsavedChanges ? 'Lưu tất cả thay đổi' : 'Không có thay đổi',
//             isLoading: _isLoading,
//               isDisabled: _settings!.enabled
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildMainSwitch() {
//     final bool isDefaultSettings = _settings!.isDefaultSettings;
//
//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         gradient: LinearGradient(
//           colors: [
//             Theme.of(context).primaryColor,
//             Theme.of(context).primaryColor.withOpacity(0.7),
//           ],
//         ),
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [
//           BoxShadow(
//             color: Theme.of(context).primaryColor.withOpacity(0.3),
//             blurRadius: 8,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Row(
//         children: [
//           Container(
//             padding: const EdgeInsets.all(12),
//             decoration: BoxDecoration(
//               color: Colors.white.withOpacity(0.2),
//               borderRadius: BorderRadius.circular(12),
//             ),
//             child: Icon(
//               isDefaultSettings ? Icons.notifications_off : Icons.notifications_active,
//               color: Colors.white,
//               size: 32,
//             ),
//           ),
//           const SizedBox(width: 16),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'notification_settings.enable_notifications'.tr(),
//                   style: const TextStyle(
//                     color: Colors.white,
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   'notification_settings.main_subtitle'.tr(),
//                   // isDefaultSettings
//                   //     ? 'notification_settings.main_subtitle_default'.tr()
//                   //     : 'notification_settings.main_subtitle'.tr(),
//                   style: const TextStyle(
//                     color: Colors.white70,
//                     fontSize: 14,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           Switch(
//             value: _settings!.enabled,
//             onChanged: _hasFcmToken
//                 ? (value) {
//               _onSettingsChanged(_settings!.copyWith(enabled: value));
//             }
//                 : null,
//             activeColor: Colors.white,
//             activeTrackColor: Colors.white.withOpacity(0.5),
//             inactiveTrackColor: Colors.grey.withOpacity(0.5),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildSectionTitle(String title) {
//     return Padding(
//       padding: const EdgeInsets.only(bottom: 12),
//       child: Text(
//         title,
//         style: TextStyle(
//           fontSize: 16,
//           fontWeight: FontWeight.bold,
//           color: Theme.of(context).textTheme.titleLarge?.color,
//         ),
//       ),
//     );
//   }
//
//   Widget _buildTypeCard({
//     required String title,
//     required String subtitle,
//     required IconData icon,
//     required Color color,
//     required bool value,
//     required ValueChanged<bool>? onChanged,
//   }) {
//     return Card(
//       elevation: 2,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: ListTile(
//         contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//         leading: Container(
//           padding: const EdgeInsets.all(10),
//           decoration: BoxDecoration(
//             color: color.withOpacity(0.1),
//             borderRadius: BorderRadius.circular(10),
//           ),
//           child: Icon(icon, color: color, size: 28),
//         ),
//         title: Text(
//           title,
//           style: const TextStyle(
//             fontWeight: FontWeight.w600,
//             fontSize: 16,
//           ),
//         ),
//         subtitle: Text(
//           subtitle,
//           style: TextStyle(
//             color: Theme.of(context).textTheme.bodySmall?.color,
//             fontSize: 13,
//           ),
//         ),
//         trailing: Switch(
//           value: value && _settings!.enabled,
//           onChanged: _hasFcmToken ? onChanged : null,
//           activeColor: color,
//           inactiveTrackColor: Colors.grey.withOpacity(0.5),
//         ),
//       ),
//     );
//   }
//
//   Widget _buildScheduleTimeCard() {
//     final bool isEnabled = _hasFcmToken && _settings!.enabled && _settings!.scheduleEnabled;
//
//     return Card(
//       elevation: 2,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: ListTile(
//         contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//         leading: Container(
//           padding: const EdgeInsets.all(10),
//           decoration: BoxDecoration(
//             color: Colors.blue.withOpacity(0.1),
//             borderRadius: BorderRadius.circular(10),
//           ),
//           child: const Icon(Icons.schedule, color: Colors.blue, size: 28),
//         ),
//         title: Text(
//           'notification_settings.schedule_time'.tr(),
//           style: const TextStyle(fontWeight: FontWeight.w600),
//         ),
//         subtitle: Text(
//           'notification_settings.schedule_time_sub'.tr(),
//           style: TextStyle(
//             fontSize: 13,
//             color: Theme.of(context).textTheme.bodySmall?.color,
//           ),
//         ),
//         trailing: Container(
//           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//           decoration: BoxDecoration(
//             color: isEnabled ? Colors.blue : Colors.grey,
//             borderRadius: BorderRadius.circular(8),
//           ),
//           child: Text(
//             _settings!.scheduleTimeString,
//             style: const TextStyle(
//               color: Colors.white,
//               fontSize: 18,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//         ),
//         onTap: isEnabled ? _selectScheduleTime : null,
//       ),
//     );
//   }
//
//   Widget _buildExamTimeCard() {
//     final bool isEnabled = _hasFcmToken && _settings!.enabled && _settings!.examEnabled;
//
//     return Card(
//       elevation: 2,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: ListTile(
//         contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//         leading: Container(
//           padding: const EdgeInsets.all(10),
//           decoration: BoxDecoration(
//             color: Colors.orange.withOpacity(0.1),
//             borderRadius: BorderRadius.circular(10),
//           ),
//           child: const Icon(Icons.event, color: Colors.orange, size: 28),
//         ),
//         title: Text(
//           'notification_settings.exam_time'.tr(),
//           style: const TextStyle(fontWeight: FontWeight.w600),
//         ),
//         subtitle: Text(
//           'notification_settings.exam_time_sub'.tr(),
//           style: TextStyle(
//             fontSize: 13,
//             color: Theme.of(context).textTheme.bodySmall?.color,
//           ),
//         ),
//         trailing: Container(
//           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//           decoration: BoxDecoration(
//             color: isEnabled ? Colors.orange : Colors.grey,
//             borderRadius: BorderRadius.circular(8),
//           ),
//           child: Text(
//             _settings!.examTimeString,
//             style: const TextStyle(
//               color: Colors.white,
//               fontSize: 18,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//         ),
//         onTap: isEnabled ? _selectExamTime : null,
//       ),
//     );
//   }
//
//   Widget _buildReminderCard() {
//     return Card(
//       elevation: 2,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               children: [
//                 Container(
//                   padding: const EdgeInsets.all(10),
//                   decoration: BoxDecoration(
//                     color: Colors.green.withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(10),
//                   ),
//                   child: const Icon(Icons.alarm, color: Colors.green, size: 28),
//                 ),
//                 const SizedBox(width: 12),
//                 Expanded(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         'notification_settings.reminder_title'.tr(),
//                         style: const TextStyle(
//                           fontWeight: FontWeight.w600,
//                           fontSize: 16,
//                         ),
//                       ),
//                       Text(
//                         _settings!.reminderMinutes > 0
//                             ? 'notification_settings.reminder_on'.tr(namedArgs: {'minutes': _settings!.reminderMinutes.toString()})
//                             : 'notification_settings.reminder_off'.tr(),
//                         style: TextStyle(
//                           fontSize: 13,
//                           color: Theme.of(context).textTheme.bodySmall?.color,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),
//             Slider(
//               value: _settings!.reminderMinutes.toDouble(),
//               min: 0,
//               max: 120,
//               divisions: 8,
//               label: _settings!.reminderMinutes == 0
//                   ? 'notification_settings.reminder_slider_off'.tr()
//                   : 'notification_settings.reminder_on'.tr(namedArgs: {'minutes': _settings!.reminderMinutes.toString()}),
//               onChanged: (_hasFcmToken && _settings!.enabled)
//                   ? (value) {
//                 _onSettingsChanged(_settings!.copyWith(
//                   reminderMinutes: value.toInt(),
//                 ));
//               }
//                   : null,
//             ),
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Text(
//                   'notification_settings.reminder_slider_off'.tr(),
//                   style: TextStyle(
//                     fontSize: 12,
//                     color: Theme.of(context).textTheme.bodySmall?.color,
//                   ),
//                 ),
//                 Text(
//                   'notification_settings.reminder_slider_max'.tr(),
//                   style: TextStyle(
//                     fontSize: 12,
//                     color: Theme.of(context).textTheme.bodySmall?.color,
//                   ),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildExamAdvanceReminderCard() {
//     return Card(
//       elevation: 2,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               children: [
//                 Container(
//                   padding: const EdgeInsets.all(10),
//                   decoration: BoxDecoration(
//                     color: Colors.red.withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(10),
//                   ),
//                   child: const Icon(Icons.calendar_today, color: Colors.red, size: 28),
//                 ),
//                 const SizedBox(width: 12),
//                 Expanded(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         'notification_settings.exam_reminder_title'.tr(),
//                         style: const TextStyle(
//                           fontWeight: FontWeight.w600,
//                           fontSize: 16,
//                         ),
//                       ),
//                       Text(
//                         _settings!.examReminderDays > 0
//                             ? 'notification_settings.exam_reminder_on'.tr(namedArgs: {'days': _settings!.examReminderDays.toString()})
//                             : 'notification_settings.exam_reminder_off'.tr(),
//                         style: TextStyle(
//                           fontSize: 13,
//                           color: Theme.of(context).textTheme.bodySmall?.color,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),
//             Slider(
//               value: _settings!.examReminderDays.toDouble(),
//               min: 0,
//               max: 7,
//               divisions: 7,
//               label: _settings!.examReminderDays == 0
//                   ? 'notification_settings.exam_slider_off'.tr()
//                   : 'notification_settings.exam_reminder_on'.tr(namedArgs: {'days': _settings!.examReminderDays.toString()}),
//               onChanged: (_hasFcmToken && _settings!.enabled && _settings!.examEnabled)
//                   ? (value) {
//                 _onSettingsChanged(_settings!.copyWith(
//                   examReminderDays: value.toInt(),
//                 ));
//               }
//                   : null,
//             ),
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Text(
//                   'notification_settings.exam_slider_off'.tr(),
//                   style: TextStyle(
//                     fontSize: 12,
//                     color: Theme.of(context).textTheme.bodySmall?.color,
//                   ),
//                 ),
//                 Text(
//                   'notification_settings.exam_slider_max'.tr(),
//                   style: TextStyle(
//                     fontSize: 12,
//                     color: Theme.of(context).textTheme.bodySmall?.color,
//                   ),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }