// lib/utils/notification_debugger.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/smart_notification_service.dart';
import 'dart:convert';

/// Helper class để debug và log notification
class NotificationDebugger {
  static const String _keyNotificationLogs = 'notification_logs';
  static const int _maxLogs = 50;

  /// Lưu log khi schedule notification
  static Future<void> logScheduled({
    required int id,
    required String type,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    await _saveLog({
      'action': 'SCHEDULED',
      'id': id,
      'type': type,
      'title': title,
      'body': body,
      'scheduledTime': scheduledTime.toIso8601String(),
      'timestamp': DateTime.now().toIso8601String(),
    });

    debugPrint('📅 SCHEDULED: [$id] $title at ${_formatDateTime(scheduledTime)}');
  }

  /// Lưu log khi nhận notification
  static Future<void> logReceived({
    required int id,
    required String title,
    required String body,
  }) async {
    await _saveLog({
      'action': 'RECEIVED',
      'id': id,
      'title': title,
      'body': body,
      'timestamp': DateTime.now().toIso8601String(),
    });

    debugPrint('✅ RECEIVED: [$id] $title');
  }

  /// Lưu log khi tap notification
  static Future<void> logTapped({
    required int id,
    required String title,
  }) async {
    await _saveLog({
      'action': 'TAPPED',
      'id': id,
      'title': title,
      'timestamp': DateTime.now().toIso8601String(),
    });

    debugPrint('👆 TAPPED: [$id] $title');
  }

  /// Lưu log khi cancel notification
  static Future<void> logCancelled({
    required int id,
  }) async {
    await _saveLog({
      'action': 'CANCELLED',
      'id': id,
      'timestamp': DateTime.now().toIso8601String(),
    });

    debugPrint('🗑️ CANCELLED: [$id]');
  }

  /// Lưu log error
  static Future<void> logError({
    required String message,
    String? stackTrace,
  }) async {
    await _saveLog({
      'action': 'ERROR',
      'message': message,
      'stackTrace': stackTrace,
      'timestamp': DateTime.now().toIso8601String(),
    });

    debugPrint('❌ ERROR: $message');
  }

  /// Lấy tất cả logs
  static Future<List<Map<String, dynamic>>> getLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final logsJson = prefs.getStringList(_keyNotificationLogs) ?? [];
    return logsJson.map((json) => jsonDecode(json) as Map<String, dynamic>).toList();
  }

  /// Xóa tất cả logs
  static Future<void> clearLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyNotificationLogs);
    debugPrint('🗑️ All logs cleared');
  }

  /// Lưu log vào SharedPreferences
  static Future<void> _saveLog(Map<String, dynamic> log) async {
    final prefs = await SharedPreferences.getInstance();
    final logs = prefs.getStringList(_keyNotificationLogs) ?? [];

    logs.insert(0, jsonEncode(log));

    // Giữ tối đa _maxLogs
    if (logs.length > _maxLogs) {
      logs.removeRange(_maxLogs, logs.length);
    }

    await prefs.setStringList(_keyNotificationLogs, logs);
  }

  /// Format DateTime thành string dễ đọc
  static String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Kiểm tra xem notification có được schedule đúng không
  static Future<Map<String, dynamic>> checkNotificationStatus() async {
    final settings = await SmartNotificationService.instance.getSettings();
    final pending = await SmartNotificationService.instance.getPendingNotifications();
    final logs = await getLogs();

    final scheduled = logs.where((log) => log['action'] == 'SCHEDULED').length;
    final received = logs.where((log) => log['action'] == 'RECEIVED').length;
    final tapped = logs.where((log) => log['action'] == 'TAPPED').length;
    final errors = logs.where((log) => log['action'] == 'ERROR').length;

    return {
      'settings_enabled': settings.enabled,
      'schedule_enabled': settings.scheduleEnabled,
      'exam_enabled': settings.examEnabled,
      'pending_count': pending.length,
      'total_scheduled': scheduled,
      'total_received': received,
      'total_tapped': tapped,
      'total_errors': errors,
      'success_rate': scheduled > 0 ? (received / scheduled * 100).toStringAsFixed(1) : '0',
    };
  }

  /// In ra báo cáo chi tiết
  static Future<void> printReport() async {
    final status = await checkNotificationStatus();

    debugPrint('\n' + '=' * 50);
    debugPrint('📊 NOTIFICATION REPORT');
    debugPrint('=' * 50);
    debugPrint('Settings Enabled: ${status['settings_enabled']}');
    debugPrint('Schedule Enabled: ${status['schedule_enabled']}');
    debugPrint('Exam Enabled: ${status['exam_enabled']}');
    debugPrint('-' * 50);
    debugPrint('Pending: ${status['pending_count']}');
    debugPrint('Scheduled: ${status['total_scheduled']}');
    debugPrint('Received: ${status['total_received']}');
    debugPrint('Tapped: ${status['total_tapped']}');
    debugPrint('Errors: ${status['total_errors']}');
    debugPrint('Success Rate: ${status['success_rate']}%');
    debugPrint('=' * 50 + '\n');

    // In 10 logs gần nhất
    final logs = await getLogs();
    if (logs.isNotEmpty) {
      debugPrint('📝 RECENT LOGS (${logs.length} total):\n');
      for (var i = 0; i < logs.length && i < 10; i++) {
        final log = logs[i];
        final action = log['action'];
        final time = log['timestamp'];
        final title = log['title'] ?? log['message'] ?? '';

        debugPrint('  [$i] $action - $title');
        debugPrint('      Time: $time\n');
      }
    }
  }
}

/// Widget hiển thị logs trong app
class NotificationLogsScreen extends StatefulWidget {
  const NotificationLogsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationLogsScreen> createState() => _NotificationLogsScreenState();
}

class _NotificationLogsScreenState extends State<NotificationLogsScreen> {
  List<Map<String, dynamic>> _logs = [];
  Map<String, dynamic>? _status;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final logs = await NotificationDebugger.getLogs();
    final status = await NotificationDebugger.checkNotificationStatus();

    setState(() {
      _logs = logs;
      _status = status;
      _isLoading = false;
    });
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa tất cả logs?'),
        content: const Text('Thao tác này không thể hoàn tác'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await NotificationDebugger.clearLogs();
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa tất cả logs')),
        );
      }
    }
  }

  Future<void> _printReport() async {
    await NotificationDebugger.printReport();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã in report ra console')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📝 Notification Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _printReport,
            tooltip: 'In report ra console',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearLogs,
            tooltip: 'Xóa logs',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          if (_status != null) _buildStatusCard(),
          Expanded(child: _buildLogsList()),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 THỐNG KÊ',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Pending', _status!['pending_count'].toString(), Colors.blue),
                _buildStatItem('Scheduled', _status!['total_scheduled'].toString(), Colors.orange),
                _buildStatItem('Received', _status!['total_received'].toString(), Colors.green),
                _buildStatItem('Errors', _status!['total_errors'].toString(), Colors.red),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Success Rate: ${_status!['success_rate']}%',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildLogsList() {
    if (_logs.isEmpty) {
      return const Center(
        child: Text(
          'Chưa có logs nào\n\nSchedule thông báo để xem logs',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: _logs.length,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemBuilder: (context, index) {
        final log = _logs[index];
        return _buildLogItem(log, index);
      },
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log, int index) {
    final action = log['action'] as String;
    final timestamp = DateTime.parse(log['timestamp'] as String);

    IconData icon;
    Color color;

    switch (action) {
      case 'SCHEDULED':
        icon = Icons.schedule;
        color = Colors.blue;
        break;
      case 'RECEIVED':
        icon = Icons.notifications_active;
        color = Colors.green;
        break;
      case 'TAPPED':
        icon = Icons.touch_app;
        color = Colors.purple;
        break;
      case 'CANCELLED':
        icon = Icons.cancel;
        color = Colors.orange;
        break;
      case 'ERROR':
        icon = Icons.error;
        color = Colors.red;
        break;
      default:
        icon = Icons.info;
        color = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          action,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (log['title'] != null)
              Text(
                log['title'] as String,
                style: const TextStyle(fontSize: 13),
              ),
            if (log['body'] != null)
              Text(
                log['body'] as String,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (log['message'] != null)
              Text(
                log['message'] as String,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Text(
              _formatTimestamp(timestamp),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        trailing: log['id'] != null
            ? Chip(
          label: Text(
            '#${log['id']}',
            style: const TextStyle(fontSize: 10),
          ),
          backgroundColor: color.withOpacity(0.1),
        )
            : null,
        onTap: () => _showLogDetails(log),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) {
      return 'Vừa xong';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} phút trước';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} giờ trước';
    } else {
      return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }

  void _showLogDetails(Map<String, dynamic> log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${log['action']}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: log.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black87),
                    children: [
                      TextSpan(
                        text: '${entry.key}: ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: '${entry.value}'),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

}


