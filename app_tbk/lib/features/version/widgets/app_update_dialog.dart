import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:app_tbk/features/version/models/app_version_model.dart';
import 'package:app_tbk/features/update/services/ota_update_service.dart';

class AppUpdateDialog extends StatelessWidget {
  final AppVersionModel appVersion;
  final String currentVersion;
  final bool forceUpdate;

  const AppUpdateDialog({
    super.key,
    required this.appVersion,
    required this.currentVersion,
    required this.forceUpdate,
  });

  static Future<void> show(
      BuildContext context, {
        required AppVersionModel appVersion,
        required String currentVersion,
        required bool forceUpdate,
      }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !forceUpdate,
      barrierColor: Colors.black54,
      builder: (_) => AppUpdateDialog(
        appVersion: appVersion,
        currentVersion: currentVersion,
        forceUpdate: forceUpdate,
      ),
    );
  }

  Future<void> _startOtaUpdate(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final urlStr = appVersion.downloadUrl.trim();

    if (urlStr.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Không tìm thấy đường dẫn tải ứng dụng.')),
      );
      return;
    }

    // Đóng dialog hiện tại
    Navigator.of(context).pop();

    // Mở Dialog tải xuống và tiến hành cài đặt
    OtaUpdateService.startDownloadAndInstall(context, urlStr, forceUpdate);
  }

  /// Tách release notes thành từng dòng, bỏ ký tự bullet ở đầu dòng.
  List<String> get _noteLines => appVersion.releaseNotes
      .split('\n')
      .map((l) => l.trim().replaceFirst(RegExp(r'^[-•*]\s*'), ''))
      .where((l) => l.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Màu nhấn: cam cho bắt buộc, màu chủ đạo cho tuỳ chọn.
    final accent = forceUpdate ? const Color(0xFFF59E0B) : scheme.primary;
    final accentDark = forceUpdate ? const Color(0xFFD97706) : scheme.primary;

    final title = appVersion.updateTitle.isNotEmpty
        ? appVersion.updateTitle
        : (forceUpdate ? 'Cập nhật ứng dụng bắt buộc' : 'Đã có phiên bản mới!');

    return PopScope(
      canPop: !forceUpdate,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: 1),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            builder: (context, value, child) => Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.scale(scale: value, child: child),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  accent: accent,
                  accentDark: accentDark,
                  forceUpdate: forceUpdate,
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _VersionRow(
                          current: currentVersion,
                          next: appVersion.version,
                          accent: accent,
                        ),
                        if (appVersion.updateDesc.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            appVersion.updateDesc,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ],
                        if (_noteLines.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          _ReleaseNotes(lines: _noteLines, accent: accent),
                        ],
                        if (forceUpdate) ...[
                          const SizedBox(height: 16),
                          _ForceNotice(color: accentDark),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _startOtaUpdate(context),
                        icon: const Icon(Icons.download_rounded, size: 20),
                        label: const Text(
                          'Cập nhật ngay',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      if (!forceUpdate) ...[
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            foregroundColor: scheme.onSurfaceVariant,
                          ),
                          child: const Text('Để sau'),
                        ),
                      ],
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
}

/// Phần đầu: nền gradient + icon nổi bật.
class _Header extends StatelessWidget {
  final Color accent;
  final Color accentDark;
  final bool forceUpdate;

  const _Header({
    required this.accent,
    required this.accentDark,
    required this.forceUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 128,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent,
            Color.lerp(accentDark, Colors.black, 0.25)!,
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Hoạ tiết tròn trang trí
          Positioned(
            top: -30,
            right: -20,
            child: _Bubble(size: 110, alpha: 0.10),
          ),
          Positioned(
            bottom: -40,
            left: -30,
            child: _Bubble(size: 130, alpha: 0.08),
          ),
          // Icon chính
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
            ),
            child: Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: Icon(
                forceUpdate
                    ? Icons.system_update_alt_rounded
                    : Icons.rocket_launch_rounded,
                size: 34,
                color: accent,
              ),
            ),
          ),
          if (forceUpdate)
            Positioned(
              top: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'BẮT BUỘC',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final double size;
  final double alpha;

  const _Bubble({required this.size, required this.alpha});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }
}

/// Hiển thị v1.0.0 → v1.1.0
class _VersionRow extends StatelessWidget {
  final String current;
  final String next;
  final Color accent;

  const _VersionRow({
    required this.current,
    required this.next,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Chip(
          label: 'v$current',
          background: scheme.surfaceContainerHighest,
          foreground: scheme.onSurfaceVariant,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: scheme.outline,
          ),
        ),
        _Chip(
          label: 'v$next',
          background: accent.withValues(alpha: 0.14),
          foreground: accent,
          bold: true,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final bool bold;

  const _Chip({
    required this.label,
    required this.background,
    required this.foreground,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          color: foreground,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

/// Danh sách chi tiết cập nhật dạng checklist.
class _ReleaseNotes extends StatelessWidget {
  final List<String> lines;
  final Color accent;

  const _ReleaseNotes({required this.lines, required this.accent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                'Có gì mới',
                style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 16,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                line,
                                style: textTheme.bodySmall?.copyWith(
                                  fontSize: 13,
                                  height: 1.45,
                                  color: scheme.onSurface.withValues(alpha: 0.85),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thông báo khi cập nhật bắt buộc.
class _ForceNotice extends StatelessWidget {
  final Color color;

  const _ForceNotice({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Bạn cần cập nhật để tiếp tục sử dụng ứng dụng.',
              style: TextStyle(
                fontSize: 12.5,
                color: color,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}