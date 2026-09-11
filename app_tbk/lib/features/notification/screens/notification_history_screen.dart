import 'dart:async';
import 'dart:convert';
import 'package:app_tbk/features/notification/screens/notification_detail_screen.dart';
import 'package:app_tbk/features/notification/services/notification_service.dart';
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
  final bool is_read;

  NotificationHistory({
    required this.id,
    required this.mssv,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    required this.is_read,
  });



  factory NotificationHistory.fromJson(Map<String, dynamic> json) {
    return NotificationHistory(
      id: json['id'],
      mssv: json['mssv'],
      title: json['title'],
      body: json['body'],
      type: json['type'],
      timestamp: DateTime.parse(json['timestamp']),
      is_read: json['is_read'] ?? false,
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
      is_read: read ?? this.is_read,
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
  final Function(int)? onTabSelected;
  const NotificationHistoryScreen({Key? key, this.onTabSelected}) : super(key: key);

  @override
  NotificationHistoryScreenState createState() => NotificationHistoryScreenState();
}

class NotificationHistoryScreenState extends State<NotificationHistoryScreen>
    with SingleTickerProviderStateMixin {

  List<NotificationHistory> _allNotifications = [];
  List<NotificationHistory> _classNotifications = [];
  List<NotificationHistory> _examNotifications = [];
  List<NotificationHistory> _reminderNotifications = [];

  late TabController _tabController;
  int _currentTabIndex = 0;

  // TRẠNG THÁI CHUNG
  bool _isDataLoaded = false;  // Đã load dữ liệu chưa?
  bool _isLoading = false;     // Đang load không?
  bool _hasError = false;      // Có lỗi không?


// PUBLIC METHOD
//   void loadTab() {
//     // if (!mounted) return;
//
//     if (!_isDataLoaded && !_isLoading) {
//       _loadData();
//     }
//   }



  bool _tabTransitionLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final newIndex = _tabController.index;

        // BẬT hiệu ứng loading khi chuyển tab
        setState(() {
          _tabTransitionLoading = true;
          _currentTabIndex = newIndex;
        });

        // TẮT sau 1 frame (khi giao diện đã render xong)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _tabTransitionLoading = false;
            });
          }
        });
      }
    });
  }

  // Trạng thái loading riêng cho từng tab
  final Map<int, bool> _tabLoading = {0: false, 1: false, 2: false, 3: false};
  final Map<int, bool> _tabLoaded = {0: false, 1: false, 2: false, 3: false};



  void _handleTabChange() {
    if (!_tabController.indexIsChanging) {
      final newIndex = _tabController.index;
      setState(() => _currentTabIndex = newIndex);

      // CHỈ LOAD KHI CHƯA TỪNG LOAD & NGƯỜI DÙNG ĐANG Ở TAB NÀY
      if (!_isDataLoaded && !_isLoading) {
        _loadData();
      }
    }
  }

  Future<void> _loadData() async {
    if (_isDataLoaded || _isLoading) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final notifications = await NotificationHistoryService.fetchNotifications(context);

      if (!mounted) return; // ✅ Kiểm tra mounted trước khi setState

      setState(() {
        _allNotifications = notifications;
        _classNotifications = notifications.where((n) => n.type == 'CLASS').toList();
        _examNotifications = notifications.where((n) => n.type == 'EXAM').toList();
        _reminderNotifications = notifications.where((n) => n.type == 'REMINDER').toList();

        _isDataLoaded = true;
        _isLoading = false;
        _hasError = false;
      });

    } on TimeoutException catch (_) {
      // ✅ TẮT loading TRƯỚC KHI hiện dialog
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _hasError = true;
      });

      // ✅ Đợi 1 frame để UI cập nhật xong
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showErrorDialog(
            'Mất kết nối',
            'Không thể kết nối đến máy chủ trong 20 giây.\nVui lòng kiểm tra mạng và thử lại.',
            onRetry: _loadData,
          );
        }
      });

    } catch (e) {
      // ✅ TẮT loading khi lỗi khác
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _hasError = true;
      });

      // ✅ Đợi 1 frame để UI cập nhật xong
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showErrorDialog(
            'Lỗi tải dữ liệu',
            e.toString(),
            onRetry: _loadData,
          );
        }
      });
    }
  }

  Future<void> _refreshAll() async {
    if (_isLoading) return; // ✅ Tránh gọi nhiều lần

    setState(() {
      _isDataLoaded = false;  // Cho phép reload
      _hasError = false;
    });

    await _loadData();
  }


  // PUBLIC METHOD
  void loadTab(int tabIndex) {
    if (!mounted || _tabLoaded[tabIndex] == true) return;

    setState(() {
      _isLoading = true;
    });

    _loadDataForTab(tabIndex).then((_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }


  Future<void> _loadDataForTab(int tabIndex) async {

    if (_tabLoading[tabIndex] == true) return;

    setState(() {
      _tabLoading[tabIndex] = true;
      _isLoading = true;
      _hasError = false;
    });

    try {
      final notifications = await NotificationHistoryService.fetchNotifications(context);

      if (!mounted) return; // ✅ Kiểm tra mounted trước khi setState

      setState(() {
        _allNotifications = notifications;
        _classNotifications = notifications.where((n) => n.type == 'CLASS').toList();
        _examNotifications = notifications.where((n) => n.type == 'EXAM').toList();
        _reminderNotifications = notifications.where((n) => n.type == 'REMINDER').toList();

        _isDataLoaded = true;
        _isLoading = false;
        _hasError = false;
      });

    } on TimeoutException catch (_) {
      // ✅ TẮT loading TRƯỚC KHI hiện dialog
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _hasError = true;
      });

      // ✅ Đợi 1 frame để UI cập nhật xong
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showErrorDialog(
            'Mất kết nối',
            'Không thể kết nối đến máy chủ trong 20 giây.\nVui lòng kiểm tra mạng và thử lại.',
            onRetry: _loadData,
          );
        }
      });

    } catch (e) {
      // ✅ TẮT loading khi lỗi khác
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _hasError = true;
      });

      // ✅ Đợi 1 frame để UI cập nhật xong
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showErrorDialog(
            'Lỗi tải dữ liệu',
            e.toString(),
            onRetry: _loadData,
          );
        }
      });
    }
  }
  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
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
                          backgroundColor: Colors.red.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 20,  color: Colors.white,),
                        label: const Text(
                          'Thử lại',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
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


  List<NotificationHistory> get _currentNotifications {
    return switch (_currentTabIndex) {
      0 => _allNotifications,
      1 => _classNotifications,
      2 => _examNotifications,
      3 => _reminderNotifications,
      _ => [],
    };
  }

  Map<String, int> get _statistics {
    return {
      'total': _allNotifications.length,
      'unread': _allNotifications.where((n) => !n.is_read).length,
      'class': _classNotifications.length,
      'exam': _examNotifications.length,
      'reminder': _reminderNotifications.length,
    };
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        backgroundColor: isDark ? Colors.grey[850] : Colors.white,
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon container với animation
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.red.withOpacity(isDark ? 0.3 : 0.15),
                    Colors.red.withOpacity(isDark ? 0.2 : 0.1),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.red.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(isDark ? 0.25 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red,
                    size: 32,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'Xác nhận xóa',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),

            // Message
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 22,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bạn có chắc muốn xóa thông báo này?',
                      style: TextStyle(
                        fontSize: 15,
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
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(
                        color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                        width: 1.5,
                      ),
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                    label: Text(
                      'Hủy',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.red,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    icon: const Icon(
                      Icons.delete_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Xóa',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // ✅ QUAN TRỌNG: Chỉ xử lý khi confirm == true
    if (confirm != true) {
      return; // Người dùng chọn "Hủy" -> không làm gì
    }

    // Từ đây trở đi chỉ chạy khi người dùng chọn "Xóa"
    try {
      final mssv = await AuthService.getSavedMssv() ?? '7231620971';
      final response = await http.delete(
        Uri.parse('http://192.168.0.9:8080/notification-service/api/notification_history/$mssv/${notification.id}'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // ✅ Xóa thành công -> reload data
        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Đã xóa thông báo',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 3),
              elevation: 6,
            ),
          );
        }
      } else {
        throw Exception('Server trả về mã lỗi ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error deleting notification: $e');

      if (mounted) {
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
        final mssv = await AuthService.getSavedMssv() ;
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
                    const Text('Đã xóa tất cả thông báo', style: TextStyle(color: Colors.white)),
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

    // final bool isCurrentTabLoading = _tabLoading[_currentTabIndex] == true;
    // final bool isCurrentTabLoaded = _tabLoaded[_currentTabIndex] == true;

    // ƯU TIÊN HIỂN THỊ LOADING KHI CHƯA CÓ DỮ LIỆU
    // if (_loading && _currentNotifications.isEmpty) {
    //   return Scaffold(
    //     backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
    //     appBar: AppBar(title: const Text('Lịch sử thông báo', style: TextStyle(fontWeight: FontWeight.bold))),
    //     body: const Center(
    //       child: CircularProgressIndicator(strokeWidth: 2.5),
    //     ),
    //   );
    // }

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: const Text('Lịch sử thông báo', style: TextStyle(fontWeight: FontWeight.bold)),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (value) {
              if (value == 'clear') _clearAll();
              if (value == 'refresh') _refreshAll();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(children: [Icon(Icons.refresh, size: 20), SizedBox(width: 12), Text('Làm mới')]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, color: Colors.red, size: 20),
                    SizedBox(width: 12),
                    Text('Xóa tất cả', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_7days',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.orange, size: 20),
                    SizedBox(width: 12),
                    Text('Xóa cũ hơn 7 ngày', style: TextStyle(color: Colors.orange)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_30days',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.amber, size: 20),
                    SizedBox(width: 12),
                    Text('Xóa cũ hơn 30 ngày', style: TextStyle(color: Colors.amber)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatisticsCard(isDark),
          _buildTabBar(isDark, theme),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _hasError
                ? _buildEmptyState(isDark) // hoặc có thể là placeholder
                : _tabTransitionLoading
                ? _buildTabSkeleton()
                : _currentNotifications.isEmpty
                ? _buildEmptyState(isDark)
                : RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: _currentNotifications.length,
                itemBuilder: (context, index) {
                  return _buildNotificationCard(_currentNotifications[index], isDark);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: 5,
      itemBuilder: (context, index) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          leading: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          title: Container(
            height: 16,
            color: Colors.grey[300],
            margin: const EdgeInsets.only(bottom: 8),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 12, color: Colors.grey[200], margin: const EdgeInsets.only(bottom: 4)),
              Container(height: 12, width: 100, color: Colors.grey[200]),
            ],
          ),
          trailing: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
        ),
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
            Theme.of(context).primaryColor.withValues(alpha:0.8),
            Theme.of(context).primaryColor.withValues(alpha:0.6),
          ]
              : [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withValues(alpha:0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withValues(alpha:0.3),
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
            color: Colors.white.withValues(alpha:0.3),
          ),
          Expanded(
            child: _buildStatItem('Chưa đọc', unread, Icons.mark_email_unread_rounded),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.white.withValues(alpha:0.3),
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
      confirmDismiss: (direction) async {
        final confirm = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: isDark ? Colors.grey[850] : Colors.white,
            contentPadding: const EdgeInsets.all(24),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.red.withOpacity(isDark ? 0.3 : 0.15),
                        Colors.red.withOpacity(isDark ? 0.2 : 0.1),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.red.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(isDark ? 0.25 : 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red,
                        size: 32,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Xác nhận xóa',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 22,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Bạn có chắc muốn xóa thông báo này?',
                          style: TextStyle(
                            fontSize: 15,
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(
                            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                            width: 1.5,
                          ),
                        ),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                        ),
                        label: Text(
                          'Hủy',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        icon: const Icon(
                          Icons.delete_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Xóa',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        if (confirm != true) {
          return false;
        }

        // 2. Lưu context trước khi await để tránh async gap
        final BuildContext cardContext = context;

        try {
          // Gọi service đúng cách (không trả về response)
          await NotificationHistoryService.deleteNotification(cardContext, notification.id);

          // Chỉ reload và show SnackBar nếu widget vẫn còn mounted
            await _loadData();

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Đã xóa thông báo',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  backgroundColor: Colors.green.shade600,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  margin: const EdgeInsets.all(16),
                  duration: const Duration(seconds: 3),
                  elevation: 6,
                ),
              );
            }

          return true; // Cho phép Dismissible xóa item khỏi list

        } catch (e) {
          print('❌ Error: $e');

          if (mounted) {
            _showErrorDialog(
              'Lỗi xóa thông báo',
              'Không thể xóa thông báo. Vui lòng thử lại.',
            );
          }

          return false;
        }
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.red.withOpacity(0.7),
              Colors.red,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Xóa',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      child: Card(
        elevation: notification.is_read ? 0 : 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.only(bottom: 8),
        color: notification.is_read
            ? (isDark ? Colors.grey[850]?.withOpacity(0.3) : Colors.grey[100])
            : (isDark ? Colors.grey[850] : Colors.white),
        child: InkWell(
          // ✅ THAY ĐỔI: Navigation đến màn hình chi tiết
          onTap: () async {
            final updatedNotification = await Navigator.push<NotificationHistory>(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    NotificationDetailScreen(
                      notification: notification,
                      onMarkAsRead: (updatedNotif) {
                        // Cập nhật trạng thái trong list
                        setState(() {
                          final allIndex = _allNotifications.indexWhere((n) => n.id == updatedNotif.id);
                          if (allIndex != -1) {
                            _allNotifications[allIndex] = updatedNotif;
                          }

                          final classIndex = _classNotifications.indexWhere((n) => n.id == updatedNotif.id);
                          if (classIndex != -1) {
                            _classNotifications[classIndex] = updatedNotif;
                          }

                          final examIndex = _examNotifications.indexWhere((n) => n.id == updatedNotif.id);
                          if (examIndex != -1) {
                            _examNotifications[examIndex] = updatedNotif;
                          }

                          final reminderIndex = _reminderNotifications.indexWhere((n) => n.id == updatedNotif.id);
                          if (reminderIndex != -1) {
                            _reminderNotifications[reminderIndex] = updatedNotif;
                          }
                        });
                      },
                    ),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  // Hiệu ứng slide từ phải sang trái + fade
                  const begin = Offset(1.0, 0.0);
                  const end = Offset.zero;
                  const curve = Curves.easeInOutCubic;

                  var slideTween = Tween(begin: begin, end: end).chain(
                    CurveTween(curve: curve),
                  );
                  var fadeTween = Tween(begin: 0.0, end: 1.0).chain(
                    CurveTween(curve: curve),
                  );

                  return SlideTransition(
                    position: animation.drive(slideTween),
                    child: FadeTransition(
                      opacity: animation.drive(fadeTween),
                      child: child,
                    ),
                  );
                },
                transitionDuration: const Duration(milliseconds: 400),
                reverseTransitionDuration: const Duration(milliseconds: 350),
              ),
            );

            // Cập nhật nếu có thay đổi trạng thái từ detail screen
            if (updatedNotification != null && updatedNotification.is_read != notification.is_read) {
              setState(() {
                final allIndex = _allNotifications.indexWhere((n) => n.id == updatedNotification.id);
                if (allIndex != -1) {
                  _allNotifications[allIndex] = updatedNotification;
                }

                final classIndex = _classNotifications.indexWhere((n) => n.id == updatedNotification.id);
                if (classIndex != -1) {
                  _classNotifications[classIndex] = updatedNotification;
                }

                final examIndex = _examNotifications.indexWhere((n) => n.id == updatedNotification.id);
                if (examIndex != -1) {
                  _examNotifications[examIndex] = updatedNotification;
                }

                final reminderIndex = _reminderNotifications.indexWhere((n) => n.id == updatedNotification.id);
                if (reminderIndex != -1) {
                  _reminderNotifications[reminderIndex] = updatedNotification;
                }
              });
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: !notification.is_read
                  ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).primaryColor.withOpacity(0.05),
                  Theme.of(context).primaryColor.withOpacity(0.02),
                ],
              )
                  : null,
              border: !notification.is_read
                  ? Border.all(
                color: Theme.of(context).primaryColor.withOpacity(0.4),
                width: 2,
              )
                  : Border.all(
                color: isDark
                    ? Colors.grey[800]!
                    : Colors.grey[200]!,
                width: 1,
              ),
              boxShadow: !notification.is_read
                  ? [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: !notification.is_read
                            ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _getTypeColor(notification.type).withOpacity(0.25),
                            _getTypeColor(notification.type).withOpacity(0.15),
                          ],
                        )
                            : null,
                        color: notification.is_read
                            ? _getTypeColor(notification.type).withOpacity(0.1)
                            : null,
                        borderRadius: BorderRadius.circular(14),
                        border: !notification.is_read
                            ? Border.all(
                          color: _getTypeColor(notification.type).withOpacity(0.3),
                          width: 1.5,
                        )
                            : null,
                      ),
                      child: Text(
                        notification.typeEmoji,
                        style: TextStyle(
                          fontSize: notification.is_read ? 22 : 26,
                        ),
                      ),
                    ),
                    if (!notification.is_read)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Theme.of(context).primaryColor,
                                Theme.of(context).primaryColor.withValues(alpha: 0.8),
                              ],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? Colors.grey[850]! : Colors.white,
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).primaryColor.withValues(alpha:  0.5),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: TextStyle(
                          fontWeight: notification.is_read ? FontWeight.w500 : FontWeight.bold,
                          fontSize: notification.is_read ? 14 : 15.5,
                          color: isDark
                              ? (notification.is_read ? Colors.grey[500] : Colors.white)
                              : (notification.is_read ? Colors.grey[600] : Colors.black87),
                          letterSpacing: notification.is_read ? 0 : 0.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        notification.body,
                        style: TextStyle(
                          color: isDark
                              ? (notification.is_read ? Colors.grey[700] : Colors.grey[400])
                              : (notification.is_read ? Colors.grey[500] : Colors.grey[700]),
                          fontSize: notification.is_read ? 12 : 13,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: !notification.is_read
                                  ? LinearGradient(
                                colors: [
                                  _getTypeColor(notification.type).withOpacity(0.2),
                                  _getTypeColor(notification.type).withOpacity(0.15),
                                ],
                              )
                                  : null,
                              color: notification.is_read
                                  ? _getTypeColor(notification.type).withOpacity(0.1)
                                  : null,
                              borderRadius: BorderRadius.circular(8),
                              border: !notification.is_read
                                  ? Border.all(
                                color: _getTypeColor(notification.type).withOpacity(0.3),
                                width: 1,
                              )
                                  : null,
                            ),
                            child: Text(
                              notification.typeLabel,
                              style: TextStyle(
                                color: _getTypeColor(notification.type),
                                fontSize: 11,
                                fontWeight: notification.is_read ? FontWeight.w600 : FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: isDark ? Colors.grey[600] : Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            notification.formattedTime,
                            style: TextStyle(
                              color: isDark ? Colors.grey[600] : Colors.grey[500],
                              fontSize: 11,
                              fontWeight: notification.is_read ? FontWeight.normal : FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          // Icon chỉ báo có thể xem chi tiết
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: isDark ? Colors.grey[600] : Colors.grey[400],
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