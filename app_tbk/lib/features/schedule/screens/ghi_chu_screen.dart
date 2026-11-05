import 'package:app_tbk/models/class_schedule.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/ghi_chu_service.dart';

/// Trang soạn ghi chú cho 1 buổi học.
/// Trả về nội dung đã lưu (String) khi đóng, để sheet chi tiết cập nhật lại.
class GhiChuScreen extends StatefulWidget {
  final LopHoc lop;

  /// Nếu đã có nội dung từ sheet thì truyền vào để khỏi tải lại / khỏi nháy.
  final String? noiDungBanDau;

  const GhiChuScreen({super.key, required this.lop, this.noiDungBanDau});

  @override
  State<GhiChuScreen> createState() => _GhiChuScreenState();
}

class _GhiChuScreenState extends State<GhiChuScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  bool _dangTai = false;
  bool _loiTai = false;
  bool _dangLuu = false;
  String? _loiLuu;
  String _noiDungGoc = '';
  DateTime? _luuLuc;

  // Dùng ValueNotifier để chỉ rebuild thanh trạng thái, không rebuild TextField.
  final _doDai = ValueNotifier<int>(0);
  final _chuaLuuN = ValueNotifier<bool>(false);

  bool get _chuaLuu => _ctrl.text.trim() != _noiDungGoc;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      _doDai.value = _ctrl.text.characters.length;
      _chuaLuuN.value = _chuaLuu;
    });
    if (widget.noiDungBanDau != null) {
      _noiDungGoc = widget.noiDungBanDau!;
      _ctrl.text = _noiDungGoc;
      // Trì hoãn 250ms chờ animation mở trang hoàn tất rồi mới gọi API ngầm
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        GhiChuService.layGhiChu(widget.lop).then((g) {
          if (mounted && g?.capNhatLuc != null) {
            setState(() {
              _luuLuc = g!.capNhatLuc;
            });
          }
        });
      });
    } else {
      // Trì hoãn 250ms cho animation chuyển cảnh mượt mà
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _tai();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _doDai.dispose();
    _chuaLuuN.dispose();
    super.dispose();
  }

  Future<void> _tai() async {
    setState(() {
      _dangTai = true;
      _loiTai = false;
    });
    try {
      final g = await GhiChuService.layGhiChu(widget.lop);
      if (!mounted) return;
      setState(() {
        _dangTai = false;
        _noiDungGoc = g?.noiDung ?? '';
        _luuLuc = g?.capNhatLuc;
        _ctrl.text = _noiDungGoc;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dangTai = false;
        _loiTai = true;
      });
    }
  }

  Future<bool> _luu() async {
    if (_dangLuu) return false;
    FocusScope.of(context).unfocus();
    setState(() {
      _dangLuu = true;
      _loiLuu = null;
    });
    try {
      final nd = _ctrl.text.trim();
      await GhiChuService.luuGhiChu(widget.lop, nd);
      if (!mounted) return true;
      setState(() {
        _dangLuu = false;
        _noiDungGoc = nd;
        _luuLuc = DateTime.now();
      });
      _chuaLuuN.value = _chuaLuu;
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _dangLuu = false;
        _loiLuu = 'Chưa lưu được — kiểm tra kết nối rồi thử lại.';
      });
      return false;
    }
  }

  Future<String?> _hienHopThoaiChuaLuu() {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final toi = theme.brightness == Brightness.dark;
        final amber = Colors.amber.shade700;

        return Dialog(
          backgroundColor: toi ? const Color(0xFF1E293B) : Colors.white,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: amber.withValues(alpha: 0.15),
                  ),
                  child: Icon(Icons.edit_note_rounded, size: 36, color: amber),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Chưa lưu ghi chú',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bạn có thay đổi chưa được lưu.\nLưu lại trước khi thoát nhé?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                // Hành động chính
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'luu'),
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text('Lưu và thoát',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Hành động phụ
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, 'o'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            side: BorderSide(
                                color: theme.dividerColor.withValues(alpha: 0.8)),
                          ),
                          child: const Text('Ở lại'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, 'bo'),
                          style: TextButton.styleFrom(
                            foregroundColor: cs.error,
                            backgroundColor: cs.error.withValues(alpha: 0.10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Bỏ thay đổi'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _xuLyThoat() async {
    if (!_chuaLuu) {
      Navigator.of(context).pop(_noiDungGoc);
      return;
    }
    FocusScope.of(context).unfocus();
    final chon = await _hienHopThoaiChuaLuu();
    if (!mounted) return;
    if (chon == 'bo') {
      Navigator.of(context).pop(_noiDungGoc);
    } else if (chon == 'luu') {
      if (await _luu() && mounted) Navigator.of(context).pop(_noiDungGoc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final toi = theme.brightness == Brightness.dark;
    final lop = widget.lop;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _xuLyThoat();
      },
      child: Scaffold(
        backgroundColor: toi ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        appBar: AppBar(
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          backgroundColor: toi ? const Color(0xFF1E293B) : Colors.white,
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ghi chú buổi học',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              Text(
                '${lop.tenMon} • ${DateFormat('dd/MM').format(lop.ngayBd)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            ValueListenableBuilder<bool>(
              valueListenable: _chuaLuuN,
              builder: (_, chuaLuu, __) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton(
                  onPressed: (!chuaLuu || _dangLuu || _dangTai) ? null : _luu,
                  child: _dangLuu
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text('Lưu'),
                ),
              ),
            ),
          ],
        ),
        // Scaffold tự co body theo bàn phím → không cần tự tính viewInsets.
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_loiTai)
                MaterialBanner(
                  backgroundColor: cs.errorContainer,
                  content: const Text('Chưa tải được ghi chú từ máy chủ.'),
                  leading: Icon(Icons.cloud_off_outlined, color: cs.error),
                  actions: [TextButton(onPressed: _tai, child: const Text('Thử lại'))],
                ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  decoration: BoxDecoration(
                    color: toi ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
                  ),
                  child: _dangTai
                      ? const Center(child: CircularProgressIndicator())
                      : TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(fontSize: 16, height: 1.5),
                    decoration: InputDecoration(
                      hintText: 'Ghi lại nội dung cần nhớ của buổi học này…',
                      hintStyle: TextStyle(color: cs.onSurfaceVariant),
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                  ),
                ),
              ),
              // Thanh trạng thái — nằm trong body nên tự trượt lên trên bàn phím
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Row(
                  children: [
                    Expanded(child: _trangThai(theme)),
                    ValueListenableBuilder<int>(
                      valueListenable: _doDai,
                      builder: (_, n, __) => Text('$n ký tự',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trangThai(ThemeData theme) {
    final cs = theme.colorScheme;
    if (_loiLuu != null) {
      return Text(_loiLuu!, style: TextStyle(fontSize: 12.5, color: cs.error));
    }
    return ValueListenableBuilder<bool>(
      valueListenable: _chuaLuuN,
      builder: (_, chuaLuu, __) {
        final timeText = _luuLuc != null 
            ? ' • Lần cuối: ${DateFormat('HH:mm').format(_luuLuc!)}' 
            : '';

        if (_dangLuu) {
          return Text('Đang lưu…$timeText', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant));
        }
        if (chuaLuu) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Chưa lưu',
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.amber.shade700)),
              if (_luuLuc != null)
                Text(timeText, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ],
          );
        }
        if (_luuLuc != null) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 14, color: Colors.green),
              const SizedBox(width: 4),
              Text('Đã lưu ${DateFormat('HH:mm').format(_luuLuc!)}',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}