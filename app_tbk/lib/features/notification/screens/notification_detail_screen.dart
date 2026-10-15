import 'dart:async';

import 'package:app_tbk/features/notification/utils/notification_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/notification_service.dart';
import 'notification_history_screen.dart'; // NotificationHistory

class NotificationDetailScreen extends StatefulWidget {
  final NotificationHistory notification;
  final Function(NotificationHistory)? onMarkAsRead;

  const NotificationDetailScreen({
    Key? key,
    required this.notification,
    this.onMarkAsRead,
  }) : super(key: key);

  @override
  State<NotificationDetailScreen> createState() => _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  late NotificationHistory _notification;

  /// Chỉ phần phụ thuộc trạng thái đọc (badge "Mới", dòng trạng thái) lắng nghe
  /// notifier này → đánh dấu đã đọc KHÔNG rebuild cả màn hình.
  late final ValueNotifier<bool> _isRead;
  bool _isMarking = false;

  ColorScheme? _scheme;
  Brightness? _schemeBrightness;

  @override
  void initState() {
    super.initState();
    _notification = widget.notification;
    _isRead = ValueNotifier<bool>(_notification.is_read);

    // Gọi sau frame đầu: service có thể dùng context, và không làm chậm lần dựng đầu.
    if (!_notification.is_read) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _markAsRead());
    }
  }

  @override
  void dispose() {
    _isRead.dispose();
    super.dispose();
  }

  Future<void> _markAsRead() async {
    if (_isMarking || _isRead.value || !mounted) return;
    _isMarking = true;
    try {
      _notification = _notification.copyWith(read: true);
      _isRead.value = true;
      widget.onMarkAsRead?.call(_notification); // cập nhật danh sách bên ngoài

      // Gọi API chạy ngầm không gây lag hay chặn UI
      unawaited(NotificationHistoryService.markAsRead(context, _notification.id).catchError((e) {
        debugPrint('❌ Silent error marking as read: $e');
      }));
    } catch (e) {
      debugPrint('❌ Error marking as read: $e');
    } finally {
      _isMarking = false;
    }
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // ---------------------------------------------------------------------
  // MÀU / ICON THEO LOẠI
  // ---------------------------------------------------------------------
  Color _typeColor(String type) {
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
        return Colors.blueGrey;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'CLASS':
        return Icons.school_rounded;
      case 'EXAM':
        return Icons.assignment_rounded;
      case 'REMINDER':
        return Icons.alarm_rounded;
      case 'EXAM_ADVANCE':
        return Icons.event_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  /// Bảng màu Material 3 sinh từ màu loại thông báo: nền, chip, chữ tự hài hòa
  /// và đúng cả light/dark, thay cho việc tô cứng Colors.grey / trắng.
  ColorScheme _schemeFor(Brightness b) {
    if (_scheme == null || _schemeBrightness != b) {
      _scheme = ColorScheme.fromSeed(
        seedColor: _typeColor(_notification.type),
        brightness: b,
      );
      _schemeBrightness = b;
    }
    return _scheme!;
  }

  String _dateText(DateTime t) {
    final day = DateTime(t.year, t.month, t.day);
    return '${NotificationDayHeader(day, 0).label()} · ${DateFormat('HH:mm').format(t)}';
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final scheme = _schemeFor(base.brightness);
    final n = _notification;
    final subject = SubjectExtractor.of(n);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // Màu đầu trang = màu AppBar → không có đường nối giữa AppBar và header
    final headerTop = Color.alphaBlend(
      scheme.primaryContainer.withValues(alpha: 0.55),
      scheme.surface,
    );

    return Theme(
      data: base.copyWith(
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
      ),
      // Mọi cách quay lại (nút, cử chỉ vuốt) đều trả về thông báo đã cập nhật
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.of(context).pop(_notification);
        },
        child: Scaffold(
          backgroundColor: scheme.surface,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                centerTitle: false,
                backgroundColor: headerTop,
                foregroundColor: scheme.onSurface,
                surfaceTintColor: Colors.transparent,
                scrolledUnderElevation: 0,
                leading: const BackButton(),
                title: const Text(
                  'Chi tiết thông báo',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Sao chép',
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: () =>
                        _copy('${n.title}\n\n${n.body}', 'Đã sao chép thông báo'),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              SliverToBoxAdapter(
                child: _Reveal(
                  child: _buildHeader(n, scheme, headerTop, subject),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + bottomInset),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _Reveal(delayMs: 80, child: _buildBodyCard(n, scheme)),
                    const SizedBox(height: 14),
                    _Reveal(delayMs: 160, child: _buildInfoCard(n, scheme, subject)),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // HEADER: chip loại + badge Mới + tiêu đề + thời gian / môn
  // ---------------------------------------------------------------------
  Widget _buildHeader(
      NotificationHistory n,
      ColorScheme scheme,
      Color headerTop,
      String? subject,
      ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [headerTop, scheme.surface],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_typeIcon(n.type), size: 18, color: scheme.onPrimaryContainer),
                    const SizedBox(width: 6),
                    Text(
                      n.typeLabel,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          SelectableText(
            n.title,
            style: TextStyle(
              fontSize: 22,
              height: 1.3,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MetaPill(
                icon: Icons.access_time_rounded,
                text: _dateText(n.timestamp),
                scheme: scheme,
              ),
              if (subject != null && subject.isNotEmpty)
                _MetaPill(
                  icon: Icons.menu_book_rounded,
                  text: subject,
                  scheme: scheme,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // NỘI DUNG (phẳng, không đổ bóng → nhẹ hơn, có thể bôi đen để sao chép)
  // ---------------------------------------------------------------------
  Widget _buildBodyCard(NotificationHistory n, ColorScheme scheme) {
    final empty = n.body.trim().isEmpty;
    return _SurfaceCard(
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notes_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Nội dung',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            empty ? 'Không có nội dung.' : n.body,
            style: TextStyle(
              fontSize: 16,
              height: 1.65,
              color: empty ? scheme.onSurfaceVariant : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // THÔNG TIN CHI TIẾT
  // ---------------------------------------------------------------------
  Widget _buildInfoCard(NotificationHistory n, ColorScheme scheme, String? subject) {
    final rows = <Widget>[
      _InfoRow(
        icon: Icons.category_rounded,
        label: 'Loại thông báo',
        scheme: scheme,
        child: _InfoText(n.typeLabel, scheme),
      ),
      _InfoRow(
        icon: Icons.schedule_rounded,
        label: 'Thời gian',
        scheme: scheme,
        child: _InfoText(DateFormat('dd/MM/yyyy HH:mm').format(n.timestamp), scheme),
      ),
      if (subject != null && subject.isNotEmpty)
        _InfoRow(
          icon: Icons.menu_book_rounded,
          label: 'Môn học',
          scheme: scheme,
          child: _InfoText(subject, scheme),
        ),
      if (n.mssv.isNotEmpty)
        _InfoRow(
          icon: Icons.badge_rounded,
          label: 'MSSV',
          scheme: scheme,
          child: _InfoText(n.mssv, scheme),
        ),
      ValueListenableBuilder<bool>(
        valueListenable: _isRead,
        builder: (_, read, __) {
          final color = read ? const Color(0xFF2E9E5B) : scheme.primary;
          return _InfoRow(
            icon: read
                ? Icons.mark_email_read_rounded
                : Icons.mark_email_unread_rounded,
            label: 'Trạng thái',
            scheme: scheme,
            tint: color,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Align(
                key: ValueKey(read),
                alignment: Alignment.centerLeft,
                child: Text(
                  read ? 'Đã đọc' : 'Chưa đọc',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ];

    final divided = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        divided.add(Divider(
          height: 1,
          indent: 50,
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ));
      }
      divided.add(rows[i]);
    }

    return _SurfaceCard(
      scheme: scheme,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(children: divided),
    );
  }
}

// =====================================================================
// WIDGET NHỎ (const / không rebuild khi đổi trạng thái đọc)
// =====================================================================

/// Thẻ phẳng: tonal surface + viền mảnh, không BoxShadow (rẻ hơn khi vẽ/cuộn).
class _SurfaceCard extends StatelessWidget {
  final ColorScheme scheme;
  final Widget child;
  final EdgeInsets padding;

  const _SurfaceCard({
    required this.scheme,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final ColorScheme scheme;

  const _MetaPill({required this.icon, required this.text, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  final ColorScheme scheme;
  final Color? tint;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.child,
    required this.scheme,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final color = tint ?? scheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoText extends StatelessWidget {
  final String text;
  final ColorScheme scheme;
  const _InfoText(this.text, this.scheme);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    );
  }
}

/// Hiện dần + trượt nhẹ, các khối xuất hiện nối tiếp. Tắt khi người dùng bật
/// "giảm chuyển động" của hệ điều hành.
class _Reveal extends StatelessWidget {
  final Widget child;
  final int delayMs;
  const _Reveal({required this.child, this.delayMs = 0});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;

    final total = 420 + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delayMs / total, 1, curve: Curves.easeOutCubic),
      child: child, // child không bị dựng lại mỗi frame
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
      ),
    );
  }
}