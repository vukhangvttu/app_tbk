import 'dart:async';
import 'dart:io';

import 'package:app_tbk/config/academic_config.dart';
import 'package:app_tbk/core/errors/exceptions.dart';
import 'package:app_tbk/models/class_schedule.dart';
import 'package:app_tbk/services/next_class_widget_service.dart';
import 'package:app_tbk/services/notification_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../services/api_service.dart';
import '../../auth/services/auth_service.dart';
import '../../auth/services/post_login_initializer.dart';
import '../services/ghi_chu_service.dart';
import 'ghi_chu_screen.dart';

// ═════════════════════════════════════════════════════════════════════════
// Hằng số & helper dùng chung (top-level để không tạo lại mỗi lần build)
// ═════════════════════════════════════════════════════════════════════════

const _thuVi = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
const _thuDayDu = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ nhật'];

// Chuẩn màu navy/slate của app
const _mauNenToi = Color(0xFF0F172A);
const _mauTheToi = Color(0xFF1E293B);
const _mauNenSang = Color(0xFFF8FAFC);

// DateFormat khá tốn kém khi khởi tạo → tạo 1 lần
final _fNgayDayDu = DateFormat('dd/MM/yyyy');
final _fNgayThang = DateFormat('dd/MM');

DateTime _ngay(DateTime d) => DateTime(d.year, d.month, d.day);

bool _laToi(ThemeData t) => t.brightness == Brightness.dark;

/// Số ngày còn lại tới ngày thi (âm = đã thi).
int _soNgayTu(DateTime ngayThi, DateTime homNay) => _ngay(ngayThi).difference(homNay).inDays;

String _nhanDemNguoc(int n) {
  if (n < 0) return 'Đã thi';
  if (n == 0) return 'Hôm nay thi!';
  if (n == 1) return 'Ngày mai thi';
  return 'Còn $n ngày';
}

Color _mauDemNguoc(int n, ThemeData theme) {
  if (n < 0) return theme.colorScheme.onSurfaceVariant;
  if (n == 0) return Colors.red;
  if (n <= 1) return Colors.deepOrange;
  if (n <= 3) return Colors.orange;
  if (n <= 7) return Colors.amber.shade700;
  return theme.colorScheme.primary;
}

BoxShadow _bongThe(ThemeData theme, {double blur = 12}) => BoxShadow(
  color: Colors.black.withValues(alpha: _laToi(theme) ? 0.2 : 0.1),
  blurRadius: blur,
  offset: const Offset(0, 4),
);

Widget _shimmerDong(ThemeData theme) {
  final toi = _laToi(theme);
  return Shimmer.fromColors(
    baseColor: toi ? Colors.grey[700]! : Colors.grey[300]!,
    highlightColor: toi ? Colors.grey[600]! : Colors.grey[100]!,
    child: Column(
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            height: 14,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
          ),
      ],
    ),
  );
}

/// Chế độ xem lịch:
/// - ngay: lịch ngày đang chọn
/// - tuan: cả tuần theo lịch (khi calendar ở dạng tuần)
/// - tuanHoc: tuần học theo học kỳ (chọn bằng dropdown)
enum _CheDo { ngay, tuan, tuanHoc }

// ───────────── Mục của danh sách lịch thi (đã tính sẵn, không tính lại khi cuộn) ─────────────

sealed class _MucThi {
  const _MucThi();
}

class _MucBanner extends _MucThi {
  final LopHoc lop;
  final int soNgay;
  const _MucBanner(this.lop, this.soNgay);
}

class _MucTieuDe extends _MucThi {
  final String nhan;
  final int soLuong;
  final IconData icon;
  final bool coKhoangTren;
  const _MucTieuDe(this.nhan, this.soLuong, this.icon, {this.coKhoangTren = false});
}

class _MucThe extends _MucThi {
  final LopHoc lop;
  final int soNgay;
  const _MucThe(this.lop, this.soNgay);
}

// ═════════════════════════════════════════════════════════════════════════
// Widget nhỏ dùng lại (StatelessWidget → Flutter bỏ qua rebuild khi props không đổi)
// ═════════════════════════════════════════════════════════════════════════

class _ChipThongTin extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool coGian;

  const _ChipThongTin({required this.icon, required this.text, this.coGian = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: _laToi(theme) ? 0.55 : 0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge "Còn X ngày".
class _BadgeDemNguoc extends StatelessWidget {
  final int soNgay;
  const _BadgeDemNguoc(this.soNgay);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mauChu = _mauDemNguoc(soNgay, theme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: mauChu.withValues(alpha: _laToi(theme) ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: mauChu.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(soNgay < 0 ? Icons.check_circle_outline : Icons.timer_outlined, size: 13, color: mauChu),
          const SizedBox(width: 4),
          Text(
            _nhanDemNguoc(soNgay),
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: mauChu),
          ),
        ],
      ),
    );
  }
}

class _TieuDeNhom extends StatelessWidget {
  final _MucTieuDe muc;
  const _TieuDeNhom(this.muc);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: muc.coKhoangTren ? 8 : 0, bottom: 10, left: 2),
      child: Row(
        children: [
          Icon(muc.icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(muc.nhan,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: _laToi(theme) ? 0.6 : 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('${muc.soLuong}',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// Banner môn thi gần nhất.
class _BannerThi extends StatelessWidget {
  final LopHoc lop;
  final int soNgay;
  final VoidCallback onTap;

  const _BannerThi({required this.lop, required this.soNgay, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = soNgay;
    final mau = _mauDemNguoc(n, theme);
    final toi = _laToi(theme);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  mau.withValues(alpha: toi ? 0.30 : 0.16),
                  mau.withValues(alpha: toi ? 0.12 : 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: mau.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Container(
                  width: 76,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: mau.withValues(alpha: toi ? 0.3 : 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        n == 0 ? '🎉' : '$n',
                        style: TextStyle(
                            fontSize: n == 0 ? 28 : 34, fontWeight: FontWeight.w800, color: mau, height: 1),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        n == 0 ? 'hôm nay' : 'ngày nữa',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: mau),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MÔN THI GẦN NHẤT',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text(lop.tenMon,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                              height: 1.25,
                              color: theme.textTheme.titleLarge?.color)),
                      const SizedBox(height: 4),
                      Text('${_fNgayDayDu.format(lop.ngayBd)} • ${lop.gioBd} • ${lop.tenPhong}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: mau.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thẻ môn thi.
///
/// Tối ưu so với bản cũ (nguyên nhân giật khi cuộn):
/// - Bỏ `IntrinsicHeight` (buộc layout 2 lượt cho mỗi thẻ) → dùng Stack + Positioned cho thanh màu.
/// - Bỏ `Opacity` (tạo saveLayer tốn GPU) → làm mờ bằng alpha của từng màu.
/// - Bỏ `Clip.antiAlias` → bo góc trực tiếp trên từng phần tử con.
/// - Được bọc `RepaintBoundary` ở ngoài để cuộn chỉ ghép layer đã vẽ sẵn.

class _TheThi extends StatelessWidget {
  final LopHoc lop;
  final int soNgay;
  final VoidCallback onTap;

  const _TheThi({required this.lop, required this.soNgay, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toi = _laToi(theme);
    final xong = soNgay < 0;
    final mauMon = lop.mauSac;
    final ngay = lop.ngayBd;
    final nenThe = toi ? _mauTheToi : Colors.white;
    final mauTieuDe = theme.textTheme.titleLarge?.color;
    final mauChuChinh = xong ? mauTieuDe?.withValues(alpha: 0.6) : mauTieuDe;
    final mauNhan = xong ? mauMon.withValues(alpha: 0.6) : mauMon;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(mauMon.withValues(alpha: toi ? 0.10 : 0.05), nenThe),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: mauMon.withValues(alpha: xong ? 0.22 : 0.4), width: 1.2),
        boxShadow: [_bongThe(theme, blur: 8)],
      ),
      child: Material(
        color: Colors.transparent,
        // Cắt nội dung theo đúng bo góc bên trong viền (20 - 1.2) → thanh màu & header sát viền
        borderRadius: BorderRadius.circular(18.8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18.8),
          splashColor: mauMon.withValues(alpha: 0.1),
          highlightColor: mauMon.withValues(alpha: 0.05),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              // Thanh nhấn màu môn bên trái: đang tắt
              // Positioned(
              //   left: 0,
              //   top: 0,
              //   bottom: 0,
              //   width: 5,
              //   child: ColoredBox(color: mauNhan),
              // ),
              Padding(
                padding: EdgeInsets.zero, // trước đây chừa 5px cho thanh màu
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dải header: ngày thi + badge đếm ngược
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                      color: mauMon.withValues(alpha: toi ? 0.2 : 0.09),
                      child: Row(
                        children: [
                          Icon(Icons.event_rounded, size: 16, color: mauNhan),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${_thuDayDu[ngay.weekday - 1]}, ${_fNgayDayDu.format(ngay)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: mauNhan),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _BadgeDemNguoc(soNgay),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Thi ${lop.tenMon}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              height: 1.25,
                              decoration: xong ? TextDecoration.lineThrough : null,
                              color: mauChuChinh,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _ChipThongTin(icon: Icons.access_time_rounded, text: '${lop.gioBd} - ${lop.gioKt}'),
                              const SizedBox(width: 8),
                              Flexible(
                                child: _ChipThongTin(icon: Icons.room_rounded, text: lop.tenPhong, coGian: true),
                              ),
                            ],
                          ),
                        ],
                      ),
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
}
// ═════════════════════════════════════════════════════════════════════════
// Màn hình chính
// ═════════════════════════════════════════════════════════════════════════

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({Key? key}) : super(key: key);

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> with SingleTickerProviderStateMixin {
  static const _soTuan = 25;
  static const _loiMang = 'Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.';

  late final TabController _tabController;

  // Dữ liệu
  List<LopHoc> lichHoc = [];
  List<LopHoc> lichThi = [];
  Map<DateTime, List<LopHoc>> suKien = {};

  /// Danh sách lịch thi đã sắp xếp + nhóm sẵn (tính 1 lần khi có dữ liệu, KHÔNG tính trong build)
  List<_MucThi> _mucThi = const [];
  DateTime _homNayThi = _ngay(DateTime.now());

  // Trạng thái tải
  bool dangTai = false; // dùng cho UI
  bool _fetching = false; // chặn gọi trùng, không gây rebuild
  bool _daTai = false; // đã có dữ liệu ít nhất 1 lần
  String loi = '';
  int demNguoc = 0;

  // Trạng thái hiển thị
  bool laHoc = true;
  _CheDo cheDo = _CheDo.ngay;
  CalendarFormat dinhDangLich = CalendarFormat.week;
  DateTime ngayTapTrung = DateTime.now();
  DateTime? ngayDuocChon;
  int tuanHocHienTai = 1;
  int tuanDuocChon = 1;

  // ───────────── Ngày tháng ─────────────

  static DateTime _congNgay(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  static DateTime _dauTuan(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

  DateTime get _ngayDau => DateTime(AcademicConfig.ngayBatDauHocKy.year, 1, 1);
  DateTime get _ngayCuoi => DateTime(AcademicConfig.ngayBatDauHocKy.year + 1, 12, 31);

  /// Thứ Hai đầu tiên của học kỳ (đầu Tuần 1)
  DateTime get _thuHaiDauTien => _dauTuan(AcademicConfig.ngayBatDauHocKy);

  DateTime _dauTuanHoc(int tuan) => _congNgay(_thuHaiDauTien, (tuan - 1) * 7);

  void _tinhTuanHienTai() {
    final soNgay = _ngay(DateTime.now()).difference(_thuHaiDauTien).inDays;
    tuanHocHienTai = ((soNgay / 7).floor() + 1).clamp(1, _soTuan).toInt();
  }

  DateTime _phanTichNgay(String? s) {
    if (s == null || s.isEmpty) return DateTime.now();
    try {
      return _ngay(DateTime.parse(s).toLocal());
    } catch (e) {
      debugPrint('Lỗi parse ngày: $e');
      return DateTime.now();
    }
  }

  // ───────────── Màu theo theme ─────────────

  Color _mauNen(ThemeData theme) => _laToi(theme) ? _mauNenToi : _mauNenSang;
  Color _mauThe(ThemeData theme) => _laToi(theme) ? _mauTheToi : Colors.white;

  // ───────────── Vòng đời ─────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    ngayDuocChon = ngayTapTrung;
    _tinhTuanHienTai();
    tuanDuocChon = tuanHocHienTai;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PostLoginInitializer.ensureInitialized(context);
    });
    taiDuLieu();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ───────────── Tải dữ liệu ─────────────

  LopHoc _taoLop(dynamic json) => LopHoc(
    tenMon: json['TENMON'] ?? '',
    thu: json['THU'] ?? 2,
    gioBd: json['GIOBD'] ?? '',
    gioKt: json['GIOKT'] ?? '',
    hoTen: json['HOTEN'] ?? '',
    tenPhong: json['TENPHONG'] ?? '',
    maNhom: json['manhom'] ?? 0,
    tenNhom: json['tennhom'] ?? '',
    soTiet: json['SOTIET'] ?? 0,
    phanBo: json['PHANBO'] ?? '',
    ngayBd: _phanTichNgay(json['NGAYBD']),
    ngayKt: _phanTichNgay(json['NGAYKT']),
    nhomThi: json['NHOMTHI'] ?? false,
    thoiGianGiaiLao: json['THOIGIAN_GIAILAO'] ?? '',
    noiDungBaiHoc: (json['NOIDUNG_BAIHOC'] as String?)?.trim() ?? '',
  );

  void _capNhatSuKien() {
    suKien = {};
    for (final lop in laHoc ? lichHoc : lichThi) {
      suKien.putIfAbsent(_ngay(lop.ngayBd), () => []).add(lop);
    }
  }

  /// Sắp xếp + chia nhóm lịch thi MỘT LẦN, lưu vào [_mucThi].
  /// Trước đây việc này chạy lại trong mỗi lần build → giật khi cuộn / rebuild.
  void _capNhatLichThi() {
    final homNay = _ngay(DateTime.now());
    _homNayThi = homNay;

    final ds = [...lichThi]..sort((a, b) {
      final c = _ngay(a.ngayBd).compareTo(_ngay(b.ngayBd));
      return c != 0 ? c : a.gioBd.compareTo(b.gioBd);
    });

    final sapThi = <_MucThe>[];
    final daThi = <_MucThe>[];
    for (final l in ds) {
      final n = _soNgayTu(l.ngayBd, homNay);
      (n >= 0 ? sapThi : daThi).add(_MucThe(l, n));
    }

    _mucThi = [
      if (sapThi.isNotEmpty) _MucBanner(sapThi.first.lop, sapThi.first.soNgay),
      if (sapThi.isNotEmpty) ...[
        _MucTieuDe('Sắp thi', sapThi.length, Icons.upcoming_outlined),
        ...sapThi,
      ],
      if (daThi.isNotEmpty) ...[
        _MucTieuDe('Đã thi', daThi.length, Icons.check_circle_outline, coKhoangTren: sapThi.isNotEmpty),
        ...daThi,
      ],
    ];
  }

  /// [refresh]: bắt buộc tải lại. [silent]: gọi từ kéo-để-làm-mới →
  /// không setState lúc bắt đầu (RefreshIndicator đã có spinner riêng) nên không bị giật.
  Future<void> taiDuLieu({bool refresh = false, bool silent = false}) async {
    if (!mounted || _fetching || (_daTai && !refresh)) return;
    _fetching = true;
    if (!silent) {
      setState(() {
        dangTai = true;
        loi = '';
      });
    }

    try {
      // Giữ tối thiểu 400ms khi kéo làm mới để animation thả tay lắng xuống
      final minWait = silent ? Future<void>.delayed(const Duration(milliseconds: 400)) : Future<void>.value();

      await AcademicConfig.fetchAcademicTerm();
      final id = (await AuthService.getIdSinhVien())?.toString();
      if (id == null || id.isEmpty) throw Exception('Không tìm thấy thông tin sinh viên');

      final List<dynamic> data = await ApiService.getThoiKhoaBieu(
        idSinhVien: id,
        hocKy: AcademicConfig.hocKy,
        namHoc: AcademicConfig.namHoc,
      );
      final tatCa = data.map(_taoLop).toList();

      await minWait;
      if (!mounted) return;

      final lanDau = !_daTai;
      setState(() {
        lichHoc = tatCa;
        lichThi = tatCa.where((l) => l.nhomThi).toList();
        _tinhTuanHienTai();
        // Chỉ đặt lại ngày/tuần ở lần tải đầu, tránh nhảy vị trí khi làm mới
        if (lanDau) {
          tuanDuocChon = tuanHocHienTai;
          ngayTapTrung = DateTime.now();
          ngayDuocChon = ngayTapTrung;
        }
        _capNhatSuKien();
        _capNhatLichThi();
        dangTai = false;
        _daTai = true;
        loi = '';
      });
      NextClassWidgetService.capNhat(lichHoc);
      if (silent) await WidgetsBinding.instance.endOfFrame;
    } catch (e) {
      await _xuLyLoi(e);
    } finally {
      _fetching = false;
    }
  }

  Future<void> _xuLyLoi(Object e) async {
    final msg = e.toString();

    if (e is UnauthorizedException) {
      await _baoLoi('Phiên đăng nhập đã hết hạn');
      return _veDangNhap();
    }
    if (e is TimeoutException) {
      await _baoLoi('Máy chủ phản hồi quá lâu. Vui lòng thử lại sau.');
      if (!_daTai) _demNguocTaiLai();
      return;
    }
    if (e is SocketException ||
        e is NoInternetException ||
        msg.contains('Không có kết nối') ||
        msg.contains('SocketException') ||
        msg.contains('ClientException')) {
      return _baoLoi(_loiMang);
    }
    if (msg.contains('Không tìm thấy token') || msg.contains('hết hạn')) {
      await _baoLoi('Vui lòng đăng nhập lại');
      return _veDangNhap();
    }
    if (msg.contains('401')) {
      await _baoLoi('Không có quyền truy cập');
      return _veDangNhap();
    }
    if (msg.contains('404')) return _baoLoi('Không tìm thấy dữ liệu');
    if (msg.contains('500')) return _baoLoi('Lỗi máy chủ');
    return _baoLoi(msg.replaceAll('Exception: ', ''));
  }

  /// Đã có dữ liệu → giữ nguyên danh sách, chỉ báo lỗi bằng snackbar.
  Future<void> _baoLoi(String msg) async {
    if (!mounted) return;
    setState(() {
      loi = _daTai ? '' : msg;
      dangTai = false;
    });
    if (_daTai) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _veDangNhap() async {
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) Navigator.of(context).pushReplacementNamed('/login');
  }

  Future<void> _demNguocTaiLai() async {
    for (var i = 5; i > 0; i--) {
      if (!mounted) return;
      setState(() => demNguoc = i);
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    setState(() => demNguoc = 0);
    await taiDuLieu();
  }

  // Đang tắt: bật khi muốn nhắc lịch học/thi hằng ngày.
  // ignore: unused_element
  Future<void> _xuLyThongBao() async {
    final idSinhVien = int.tryParse((await AuthService.getIdSinhVien()).toString()) ?? 0;
    if (idSinhVien == 0) return;

    final homNay = DateTime.now();
    final ngayStr = '${homNay.day}/${homNay.month}/${homNay.year}';
    bool coLich(List<LopHoc> ds, bool thi) => ds.any((l) =>
    l.ngayBd.isBefore(homNay.add(const Duration(days: 1))) &&
        l.ngayKt.isAfter(homNay.subtract(const Duration(days: 1))) &&
        l.nhomThi == thi);

    Future<void> nhac(int id, String tieuDe, String noiDung, String loai) async {
      final dichVu = NotificationService();
      await dichVu.showAndSaveNotification(
          idSinhVien: idSinhVien, title: tieuDe, body: noiDung, loaiLich: loai);
      await dichVu.scheduleDailyNotification(
          id: id, title: tieuDe, body: noiDung, loaiLich: loai, hour: 8, minute: 55);
    }

    if (coLich(lichHoc, false)) {
      await nhac(1, '📘 Lịch học hôm nay', 'Nhắc nhở: Bạn có lịch học hôm nay ($ngayStr).', 'LICH_HOC');
    }
    if (coLich(lichThi, true)) {
      await nhac(2, '🧾 Lịch thi hôm nay', 'Nhắc nhở: Bạn có lịch thi hôm nay ($ngayStr).', 'LICH_THI');
    }
  }

  // ───────────── Ghim widget ra màn hình chính ─────────────

  Future<void> _ghimWidget() async {
    void bao(String s) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }

    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported();
      if (supported != true) {
        bao('Thiết bị không hỗ trợ ghim widget');
        return;
      }

      // 1. Thử gọi Native MethodChannel (tối ưu với PendingIntent callback cho ColorOS / Realme UI / MIUI)
      const platform = MethodChannel('com.example.app_tbk/widget_pin');
      bool? nativeSuccess = false;
      try {
        nativeSuccess = await platform.invokeMethod<bool>('requestPinWidget');
      } catch (_) {}

      // 2. Nếu Native Channel không xử lý -> gọi qua HomeWidget
      if (nativeSuccess != true) {
        await HomeWidget.requestPinWidget(
          name: 'NextClassWidgetProvider',
          androidName: 'NextClassWidgetProvider',
          qualifiedAndroidName: 'com.example.app_tbk.widget.NextClassWidgetProvider',
        );
      }
      bao('Đã gửi yêu cầu ghim xong');
    } catch (e) {
      bao('Lỗi ghim widget: $e');
    }
  }

  // ───────────── Lọc & nhóm lịch học ─────────────

  List<LopHoc> _trongTuan(List<LopHoc> nguon, DateTime dau) {
    final cuoi = _congNgay(dau, 6);
    return nguon.where((l) {
      final d = _ngay(l.ngayBd);
      return !d.isBefore(dau) && !d.isAfter(cuoi);
    }).toList();
  }

  List<LopHoc> _layLichHienThi() {
    return switch (cheDo) {
      _CheDo.ngay => () {
        final n = _ngay(ngayDuocChon ?? ngayTapTrung);
        return lichHoc.where((l) => _ngay(l.ngayBd) == n).toList();
      }(),
      _CheDo.tuan => _trongTuan(lichHoc, _dauTuan(ngayTapTrung)),
      _CheDo.tuanHoc => _trongTuan(lichHoc, _dauTuanHoc(tuanDuocChon)),
    };
  }

  List<MapEntry<DateTime, Map<String, List<LopHoc>>>> _nhomTheoNgay(List<LopHoc> ds) {
    final nhom = <DateTime, Map<String, List<LopHoc>>>{};
    for (final lop in ds) {
      final theoBuoi = nhom.putIfAbsent(_ngay(lop.ngayBd), () => {});
      (theoBuoi[lop.buoiHoc] ??= []).add(lop);
    }
    return nhom.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  }

  int _soNgayToiThi(LopHoc lop) => _soNgayTu(lop.ngayBd, _ngay(DateTime.now()));

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: _mauNen(theme),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        scrolledUnderElevation: 0,
        backgroundColor: _mauThe(theme),
        surfaceTintColor: Colors.transparent,
        title: Text('home.title_1'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.widgets_outlined),
            tooltip: 'Ghim widget ra màn hình chính',
            onPressed: _ghimWidget,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'home.refresh'.tr(),
            onPressed: () => taiDuLieu(refresh: true),
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.primary,
          indicatorWeight: 3,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          tabs: [
            Tab(text: 'home.schedule'.tr()),
            Tab(text: 'home.exam'.tr()),
          ],
          onTap: (i) => setState(() {
            laHoc = i == 0;
            _capNhatSuKien();
            // Qua ngày mới (app mở qua đêm) → tính lại số ngày đếm ngược
            if (!laHoc && _homNayThi != _ngay(DateTime.now())) _capNhatLichThi();
          }),
        ),
      ),
      body: _buildBody(theme),
      floatingActionButton: _buildFab(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    // Skeleton / màn hình lỗi chỉ khi CHƯA có dữ liệu → làm mới không làm mất danh sách
    if (!_daTai && dangTai) return _buildSkeleton(theme);
    if (!_daTai && loi.isNotEmpty) return _buildLoi(theme);

    return Column(
      children: [
        if (dangTai) const LinearProgressIndicator(minHeight: 2),
        if (laHoc && cheDo != _CheDo.tuanHoc) _buildLich(theme),
        if (laHoc && cheDo == _CheDo.tuanHoc) _buildChonTuan(theme),
        Expanded(child: laHoc ? _buildDanhSach(theme) : _buildDanhSachThi(theme)),
      ],
    );
  }

  Widget? _buildFab(ThemeData theme) {
    if (!laHoc) return null;
    final dangTuanHoc = cheDo == _CheDo.tuanHoc;

    return FloatingActionButton(
      backgroundColor: theme.primaryColor,
      tooltip: dangTuanHoc ? 'home.return_to_the_date_calendar'.tr() : 'home.view_by_school_week'.tr(),
      onPressed: () => setState(() {
        if (dangTuanHoc) {
          cheDo = _CheDo.ngay;
          ngayTapTrung = DateTime.now();
          ngayDuocChon = ngayTapTrung;
          _capNhatSuKien();
        } else {
          cheDo = _CheDo.tuanHoc;
          ngayTapTrung = _dauTuanHoc(tuanDuocChon);
          ngayDuocChon = ngayTapTrung;
        }
      }),
      child: Icon(
        dangTuanHoc ? Icons.calendar_today : Icons.calendar_view_week,
        color: Colors.white,
      ),
    );
  }

  // ───────────── Lịch (TableCalendar) ─────────────

  Widget _buildLich(ThemeData theme) {
    final cs = theme.colorScheme;
    final locale = context.locale.languageCode;
    final vi = locale == 'vi';

    return Container(
      decoration: BoxDecoration(color: _mauThe(theme), boxShadow: [_bongThe(theme)]),
      child: TableCalendar<LopHoc>(
        firstDay: _ngayDau,
        lastDay: _ngayCuoi,
        focusedDay: ngayTapTrung,
        locale: locale,
        startingDayOfWeek: StartingDayOfWeek.monday,
        calendarFormat: dinhDangLich,
        availableCalendarFormats: vi
            ? const {CalendarFormat.month: 'Tháng', CalendarFormat.week: 'Tuần'}
            : const {CalendarFormat.month: 'Month', CalendarFormat.week: 'Week'},

        // Chỉ vuốt ngang để đổi tháng/tuần; vuốt dọc không đổi dạng (tránh xung đột với cuộn list)
        availableGestures: AvailableGestures.horizontalSwipe,
        rowHeight: 44,
        daysOfWeekHeight: 28,
        pageAnimationDuration: const Duration(milliseconds: 250),
        pageAnimationCurve: Curves.easeOut,
        formatAnimationDuration: const Duration(milliseconds: 250),
        formatAnimationCurve: Curves.easeOut,

        selectedDayPredicate: (d) => isSameDay(ngayDuocChon, d),
        eventLoader: (d) => suKien[_ngay(d)] ?? const <LopHoc>[],

        onDaySelected: (chon, tapTrung) => setState(() {
          ngayDuocChon = chon;
          ngayTapTrung = tapTrung;
          cheDo = _CheDo.ngay;
        }),
        onFormatChanged: (f) => setState(() {
          dinhDangLich = f;
          cheDo = f == CalendarFormat.week ? _CheDo.tuan : _CheDo.ngay;
        }),
        // Vuốt sang tháng/tuần khác: chỉ rebuild khi đang xem cả tuần
        onPageChanged: (focused) {
          ngayTapTrung = focused;
          if (cheDo == _CheDo.tuan) setState(() {});
        },

        headerStyle: HeaderStyle(
          titleCentered: true,
          headerPadding: const EdgeInsets.symmetric(vertical: 6),
          titleTextStyle: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600),
          titleTextFormatter: (date, loc) =>
          vi ? 'Tháng ${date.month}, ${date.year}' : DateFormat('MMMM yyyy', loc).format(date),
          formatButtonTextStyle: theme.textTheme.labelMedium!,
          formatButtonPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          formatButtonDecoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          defaultTextStyle: TextStyle(color: cs.onSurface),
          weekendTextStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
          todayDecoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
          todayTextStyle: TextStyle(color: cs.primary, fontWeight: FontWeight.bold),
          selectedDecoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
          selectedTextStyle: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.bold),
          markersMaxCount: 1,
          markerSize: 5,
          markerDecoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
        ),
        calendarBuilders: vi
            ? CalendarBuilders<LopHoc>(
          dowBuilder: (context, day) => Center(
            child: Text(
              _thuVi[day.weekday - 1],
              style: theme.textTheme.labelMedium!.copyWith(
                fontWeight: FontWeight.bold,
                color: day.weekday == DateTime.sunday ? Colors.redAccent : null,
              ),
            ),
          ),
        )
            : const CalendarBuilders<LopHoc>(),
      ),
    );
  }

  Widget _buildChonTuan(ThemeData theme) {
    final dau = _dauTuanHoc(tuanDuocChon);

    return Container(
      decoration: BoxDecoration(color: _mauThe(theme), boxShadow: [_bongThe(theme)]),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('home.select_week'.tr(),
                    style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold)),
                Text('${_fNgayThang.format(dau)} – ${_fNgayThang.format(_congNgay(dau, 6))}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          DropdownButton<int>(
            value: tuanDuocChon,
            underline: const SizedBox(),
            dropdownColor: _mauThe(theme),
            items: [
              for (var t = 1; t <= _soTuan; t++)
                DropdownMenuItem(
                  value: t,
                  child: Text(
                    '${'home.week'.tr()} $t',
                    style: TextStyle(
                      color: t == tuanHocHienTai ? Colors.green : null,
                      fontWeight: t == tuanDuocChon ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                tuanDuocChon = v;
                ngayTapTrung = _dauTuanHoc(v);
              });
            },
          ),
        ],
      ),
    );
  }

  // ───────────── Danh sách lịch học ─────────────

  /// Trạng thái rỗng — vẫn cuộn được để kéo làm mới.
  Widget _buildRong(ThemeData theme, IconData icon, Color? mauIcon) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
        Icon(icon, size: 80, color: mauIcon),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'home.no_schedule'.tr(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDanhSach(ThemeData theme) {
    final nhom = _nhomTheoNgay(_layLichHienThi());
    final fmt = DateFormat('EEEE, dd/MM/yyyy', context.locale.languageCode);
    final laMayTinhBang = MediaQuery.sizeOf(context).width > 600;
    final toi = _laToi(theme);

    return RefreshIndicator(
      onRefresh: () => taiDuLieu(refresh: true, silent: true),
      child: nhom.isEmpty
          ? _buildRong(theme, Icons.event_busy_rounded, toi ? Colors.grey[600] : Colors.grey[400])
          : ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(laMayTinhBang ? 24 : 16),
        itemCount: nhom.length,
        cacheExtent: 500,
        itemBuilder: (_, i) => RepaintBoundary(
          child: xayDungTheNgay(nhom[i].key, fmt.format(nhom[i].key), nhom[i].value, laMayTinhBang),
        ),
      ),
    );
  }

  Widget xayDungTheNgay(DateTime ngay, String nhanNgay, Map<String, List<LopHoc>> cacBuoi, bool laMayTinhBang) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tongBuoi = cacBuoi.values.fold<int>(0, (s, ds) => s + ds.length);

    return Container(
      margin: EdgeInsets.only(bottom: laMayTinhBang ? 20 : 16),
      decoration: BoxDecoration(
        color: _mauThe(theme),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [_bongThe(theme)],
      ),
      child: Padding(
        padding: EdgeInsets.all(laMayTinhBang ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [theme.primaryColor, cs.secondary],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    nhanNgay,
                    style: TextStyle(
                      fontSize: laMayTinhBang ? 18 : 16.5,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.titleLarge?.color,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: _laToi(theme) ? 0.6 : 1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '$tongBuoi buổi',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            xayDungNhomBuoi('home.morning'.tr(), cacBuoi['Sang'] ?? [], Icons.wb_sunny_outlined, laMayTinhBang),
            xayDungNhomBuoi('home.afternoon'.tr(), cacBuoi['Chieu'] ?? [], Icons.wb_cloudy_outlined, laMayTinhBang),
            xayDungNhomBuoi('home.evening'.tr(), cacBuoi['Toi'] ?? [], Icons.nightlight_outlined, laMayTinhBang),
          ],
        ),
      ),
    );
  }

  Widget xayDungNhomBuoi(String buoi, List<LopHoc> cacLop, IconData bieuTuong, bool laMayTinhBang) {
    if (cacLop.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: _laToi(theme) ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(bieuTuong, size: 15, color: cs.primary),
            ),
            const SizedBox(width: 8),
            Text(
              buoi,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: theme.textTheme.titleMedium?.color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Divider(color: theme.dividerColor.withValues(alpha: 0.5), height: 1)),
          ],
        ),
        const SizedBox(height: 10),
        ...cacLop.map((lop) => xayDungMucLop(lop, laMayTinhBang)),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget xayDungMucLop(LopHoc lop, bool laMayTinhBang) {
    final theme = Theme.of(context);
    final displayTenMon = lop.nhomThi ? 'Thi ${lop.tenMon}' : lop.tenMon;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: lop.mauSac.withValues(alpha: _laToi(theme) ? 0.13 : 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: lop.nhomThi ? Colors.red.withValues(alpha: 0.35) : lop.mauSac.withValues(alpha: 0.28),
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => hienChiTietLop(lop),
          borderRadius: BorderRadius.circular(16),
          splashColor: lop.mauSac.withValues(alpha: 0.1),
          highlightColor: lop.mauSac.withValues(alpha: 0.05),
          child: Padding(
            padding: EdgeInsets.all(laMayTinhBang ? 15 : 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTenMon,
                        style: TextStyle(
                          fontSize: laMayTinhBang ? 16 : 15.5,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.titleLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _ChipThongTin(icon: Icons.access_time_rounded, text: '${lop.gioBd} - ${lop.gioKt}'),
                          const SizedBox(width: 8),
                          Flexible(
                            child: _ChipThongTin(icon: Icons.room_rounded, text: lop.tenPhong, coGian: true),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!lop.nhomThi)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(color: lop.mauSac, borderRadius: BorderRadius.circular(9)),
                    child: Text(
                      lop.phanBo.split('/').first,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  )
                else
                  _BadgeDemNguoc(_soNgayToiThi(lop)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───────────── Danh sách lịch thi (lazy + dữ liệu đã tính sẵn) ─────────────

  Widget _buildDanhSachThi(ThemeData theme) {
    final laMayTinhBang = MediaQuery.sizeOf(context).width > 600;
    final pad = laMayTinhBang ? 24.0 : 16.0;

    return RefreshIndicator(
      onRefresh: () => taiDuLieu(refresh: true, silent: true),
      child: _mucThi.isEmpty
          ? _buildRong(
        theme,
        Icons.event_available_rounded,
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      )
          : ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        // 80: chừa chỗ cho thanh điều hướng
        padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 80),
        itemCount: _mucThi.length,
        cacheExtent: 600,
        addAutomaticKeepAlives: false,
        itemBuilder: (_, i) {
          final muc = _mucThi[i];
          return switch (muc) {
            _MucBanner() => _BannerThi(
              lop: muc.lop,
              soNgay: muc.soNgay,
              onTap: () => hienChiTietLop(muc.lop),
            ),
            _MucTieuDe() => _TieuDeNhom(muc),
            _MucThe() => RepaintBoundary(
              child: _TheThi(
                lop: muc.lop,
                soNgay: muc.soNgay,
                onTap: () => hienChiTietLop(muc.lop),
              ),
            ),
          };
        },
      ),
    );
  }

  // ───────────── Chi tiết buổi học / buổi thi ─────────────

  void hienChiTietLop(LopHoc lop) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ChiTietLopSheet(
        lop: lop,
        lichHoc: lichHoc,
        onMoBuoiHoc: hienChiTietLop,
      ),
    );
  }

  // ───────────── Skeleton & lỗi ─────────────

  Widget _buildSkeleton(ThemeData theme) {
    final dark = _laToi(theme);
    return Shimmer.fromColors(
      baseColor: dark ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: dark ? Colors.grey[700]! : Colors.grey[100]!,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: 4,
        itemBuilder: (_, __) => Container(
          height: 110,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildLoi(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 72, color: theme.colorScheme.error.withValues(alpha: 0.7)),
            const SizedBox(height: 20),
            Text(loi, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 24),
            demNguoc > 0
                ? Text(
              'home.retry_in_seconds'.tr(namedArgs: {'seconds': demNguoc.toString()}),
              style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold),
            )
                : FilledButton.icon(
              onPressed: () => taiDuLieu(refresh: true),
              icon: const Icon(Icons.refresh),
              label: Text('home.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Sheet chi tiết 1 buổi học / buổi thi
// - Buổi học: thêm mục "Ghi chú buổi học" (lưu BE qua [GhiChuService]).
// - Buổi thi: hiện dải đếm ngược + toàn bộ ghi chú ôn tập của môn.
// ═════════════════════════════════════════════════════════════════════════

class _ChiTietLopSheet extends StatefulWidget {
  final LopHoc lop;

  /// Toàn bộ buổi học (không gồm buổi thi) — để lọc ghi chú theo môn
  /// và mở lại đúng buổi học khi chạm vào 1 ghi chú.
  final List<LopHoc> lichHoc;
  final void Function(LopHoc) onMoBuoiHoc;

  const _ChiTietLopSheet({
    required this.lop,
    required this.lichHoc,
    required this.onMoBuoiHoc,
  });

  @override
  State<_ChiTietLopSheet> createState() => _ChiTietLopSheetState();
}

class _ChiTietLopSheetState extends State<_ChiTietLopSheet> {
  // Ghi chú của buổi học (chỉ đọc, soạn ở GhiChuScreen)
  bool _dangTaiNote = true;
  bool _loiTaiNote = false;
  String _noiDungGoc = '';

  // Ghi chú ôn tập theo môn (chỉ dùng khi nhomThi)
  List<GhiChu> _dsGhiChu = const [];
  bool _dangTaiDs = true;
  bool _loiDs = false;

  bool get _laThi => widget.lop.nhomThi;

  @override
  void initState() {
    super.initState();
    // Chờ 250ms cho animation trượt sheet lên hoàn tất rồi mới gọi API lấy ghi chú,
    // giúp hiệu ứng mở sheet mượt mà 60/120fps không bị khựng/lag.
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      if (_laThi) {
        _taiGhiChuMon();
      } else {
        _taiGhiChu();
      }
    });
  }

  // ───────────── Dữ liệu ghi chú ─────────────

  Future<void> _taiGhiChu() async {
    setState(() {
      _dangTaiNote = true;
      _loiTaiNote = false;
    });
    try {
      final g = await GhiChuService.layGhiChu(widget.lop);
      if (!mounted) return;
      setState(() {
        _dangTaiNote = false;
        _noiDungGoc = g?.noiDung ?? '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dangTaiNote = false;
        _loiTaiNote = true;
      });
    }
  }

  Future<void> _moGhiChu() async {
    final kq = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => GhiChuScreen(
          lop: widget.lop,
          // Null → trang ghi chú tự tải (trường hợp lần tải ở sheet bị lỗi)
          noiDungBanDau: _loiTaiNote ? null : _noiDungGoc,
        ),
      ),
    );
    if (kq != null && mounted) setState(() => _noiDungGoc = kq);
  }

  Future<void> _taiGhiChuMon() async {
    setState(() {
      _dangTaiDs = true;
      _loiDs = false;
    });
    try {
      final ds = await GhiChuService.layTheoMon(widget.lop.tenNhom);
      if (!mounted) return;
      // Chỉ giữ ghi chú thuộc các buổi học của đúng môn này
      final khoaCuaMon = widget.lichHoc
          .where((l) => l.tenMon == widget.lop.tenMon)
          .map(GhiChuService.khoaBuoi)
          .toSet();
      setState(() {
        _dangTaiDs = false;
        _dsGhiChu = khoaCuaMon.isEmpty ? ds : ds.where((g) => khoaCuaMon.contains(g.buoiKey)).toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dangTaiDs = false;
        _loiDs = true;
      });
    }
  }

  void _moBuoiHoc(GhiChu g) {
    LopHoc? tim;
    for (final l in widget.lichHoc) {
      if (GhiChuService.khoaBuoi(l) == g.buoiKey) {
        tim = l;
        break;
      }
    }
    if (tim == null) return;
    Navigator.of(context).pop();
    widget.onMoBuoiHoc(tim);
  }

  int get _soNgayToiThi => _soNgayTu(widget.lop.ngayBd, _ngay(DateTime.now()));

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final lop = widget.lop;
    final toi = _laToi(theme);

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
      decoration: BoxDecoration(
        color: toi ? _mauTheToi : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDauSheet(theme),
                  const SizedBox(height: 20),
                  if (_laThi) ...[
                    _buildDaiDemNguoc(theme),
                    const SizedBox(height: 20),
                  ],
                  if (!_laThi) _hangChiTiet(theme, Icons.person_outline, 'home.lecturer'.tr(), lop.hoTen),
                  _hangChiTiet(theme, Icons.room_outlined, 'home.classroom'.tr(), lop.tenPhong),
                  _hangChiTiet(theme, Icons.access_time_outlined, 'home.time'.tr(), '${lop.gioBd} - ${lop.gioKt}'),
                  _hangChiTiet(
                    theme,
                    Icons.calendar_today_outlined,
                    _laThi ? 'Ngày thi' : 'home.school_day'.tr(),
                    _fNgayDayDu.format(lop.ngayBd),
                  ),
                  if (!_laThi)
                    _hangChiTiet(theme, Icons.list_outlined, 'home.number_of_periods'.tr(),
                        '${lop.soTiet} ${'home.periods'.tr()}'),
                  if (!_laThi && lop.thoiGianGiaiLao.isNotEmpty) _hangGiaiLao(theme, lop.thoiGianGiaiLao),
                  if (!_laThi) ...[
                    _khoiNoiDungBaiHoc(theme, lop),
                    const SizedBox(height: 20),
                    _mucGhiChu(theme),
                  ] else ...[
                    const SizedBox(height: 4),
                    _mucOnTap(theme),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + media.padding.bottom),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: lop.mauSac,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  'common.close'.tr(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _oIcon(ThemeData theme, IconData icon) {
    final cs = theme.colorScheme;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: _laToi(theme) ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 17, color: cs.primary),
    );
  }

  Widget _buildDauSheet(ThemeData theme) {
    final lop = widget.lop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _laThi ? 'Thi ${lop.tenMon}' : lop.tenMon,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: theme.textTheme.titleLarge?.color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _laThi ? 'Lịch thi' : 'Chi tiết buổi học',
          style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildDaiDemNguoc(ThemeData theme) {
    final lop = widget.lop;
    final n = _soNgayToiThi;
    final mau = _mauDemNguoc(n, theme);
    final toi = _laToi(theme);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            mau.withValues(alpha: toi ? 0.28 : 0.14),
            mau.withValues(alpha: toi ? 0.14 : 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mau.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        children: [
          if (n >= 0) ...[
            Text(
              n == 0 ? '🎉' : '$n',
              style: TextStyle(fontSize: n == 0 ? 30 : 40, fontWeight: FontWeight.w800, color: mau, height: 1),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n == 0 ? 'Hôm nay thi!' : (n == 1 ? 'Ngày mai thi' : 'ngày nữa là thi'),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: mau),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_fNgayDayDu.format(lop.ngayBd)} • ${lop.gioBd} • ${lop.tenPhong}',
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ] else
            Expanded(
              child: Text(
                'Đã thi ngày ${_fNgayDayDu.format(lop.ngayBd)}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: mau),
              ),
            ),
          Icon(Icons.timer_outlined, color: mau.withValues(alpha: 0.7), size: 26),
        ],
      ),
    );
  }

  Widget _hangChiTiet(ThemeData theme, IconData icon, String nhan, String giaTri) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _oIcon(theme, icon),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('$nhan:', style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                giaTri,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hangGiaiLao(ThemeData theme, String giaTri) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _oIcon(theme, Icons.av_timer_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                giaTri,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _khoiNoiDungBaiHoc(ThemeData theme, LopHoc lop) {
    final cs = theme.colorScheme;
    final toi = _laToi(theme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _oIcon(theme, Icons.menu_book_outlined),
            const SizedBox(width: 12),
            Text('Nội dung bài học:', style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: toi ? 0.35 : 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            lop.noiDungBaiHoc.isNotEmpty ? lop.noiDungBaiHoc : 'Không có',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
        ),
      ],
    );
  }

  // ───────────── Mục ghi chú buổi học ─────────────

  Widget _mucGhiChu(ThemeData theme) {
    final cs = theme.colorScheme;
    final toi = _laToi(theme);
    final coNoiDung = _noiDungGoc.trim().isNotEmpty;

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: toi ? 0.35 : 0.5),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _dangTaiNote ? null : _moGhiChu,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.edit_note_rounded, size: 21, color: cs.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Ghi chú buổi học',
                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
                  ),
                  if (_dangTaiNote)
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Icon(coNoiDung ? Icons.edit_outlined : Icons.add_rounded, size: 18, color: cs.primary),
                ],
              ),
              const SizedBox(height: 10),
              if (_dangTaiNote)
                _shimmerDong(theme)
              else if (_loiTaiNote)
                Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 16, color: cs.error),
                    const SizedBox(width: 6),
                    const Expanded(child: Text('Chưa tải được ghi chú.', style: TextStyle(fontSize: 13))),
                    TextButton(onPressed: _taiGhiChu, child: const Text('Thử lại')),
                  ],
                )
              else
                Text(
                  coNoiDung ? _noiDungGoc : 'Chạm để thêm ghi chú cho buổi học này…',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                    color: coNoiDung ? theme.textTheme.bodyLarge?.color : cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _saoChepTatCa() {
    if (_dsGhiChu.isEmpty) return;
    final sb = StringBuffer();
    sb.writeln('=== GHI CHÚ ÔN TẬP: ${widget.lop.tenMon} ===\n');
    for (final g in _dsGhiChu) {
      final ngay = g.ngayHoc;
      final nhanThu = ngay == null ? '' : _thuVi[ngay.weekday - 1];
      final ngayStr = ngay == null
          ? ''
          : '$nhanThu, ${DateFormat('dd/MM/yyyy').format(ngay)}';
      sb.writeln('📌 [$ngayStr${g.gioBd.isNotEmpty ? ' • Buổi ${g.gioBd}' : ''}]');
      sb.writeln(g.noiDung.trim());
      sb.writeln('----------------------------------------');
    }
    Clipboard.setData(ClipboardData(text: sb.toString().trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã sao chép toàn bộ ghi chú của môn học!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _moGiaoDienGhiChuRien() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SheetGhiChuOnTapToanManHinh(
        lop: widget.lop,
        dsGhiChu: _dsGhiChu,
        onMoBuoiHoc: (g) {
          Navigator.pop(ctx);
          _moBuoiHoc(g);
        },
        onSaoChepTatCa: _saoChepTatCa,
      ),
    );
  }

  // ───────────── Mục ghi chú ôn tập (lịch thi) ─────────────

  Widget _mucOnTap(ThemeData theme) {
    final cs = theme.colorScheme;
    final toi = _laToi(theme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.menu_book_rounded, size: 21, color: cs.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Ghi chú ôn tập', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
            ),
            if (!_dangTaiDs && !_loiDs && _dsGhiChu.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: toi ? 0.22 : 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '${_dsGhiChu.length} ghi chú',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.primary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Toàn bộ ghi chú bạn đã note ở từng buổi học của môn này.',
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
        ),
        if (!_dangTaiDs && !_loiDs && _dsGhiChu.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _moGiaoDienGhiChuRien,
                icon: const Icon(Icons.fullscreen_rounded, size: 18),
                label: const Text('Xem tập trung'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _saoChepTatCa,
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Sao chép tất cả'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (_dangTaiDs)
          _shimmerDong(theme)
        else if (_loiDs)
          Row(
            children: [
              Icon(Icons.cloud_off_outlined, size: 16, color: cs.error),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Chưa tải được ghi chú từ máy chủ.', style: TextStyle(fontSize: 13)),
              ),
              TextButton(onPressed: _taiGhiChuMon, child: const Text('Thử lại')),
            ],
          )
        else if (_dsGhiChu.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: toi ? 0.35 : 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Chưa có ghi chú nào cho môn này. Mở từng buổi học ở tab Lịch học để ghi chú lại nội dung cần ôn.',
              style: TextStyle(fontSize: 13.5, height: 1.4, color: cs.onSurfaceVariant),
            ),
          )
        else
          ..._dsGhiChu.map((g) => _mucGhiChuOnTap(theme, g)),
      ],
    );
  }

  Widget _mucGhiChuOnTap(ThemeData theme, GhiChu g) {
    final cs = theme.colorScheme;
    final toi = _laToi(theme);
    final ngay = g.ngayHoc;
    final nhanThu = ngay == null ? '' : _thuVi[ngay.weekday - 1];
    final capNhatText = g.capNhatLuc != null
        ? 'Đã lưu ${DateFormat('HH:mm dd/MM').format(g.capNhatLuc!)}'
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: toi ? 0.35 : 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cs.primary.withValues(alpha: toi ? 0.3 : 0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: toi ? 0.18 : 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            ngay == null
                                ? 'Buổi học'
                                : '$nhanThu, ${DateFormat('dd/MM/yyyy').format(ngay)}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (g.gioBd.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Buổi ${g.gioBd}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // const SizedBox(width: 6),
                  // IconButton(
                  //   icon: const Icon(Icons.copy_rounded, size: 16),
                  //   visualDensity: VisualDensity.compact,
                  //   padding: EdgeInsets.zero,
                  //   constraints: const BoxConstraints(),
                  //   tooltip: 'Sao chép ghi chú',
                  //   onPressed: () {
                  //     Clipboard.setData(ClipboardData(text: g.noiDung));
                  //     ScaffoldMessenger.of(context).showSnackBar(
                  //       const SnackBar(
                  //         content: Text('Đã sao chép ghi chú buổi này!'),
                  //         duration: Duration(seconds: 2),
                  //       ),
                  //     );
                  //   },
                  // ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () => _moBuoiHoc(g),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Sửa',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, size: 16, color: cs.primary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    g.noiDung,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  if (capNhatText != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(Icons.access_time_rounded, size: 12, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          capNhatText,
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Sheet xem tập trung toàn bộ ghi chú môn học (Giao diện riêng rộng rãi)
// ═════════════════════════════════════════════════════════════════════════

class _SheetGhiChuOnTapToanManHinh extends StatefulWidget {
  final LopHoc lop;
  final List<GhiChu> dsGhiChu;
  final void Function(GhiChu) onMoBuoiHoc;
  final VoidCallback onSaoChepTatCa;

  const _SheetGhiChuOnTapToanManHinh({
    required this.lop,
    required this.dsGhiChu,
    required this.onMoBuoiHoc,
    required this.onSaoChepTatCa,
  });

  @override
  State<_SheetGhiChuOnTapToanManHinh> createState() =>
      _SheetGhiChuOnTapToanManHinhState();
}

class _SheetGhiChuOnTapToanManHinhState
    extends State<_SheetGhiChuOnTapToanManHinh> {
  String _tuKhoa = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final toi = theme.brightness == Brightness.dark;

    final dsHienThi = _tuKhoa.trim().isEmpty
        ? widget.dsGhiChu
        : widget.dsGhiChu
            .where((g) =>
                g.noiDung.toLowerCase().contains(_tuKhoa.trim().toLowerCase()))
            .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: toi ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4.5,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ghi chú ôn tập',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.lop.tenMon} (${widget.dsGhiChu.length} buổi)',
                        style:
                            TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: widget.onSaoChepTatCa,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Sao chép'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 16),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _tuKhoa = v),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm trong tất cả ghi chú…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _tuKhoa.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () => setState(() => _tuKhoa = ''),
                      )
                    : null,
                filled: true,
                fillColor: toi ? const Color(0xFF1E293B) : Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          Expanded(
            child: dsHienThi.isEmpty
                ? Center(
                    child: Text(
                      _tuKhoa.isNotEmpty
                          ? 'Không tìm thấy ghi chú phù hợp'
                          : 'Chưa có ghi chú nào',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: dsHienThi.length,
                    itemBuilder: (ctx, i) {
                      final g = dsHienThi[i];
                      return _buildCardItem(ctx, theme, g, toi, cs);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardItem(
    BuildContext context,
    ThemeData theme,
    GhiChu g,
    bool toi,
    ColorScheme cs,
  ) {
    final ngay = g.ngayHoc;
    final nhanThu = ngay == null ? '' : _thuVi[ngay.weekday - 1];
    final capNhatText = g.capNhatLuc != null
        ? 'Đã lưu ${DateFormat('HH:mm dd/MM').format(g.capNhatLuc!)}'
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: toi ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: toi ? 0.15 : 0.08),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            ngay == null
                                ? 'Buổi học'
                                : '$nhanThu, ${DateFormat('dd/MM/yyyy').format(ngay)}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (g.gioBd.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Buổi ${g.gioBd}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Sao chép ghi chú',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: g.noiDung));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Đã sao chép ghi chú buổi này!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () => widget.onMoBuoiHoc(g),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Chỉnh sửa',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 16, color: cs.primary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    g.noiDung,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  if (capNhatText != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(Icons.access_time_rounded,
                            size: 12, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          capNhatText,
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}