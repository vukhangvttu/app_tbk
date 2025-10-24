// // lib/screens/notification_test_screen.dart
// import 'package:flutter/material.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import '../services/smart_notification_service.dart';
// import '../services/notification_scheduler.dart';
//
// class NotificationTestScreen extends StatefulWidget {
//   const NotificationTestScreen({Key? key}) : super(key: key);
//
//   @override
//   State<NotificationTestScreen> createState() => _NotificationTestScreenState();
// }
//
// class _NotificationTestScreenState extends State<NotificationTestScreen> {
//   List<PendingNotificationRequest> _pendingNotifications = [];
//   AppNotificationSettings? _settings;
//   bool _isLoading = false;
//   String _lastAction = '';
//
//   @override
//   void initState() {
//     super.initState();
//     _loadData();
//   }
//
//   Future<void> _loadData() async {
//     setState(() => _isLoading = true);
//     try {
//       final settings = await SmartNotificationService.instance.getSettings();
//       final pending = await SmartNotificationService.instance.getPendingNotifications();
//
//       setState(() {
//         _settings = settings;
//         _pendingNotifications = pending;
//         _isLoading = false;
//       });
//     } catch (e) {
//       setState(() => _isLoading = false);
//       _showError('Lỗi load data: $e');
//     }
//   }
//
//   // ==================== TEST METHODS ====================
//
//   /// Test 1: Gửi thông báo ngay lập tức
//   Future<void> _testInstantNotification() async {
//     try {
//       await SmartNotificationService.instance.scheduleForClass(
//         id: 99999,
//         tenMon: 'Test Môn Học',
//         ngayHoc: DateTime.now().add(const Duration(seconds: 5)),
//         gioHoc: _formatTime(DateTime.now().add(const Duration(seconds: 5))),
//         phongHoc: 'A101',
//         isExam: false,
//       );
//
//       setState(() => _lastAction = '✅ Sẽ nhận thông báo sau 5 giây');
//       _showSuccess('Thông báo test đã được lên lịch!');
//       await _loadData();
//     } catch (e) {
//       _showError('Lỗi test: $e');
//     }
//   }
//
//   /// Test 2: Test thông báo thi (sau 10 giây)
//   Future<void> _testExamNotification() async {
//     try {
//       await SmartNotificationService.instance.scheduleForClass(
//         id: 99998,
//         tenMon: 'Test Kỳ Thi',
//         ngayHoc: DateTime.now().add(const Duration(seconds: 10)),
//         gioHoc: _formatTime(DateTime.now().add(const Duration(seconds: 10))),
//         phongHoc: 'B202',
//         isExam: true,
//       );
//
//       setState(() => _lastAction = '✅ Sẽ nhận thông báo thi sau 10 giây');
//       _showSuccess('Thông báo thi đã được lên lịch!');
//       await _loadData();
//     } catch (e) {
//       _showError('Lỗi test: $e');
//     }
//   }
//
//   /// Test 3: Sync toàn bộ lịch hôm nay
//   Future<void> _testFullSync() async {
//     setState(() {
//       _isLoading = true;
//       _lastAction = '⏳ Đang sync lịch từ API...';
//     });
//
//     try {
//       await NotificationScheduler.syncNow();
//       setState(() => _lastAction = '✅ Sync thành công!');
//       _showSuccess('Đã sync toàn bộ lịch hôm nay');
//       await _loadData();
//     } catch (e) {
//       setState(() => _lastAction = '❌ Sync thất bại: $e');
//       _showError('Lỗi sync: $e');
//     }
//
//     setState(() => _isLoading = false);
//   }
//
//   /// Test 4: Test nhắc trước giờ học (1 phút sau)
//   Future<void> _testReminderNotification() async {
//     try {
//       final now = DateTime.now();
//       final classTime = now.add(const Duration(minutes: 2));
//
//       await SmartNotificationService.instance.scheduleForClass(
//         id: 99997,
//         tenMon: 'Test Nhắc Nhở',
//         ngayHoc: classTime,
//         gioHoc: _formatTime(classTime),
//         phongHoc: 'C303',
//         isExam: false,
//       );
//
//       setState(() => _lastAction = '✅ Sẽ nhắc trước 30p (nếu setting = 30)');
//       _showSuccess('Nếu reminder = 30 phút, sẽ không nhận vì quá gần!\nĐổi reminder thành 1 phút để test');
//       await _loadData();
//     } catch (e) {
//       _showError('Lỗi test: $e');
//     }
//   }
//
//   /// Test 5: Xóa tất cả thông báo
//   Future<void> _clearAllNotifications() async {
//     final confirm = await _showConfirmDialog(
//       'Xóa tất cả thông báo?',
//       'Thao tác này sẽ hủy toàn bộ thông báo đang chờ',
//     );
//
//     if (confirm == true) {
//       try {
//         await SmartNotificationService.instance.cancelAllNotifications();
//         setState(() => _lastAction = '🗑️ Đã xóa tất cả thông báo');
//         _showSuccess('Đã xóa tất cả thông báo');
//         await _loadData();
//       } catch (e) {
//         _showError('Lỗi xóa: $e');
//       }
//     }
//   }
//
//   // ==================== UI HELPERS ====================
//
//   String _formatTime(DateTime dt) {
//     return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
//   }
//
//   void _showSuccess(String msg) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text(msg), backgroundColor: Colors.green),
//     );
//   }
//
//   void _showError(String msg) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text(msg), backgroundColor: Colors.red),
//     );
//   }
//
//   Future<bool?> _showConfirmDialog(String title, String content) {
//     return showDialog<bool>(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: Text(title),
//         content: Text(content),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context, false),
//             child: const Text('Hủy'),
//           ),
//           ElevatedButton(
//             onPressed: () => Navigator.pop(context, true),
//             child: const Text('Xác nhận'),
//           ),
//         ],
//       ),
//     );
//   }
//
//   // ==================== UI BUILD ====================
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('🧪 Notification Test'),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: _loadData,
//           ),
//         ],
//       ),
//       body: _isLoading
//           ? const Center(child: CircularProgressIndicator())
//           : SingleChildScrollView(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             // Settings Info
//             _buildSettingsCard(),
//             const SizedBox(height: 16),
//
//             // Last Action
//             if (_lastAction.isNotEmpty)
//               Card(
//                 color: Colors.blue.shade50,
//                 child: Padding(
//                   padding: const EdgeInsets.all(12),
//                   child: Text(
//                     _lastAction,
//                     style: const TextStyle(
//                       fontSize: 14,
//                       fontWeight: FontWeight.w500,
//                     ),
//                   ),
//                 ),
//               ),
//             const SizedBox(height: 16),
//
//             // Pending Notifications
//             _buildPendingCard(),
//             const SizedBox(height: 24),
//
//             // Test Buttons
//             const Text(
//               '🧪 CHẠY TEST',
//               style: TextStyle(
//                 fontSize: 18,
//                 fontWeight: FontWeight.bold,
//               ),
//             ),
//             const SizedBox(height: 12),
//
//             _buildTestButton(
//               '⚡ Test Ngay (5s)',
//               'Gửi thông báo sau 5 giây',
//               Colors.green,
//               _testInstantNotification,
//             ),
//             const SizedBox(height: 8),
//
//             _buildTestButton(
//               '📝 Test Thi (10s)',
//               'Gửi thông báo thi sau 10 giây',
//               Colors.orange,
//               _testExamNotification,
//             ),
//             const SizedBox(height: 8),
//
//             _buildTestButton(
//               '⏰ Test Reminder',
//               'Test nhắc trước giờ học (2 phút sau)',
//               Colors.purple,
//               _testReminderNotification,
//             ),
//             const SizedBox(height: 8),
//
//             _buildTestButton(
//               '🔄 Sync API',
//               'Đồng bộ lịch thật từ API',
//               Colors.blue,
//               _testFullSync,
//             ),
//             const SizedBox(height: 16),
//
//             _buildTestButton(
//               '🗑️ Xóa Tất Cả',
//               'Hủy toàn bộ thông báo',
//               Colors.red,
//               _clearAllNotifications,
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildSettingsCard() {
//     if (_settings == null) return const SizedBox();
//
//     return Card(
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Text(
//               '⚙️ CÀI ĐẶT HIỆN TẠI',
//               style: TextStyle(
//                 fontSize: 16,
//                 fontWeight: FontWeight.bold,
//               ),
//             ),
//             const Divider(height: 16),
//             _buildSettingRow(
//               'Notifications',
//               _settings!.enabled ? 'Bật ✅' : 'Tắt ❌',
//             ),
//             _buildSettingRow(
//               'Lịch học',
//               _settings!.scheduleEnabled
//                   ? 'Bật - ${_settings!.scheduleTimeString}'
//                   : 'Tắt',
//             ),
//             _buildSettingRow(
//               'Lịch thi',
//               _settings!.examEnabled
//                   ? 'Bật - ${_settings!.examTimeString}'
//                   : 'Tắt',
//             ),
//             _buildSettingRow(
//               'Nhắc trước',
//               '${_settings!.reminderMinutes} phút',
//             ),
//             _buildSettingRow(
//               'Nhắc thi trước',
//               '${_settings!.examReminderDays} ngày',
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildSettingRow(String label, String value) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 4),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           Text(label),
//           Text(
//             value,
//             style: const TextStyle(fontWeight: FontWeight.w600),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildPendingCard() {
//     return Card(
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 const Text(
//                   '📋 THÔNG BÁO CHỜ',
//                   style: TextStyle(
//                     fontSize: 16,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 Container(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 12,
//                     vertical: 4,
//                   ),
//                   decoration: BoxDecoration(
//                     color: _pendingNotifications.isEmpty
//                         ? Colors.grey.shade300
//                         : Colors.green.shade100,
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Text(
//                     '${_pendingNotifications.length}',
//                     style: TextStyle(
//                       fontWeight: FontWeight.bold,
//                       color: _pendingNotifications.isEmpty
//                           ? Colors.grey.shade700
//                           : Colors.green.shade900,
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//             const Divider(height: 16),
//
//             if (_pendingNotifications.isEmpty)
//               const Center(
//                 child: Padding(
//                   padding: EdgeInsets.all(16),
//                   child: Text(
//                     'Không có thông báo nào đang chờ\n\nẤn "Test Ngay" để thử!',
//                     textAlign: TextAlign.center,
//                     style: TextStyle(color: Colors.grey),
//                   ),
//                 ),
//               )
//             else
//               Column(
//                 children: _pendingNotifications.map((notif) {
//                   return ListTile(
//                     dense: true,
//                     contentPadding: EdgeInsets.zero,
//                     leading: CircleAvatar(
//                       backgroundColor: Colors.blue.shade100,
//                       child: Text(
//                         notif.id.toString(),
//                         style: const TextStyle(fontSize: 10),
//                       ),
//                     ),
//                     title: Text(
//                       notif.title ?? 'No title',
//                       style: const TextStyle(fontSize: 14),
//                     ),
//                     subtitle: Text(
//                       notif.body ?? 'No body',
//                       style: const TextStyle(fontSize: 12),
//                       maxLines: 2,
//                       overflow: TextOverflow.ellipsis,
//                     ),
//                   );
//                 }).toList(),
//               ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildTestButton(
//       String title,
//       String subtitle,
//       Color color,
//       VoidCallback onPressed,
//       ) {
//     return ElevatedButton(
//       onPressed: onPressed,
//       style: ElevatedButton.styleFrom(
//         backgroundColor: color,
//         foregroundColor: Colors.white,
//         padding: const EdgeInsets.all(16),
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(12),
//         ),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             title,
//             style: const TextStyle(
//               fontSize: 16,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//           const SizedBox(height: 4),
//           Text(
//             subtitle,
//             style: const TextStyle(
//               fontSize: 12,
//               color: Colors.white70,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }