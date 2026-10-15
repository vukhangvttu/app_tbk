import 'dart:async';
import 'dart:io';

import 'package:app_tbk/config/academic_config.dart';
import 'package:app_tbk/core/errors/exceptions.dart';
import 'package:app_tbk/models/class_schedule.dart';
import 'package:app_tbk/services/notification_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../services/api_service.dart';
import '../../auth/services/auth_service.dart';
import '../../auth/services/post_login_initializer.dart';

/// Chế độ xem lịch:
/// - ngay: lịch ngày đang chọn
/// - tuan: cả tuần theo lịch (khi calendar ở dạng tuần)
/// - tuanHoc: tuần học theo học kỳ (chọn bằng dropdown)
enum _CheDo { ngay, tuan, tuanHoc }

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({Key? key}) : super(key: key);

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> with SingleTickerProviderStateMixin {
  static const _soTuan = 25;
  static const _loiMang = 'Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.';
  static const _thuVi = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

  late final TabController _tabController;

  // Dữ liệu
  List<LopHoc> lichHoc = [];
  List<LopHoc> lichThi = [];
  Map<DateTime, List<LopHoc>> suKien = {};

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

  static DateTime _ngay(DateTime d) => DateTime(d.year, d.month, d.day);
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
        dangTai = false;
        _daTai = true;
        loi = '';
      });
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

  // Đang tắt (xem TODO cũ): bật khi muốn nhắc lịch học/thi hằng ngày.
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

  // ───────────── Lọc & nhóm lịch ─────────────

  List<LopHoc> _trongTuan(List<LopHoc> nguon, DateTime dau) {
    final cuoi = _congNgay(dau, 6);
    return nguon.where((l) {
      final d = _ngay(l.ngayBd);
      return !d.isBefore(dau) && !d.isAfter(cuoi);
    }).toList();
  }

  List<LopHoc> _layLichHienThi() {
    if (!laHoc) return lichThi; // lịch thi: hiển thị tất cả
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

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        scrolledUnderElevation: 0,
        title: Text('home.title_1'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'home.refresh'.tr(),
            onPressed: () => taiDuLieu(refresh: true),
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'home.schedule'.tr()),
            Tab(text: 'home.exam'.tr()),
          ],
          onTap: (i) => setState(() {
            laHoc = i == 0;
            _capNhatSuKien();
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
        Expanded(child: _buildDanhSach(theme)),
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
      color: theme.cardColor,
      child: TableCalendar<LopHoc>(
        firstDay: _ngayDau,
        lastDay: _ngayCuoi,
        focusedDay: ngayTapTrung,
        locale: locale,
        startingDayOfWeek: StartingDayOfWeek.monday,
        calendarFormat: dinhDangLich,

        // Chữ trên nút đổi dạng: chỉ còn 2 dạng, Việt hóa
        availableCalendarFormats: vi
            ? const {CalendarFormat.month: 'Tháng', CalendarFormat.week: 'Tuần'}
            : const {CalendarFormat.month: 'Month', CalendarFormat.week: 'Week'},

        // Chỉ vuốt ngang để đổi tháng/tuần; vuốt dọc không còn đổi dạng (tránh xung đột với cuộn list)
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
        // Vuốt sang tháng/tuần khác: chỉ rebuild khi đang xem cả tuần,
        // còn lại chỉ ghi nhớ ngày tập trung → mượt hơn.
        onPageChanged: (focused) {
          ngayTapTrung = focused;
          if (cheDo == _CheDo.tuan) setState(() {});
        },

        headerStyle: HeaderStyle(
          titleCentered: true,
          headerPadding: const EdgeInsets.symmetric(vertical: 6),
          titleTextStyle: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600),
          // "Month yyyy" → "Tháng M, yyyy"
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
    final f = DateFormat('dd/MM');

    return Container(
      color: theme.cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('home.select_week'.tr(),
                    style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold)),
                Text('${f.format(dau)} – ${f.format(_congNgay(dau, 6))}', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          DropdownButton<int>(
            value: tuanDuocChon,
            underline: const SizedBox(),
            dropdownColor: theme.cardColor,
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

  // ───────────── Danh sách lịch (giao diện gốc) ─────────────

  Widget _buildDanhSach(ThemeData theme) {
    final nhom = _nhomTheoNgay(_layLichHienThi());
    final fmt = DateFormat('EEEE, dd/MM/yyyy', context.locale.languageCode);
    final laMayTinhBang = MediaQuery.sizeOf(context).width > 600;
    final isDarkMode = theme.brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () => taiDuLieu(refresh: true, silent: true),
      child: nhom.isEmpty
      // Vẫn cuộn được để kéo làm mới khi danh sách rỗng
          ? ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
          Icon(
            Icons.event_busy_rounded,
            size: 80,
            color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
          ),
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
      )
          : ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(laMayTinhBang ? 24 : 16),
        itemCount: nhom.length,
        itemBuilder: (_, i) =>
            xayDungTheNgay(fmt.format(nhom[i].key), nhom[i].value, laMayTinhBang),
      ),
    );
  }

  Widget xayDungTheNgay(String ngay, Map<String, List<LopHoc>> cacBuoi, bool laMayTinhBang) {
    return Card(
      margin: EdgeInsets.only(bottom: laMayTinhBang ? 20 : 16),
      color: Theme.of(context).cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
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
                      colors: [
                        Theme.of(context).primaryColor,
                        Theme.of(context).colorScheme.secondary,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ngay,
                    style: TextStyle(
                      fontSize: laMayTinhBang ? 20 : 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.titleLarge?.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(bieuTuong, size: 18, color: Theme.of(context).iconTheme.color),
            const SizedBox(width: 8),
            Text(
              buoi,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.titleMedium?.color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...cacLop.map((lop) => xayDungMucLop(lop, laMayTinhBang)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget xayDungMucLop(LopHoc lop, bool laMayTinhBang) {
    final displayTenMon = lop.nhomThi ? 'Thi ${lop.tenMon}' : lop.tenMon;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            lop.mauSac.withValues(alpha: 0.08),
            lop.mauSac.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: lop.mauSac.withValues(alpha: 0.3),
          width: 1.5,
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
            padding: EdgeInsets.all(laMayTinhBang ? 16 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: lop.mauSac,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: lop.mauSac.withValues(alpha: 0.4),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        displayTenMon,
                        style: TextStyle(
                          fontSize: laMayTinhBang ? 17 : 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.titleLarge?.color,
                        ),
                      ),
                    ),
                    if (!lop.nhomThi)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: lop.mauSac,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: lop.mauSac.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          lop.phanBo.split('/').first,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    if (lop.nhomThi)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.warning_rounded, color: Colors.red, size: 20),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded,
                        size: 16, color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Text(
                      '${lop.gioBd} - ${lop.gioKt}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.room_rounded,
                        size: 16, color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        lop.tenPhong,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───────────── Chi tiết (giao diện gốc) ─────────────

  void hienChiTietLop(LopHoc lop) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: lop.mauSac, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      lop.tenMon,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (!lop.nhomThi)
                xayDungHangChiTiet(Icons.person_outline, 'home.lecturer'.tr(), lop.hoTen),
              xayDungHangChiTiet(Icons.room_outlined, 'home.classroom'.tr(), lop.tenPhong),
              xayDungHangChiTiet(
                  Icons.access_time_outlined, 'home.time'.tr(), '${lop.gioBd} - ${lop.gioKt}'),
              if (!lop.nhomThi)
                xayDungHangChiTiet(Icons.calendar_today_outlined, 'home.school_day'.tr(),
                    DateFormat('dd/MM/yyyy').format(lop.ngayBd))
              else
                xayDungHangChiTiet(Icons.calendar_today_outlined, 'Ngày thi',
                    DateFormat('dd/MM/yyyy').format(lop.ngayBd)),
              if (!lop.nhomThi)
                xayDungHangChiTiet(Icons.list_outlined, 'home.number_of_periods'.tr(),
                    '${lop.soTiet} ${'home.periods'.tr()}'),
              if (!lop.nhomThi && lop.thoiGianGiaiLao.isNotEmpty)
                xayDungHangChiTietThoiGianGiaiLao(Icons.av_timer_outlined, lop.thoiGianGiaiLao),
              if (!lop.nhomThi)
                xayDungHangChiTiet(Icons.menu_book_outlined, 'Nội dung', lop.noiDungBaiHoc.isNotEmpty ? lop.noiDungBaiHoc : 'Không có', isNoiDung: true),
              const SizedBox(height: 24),
              SizedBox(
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
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        );
      },
    );
  }

  Widget xayDungHangChiTiet(IconData bieuTuong, String nhan, String giaTri, {bool isNoiDung = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: isNoiDung
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(bieuTuong, size: 20, color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.7)),
                    const SizedBox(width: 12),
                    Text(
                      '$nhan:',
                      style: TextStyle(
                        fontSize: 15,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 32.0),
                  child: Text(
                    giaTri,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500, // Reduced font weight slightly for readability of long text
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      height: 1.4, // Added line height for better reading
                    ),
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(bieuTuong, size: 20, color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.7)),
                const SizedBox(width: 12),
                Text(
                  '$nhan:',
                  style: TextStyle(
                    fontSize: 15,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    giaTri,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget xayDungHangChiTietThoiGianGiaiLao(IconData bieuTuong, String giaTri) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(bieuTuong, size: 20, color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.7)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              giaTri,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────── Skeleton & lỗi ─────────────

  Widget _buildSkeleton(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
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