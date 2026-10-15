// lib/models/class_schedule.dart
import 'package:flutter/material.dart';

class LopHoc {
  final String tenMon;
  final int thu;
  final String gioBd;
  final String gioKt;
  final String hoTen;
  final String tenPhong;
  final int maNhom;
  final int soTiet;
  final String phanBo;
  final DateTime ngayBd;
  final DateTime ngayKt;
  final Color mauSac;
  final bool nhomThi;
  final String thoiGianGiaiLao;
  final String noiDungBaiHoc;

  LopHoc({
    required this.tenMon,
    required this.thu,
    required this.gioBd,
    required this.gioKt,
    required this.hoTen,
    required this.tenPhong,
    required this.maNhom,
    required this.soTiet,
    required this.phanBo,
    required this.ngayBd,
    required this.ngayKt,
    Color? mauSac,
    required this.nhomThi,
    required this.thoiGianGiaiLao,
    required this.noiDungBaiHoc
  }) : mauSac = mauSac ?? _layMauSacChoMonHoc(tenMon);

  factory LopHoc.fromJson(Map<String, dynamic> json) {
    return LopHoc(
      tenMon: (json['TENMON'] as String?)?.trim() ?? '',
      thu: json['THU'] ?? 2,
      gioBd: json['GIOBD'] ?? '',
      gioKt: json['GIOKT'] ?? '',
      hoTen: (json['HOTEN'] as String?)?.trim() ?? '',
      tenPhong: (json['TENPHONG'] as String?)?.trim() ?? '',
      maNhom: json['manhom'] ?? 0,
      soTiet: json['SOTIET'] ?? 0,
      phanBo: json['PHANBO'] ?? '',
      ngayBd: _phanTichNgay(json['NGAYBD']),
      ngayKt: _phanTichNgay(json['NGAYKT']),
      nhomThi: json['NHOMTHI'] ?? false,
      thoiGianGiaiLao: json['THOIGIAN_GIAILAO'] ?? '',
      noiDungBaiHoc: json['NOIDUNG_BAIHOC'] ?? '',
    );
  }

  static DateTime _phanTichNgay(String? ngayStr) {
    if (ngayStr == null || ngayStr.isEmpty) {
      return DateTime.now();
    }
    try {
      final utcDate = DateTime.parse(ngayStr);
      final localDate = utcDate.toLocal();
      return DateTime(localDate.year, localDate.month, localDate.day);
    } catch (e) {
      return DateTime.now();
    }
  }

  static final Map<String, Color> _assignedColors = {};
  static int _colorIndex = 0;

  static Color _layMauSacChoMonHoc(String monHoc) {
    if (_assignedColors.containsKey(monHoc)) {
      return _assignedColors[monHoc]!;
    }

    final mauSacList = [
      const Color(0xFF6366F1), // Indigo
      const Color(0xFFF59E0B), // Amber
      const Color(0xFF10B981), // Emerald
      const Color(0xFFEC4899), // Pink
      const Color(0xFF3B82F6), // Blue
      const Color(0xFF8B5CF6), // Violet
      const Color(0xFFEF4444), // Red
      const Color(0xFF06B6D4), // Cyan
      const Color(0xFFF97316), // Orange
      const Color(0xFF14B8A6), // Teal
      const Color(0xFF84CC16), // Lime
      const Color(0xFF64748B), // Slate
    ];
    
    final color = mauSacList[_colorIndex % mauSacList.length];
    _assignedColors[monHoc] = color;
    _colorIndex++;
    return color;
  }

  String get buoiHoc {
    final gio = int.parse(gioBd.split(':')[0]);
    if (gio < 12) return 'Sang';
    if (gio < 18) return 'Chieu';
    return 'Toi';
  }
}