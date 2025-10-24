// lib/models/class_schedule.dart
import 'dart:ffi';

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
  }) : mauSac = mauSac ?? _layMauSacChoMonHoc(tenMon);

  static Color _layMauSacChoMonHoc(String monHoc) {
    final mauSacList = [
      const Color(0xFF6366F1),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFF06B6D4),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF3B82F6),
    ];
    return mauSacList[monHoc.hashCode % mauSacList.length];
  }

  String get buoiHoc {
    final gio = int.parse(gioBd.split(':')[0]);
    if (gio < 12) return 'Sang';
    if (gio < 18) return 'Chieu';
    return 'Toi';
  }
}