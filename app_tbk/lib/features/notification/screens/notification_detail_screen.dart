import 'dart:async';

import 'package:app_tbk/features/notification/utils/notification_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
      case 'BROADCAST':
      case 'ANNOUNCEMENT':
        return const Color(0xFF2196F3);
      case 'EXAM':
        return const Color(0xFFFF9800);
      case 'REMINDER':
      case 'ATTENDANCE_IN':
      case 'ATTENDANCE_OUT':
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
      case 'BROADCAST':
      case 'ANNOUNCEMENT':
        return Icons.campaign_rounded;
      case 'EXAM':
        return Icons.assignment_rounded;
      case 'REMINDER':
        return Icons.alarm_rounded;
      case 'ATTENDANCE_IN':
        return Icons.login_rounded;
      case 'ATTENDANCE_OUT':
        return Icons.logout_rounded;
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
                    if (n.hasAttachment) ...[
                      const SizedBox(height: 14),
                      _Reveal(delayMs: 120, child: _buildAttachmentCard(n, scheme)),
                    ],
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
        label: 'Thời gian nhận',
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
      // ValueListenableBuilder<bool>(
      //   valueListenable: _isRead,
      //   builder: (_, read, __) {
      //     final color = read ? const Color(0xFF2E9E5B) : scheme.primary;
      //     return _InfoRow(
      //       icon: read
      //           ? Icons.mark_email_read_rounded
      //           : Icons.mark_email_unread_rounded,
      //       label: 'Trạng thái',
      //       scheme: scheme,
      //       tint: color,
      //       child: AnimatedSwitcher(
      //         duration: const Duration(milliseconds: 250),
      //         child: Align(
      //           key: ValueKey(read),
      //           alignment: Alignment.centerLeft,
      //           child: Text(
      //             read ? 'Đã đọc' : 'Chưa đọc',
      //             style: TextStyle(
      //               fontSize: 14.5,
      //               fontWeight: FontWeight.w700,
      //               color: color,
      //             ),
      //           ),
      //         ),
      //       ),
      //     );
      //   },
      // ),
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

  // ---------------------------------------------------------------------
  // FILE ĐÍNH KÈM
  // ---------------------------------------------------------------------
  static final _imgExt = RegExp(r'\.(png|jpe?g|gif|webp|bmp|heic)(\?.*)?$', caseSensitive: false);
  static final _docExt = RegExp(r'\.(pdf|docx?|xlsx?|csv)(\?.*)?$', caseSensitive: false);

  bool _isDrive(String url) => url.contains('drive.google.com') || url.contains('docs.google.com');

  /// Trả về 'word' | 'pdf' | 'excel' hoặc null nếu không phải tài liệu.
  /// Chỉ xét type + tên + đuôi file / đường dẫn Google Docs (KHÔNG tìm chuỗi trong id Drive,
  /// vì id ngẫu nhiên có thể tình cờ chứa "doc", "pdf"...).
  String? _docKind(NotificationHistory n) {
    final meta = '${n.attachmentType ?? ''} ${n.attachmentName ?? ''}'.toLowerCase();
    final url = (n.attachmentUrl ?? '').toLowerCase();

    if (meta.contains('pdf') || RegExp(r'\.pdf(\?.*)?$').hasMatch(url)) return 'pdf';
    if (RegExp(r'xls|excel|sheet|csv').hasMatch(meta) ||
        RegExp(r'\.(xlsx?|csv)(\?.*)?$').hasMatch(url) ||
        url.contains('/spreadsheets/')) {
      return 'excel';
    }
    if (RegExp(r'doc|word').hasMatch(meta) ||
        RegExp(r'\.docx?(\?.*)?$').hasMatch(url) ||
        url.contains('/document/')) {
      return 'word';
    }
    return null;
  }

  String _kindLabel(String? kind) => switch (kind) {
        'pdf' => 'PDF',
        'excel' => 'Excel',
        'word' => 'Word',
        _ => 'Tệp',
      };

  Color _kindColor(String? kind, ColorScheme scheme) => switch (kind) {
        'pdf' => const Color(0xFFE53935),
        'excel' => const Color(0xFF2E7D32),
        'word' => const Color(0xFF1565C0),
        _ => scheme.primary,
      };

  bool _isImage(NotificationHistory n) {
    if (_docKind(n) != null) return false; // MỚI: docx/pdf/excel luôn hiển thị dạng link
    final t = (n.attachmentType ?? '').toLowerCase();
    if (t.contains('image') || const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'img', 'hinh', 'photo'].contains(t)) {
      return true;
    }
    if (t.isNotEmpty && !t.contains('drive') && !t.contains('link')) return false; // type đã nói rõ là docx/pdf...
    return _imgExt.hasMatch(n.attachmentUrl!);
  }

  String? _driveId(String url) =>
      (RegExp(r'/d/([a-zA-Z0-9_-]+)').firstMatch(url) ?? RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(url))
          ?.group(1);

  /// Link Drive dạng /view không hiển thị được bằng Image.network → đổi sang link thumbnail.
  String _imageSrc(String url) {
    if (!_isDrive(url)) return url;
    final id = _driveId(url);
    return id == null ? url : 'https://drive.google.com/thumbnail?id=$id&sz=w1600';
  }

  String _attachmentTitle(NotificationHistory n) {
    if (n.attachmentName != null) return n.attachmentName!;
    final seg = Uri.tryParse(n.attachmentUrl!)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    return seg ?? 'Tệp đính kèm';
  }

  IconData _fileIcon(NotificationHistory n) {
    switch (_docKind(n)) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'excel':
        return Icons.table_chart_rounded;
      case 'word':
        return Icons.description_rounded;
    }
    if (_isDrive(n.attachmentUrl!)) return Icons.add_to_drive_rounded;
    return Icons.attach_file_rounded;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Không thể mở liên kết'),
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  void _openImageViewer(String src, String url) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Mở bằng trình duyệt',
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: () => _openUrl(url),
            ),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.network(
              src,
              loadingBuilder: (_, child, p) => p == null
                  ? child
                  : const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
            ),
          ),
        ),
      ),
    ));
  }

  Widget _buildAttachmentCard(NotificationHistory n, ColorScheme scheme) {
    final url = n.attachmentUrl!;
    final isImage = _isImage(n);
    final title = _attachmentTitle(n);

    return _SurfaceCard(
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_file_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Tệp đính kèm',
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
          if (isImage) ...[
            _buildImagePreview(url, scheme),
            const SizedBox(height: 10),
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: scheme.onSurface)),
          ] else
            _buildFileTile(n, title, scheme),
        ],
      ),
    );
  }

  Widget _buildImagePreview(String url, ColorScheme scheme) {
    final src = _imageSrc(url);
    return GestureDetector(
      onTap: () => _openImageViewer(src, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320, minHeight: 120),
          child: SizedBox(
            width: double.infinity,
            child: Image.network(
              src,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, p) => p == null
                  ? child
                  : Container(
                      height: 160,
                      color: scheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
              errorBuilder: (_, __, ___) => Container(
                height: 120,
                color: scheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_rounded, color: scheme.onSurfaceVariant, size: 32),
                    const SizedBox(height: 6),
                    TextButton(onPressed: () => _openUrl(url), child: const Text('Mở liên kết')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileTile(NotificationHistory n, String title, ColorScheme scheme) {
    final url = n.attachmentUrl!;
    final kind = _docKind(n);
    final isDoc = kind != null;
    final color = _kindColor(kind, scheme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thẻ tên file
        Material(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openUrl(url),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_fileIcon(n), color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                        const SizedBox(height: 2),
                        Text(
                          isDoc
                              ? 'Tệp ${_kindLabel(kind)}${_isDrive(url) ? ' · Google Drive' : ''}'
                              : (_isDrive(url) ? 'Google Drive' : 'Liên kết'),
                          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Thông báo + đường link đầy đủ
        const SizedBox(height: 12),
        if (isDoc)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đây là tệp ${_kindLabel(kind)}. Hãy nhấn "Mở tệp đầy đủ" hoặc mở link bên dưới '
                    'để xem toàn bộ nội dung (tất cả các trang).',
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        Text('Đường dẫn',
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _openUrl(url),
          child: Text(
            url,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: scheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: scheme.primary,
            ),
          ),
        ),

        // Nút hành động
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
                onPressed: () => _openUrl(url),
                icon: const Icon(Icons.open_in_new_rounded, size: 17),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    isDoc ? 'Mở tệp đầy đủ' : 'Mở liên kết',
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
                onPressed: () => _copy(url, 'Đã sao chép liên kết'),
                icon: const Icon(Icons.link_rounded, size: 17),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Sao chép link',
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
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