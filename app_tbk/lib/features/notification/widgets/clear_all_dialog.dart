import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// =====================================================================
/// HỘP THOẠI "XÓA TẤT CẢ THÔNG BÁO"
/// Đặt tại: lib/features/notification/widgets/clear_all_dialog.dart
///
/// Một hộp thoại duy nhất đi qua 4 trạng thái, không mở thêm dialog nào:
///   xác nhận → đang xóa (spinner) → thành công (hiệu ứng tick) → tự đóng
///                                 ↘ lỗi (thông báo ngay trong hộp + Thử lại)
/// =====================================================================

enum _Phase { confirm, deleting, success, error }

class ClearAllDialog extends StatefulWidget {
  /// Số thông báo sẽ bị xóa (chỉ để hiển thị). 0 = ẩn dòng đếm.
  final int count;

  /// Gọi API xóa. Ném lỗi để hộp thoại chuyển sang trạng thái lỗi.
  final Future<void> Function() onConfirm;

  /// Gọi NGAY khi xóa thành công (trước khi hộp thoại đóng) → màn hình phía sau
  /// dọn danh sách cục bộ, khi hộp thoại đóng thì trạng thái trống đã sẵn sàng.
  final VoidCallback? onCleared;

  final String title;
  final String bodyText;
  final String buttonText;

  const ClearAllDialog({
    super.key,
    required this.count,
    required this.onConfirm,
    this.onCleared,
    this.title = 'Xóa tất cả thông báo?',
    this.bodyText = 'Toàn bộ lịch sử thông báo sẽ bị xóa khỏi tài khoản của bạn.\nHành động này không thể hoàn tác.',
    this.buttonText = 'Xóa tất cả',
  });

  /// Trả về true nếu đã xóa xong, false/null nếu người dùng hủy.
  static Future<bool?> show(
    BuildContext context, {
    required int count,
    required Future<void> Function() onConfirm,
    VoidCallback? onCleared,
    String title = 'Xóa tất cả thông báo?',
    String bodyText = 'Toàn bộ lịch sử thông báo sẽ bị xóa khỏi tài khoản của bạn.\nHành động này không thể hoàn tác.',
    String buttonText = 'Xóa tất cả',
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => ClearAllDialog(
        count: count,
        onConfirm: onConfirm,
        onCleared: onCleared,
        title: title,
        bodyText: bodyText,
        buttonText: buttonText,
      ),
    );
  }

  @override
  State<ClearAllDialog> createState() => _ClearAllDialogState();
}

class _ClearAllDialogState extends State<ClearAllDialog>
    with TickerProviderStateMixin {
  _Phase _phase = _Phase.confirm;
  String _error = '';
  bool _closed = false;
  Timer? _autoClose;

  // Hai controller riêng, mỗi cái chỉ chạy đúng lúc cần
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();
  late final AnimationController _success = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  @override
  void dispose() {
    _autoClose?.cancel();
    _intro.dispose();
    _success.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // LOGIC
  // ---------------------------------------------------------------------
  Future<void> _run() async {
    HapticFeedback.mediumImpact();
    setState(() => _phase = _Phase.deleting);
    try {
      // Tối thiểu 400ms ở trạng thái "đang xóa" để không bị chớp khi mạng quá nhanh
      await Future.wait([
        widget.onConfirm(),
        Future<void>.delayed(const Duration(milliseconds: 400)),
      ]);
      if (!mounted) return;

      setState(() => _phase = _Phase.success);
      _success.forward(from: 0);
      HapticFeedback.lightImpact();
      widget.onCleared?.call();

      _autoClose = Timer(const Duration(milliseconds: 1300), () => _close(true));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendly(e);
        _phase = _Phase.error;
      });
    }
  }

  void _close(bool result) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  String _friendly(Object e) {
    final m = e.toString();
    if (m.contains('SocketException') ||
        m.contains('ClientException') ||
        m.contains('Không có kết nối') ||
        m.contains('Internet')) {
      return 'Không có kết nối mạng. Vui lòng kiểm tra Internet rồi thử lại.';
    }
    if (e is TimeoutException || m.contains('timeout')) {
      return 'Máy chủ phản hồi quá lâu. Vui lòng thử lại.';
    }
    return 'Không thể xóa tất cả thông báo. Vui lòng thử lại.';
  }

  // ---------------------------------------------------------------------
  // MÀU (đồng bộ với MarkAllReadDialog: nền trung tính, màu nhấn dịu ở dark)
  // ---------------------------------------------------------------------
  static Color _tone(Color base, bool isDark) {
    if (!isDark) return base;
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness(hsl.lightness < 0.62 ? 0.64 : hsl.lightness)
        .withSaturation(hsl.saturation.clamp(0.4, 0.8))
        .toColor();
  }

  static Color _deeper(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - 0.12).clamp(0.2, 0.9)).toColor();
  }

  static Color _on(Color c) =>
      ThemeData.estimateBrightnessForColor(c) == Brightness.dark
          ? Colors.white
          : const Color(0xFF111111);

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = _Palette(
      isDark: isDark,
      danger: _tone(const Color(0xFFE5484D), isDark),
      success: _tone(const Color(0xFF2E9E5B), isDark),
    );

    final accent = _phase == _Phase.success ? p.success : p.danger;

    return PopScope(
      // Đang xóa: chặn thoát. Thành công: back = đóng luôn (kết quả vẫn là true).
      canPop: _phase == _Phase.confirm || _phase == _Phase.error,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase == _Phase.success) _close(true);
      },
      child: Dialog(
        backgroundColor: p.dialogBg,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        elevation: isDark ? 0 : 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
          ),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [accent.withValues(alpha: isDark ? 0.16 : 0.09), p.dialogBg],
              stops: const [0.0, 0.5],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              // Chỉ giữ phần tử mới → AnimatedSize đổi chiều cao mượt, không "phồng rồi co"
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [if (current != null) current],
              ),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey<_Phase>(_phase),
                child: _content(p),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(_Palette p) {
    switch (_phase) {
      case _Phase.confirm:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _dangerIcon(p, animate: true)),
            const SizedBox(height: 22),
            _title(p, widget.title),
            const SizedBox(height: 10),
            _body(p, widget.bodyText),
            if (widget.count > 0) ...[
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: p.danger.withValues(alpha: p.isDark ? 0.14 : 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_forever_rounded, size: 16, color: p.danger),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.count} thông báo sẽ bị xóa',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: p.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _tonalButton(p, 'Hủy', () => _close(false)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: _dangerButton(p, widget.buttonText, Icons.delete_rounded, _run),
                ),
              ],
            ),
          ],
        );

      case _Phase.deleting:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _dangerIcon(p, busy: true)),
            const SizedBox(height: 22),
            _title(p, 'Đang xóa...'),
            const SizedBox(height: 10),
            _body(p, 'Vui lòng đợi trong giây lát.'),
            const SizedBox(height: 14),
          ],
        );

      case _Phase.success:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SizedBox(
                width: 120,
                height: 120,
                // RepaintBoundary + repaint: controller → chỉ vùng này vẽ lại mỗi frame
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SuccessPainter(
                      t: _success,
                      color: p.success,
                      onColor: _on(p.success),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _title(p, 'Đã xóa xong'),
            const SizedBox(height: 10),
            _body(
              p,
              widget.count > 0
                  ? '${widget.count} thông báo đã được xóa.'
                  : 'Lịch sử thông báo đã được dọn sạch.',
            ),
            const SizedBox(height: 14),
          ],
        );

      case _Phase.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _dangerIcon(p, icon: Icons.error_outline_rounded)),
            const SizedBox(height: 22),
            _title(p, 'Xóa không thành công'),
            const SizedBox(height: 10),
            _body(p, _error),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _tonalButton(p, 'Đóng', () => _close(false)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: _dangerButton(p, 'Thử lại', Icons.refresh_rounded, _run),
                ),
              ],
            ),
          ],
        );
    }
  }

  // ---------------------------------------------------------------------
  // THÀNH PHẦN
  // ---------------------------------------------------------------------
  Widget _dangerIcon(
    _Palette p, {
    bool animate = false,
    bool busy = false,
    IconData icon = Icons.delete_sweep_rounded,
  }) {
    final onDanger = _on(p.danger);

    final Widget glyph = busy
        ? SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 3, color: onDanger),
          )
        : (animate
            // Lắc nhẹ biểu tượng sau khi hiện (chỉ icon xoay, không vẽ lại vòng tròn)
            ? AnimatedBuilder(
                animation: _intro,
                child: Icon(icon, size: 34, color: onDanger),
                builder: (_, child) {
                  final t = ((_intro.value - 0.5) / 0.5).clamp(0.0, 1.0);
                  final wobble = math.sin(t * math.pi * 3) * 0.16 * (1 - t);
                  return Transform.rotate(angle: wobble, child: child);
                },
              )
            : Icon(icon, size: 34, color: onDanger));

    final circle = Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.danger, _deeper(p.danger)],
        ),
        boxShadow: [
          BoxShadow(
            color: p.danger.withValues(alpha: p.isDark ? 0.40 : 0.35),
            blurRadius: 24,
            spreadRadius: 1,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: glyph,
    );

    if (!animate) return circle;

    // Hiện ra dạng "nảy" khi mở hộp thoại
    return AnimatedBuilder(
      animation: _intro,
      child: circle,
      builder: (_, child) => Transform.scale(
        scale: Curves.easeOutBack.transform((_intro.value / 0.5).clamp(0.0, 1.0)),
        child: child,
      ),
    );
  }

  Widget _title(_Palette p, String text) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: p.title,
        ),
      );

  Widget _body(_Palette p, String text) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, height: 1.5, color: p.body),
      );

  Widget _tonalButton(_Palette p, String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: p.tonalBg,
        foregroundColor: p.tonalFg,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _dangerButton(
    _Palette p,
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) {
    final on = _on(p.danger);
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: on),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: on),
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        backgroundColor: p.danger,
        foregroundColor: on,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _Palette {
  final bool isDark;
  final Color danger;
  final Color success;

  _Palette({required this.isDark, required this.danger, required this.success});

  // Nền trung tính, khớp Colors.grey[850]/[900] của màn hình, không ngả xanh
  Color get dialogBg => isDark ? const Color(0xFF262626) : Colors.white;
  Color get title => isDark ? const Color(0xFFF5F5F5) : const Color(0xFF111827);
  Color get body => isDark ? const Color(0xFFA3A3A3) : const Color(0xFF6B7280);
  Color get tonalBg =>
      isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF3F4F6);
  Color get tonalFg => isDark ? const Color(0xFFE5E5E5) : const Color(0xFF374151);
}

// =====================================================================
// HIỆU ỨNG THÀNH CÔNG: vòng lan tỏa + chấm + vòng tròn bật ra + tick vẽ dần
// Vẽ trực tiếp trên Canvas, lắng nghe controller qua `repaint` → không rebuild widget.
// =====================================================================
class _SuccessPainter extends CustomPainter {
  final Animation<double> t;
  final Color color;
  final Color onColor;

  _SuccessPainter({required this.t, required this.color, required this.onColor})
      : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final c = size.center(Offset.zero);
    final maxR = size.width / 2;
    final r = maxR * 0.6; // bán kính vòng tròn chính (~72px)

    // 1) Vòng lan tỏa mờ dần
    final ringT = Curves.easeOut.transform((v / 0.75).clamp(0.0, 1.0));
    canvas.drawCircle(
      c,
      r + (maxR - r) * ringT,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: (1 - ringT) * 0.5),
    );

    // 2) Tám chấm bắn ra
    final dotPaint = Paint()..color = color.withValues(alpha: 1 - ringT);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + math.pi / 8;
      final d = r + 4 + (maxR - r - 8) * ringT;
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * d,
        3.2 * (1 - ringT) + 0.6,
        dotPaint,
      );
    }

    // 3) Vòng tròn chính bật ra (nảy nhẹ)
    final circleT = Curves.easeOutBack.transform((v / 0.4).clamp(0.0, 1.0));
    canvas.drawCircle(c, r * circleT, Paint()..color = color);

    // 4) Dấu tick vẽ dần
    final tickT = Curves.easeOutCubic.transform(((v - 0.3) / 0.45).clamp(0.0, 1.0));
    if (tickT > 0) {
      final path = Path()
        ..moveTo(c.dx - r * 0.34, c.dy + r * 0.02)
        ..lineTo(c.dx - r * 0.08, c.dy + r * 0.28)
        ..lineTo(c.dx + r * 0.36, c.dy - r * 0.22);
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * tickT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.16
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = onColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SuccessPainter old) =>
      old.color != color || old.onColor != onColor;
}

// =====================================================================
// Bọc trạng thái trống: hiện dần + phóng nhẹ, để danh sách vừa xóa xong
// chuyển sang "Không có thông báo" thật mượt (tắt khi bật "giảm chuyển động").
// =====================================================================
class FadeScaleIn extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final double beginScale;

  const FadeScaleIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 420),
    this.beginScale = 0.94,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.scale(scale: beginScale + (1 - beginScale) * v, child: child),
      ),
    );
  }
}