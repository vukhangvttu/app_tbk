import 'package:easy_localization/easy_localization.dart';
import 'dart:async';
import 'dart:io';
import 'package:app_tbk/models/class_schedule.dart';
import 'package:app_tbk/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:table_calendar/table_calendar.dart';

import '../../../services/api_service.dart';
import '../../auth/services/auth_service.dart';



class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({Key? key}) : super(key: key);

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> with SingleTickerProviderStateMixin {
  List<LopHoc> lichHoc = [];
  List<LopHoc> lichThi = [];
  bool dangTai = false;
  String loi = '';
  bool laHoc = true;
  bool laTuan = false;
  bool laTuanHoc = false;
  DateTime ngayTapTrung = DateTime.now();
  DateTime? ngayDuocChon;
  CalendarFormat dinhDangLich = CalendarFormat.week;
  Map<DateTime, List<LopHoc>> suKien = {};
  int tuanHocHienTai = 1;
  int tuanDuocChon = 1;
  List<int> danhSachTuan = List.generate(25, (i) => i + 1);

  static final DateTime ngayBatDauHocKy = DateTime(2025, 9, 1);
  late final DateTime ngayDau = DateTime(ngayBatDauHocKy.year, 1, 1); // Đầu năm của học kỳ
  late final DateTime ngayCuoi = DateTime(ngayBatDauHocKy.year + 1, 12, 31); // Cuối năm sau

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    ngayTapTrung = DateTime.now();
    ngayDuocChon = ngayTapTrung;
    tinhTuanHocHienTai();
    tuanDuocChon = tuanHocHienTai;
    taiDuLieu();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // void tinhTuanHocHienTai() {
  //   final now = DateTime.now();
  //   final difference = now.difference(ngayBatDauHocKy).inDays;
  //   tuanHocHienTai = (difference / 7).ceil();
  //   if (tuanHocHienTai < 1) tuanHocHienTai = 1;
  //   if (tuanHocHienTai > 25) tuanHocHienTai = 25;
  // }
  void tinhTuanHocHienTai() {
    final now = DateTime.now();
    final difference = now.difference(ngayBatDauHocKy).inDays;

    // Mỗi tuần tính từ thứ Hai
    tuanHocHienTai = (difference / 7).floor() + 1;

    // Giới hạn biên
    if (tuanHocHienTai < 1) tuanHocHienTai = 1;
    if (tuanHocHienTai > 25) tuanHocHienTai = 25;
  }


  void capNhatSuKien() {
    suKien = {};
    final lichHienTai = layLichHienTai();
    for (var lop in lichHienTai) {
      final ngay = DateTime(lop.ngayBd.year, lop.ngayBd.month, lop.ngayBd.day);
      suKien[ngay] ??= [];
      suKien[ngay]!.add(lop);
    }
  }

  Future<void> taiDuLieu() async {
    // Nếu đã có dữ liệu và không đang tải thì return
    if (lichHoc.isNotEmpty && lichThi.isNotEmpty && !dangTai) return;

    setState(() {
      dangTai = true;
      loi = '';
    });

    try {
      // Lấy ID sinh viên từ AuthService
      final idSinhVien = await AuthService.getIdSinhVien();
      if (idSinhVien == null || idSinhVien.isEmpty) {
        throw Exception('Không tìm thấy thông tin sinh viên');
      }

      // Gọi API trực tiếp qua ApiService
      final List<dynamic> data = await ApiService.getSchedule(
        int.parse(idSinhVien), // Hoặc hardcode: 19719
        1,                    // Học kỳ
        '2025-2026',         // Năm học
      );

      // Parse dữ liệu
      List<LopHoc> tatCa = data.map((json) {
        return LopHoc(
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
        );
      }).toList();

      setState(() {
        lichHoc = tatCa;
        lichThi = tatCa.where((lop) => lop.nhomThi).toList();
        capNhatSuKien();
        dangTai = false;
        ngayTapTrung = DateTime.now();
        ngayDuocChon = ngayTapTrung;
      });

      // Kiểm tra và thông báo lịch hôm nay
      // _xuLyThongBao();

    } on UnauthorizedException catch (e) {
      // Token hết hạn hoặc không hợp lệ
      setState(() {
        loi = 'Phiên đăng nhập đã hết hạn';
        dangTai = false;
      });

      // Chuyển về màn hình login sau 1 giây
      await Future.delayed(Duration(seconds: 1));
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
        // Hoặc nếu dùng GetX:
        // Get.offAllNamed('/login');
      }

    } on TimeoutException catch (e) {
      setState(() {
        loi = 'Máy chủ phản hồi quá lâu. Vui lòng thử lại sau.';
        dangTai = false;
      });
      batDauDemNguocTaiLai();

    } on SocketException catch (e) {
      setState(() {
        loi = 'Không có kết nối internet';
        dangTai = false;
      });

    } catch (e) {
      setState(() {
        // Xử lý các lỗi khác
        String errorMsg = e.toString();

        if (errorMsg.contains('Không tìm thấy token') ||
            errorMsg.contains('hết hạn')) {
          loi = 'Vui lòng đăng nhập lại';
          // Chuyển về login
          Future.delayed(Duration(seconds: 1), () {
            if (mounted) {
              Navigator.of(context).pushReplacementNamed('/login');
            }
          });
        } else if (errorMsg.contains('401')) {
          loi = 'Không có quyền truy cập';
        } else if (errorMsg.contains('404')) {
          loi = 'Không tìm thấy dữ liệu';
        } else if (errorMsg.contains('500')) {
          loi = 'Lỗi máy chủ';
        } else {
          loi = errorMsg.replaceAll('Exception: ', '');
        }

        dangTai = false;
      });
    }
  }

// Hàm helper phân tích ngày
  DateTime _phanTichNgay(String? ngayStr) {
    if (ngayStr == null || ngayStr.isEmpty) {
      return DateTime.now();
    }

    try {
      final utcDate = DateTime.parse(ngayStr);
      final localDate = utcDate.toLocal();
      return DateTime(localDate.year, localDate.month, localDate.day);
    } catch (e) {
      print('Lỗi parse ngày: $e');
      return DateTime.now();
    }
  }

// Hàm tải lại (dùng cho Pull-to-Refresh)
  Future<void> taiLaiDuLieu() async {
    setState(() {
      lichHoc.clear();
      lichThi.clear();
    });
    await taiDuLieu();
  }

  Future<void> _xuLyThongBao() async {
    final homNay = DateTime.now();
    final coLichHocHomNay = lichHoc.any((lop) {
      return lop.ngayBd.isBefore(homNay.add(const Duration(days: 1))) &&
          lop.ngayKt.isAfter(homNay.subtract(const Duration(days: 1))) &&
          !lop.nhomThi;
    });
    final coLichThiHomNay = lichThi.any((lop) {
      return lop.ngayBd.isBefore(homNay.add(const Duration(days: 1))) &&
          lop.ngayKt.isAfter(homNay.subtract(const Duration(days: 1))) &&
          lop.nhomThi;
    });

    if (coLichHocHomNay || coLichThiHomNay) {
      if (coLichHocHomNay) {
        final noiDungHoc = 'Nhắc nhở: Bạn có lịch học hôm nay (${homNay.day}/${homNay.month}/${homNay.year}).';
        await NotificationService().showAndSaveNotification(
          idSinhVien: 19719,
          title: '📘 Lịch học hôm nay',
          body: noiDungHoc,
          loaiLich: 'LICH_HOC',
        );
        await NotificationService().scheduleDailyNotification(
          id: 1,
          title: '📘 Lịch học hôm nay',
          body: noiDungHoc,
          loaiLich: 'LICH_HOC',
          hour: 8,
          minute: 55,
        );
      }
      if (coLichThiHomNay) {
        final noiDungThi = 'Nhắc nhở: Bạn có lịch thi hôm nay (${homNay.day}/${homNay.month}/${homNay.year}).';
        await NotificationService().showAndSaveNotification(
          idSinhVien: 19719,
          title: '🧾 Lịch thi hôm nay',
          body: noiDungThi,
          loaiLich: 'LICH_THI',
        );
        await NotificationService().scheduleDailyNotification(
          id: 2,
          title: '🧾 Lịch thi hôm nay',
          body: noiDungThi,
          loaiLich: 'LICH_THI',
          hour: 8,
          minute: 55,
        );
      }
    }
  }

  String layLoi(String loi) {
    if (loi.contains('timeout') || loi.contains('timed out')) {
      return 'Không thể kết nối tới server.';
    } else {
      return 'Error: ${loi.length > 200 ? loi.substring(0, 200) + "..." : loi}';
    }
  }

  int demNguoc = 0;
  Future<void> batDauDemNguocTaiLai() async {
    setState(() {
      demNguoc = 5;
    });

    for (int i = 5; i > 0; i--) {
      setState(() {
        demNguoc = i;
      });
      await Future.delayed(const Duration(seconds: 1));
    }

    setState(() {
      demNguoc = 0;
    });

    taiDuLieu();
  }

  List<LopHoc> layLichHienTai() {
    return laHoc ? lichHoc : lichThi;
  }

  List<LopHoc> layLichNgay(DateTime ngay) {
    final ngayNormalized = DateTime.utc(ngay.year, ngay.month, ngay.day);
    return laHoc
        ? layLichHienTai().where((s) {
      final ngayBdNormalized = DateTime.utc(s.ngayBd.year, s.ngayBd.month, s.ngayBd.day);
      return ngayBdNormalized.isAtSameMomentAs(ngayNormalized);
    }).toList()
        : layLichHienTai();
  }

  List<LopHoc> layLichLoc() {
    DateTime tuanBatDau = DateTime.utc(ngayTapTrung.year, ngayTapTrung.month, ngayTapTrung.day)
        .subtract(Duration(days: ngayTapTrung.weekday - 1));
    DateTime tuanKetThuc = tuanBatDau.add(const Duration(days: 6));
    return laHoc
        ? layLichHienTai().where((s) {
      final ngayBdNormalized = DateTime.utc(s.ngayBd.year, s.ngayBd.month, s.ngayBd.day);
      return !ngayBdNormalized.isBefore(tuanBatDau) && !ngayBdNormalized.isAfter(tuanKetThuc);
    }).toList()
        : layLichHienTai();
  }

  List<LopHoc> layLichTuanHoc(int tuanSo) {
    final tuanBatDau = ngayBatDauHocKy.add(Duration(days: (tuanSo - 1) * 7));
    final tuanKetThuc = tuanBatDau.add(const Duration(days: 6));
    return laHoc
        ? layLichHienTai().where((s) {
      final ngayBdNormalized = DateTime.utc(s.ngayBd.year, s.ngayBd.month, s.ngayBd.day);
      return !ngayBdNormalized.isBefore(tuanBatDau) && !ngayBdNormalized.isAfter(tuanKetThuc);
    }).toList()
        : layLichHienTai();
  }

  Map<String, Map<String, List<LopHoc>>> nhomLichTheoNgay(List<LopHoc> lichLoc) {
    Map<String, Map<String, List<LopHoc>>> nhom = {};
    final locale = context.locale.languageCode;

    for (var lop in lichLoc) {
      String khoaNgay = DateFormat('EEEE, dd/MM/yyyy', locale).format(lop.ngayBd);
      if (!nhom.containsKey(khoaNgay)) {
        nhom[khoaNgay] = {'Sang': [], 'Chieu': [], 'Toi': []};
      }
      nhom[khoaNgay]![lop.buoiHoc]!.add(lop);
    }

    var cacMucDaSapXep = nhom.entries.toList()
      ..sort((a, b) {
        String ngayA = a.key.split(', ')[1];
        String ngayB = b.key.split(', ')[1];
        DateTime phanTichA = DateFormat('dd/MM/yyyy').parse(ngayA);
        DateTime phanTichB = DateFormat('dd/MM/yyyy').parse(ngayB);
        return phanTichA.compareTo(phanTichB);
      });

    return Map.fromIterable(cacMucDaSapXep, key: (e) => e.key, value: (e) => e.value);
  }

  @override
  Widget build(BuildContext context) {
    capNhatSuKien();
    final kichThuoc = MediaQuery.of(context).size;
    final laMayTinhBang = kichThuoc.width > 600;
    final lichHienTai = laTuanHoc
        ? layLichTuanHoc(tuanDuocChon)
        : (laTuan ? layLichLoc() : layLichNgay(ngayDuocChon ?? ngayTapTrung));
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        title: Text(
          'home.title_1'.tr(),
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
            onPressed: taiDuLieu,
            tooltip: 'home.refresh'.tr(),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'home.schedule'.tr()),
            Tab(text: 'home.exam'.tr()),
          ],
          labelColor: Theme.of(context).tabBarTheme.labelColor,
          unselectedLabelColor: Theme.of(context).tabBarTheme.unselectedLabelColor,
          indicatorColor: Theme.of(context).tabBarTheme.indicatorColor,
          onTap: (chiSo) {
            setState(() {
              laHoc = chiSo == 0;
              capNhatSuKien();
            });
          },
        ),
      ),
      body: dangTai
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 16),
            Text(
              'home.loading'.tr(),
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      )
          : loi.isNotEmpty
          ? Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 80,
                color: isDarkMode ? Colors.red[200] : Colors.red[300],
              ),
              const SizedBox(height: 24),
              Text(
                layLoi(loi),
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
              const SizedBox(height: 32),
              demNguoc > 0
                  ? Text(
                'home.retry_in_seconds'.tr(namedArgs: {'seconds': demNguoc.toString()}),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              )
                  : ElevatedButton.icon(
                onPressed: taiDuLieu,
                icon: const Icon(Icons.refresh),
                label:  Text('home.retry'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      )
          : Column(
        children: [
          if (laHoc && !laTuanHoc) xayDungLich(),
          if (laTuanHoc) _xayDungTuanHoc(),
          Expanded(
            child: lichHienTai.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_busy_rounded,
                    size: 80,
                    color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'home.no_schedule'.tr(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'home.pull_down_to_reload'.tr(),
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: taiDuLieu,
              child: ListView(
                padding: EdgeInsets.all(laMayTinhBang ? 24 : 16),
                children: nhomLichTheoNgay(lichHienTai).entries.map((mucNgay) {
                  return xayDungTheNgay(mucNgay.key, mucNgay.value, laMayTinhBang);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: laHoc && !laTuanHoc
          ? FloatingActionButton(
        onPressed: () {
          setState(() {
            laTuanHoc = true;
            laTuan = true;
            ngayTapTrung = ngayBatDauHocKy.add(Duration(days: (tuanDuocChon - 1) * 7));
            ngayDuocChon = ngayTapTrung;
          });
        },
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.calendar_view_week),
        tooltip: 'home.view_by_school_week'.tr(),
      )
          : laTuanHoc
          ? FloatingActionButton(
        onPressed: () {
          setState(() {
            laTuanHoc = false;
            laTuan = false;
            ngayTapTrung = DateTime.now();
            ngayDuocChon = ngayTapTrung;
            capNhatSuKien();
          });
        },
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.calendar_today),
        tooltip: 'home.return_to_the_date_calendar'.tr(),
      )
          : null,
    );
  }

  Widget _xayDungTuanHoc() {
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'home.select_week'.tr(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              DropdownButton<int>(
                value: tuanDuocChon,
                items: danhSachTuan.map((tuan) {
                  return DropdownMenuItem<int>(
                    value: tuan,
                    child: Text(
                      '${'home.week'.tr()} $tuan',
                        style: TextStyle(
                        color: tuan == tuanHocHienTai
                            ? Colors.green
                            : (tuan == tuanDuocChon
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface),
                        fontSize: 16,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (int? newValue) {
                  if (newValue != null) {
                    setState(() {
                      tuanDuocChon = newValue;
                      ngayTapTrung = ngayBatDauHocKy.add(Duration(days: (tuanDuocChon - 1) * 7));
                      capNhatSuKien();
                    });
                  }
                },
                dropdownColor: Theme.of(context).cardColor,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                  fontSize: 16,
                ),
                iconEnabledColor: Theme.of(context).iconTheme.color,
                underline: const SizedBox(),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget xayDungLich() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: Theme.of(context).cardColor,
      child: TableCalendar<LopHoc>(
        firstDay: ngayDau,
        lastDay: ngayCuoi,
        focusedDay: ngayTapTrung,
        startingDayOfWeek: StartingDayOfWeek.monday,
        calendarFormat: dinhDangLich,
        selectedDayPredicate: (ngay) => isSameDay(ngayDuocChon, ngay),
        eventLoader: (ngay) => suKien[DateTime(ngay.year, ngay.month, ngay.day)] ?? [],
        onDaySelected: (chon, tapTrung) {
          if (!isSameDay(ngayDuocChon, chon)) {
            setState(() {
              ngayDuocChon = chon;
              ngayTapTrung = tapTrung;
              laTuan = false;
            });
          }
        },
        onFormatChanged: (dinhDang) {
          if (dinhDangLich != dinhDang) {
            setState(() {
              dinhDangLich = dinhDang;
              laTuan = dinhDang == CalendarFormat.week;
            });
          }
        },
        onPageChanged: (tapTrung) {
          setState(() {
            ngayTapTrung = tapTrung;
            tinhTuanHocHienTai();
          });
        },
        locale: 'vi_VN',
        headerStyle: HeaderStyle(
          formatButtonVisible: true,
          titleCentered: true,
          titleTextStyle: Theme.of(context).textTheme.titleLarge!,
          formatButtonTextStyle: Theme.of(context).textTheme.labelLarge!,
          titleTextFormatter: (date, locale) {
            return DateFormat('MM - yyyy', locale).format(date);
          },
        ),
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: isDarkMode
                ? Colors.grey[300]
                : Theme.of(context).primaryColor.withOpacity(0.4),
            shape: BoxShape.circle,
            border: Border.all(
              color: isDarkMode ? Colors.grey[400]! : Colors.transparent,
              width: 1,
            ),
          ),
          selectedDecoration: BoxDecoration(
            color: isDarkMode
                ? Colors.blue[200]
                : Theme.of(context).primaryColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: isDarkMode ? Colors.blue[300]! : Colors.transparent,
              width: 1,
            ),
          ),
          todayTextStyle: TextStyle(color: isDarkMode ? Colors.black : Colors.black87),
          selectedTextStyle: TextStyle(color: isDarkMode ? Colors.black : Colors.white),
          defaultTextStyle: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black87),
          outsideDaysVisible: false,
        ),
        calendarBuilders: CalendarBuilders(
          markerBuilder: (context, ngay, suKien) {
            if (suKien.isNotEmpty) {
              return Positioned(
                right: 1,
                bottom: 1,
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red,
                  ),
                  width: 6.0,
                  height: 6.0,
                ),
              );
            }
            return null;
          },
          dowBuilder: (context, day) {
            final text = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][day.weekday - 1];
            return Center(
              child: Text(
                text,
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  fontWeight: FontWeight.bold,
                  color: day.weekday == DateTime.sunday
                      ? Colors.redAccent
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget xayDungTheNgay(String ngay, Map<String, List<LopHoc>> cacBuoi, bool laMayTinhBang) {
    bool coLop = cacBuoi.values.any((cacLop) => cacLop.isNotEmpty);

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
                    gradient: coLop
                        ? LinearGradient(
                      colors: [
                        Theme.of(context).primaryColor,
                        Theme.of(context).colorScheme.secondary,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    )
                        : null,
                    color: coLop ? null : Theme.of(context).dividerColor,
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
                if (!coLop)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Không có lịch',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            if (coLop) ...[
              const SizedBox(height: 16),
              xayDungNhomBuoi(
                  'home.morning'.tr(), cacBuoi['Sang'] ?? [], Icons.wb_sunny_outlined, laMayTinhBang),
              xayDungNhomBuoi(
                  'home.afternoon'.tr(), cacBuoi['Chieu'] ?? [], Icons.wb_cloudy_outlined, laMayTinhBang),
              xayDungNhomBuoi(
                  'home.evening'.tr(), cacBuoi['Toi'] ?? [], Icons.nightlight_outlined, laMayTinhBang),
            ],
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
        ...cacLop.map((lop) => xayDungMucLop(lop, laMayTinhBang)).toList(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget xayDungMucLop(LopHoc lop, bool laMayTinhBang) {
    String displayTenMon = lop.nhomThi ? 'Thi ${lop.tenMon}' : lop.tenMon;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            lop.mauSac.withOpacity(0.08),
            lop.mauSac.withOpacity(0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: lop.mauSac.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => hienChiTietLop(lop),
          borderRadius: BorderRadius.circular(16),
          splashColor: lop.mauSac.withOpacity(0.1),
          highlightColor: lop.mauSac.withOpacity(0.05),
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
                            color: lop.mauSac.withOpacity(0.4),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: lop.mauSac,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: lop.mauSac.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        '${lop.phanBo.split('/').first}',
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
                        child: Icon(
                          Icons.warning_rounded,
                          color: Colors.red,
                          size: 20,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded,
                        size: 16, color: Theme.of(context).iconTheme.color?.withOpacity(0.7)),
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
                        size: 16, color: Theme.of(context).iconTheme.color?.withOpacity(0.7)),
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
                color: Colors.black.withOpacity(0.1),
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
                    decoration: BoxDecoration(
                      color: lop.mauSac,
                      shape: BoxShape.circle,
                    ),
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
              xayDungHangChiTiet(
                  Icons.person_outline, 'home.lecturer'.tr(), lop.hoTen),
              xayDungHangChiTiet(
                  Icons.room_outlined, 'home.classroom'.tr(), lop.tenPhong),
              xayDungHangChiTiet(Icons.access_time_outlined, 'home.time'.tr(),
                  '${lop.gioBd} - ${lop.gioKt}'),
              xayDungHangChiTiet(Icons.calendar_today_outlined, 'home.school_day'.tr(),
                  DateFormat('dd/MM/yyyy').format(lop.ngayBd)),
              // xayDungHangChiTiet(
              //     Icons.repeat_outlined, 'Phân bổ', lop.phanBo),
              // xayDungHangChiTiet(
              //     Icons.numbers_outlined, 'Mã nhóm', lop.maNhom.toString()),
              xayDungHangChiTiet(
                  Icons.list_outlined, 'home.number_of_periods'.tr(), '${lop.soTiet} ${'home.periods'.tr()}'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: lop.mauSac,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child:  Text(
                    'common.close'.tr(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
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

  Widget xayDungHangChiTiet(IconData bieuTuong, String nhan, String giaTri) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(bieuTuong, size: 20, color: Theme.of(context).iconTheme.color?.withOpacity(0.7)),
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
}