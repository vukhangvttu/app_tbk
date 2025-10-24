import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/services/auth_service.dart';

class NotificationHistory {
  final int id;
  final String mssv;
  final String title;
  final String body;
  final String type;
  final DateTime timestamp;
  final bool read;

  NotificationHistory({
    required this.id,
    required this.mssv,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    required this.read,
  });

  factory NotificationHistory.fromJson(Map<String, dynamic> json) {
    return NotificationHistory(
      id: json['id'],
      mssv: json['mssv'],
      title: json['title'],
      body: json['body'],
      type: json['type'],
      timestamp: DateTime.parse(json['timestamp']),
      read: json['read'] ?? false,
    );
  }

  NotificationHistory copyWith({bool? read}) {
    return NotificationHistory(
      id: id,
      mssv: mssv,
      title: title,
      body: body,
      type: type,
      timestamp: timestamp,
      read: read ?? this.read,
    );
  }

  String get typeEmoji {
    switch (type) {
      case 'CLASS':
        return '📚';
      case 'EXAM':
        return '📝';
      case 'REMINDER':
        return '⏰';
      case 'EXAM_ADVANCE':
        return '📅';
      default:
        return '📬';
    }
  }

  String get typeLabel {
    switch (type) {
      case 'CLASS':
        return 'Lịch học';
      case 'EXAM':
        return 'Lịch thi';
      case 'REMINDER':
        return 'Nhắc nhở';
      case 'EXAM_ADVANCE':
        return 'Nhắc thi';
      default:
        return type;
    }
  }

  String get formattedTime {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Vừa xong';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} phút trước';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} giờ trước';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else {
      return DateFormat('dd/MM/yyyy HH:mm').format(timestamp);
    }
  }
}

class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({Key? key}) : super(key: key);

  @override
  State<NotificationHistoryScreen> createState() => _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen>
    with SingleTickerProviderStateMixin {
  List<NotificationHistory> _allNotifications = [];
  List<NotificationHistory> _classNotifications = [];
  List<NotificationHistory> _examNotifications = [];
  List<NotificationHistory> _reminderNotifications = [];

  bool _loading = true;
  late TabController _tabController;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Helper method để show error dialog
  void _showErrorDialog(String title, String message, {VoidCallback? onRetry}) {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        elevation: 8,
        backgroundColor: isDark ? Colors.grey[850] : Colors.white,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.red.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Error icon with animation
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(isDark ? 0.2 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(isDark ? 0.3 : 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.red,
                      size: 36,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Message
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(
                          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                        ),
                      ),
                      child: Text(
                        'Đóng',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          onRetry();
                        },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: const Text(
                          'Thử lại',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final mssv = await AuthService.getSavedMssv() ?? '7231620971';
      final response = await http.get(
        Uri.parse('http://192.168.1.120:8080/notification-service/api/notification_history/$mssv'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      print('📥 API response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        final notifications = jsonData
            .map((json) => NotificationHistory.fromJson(json))
            .toList();

        // Sắp xếp theo thời gian mới nhất
        notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        setState(() {
          _allNotifications = notifications;
          _classNotifications = notifications.where((n) => n.type == 'CLASS').toList();
          _examNotifications = notifications.where((n) => n.type == 'EXAM').toList();
          _reminderNotifications = notifications.where((n) => n.type == 'REMINDER').toList();
          _loading = false;
        });

        print('✅ Loaded ${notifications.length} notifications');
      } else {
        throw Exception('Server trả về mã lỗi ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error loading notifications: $e');
      setState(() {
        _loading = false;
      });

      String errorMessage = 'Không thể kết nối đến máy chủ. Vui lòng kiểm tra kết nối mạng của bạn.';

      if (e.toString().contains('SocketException')) {
        errorMessage = 'Không thể kết nối đến máy chủ. Vui lòng kiểm tra kết nối mạng.';
      } else if (e.toString().contains('TimeoutException')) {
        errorMessage = 'Yêu cầu quá thời gian chờ. Vui lòng thử lại sau.';
      } else if (e.toString().contains('FormatException')) {
        errorMessage = 'Dữ liệu từ máy chủ không hợp lệ. Vui lòng liên hệ hỗ trợ.';
      }

      _showErrorDialog(
        'Lỗi tải thông báo',
        errorMessage,
        onRetry: _loadData,
      );
    }
  }

  List<NotificationHistory> get _currentNotifications {
    switch (_currentTabIndex) {
      case 0:
        return _allNotifications;
      case 1:
        return _classNotifications;
      case 2:
        return _examNotifications;
      case 3:
        return _reminderNotifications;
      default:
        return _allNotifications;
    }
  }

  Map<String, int> get _statistics {
    return {
      'total': _allNotifications.length,
      'unread': _allNotifications.where((n) => !n.read).length,
      'class': _classNotifications.length,
      'exam': _examNotifications.length,
      'reminder': _reminderNotifications.length,
    };
  }

  Future<void> _markAsRead(NotificationHistory notification) async {
    if (notification.read) return;

    try {
      final mssv = await AuthService.getSavedMssv() ?? '7231620971';
      final response = await http.put(
        Uri.parse('http://192.168.0.9:8080/notification-service/api/notification_history/$mssv/${notification.id}/read'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() {
          final allIndex = _allNotifications.indexWhere((n) => n.id == notification.id);
          if (allIndex != -1) {
            _allNotifications[allIndex] = notification.copyWith(read: true);
          }

          final classIndex = _classNotifications.indexWhere((n) => n.id == notification.id);
          if (classIndex != -1) {
            _classNotifications[classIndex] = notification.copyWith(read: true);
          }

          final examIndex = _examNotifications.indexWhere((n) => n.id == notification.id);
          if (examIndex != -1) {
            _examNotifications[examIndex] = notification.copyWith(read: true);
          }

          final reminderIndex = _reminderNotifications.indexWhere((n) => n.id == notification.id);
          if (reminderIndex != -1) {
            _reminderNotifications[reminderIndex] = notification.copyWith(read: true);
          }
        });
        print('✅ Marked notification ${notification.id} as read');
      } else {
        throw Exception('Server trả về mã lỗi ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error marking as read: $e');
      _showErrorDialog(
        'Lỗi đánh dấu đã đọc',
        'Không thể đánh dấu thông báo là đã đọc. Vui lòng thử lại.',
      );
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final mssv = await AuthService.getSavedMssv() ?? '7231620971';
      final response = await http.put(
        Uri.parse('http://192.168.0.9:8080/notification-service/api/notification_history/$mssv/read-all'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text('Đã đánh dấu tất cả là đã đọc'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else {
        throw Exception('Server trả về mã lỗi ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error marking all as read: $e');
      _showErrorDialog(
        'Lỗi đánh dấu tất cả',
        'Không thể đánh dấu tất cả thông báo là đã đọc. Vui lòng thử lại.',
        onRetry: _markAllAsRead,
      );
    }
  }

  Future<void> _deleteNotification(NotificationHistory notification) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Xác nhận xóa')),
          ],
        ),
        content: const Text('Bạn có chắc muốn xóa thông báo này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final mssv = await AuthService.getSavedMssv() ?? '7231620971';
        final response = await http.delete(
          Uri.parse('http://192.168.0.9:8080/notification-service/api/notification_history/$mssv/${notification.id}'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          await _loadData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.delete_sweep, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text('Đã xóa thông báo'),
                  ],
                ),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        } else {
          throw Exception('Server trả về mã lỗi ${response.statusCode}');
        }
      } catch (e) {
        print('❌ Error deleting notification: $e');
        _showErrorDialog(
          'Lỗi xóa thông báo',
          'Không thể xóa thông báo. Vui lòng thử lại.',
        );
      }
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Xóa tất cả thông báo')),
          ],
        ),
        content: const Text('Bạn có chắc muốn xóa TẤT CẢ thông báo? Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa tất cả'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final mssv = await AuthService.getSavedMssv() ?? '7231620971';
        final response = await http.delete(
          Uri.parse('http://192.168.0.9:8080/notification-service/api/notification_history/$mssv'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          await _loadData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.delete_sweep, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text('Đã xóa tất cả thông báo'),
                  ],
                ),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        } else {
          throw Exception('Server trả về mã lỗi ${response.statusCode}');
        }
      } catch (e) {
        print('❌ Error clearing all: $e');
        _showErrorDialog(
          'Lỗi xóa tất cả',
          'Không thể xóa tất cả thông báo. Vui lòng thử lại.',
          onRetry: _clearAll,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Lịch sử thông báo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        actions: [
          if (_statistics['unread']! > 0)
            IconButton(
              icon: const Icon(Icons.done_all_rounded),
              tooltip: 'Đánh dấu tất cả đã đọc',
              onPressed: _markAllAsRead,
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (value) {
              if (value == 'clear') {
                _clearAll();
              } else if (value == 'refresh') {
                _loadData();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 20),
                    SizedBox(width: 12),
                    Text('Làm mới'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, color: Colors.red, size: 20),
                    SizedBox(width: 12),
                    Text(
                      'Xóa tất cả',
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildStatisticsCard(isDark),
          _buildTabBar(isDark, theme),
          Expanded(
            child: _currentNotifications.isEmpty
                ? _buildEmptyState(isDark)
                : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: _currentNotifications.length,
                itemBuilder: (context, index) {
                  return _buildNotificationCard(
                    _currentNotifications[index],
                    isDark,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard(bool isDark) {
    final total = _statistics['total']!;
    final unread = _statistics['unread']!;
    final classCount = _statistics['class']!;
    final examCount = _statistics['exam']!;
    final reminderCount = _statistics['reminder']!;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
            Theme.of(context).primaryColor.withOpacity(0.8),
            Theme.of(context).primaryColor.withOpacity(0.6),
          ]
              : [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withOpacity(0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem('Tổng', total, Icons.notifications_active_rounded),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.white.withOpacity(0.3),
          ),
          Expanded(
            child: _buildStatItem('Chưa đọc', unread, Icons.mark_email_unread_rounded),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.white.withOpacity(0.3),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMiniCount('📚', classCount),
                _buildMiniCount('📝', examCount),
                _buildMiniCount('⏰', reminderCount),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 6),
        Text(
          value.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniCount(String emoji, int count) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 2),
        Text(
          count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(bool isDark, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorWeight: 3,
        indicatorColor: theme.primaryColor,
        labelColor: isDark ? Colors.white : theme.primaryColor,
        unselectedLabelColor: isDark ? Colors.grey[500] : Colors.grey[600],
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        tabs: [
          Tab(
            icon: const Icon(Icons.apps_rounded, size: 20),
            text: 'Tất cả',
          ),
          Tab(
            icon: const Icon(Icons.school_rounded, size: 20),
            text: 'Lớp học',
          ),
          Tab(
            icon: const Icon(Icons.assignment_rounded, size: 20),
            text: 'Lịch thi',
          ),
          Tab(
            icon: const Icon(Icons.alarm_rounded, size: 20),
            text: 'Nhắc nhở',
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(NotificationHistory notification, bool isDark) {
    return Dismissible(
      key: Key(notification.id.toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Colors.red, Colors.redAccent],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 28),
      ),
      onDismissed: (direction) => _deleteNotification(notification),
      child: Card(
        elevation: notification.read ? 0 : 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.only(bottom: 8),
        color: notification.read
            ? (isDark ? Colors.grey[850]?.withOpacity(0.5) : Colors.grey[100])
            : (isDark ? Colors.grey[800] : Colors.white),
        child: InkWell(
          onTap: () => _markAsRead(notification),
          borderRadius: BorderRadius.circular(14),
          child: Opacity(
            opacity: notification.read ? 0.6 : 1.0,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: !notification.read
                    ? Border.all(
                  color: Theme.of(context).primaryColor.withOpacity(isDark ? 0.5 : 0.3),
                  width: 1.5,
                )
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _getTypeColor(notification.type).withOpacity(isDark ? 0.2 : 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          notification.typeEmoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                      if (!notification.read)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? Colors.grey[800]! : Colors.white,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight: notification.read ? FontWeight.w500 : FontWeight.bold,
                            fontSize: 14,
                            color: isDark
                                ? (notification.read ? Colors.grey[500] : Colors.white)
                                : (notification.read ? Colors.grey[600] : Colors.black87),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notification.body,
                          style: TextStyle(
                            color: isDark ? Colors.grey[600] : Colors.grey[600],
                            fontSize: 12,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _getTypeColor(notification.type).withOpacity(isDark ? 0.2 : 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                notification.typeLabel,
                                style: TextStyle(
                                  color: _getTypeColor(notification.type),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.access_time_rounded,
                              size: 12,
                              color: isDark ? Colors.grey[600] : Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              notification.formattedTime,
                              style: TextStyle(
                                color: isDark ? Colors.grey[600] : Colors.grey[500],
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_off_rounded,
              size: 56,
              color: isDark ? Colors.grey[600] : Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Không có thông báo',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.grey[400] : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _getEmptyMessage(),
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[600] : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  String _getEmptyMessage() {
    switch (_currentTabIndex) {
      case 1:
        return 'Chưa có thông báo lịch học';
      case 2:
        return 'Chưa có thông báo lịch thi';
      case 3:
        return 'Chưa có thông báo nhắc nhở';
      default:
        return 'Chưa có thông báo nào';
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'CLASS':
        return const Color(0xFF2196F3);
      case 'EXAM':
        return const Color(0xFFFF9800);
      case 'REMINDER':
        return const Color(0xFF4CAF50);
      case 'EXAM_ADVANCE':
        return const Color(0xFFF44336);
      default:
        return Colors.grey;
    }
  }
}