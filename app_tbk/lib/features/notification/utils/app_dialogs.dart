import 'package:flutter/material.dart';

// Bảng màu dùng chung với màn hình cài đặt thông báo.
class _C {
  const _C(this.dark);
  final bool dark;

  static _C of(BuildContext context) =>
      _C(Theme.of(context).brightness == Brightness.dark);

  Color get card => dark ? const Color(0xFF141B30) : Colors.white;
  Color get cardAlt =>
      dark ? const Color(0xFF1B2440) : const Color(0xFFF3F6FC);
  Color get border =>
      dark ? const Color(0xFF232E4D) : const Color(0xFFE4E9F3);
  Color get text => dark ? const Color(0xFFEAEFFC) : const Color(0xFF111827);
  Color get muted => dark ? const Color(0xFF8E99B8) : const Color(0xFF6B7487);
  Color get accent => dark ? const Color(0xFF5B8CFF) : const Color(0xFF2F6BFF);
  Color get danger => dark ? const Color(0xFFFF6B6B) : const Color(0xFFE5484D);
  Color get success =>
      dark ? const Color(0xFF3DDBA4) : const Color(0xFF0E9F73);
}

// ───────────────────────── Xác nhận ─────────────────────────

/// Hộp thoại xác nhận. Trả về true nếu người dùng bấm nút chính.
Future<bool> showAppConfirm(
    BuildContext context, {
      required IconData icon,
      required String title,
      required String message,
      String okLabel = 'Xác nhận',
      String cancelLabel = 'Hủy',
      Color? color,
      bool destructive = false,
      bool barrierDismissible = true,
    }) async {
  final c = _C.of(context);
  final tone = color ?? (destructive ? c.danger : c.accent);

  final result = await _showShell(
    context,
    barrierLabel: cancelLabel,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => _DialogShell(
      c: c,
      icon: icon,
      tone: tone,
      title: title,
      message: message,
      actions: [
        _DialogButton(
          label: cancelLabel,
          background: c.cardAlt,
          foreground: c.text,
          onTap: () => Navigator.pop(ctx, false),
        ),
        _DialogButton(
          label: okLabel,
          background: tone,
          foreground: Colors.white,
          onTap: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  return result ?? false;
}

// ───────────────────────── Lỗi ─────────────────────────

/// Hộp thoại báo lỗi. Nếu có [onRetry] sẽ hiện thêm nút "Thử lại".
Future<void> showAppError(
    BuildContext context, {
      String title = 'Có lỗi xảy ra',
      required String message,
      VoidCallback? onRetry,
    }) async {
  final c = _C.of(context);

  final retry = await _showShell(
    context,
    barrierLabel: 'Đóng',
    builder: (ctx) => _DialogShell(
      c: c,
      icon: Icons.error_outline_rounded,
      tone: c.danger,
      title: title,
      message: message,
      actions: [
        _DialogButton(
          label: 'Đóng',
          background: c.cardAlt,
          foreground: c.text,
          onTap: () => Navigator.pop(ctx, false),
        ),
        if (onRetry != null)
          _DialogButton(
            label: 'Thử lại',
            background: c.accent,
            foreground: Colors.white,
            onTap: () => Navigator.pop(ctx, true),
          ),
      ],
    ),
  );

  if (retry == true) onRetry?.call();
}

// ───────────────────────── Toast ─────────────────────────

void showAppToast(BuildContext context, String message, {bool error = false}) {
  final c = _C.of(context);

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        backgroundColor:
        c.dark ? const Color(0xFF1B2440) : const Color(0xFF111827),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: c.dark ? BorderSide(color: c.border) : BorderSide.none,
        ),
        content: Row(
          children: [
            Icon(
              error ? Icons.error_rounded : Icons.check_circle_rounded,
              color: error ? c.danger : c.success,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
}

// ───────────────────────── Thành phần nội bộ ─────────────────────────

Future<bool?> _showShell(
    BuildContext context, {
      required String barrierLabel,
      required WidgetBuilder builder,
      bool barrierDismissible = true,
    }) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => builder(ctx),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _DialogShell extends StatelessWidget {
  const _DialogShell({
    required this.c,
    required this.icon,
    required this.tone,
    required this.title,
    required this.message,
    required this.actions,
  });

  final _C c;
  final IconData icon;
  final Color tone;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: c.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: c.dark ? 0.16 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: tone, size: 30),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.4,
                      color: c.muted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}