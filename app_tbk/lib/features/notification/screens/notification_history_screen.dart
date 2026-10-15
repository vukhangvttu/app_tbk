import 'dart:async';
import 'package:app_tbk/core/errors/exceptions.dart';
import 'package:app_tbk/features/notification/screens/notification_detail_screen.dart';
import 'package:app_tbk/features/notification/services/notification_service.dart';
import 'package:app_tbk/features/notification/utils/notification_filter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:app_tbk/features/notification/widgets/clear_all_dialog.dart';
import 'package:shimmer/shimmer.dart';

// ─────────────────────────────── MODEL ───────────────────────────────

class NotificationHistory implements FilterableNotification {
  final int id;
  final String mssv;
  final String title;
  final String body;
  final String type;
  final DateTime timestamp;
  final bool is_read;
  @override
  final String? subject;

  NotificationHistory({
    required this.id,
    required this.mssv,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    required this.is_read,
    this.subject,
  });

  factory NotificationHistory.fromJson(Map<String, dynamic> json) {
    String str(List<String> keys) {
      for (final k in keys) {
        final v = json[k]?.toString();
        if (v != null && v.isNotEmpty) return v;
      }
      return '';
    }

    final read = json['is_read'] ?? json['isRead'];
    return NotificationHistory(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      mssv: str(['mssv']),
      title: str(['title', 'tieuDe']),
      body: str(['body', 'noiDung']),
      type: str(['type', 'loaiLich']),
      timestamp: _parseTimestamp(json),
      is_read: read == true || read == 1 || read?.toString() == 'true',
      subject: _readSubject(json),
    );
  }

  static String? _readSubject(Map<String, dynamic> json) {
    for (final k in const ['subject', 'tenMon', 'ten_mon', 'monHoc', 'mon_hoc', 'tenHocPhan']) {
      final v = json[k]?.toString().trim();
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  /// Server trả giờ VN thật nhưng đôi khi gắn nhãn 'Z' → bỏ cờ UTC, giữ nguyên giờ,
  /// tránh bị .toLocal() cộng thêm 7 tiếng.
  static DateTime _stripUtc(DateTime d) => d.isUtc
      ? DateTime(d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond, d.microsecond)
      : d;

  static DateTime _parseTimestamp(Map<String, dynamic> json) {
    const keys = ['timestamp', 'created_at', 'createdAt', 'sentAt', 'sent_at', 'ngayTao', 'ngay_tao', 'time', 'date'];
    dynamic raw;
    for (final k in keys) {
      if (json[k] != null) {
        raw = json[k];
        break;
      }
    }
    if (raw == null) return DateTime.now();
    if (raw is DateTime) return _stripUtc(raw);

    // Jackson mặc định của LocalDateTime: [y, M, d, h, m, s]
    if (raw is List && raw.isNotEmpty) {
      try {
        int at(int i, int def) => i < raw.length ? (raw[i] as num).toInt() : def;
        return DateTime(at(0, 1970), at(1, 1), at(2, 1), at(3, 0), at(4, 0), at(5, 0));
      } catch (_) {}
    }

    final s = raw.toString().trim();
    if (s.isEmpty) return DateTime.now();

    // Epoch (giây hoặc mili giây)
    final n = raw is num ? raw.toInt() : int.tryParse(s);
    if (n != null && n > 0) {
      return DateTime.fromMillisecondsSinceEpoch(n > 100000000000 ? n : n * 1000).toLocal();
    }

    final clean = s.replaceAll(RegExp(r'[Zz]$'), '');
    final iso = DateTime.tryParse(clean);
    if (iso != null) return _stripUtc(iso);

    for (final f in const ['dd/MM/yyyy HH:mm:ss', 'dd/MM/yyyy HH:mm', 'dd/MM/yyyy', 'yyyy/MM/dd HH:mm:ss']) {
      try {
        return DateFormat(f).parseStrict(clean);
      } catch (_) {}
    }
    return DateTime.now();
  }

  NotificationHistory copyWith({bool? read, String? subject}) => NotificationHistory(
    id: id,
    mssv: mssv,
    title: title,
    body: body,
    type: type,
    timestamp: timestamp,
    is_read: read ?? is_read,
    subject: subject ?? this.subject,
  );

  static const _types = <String, (String, String, Color)>{
    'CLASS': ('📚', 'Lịch học', Color(0xFF2196F3)),
    'EXAM': ('📝', 'Lịch thi', Color(0xFFFF9800)),
    'REMINDER': ('⏰', 'Nhắc nhở', Color(0xFF4CAF50)),
    'EXAM_ADVANCE': ('📅', 'Nhắc thi', Color(0xFFF44336)),
  };

  String get typeEmoji => _types[type]?.$1 ?? '📬';
  String get typeLabel => _types[type]?.$2 ?? type;
  Color get color => _types[type]?.$3 ?? Colors.grey;

  // Tạo DateFormat rất tốn kém → dùng chung 1 instance, và chỉ format khi thật sự cần.
  static final _fullFmt = DateFormat('dd/MM/yyyy HH:mm');

  String get formattedTime {
    final d = DateTime.now().difference(timestamp);
    // Âm = lệch đồng hồ server/thiết bị vài giây
    if (d.isNegative) return d.inMinutes > -60 ? 'Vừa xong' : _fullFmt.format(timestamp);
    if (d.inSeconds < 60) return 'Vừa xong';
    if (d.inMinutes < 60) return '${d.inMinutes} phút trước';
    if (d.inHours < 24) return '${d.inHours} giờ trước';
    if (d.inDays < 7) return '${d.inDays} ngày trước';
    return _fullFmt.format(timestamp);
  }
}

// ─────────────────────────────── SCREEN ───────────────────────────────

enum _View { skeleton, error, empty, filteredEmpty, list }

class NotificationHistoryScreen extends StatefulWidget {
  final Function(int)? onTabSelected; // giữ lại cho tương thích với nơi gọi
  final VoidCallback? onNotificationChanged;

  const NotificationHistoryScreen({
    Key? key,
    this.onTabSelected,
    this.onNotificationChanged,
  }) : super(key: key);

  @override
  NotificationHistoryScreenState createState() => NotificationHistoryScreenState();
}

class NotificationHistoryScreenState extends State<NotificationHistoryScreen>
    with SingleTickerProviderStateMixin {
  static const _limit = 20;

  late final TabController _tabController;
  final _scrollController = ScrollController();

  /// Nguồn dữ liệu duy nhất; các tab chỉ là bộ lọc trên danh sách này.
  List<NotificationHistory> _all = [];
  NotificationFilter _filter = const NotificationFilter();

  bool _loaded = false;
  bool _isLoading = false; // chỉ dùng cho UI (spinner / thanh tiến trình)
  bool _hasError = false;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _page = 1;
  int _serverTotal = 0;
  int _serverUnread = 0;

  /// Cờ "đang gọi API" KHÔNG đi kèm setState → kéo-để-làm-mới không bị rebuild giữa chừng.
  bool _fetching = false;

  /// Tăng mỗi lần reload; dùng để bỏ kết quả "tải thêm" cũ nếu list đã bị làm mới.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) setState(() {});
      });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// Được widget cha gọi khi tab này được chọn (tải lười, chỉ tải 1 lần).
  void loadTab([int? _]) => _loadData();

  // ───────────── Dữ liệu dẫn xuất ─────────────

  List<NotificationHistory> get _tabItems => switch (_tabController.index) {
    1 => _all.where((n) => n.type == 'CLASS').toList(),
    2 => _all.where((n) => n.type == 'EXAM' || n.type == 'EXAM_ADVANCE').toList(),
    3 => _all.where((n) => n.type == 'REMINDER').toList(),
    _ => _all,
  };

  int get _total => _serverTotal > _all.length ? _serverTotal : _all.length;

  int get _unread {
    final local = _all.where((n) => !n.is_read).length;
    return _serverUnread > local ? _serverUnread : local;
  }

  // ───────────── Tải dữ liệu ─────────────

  /// [silent] = true khi gọi từ RefreshIndicator (nó đã có spinner riêng):
  /// không setState lúc bắt đầu → không rebuild cả màn hình giữa lúc người dùng đang kéo.
  Future<void> _loadData({bool force = false, bool silent = false}) async {
    if (_fetching || (_loaded && !force)) return;
    _fetching = true;
    _gen++;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    try {
      // Kéo-để-làm-mới: server trả quá nhanh thì dữ liệu bị thay ngay lúc list còn đang
      // nảy về chỗ cũ sau khi thả tay → khựng. Giữ tối thiểu 400ms cho animation lắng xuống.
      final minWait = silent
          ? Future<void>.delayed(const Duration(milliseconds: 400))
          : Future<void>.value();

      final results = await Future.wait([
        NotificationHistoryService.fetchNotifications(context, page: 1, limit: _limit),
        NotificationHistoryService.getNotificationStats(context),
      ]);
      await minWait;
      if (!mounted) return;

      final response = results[0] as Map<String, dynamic>;
      final stats = results[1] as Map<String, int>;
      final data = (response['data'] as List).cast<NotificationHistory>();
      final hasMore = response['has_more'] == true;
      final total = stats['total'] ?? 0;
      final unreadSrv = stats['unread'] ?? 0;
      final before = (_total, _unread);

      // Không có gì thay đổi → không rebuild gì cả (trường hợp phổ biến khi kéo làm mới).
      final unchanged = _loaded &&
          !_hasError &&
          !_isLoading &&
          _page == 1 &&
          _hasMore == hasMore &&
          _serverTotal == total &&
          _serverUnread == unreadSrv &&
          _sameList(_all, data);

      if (!unchanged) {
        setState(() {
          _all = data;
          _hasMore = hasMore;
          _page = 1;
          _serverTotal = total;
          _serverUnread = unreadSrv;
          _loaded = true;
          _isLoading = false;
          _hasError = false;
        });
        // Đợi list dựng xong rồi mới trả future → RefreshIndicator mới bắt đầu animation đóng,
        // tránh dựng list và animate cùng một khung hình.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }

      // Báo cho widget cha SAU khung hình hiện tại và chỉ khi số liệu đổi,
      // để không rebuild cây cha đúng lúc spinner đang đóng lại.
      if (before != (_total, _unread)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onNotificationChanged?.call();
        });
      }
    } on TimeoutException {
      _fail('Mất kết nối', 'Không thể kết nối đến máy chủ trong 20 giây.\nVui lòng kiểm tra mạng và thử lại.');
    } catch (e) {
      final offline = e is NoInternetException ||
          e.toString().contains('Không có kết nối') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('ClientException');
      _fail(
        offline ? 'Không có kết nối mạng' : 'Lỗi tải dữ liệu',
        offline
            ? 'Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.'
            : e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      _fetching = false;
    }
  }

  static bool _sameList(List<NotificationHistory> a, List<NotificationHistory> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].is_read != b[i].is_read || a[i].title != b[i].title) return false;
    }
    return true;
  }

  void _fail(String title, String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _hasError = !_loaded; // đã có dữ liệu thì giữ nguyên list, chỉ báo lỗi bằng dialog
    });
    _showError(title, message, onRetry: () => _loadData(force: true));
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore || _fetching || !_loaded) return;
    final gen = _gen;
    setState(() => _isLoadingMore = true);
    try {
      final response = await NotificationHistoryService.fetchNotifications(
        context,
        page: _page + 1,
        limit: _limit,
        beforeId: _all.isNotEmpty ? _all.last.id : null,
      );
      if (!mounted || gen != _gen) return; // list đã bị làm mới → bỏ kết quả cũ
      setState(() {
        _page++;
        _hasMore = response['has_more'] as bool;
        final ids = _all.map((n) => n.id).toSet();
        _all = [..._all, ...(response['data'] as List<NotificationHistory>).where((n) => ids.add(n.id))];
      });
    } catch (e) {
      debugPrint('Load more error: $e'); // không làm phiền người dùng
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final p = _scrollController.position;
    // maxScrollExtent > 0: list ngắn (max = 0) trước đây luôn thỏa điều kiện → gọi _loadMore
    // liên tục mỗi khi người dùng kéo xuống để refresh.
    if (p.maxScrollExtent > 0 && p.pixels >= p.maxScrollExtent - 200) _loadMore();
  }

  // ───────────── Lọc ─────────────

  void _setFilter(NotificationFilter f) {
    setState(() => _filter = f);
    _autoLoadForFilter();
  }

  Future<void> _openFilterSheet() async {
    final items = _tabItems;
    final result = await showNotificationFilterSheet(
      context,
      current: _filter,
      facets: NotificationFilter.subjectFacets(items),
      
    );
    if (result != null && mounted) _setFilter(result);
  }

  /// Lọc chạy trên dữ liệu đã tải: ít kết quả mà server còn dữ liệu cũ → tải thêm (tối đa 10 trang).
  Future<void> _autoLoadForFilter() async {
    if (!_filter.hasCriteria) return;
    var guard = 0;
    while (mounted &&
        _hasMore &&
        !_isLoadingMore &&
        !_fetching &&
        _filter.apply(_tabItems).length < 15 &&
        guard++ < 10) {
      await _loadMore();
    }
  }

  // ───────────── Hành động ─────────────

  void _applyRead(NotificationHistory updated) {
    final i = _all.indexWhere((n) => n.id == updated.id);
    if (i == -1) return;
    final becameRead = !_all[i].is_read && updated.is_read;
    setState(() {
      _all[i] = updated;
      if (becameRead && _serverUnread > 0) _serverUnread--;
    });
    if (becameRead) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onNotificationChanged?.call();
      });
    }
  }

  /// Hoàn thành khi animation đóng của route đã chạy xong.
  Future<void> _waitRouteDismissed(ModalRoute<dynamic> route) {
    final anim = route.animation;
    if (anim == null || anim.status == AnimationStatus.dismissed) return Future.value();

    final done = Completer<void>();
    void onStatus(AnimationStatus s) {
      if (s == AnimationStatus.dismissed && !done.isCompleted) {
        anim.removeStatusListener(onStatus);
        done.complete();
      }
    }

    anim.addStatusListener(onStatus);
    return done.future;
  }

  Future<void> _open(NotificationHistory n) async {
    final wasUnread = !n.is_read;

    // Đánh dấu đã đọc ngầm trên server (không rebuild UI)
    if (wasUnread) {
      unawaited(() async {
        try {
          await NotificationHistoryService.markAsRead(context, n.id);
        } catch (e) {
          debugPrint('❌ Silent error marking as read: $e');
        }
      }());
    }

    final route = MaterialPageRoute<NotificationHistory>(
      builder: (_) => NotificationDetailScreen(
        notification: n.copyWith(read: true),
      ),
    );
    await Navigator.push(context, route);

    // Future của push xong NGAY KHI BẮT ĐẦU pop → phải chờ animation quay lại kết thúc
    // rồi mới cập nhật UI, nếu không setState sẽ chạy chung khung hình với animation.
    await _waitRouteDismissed(route);
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted || !wasUnread) return;
    _applyRead(n.copyWith(read: true));
  }

  Future<void> _markAllAsRead() async {
    final ok = await _confirm(
      icon: Icons.done_all_rounded,
      color: Theme.of(context).primaryColor,
      title: 'Đánh dấu tất cả đã đọc?',
      message: '$_unread thông báo chưa đọc sẽ chuyển sang đã đọc.',
      okLabel: 'Xác nhận',
    );
    if (!ok || !mounted) return;
    try {
      await NotificationHistoryService.markAllAsRead(context);
      await _loadData(force: true);
      _toast('Đã đánh dấu tất cả là đã đọc');
    } catch (e) {
      debugPrint('Error marking all as read: $e');
      if (mounted) {
        _showError('Lỗi', 'Không thể đánh dấu tất cả đã đọc. Vui lòng thử lại.', onRetry: _markAllAsRead);
      }
    }
  }

  Future<void> _clearAll() async {
    await ClearAllDialog.show(
      context,
      count: _total,
      onConfirm: () => NotificationHistoryService.deleteAllNotifications(context),
      onCleared: _applyClearedState,
    );
  }

  Future<void> _clearOlderThan7Days() async {
    await ClearAllDialog.show(
      context,
      count: 0,
      title: 'Xóa thông báo cũ?',
      bodyText: 'Các thông báo gửi trước 7 ngày sẽ bị xóa.\nHành động này không thể hoàn tác.',
      buttonText: 'Xóa',
      onConfirm: () => NotificationHistoryService.deleteOlderThan7Days(context),
      onCleared: () => _loadData(force: true),
    );
  }

  Future<void> _clearOlderThan30Days() async {
    await ClearAllDialog.show(
      context,
      count: 0,
      title: 'Xóa thông báo cũ?',
      bodyText: 'Các thông báo gửi trước 30 ngày sẽ bị xóa.\nHành động này không thể hoàn tác.',
      buttonText: 'Xóa',
      onConfirm: () => NotificationHistoryService.deleteOlderThan30Days(context),
      onCleared: () => _loadData(force: true),
    );
  }

  void _applyClearedState() {
    if (!mounted) return;
    setState(() {
      _gen++;
      _all = [];
      _serverTotal = 0;
      _serverUnread = 0;
      _hasMore = false;
      _page = 1;
      _filter = const NotificationFilter();
    });
    widget.onNotificationChanged?.call();
  }

  /// Dùng cho Dismissible.confirmDismiss: hỏi → gọi API → true thì item bị gỡ khỏi UI.
  Future<bool> _deleteOne(NotificationHistory n) async {
    final result = await ClearAllDialog.show(
      context,
      count: 0,
      title: 'Xác nhận xóa',
      bodyText: 'Bạn có chắc muốn xóa thông báo này?',
      buttonText: 'Xóa',
      onConfirm: () => NotificationHistoryService.deleteNotification(context, n.id),
      onCleared: () {}, // Dismissible tự gọi _removeLocal khi onDismissed
    );
    return result == true;
  }

  void _removeLocal(NotificationHistory n) {
    setState(() {
      _all.removeWhere((x) => x.id == n.id);
      if (_serverTotal > 0) _serverTotal--;
      if (!n.is_read && _serverUnread > 0) _serverUnread--;
    });
    widget.onNotificationChanged?.call();
    _toast('Đã xóa thông báo');
  }

  // ───────────── Dialog / Snackbar dùng chung ─────────────

  Future<bool> _confirm({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    required String okLabel,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: Icon(icon, color: color, size: 32),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(c, true),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    return r == true;
  }

  void _showError(String title, String message, {VoidCallback? onRetry}) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.error_outline_rounded, color: Colors.red, size: 32),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Đóng')),
          if (onRetry != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                onRetry();
              },
              child: const Text('Thử lại'),
            ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
    );
  }

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    // Tính 1 lần mỗi build (trước đây _tabItems/_unread bị tính lặp nhiều lần).
    final items = _tabItems;
    final shown = _filter.apply(items);
    final total = _total;
    final unread = _unread;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final view = (!_loaded && !_hasError)
        ? _View.skeleton // gồm cả lúc chưa bắt đầu tải → không còn nháy "Không có thông báo"
        : _hasError
            ? _View.error
            : shown.isEmpty
                ? (_filter.hasCriteria ? _View.filteredEmpty : _View.empty)
                : _View.list;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        centerTitle: false, // tiêu đề nằm bên trái
        titleSpacing: 16,   // khoảng cách từ mép trái (tùy chỉnh
        title: Text(
          'Lịch sử thông báo',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        elevation: 0,
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Colors.black87,
        ),
        actions: [
          if (unread > 0)
            IconButton(
              icon: const Icon(Icons.done_all_rounded),
              tooltip: 'Đánh dấu tất cả đã đọc',
              onPressed: _markAllAsRead,
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'clear':
                  _clearAll();
                case 'clear_7days':
                  _clearOlderThan7Days();
                case 'clear_30days':
                  _clearOlderThan30Days();
                default:
                  _loadData(force: true);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('Làm mới')),
              PopupMenuItem(value: 'clear', child: Text('Xóa tất cả', style: TextStyle(color: Colors.red))),
              PopupMenuItem(value: 'clear_7days', child: Text('Xóa cũ hơn 7 ngày', style: TextStyle(color: Colors.orange))),
              PopupMenuItem(value: 'clear_30days', child: Text('Xóa cũ hơn 30 ngày', style: TextStyle(color: Colors.amber))),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false, // 4 tab chia đều chiều rộng màn hình
          tabAlignment: TabAlignment.fill,
          indicatorSize: TabBarIndicatorSize.tab,
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          tabs: const [
            _FitTab('Tất cả'),
            _FitTab('Lớp học'),
            _FitTab('Lịch thi'),
            _FitTab('Nhắc nhở'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_isLoading && _loaded) const LinearProgressIndicator(minHeight: 2),

          // Giữ chỗ, chỉ hiện mờ dần khi có số liệu → không bị nhảy số
          AnimatedOpacity(
            opacity: _loaded ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('$total thông báo · $unread chưa đọc',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          ),

          // Thanh lọc trượt ra mượt, không đẩy danh sách đột ngột
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: (_all.isNotEmpty || _filter.isActive)
                ? NotificationFilterBar(
                    filter: _filter,
                    items: items,
                    onChanged: _setFilter,
                    onOpenSheet: _openFilterSheet,
                  )
                : const SizedBox(width: double.infinity),
          ),

          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, if (current != null) current],
              ),
              // key theo TRẠNG THÁI (không phải theo dữ liệu) → chỉ cross-fade khi đổi trạng thái
              child: KeyedSubtree(
                key: ValueKey(view),
                child: _buildContent(view, shown, isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(_View view, List<NotificationHistory> shown, bool isDark) {
    return switch (view) {
      _View.skeleton => _buildSkeleton(isDark),
      _View.error => _empty(Icons.error_outline_rounded, 'Không tải được thông báo',
          actionLabel: 'Thử lại', onAction: () => _loadData(force: true)),
      _View.filteredEmpty => _empty(
          Icons.filter_alt_off_rounded,
          'Không có thông báo phù hợp',
          subtitle: _hasMore
              ? 'Thử tải thêm thông báo cũ hơn hoặc nới lỏng bộ lọc.'
              : 'Hãy nới lỏng bộ lọc.',
          actionLabel: _hasMore ? 'Tải thêm thông báo cũ hơn' : null,
          onAction: _loadMore,
          secondaryLabel: 'Xóa bộ lọc',
          onSecondary: () => _setFilter(const NotificationFilter()),
        ),
      _View.empty => _empty(
          Icons.notifications_off_rounded,
          'Không có thông báo',
          subtitle: switch (_tabController.index) {
            1 => 'Chưa có thông báo lịch học',
            2 => 'Chưa có thông báo lịch thi',
            3 => 'Chưa có thông báo nhắc nhở',
            _ => 'Chưa có thông báo nào',
          },
        ),
      _View.list => _buildList(shown),
    };
  }

  /// Skeleton có hình dạng giống card thật → khi dữ liệu về chỉ là cross-fade, không đổi bố cục.
  Widget _buildSkeleton(bool isDark) {
    Widget bar(double factor, double h) => FractionallySizedBox(
          widthFactor: factor,
          alignment: Alignment.centerLeft,
          child: Container(
            height: h,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
          ),
        );

    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade300,
      highlightColor: isDark ? const Color(0xFF334155) : Colors.grey.shade100,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        itemCount: 8,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 1.5), // viền để thấy hình card
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(0.6, 13),
                    const SizedBox(height: 7),
                    bar(0.9, 11),
                    const SizedBox(height: 7),
                    bar(0.35, 9),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<NotificationHistory> shown) {
    final entries = _filter.effectiveGroupByDay
        ? NotificationFilter.buildEntries(shown)
        : List<Object>.of(shown);
    final showMoreBtn = _filter.hasCriteria && _hasMore && !_isLoadingMore;
    final extra = (_isLoadingMore || showMoreBtn) ? 1 : 0;

    return RefreshIndicator(
      // silent: RefreshIndicator đã có spinner → không setState lúc bắt đầu kéo
      onRefresh: () => _loadData(force: true, silent: true),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        itemCount: entries.length + extra,
        itemBuilder: (_, i) {
          if (i >= entries.length) {
            return _isLoadingMore
                ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
                : Center(
              child: TextButton.icon(
                onPressed: _loadMore,
                icon: const Icon(Icons.history_rounded),
                label: const Text('Tải thêm thông báo cũ hơn'),
              ),
            );
          }
          final e = entries[i];
          return e is NotificationDayHeader
              ? NotificationDayHeaderTile(header: e)
              : _buildCard(e as NotificationHistory);
        },
      ),
    );
  }

  Widget _buildCard(NotificationHistory n) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final unread = !n.is_read;

    // Màu nền card
    final cardBg = unread
        ? (isDark
            ? Color.alphaBlend(theme.primaryColor.withValues(alpha: 0.18), const Color(0xFF1E293B))
            : Colors.white)
        : (isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.6)
            : Colors.grey.shade100.withValues(alpha: 0.6));

    // Viền card
    final borderColor = unread
        ? (isDark ? theme.primaryColor.withValues(alpha: 0.6) : theme.primaryColor.withValues(alpha: 0.4))
        : (isDark ? Colors.grey.shade800.withValues(alpha: 0.5) : Colors.grey.shade300.withValues(alpha: 0.5));

    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _deleteOne(n),
      onDismissed: (_) => _removeLocal(n),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 6),
        elevation: unread ? (isDark ? 0 : 1) : 0,
        clipBehavior: Clip.hardEdge, // antiAlias tốn hơn trên mỗi item khi cuộn/overscroll
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: borderColor,
            width: unread ? 1.5 : 1.0,
          ),
        ),
        color: cardBg,
        child: ListTile(
          onTap: () => _open(n), // xem toàn bộ nội dung ở màn hình chi tiết
          dense: true,
          minLeadingWidth: 0,
          horizontalTitleGap: 10,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: CircleAvatar(
            radius: 15,
            backgroundColor: unread
                ? n.color.withValues(alpha: isDark ? 0.25 : 0.15)
                : (isDark ? Colors.grey.shade800.withValues(alpha: 0.5) : Colors.grey.shade200),
            child: Text(
              n.typeEmoji,
              style: TextStyle(
                fontSize: 14,
                color: unread ? null : (isDark ? Colors.grey.shade600 : Colors.grey.shade500),
              ),
            ),
          ),
          title: Text(
            n.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: unread ? FontWeight.bold : FontWeight.normal,
              fontSize: unread ? 14.5 : 13.5,
              color: unread
                  ? (isDark ? Colors.white : const Color(0xFF0F172A))
                  : (isDark ? Colors.grey.shade500 : Colors.grey.shade600),
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                n.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: unread ? 12.5 : 12.0,
                  color: unread
                      ? (isDark ? Colors.grey.shade300 : Colors.grey.shade800)
                      : (isDark ? Colors.grey.shade600 : Colors.grey.shade500),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${n.typeLabel} · ${n.formattedTime}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: unread
                      ? n.color
                      : (isDark ? Colors.grey.shade600 : Colors.grey.shade500),
                  fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
          trailing: unread
              ? Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    shape: BoxShape.circle,
                    boxShadow: isDark
                        ? [
                            BoxShadow(
                              color: theme.primaryColor.withValues(alpha: 0.6),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _empty(
      IconData icon,
      String title, {
        String? subtitle,
        String? actionLabel,
        VoidCallback? onAction,
        String? secondaryLabel,
        VoidCallback? onSecondary,
      }) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: muted),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: muted)),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
            ],
            if (secondaryLabel != null) TextButton(onPressed: onSecondary, child: Text(secondaryLabel)),
          ],
        ),
      ),
    );
  }
}

/// Tab tự thu nhỏ chữ nếu màn hình hẹp, không bao giờ bị cắt.
class _FitTab extends StatelessWidget {
  final String label;
  const _FitTab(this.label);

  @override
  Widget build(BuildContext context) => Tab(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(label, maxLines: 1, softWrap: false),
    ),
  );
}
