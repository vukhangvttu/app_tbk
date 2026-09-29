import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_tbk/features/auth/services/auth_service.dart';

class AcademicConfig {
  static const String _prefKeyNgayBatDau = 'academic_ngay_bat_dau';
  static const String _prefKeyHocKy = 'academic_hoc_ky';
  static const String _prefKeyNamHoc = 'academic_nam_hoc';

  /// Ngày bắt đầu của học kỳ hiện tại (mặc định nếu chưa load từ API)
  static DateTime _ngayBatDauHocKy = DateTime(2026, 9, 1);

  /// Học kỳ hiện tại
  static int _hocKy = 1;

  /// Năm học hiện tại
  static String _namHoc = '2026-2027';

  static bool _isLoaded = false;

  static DateTime get ngayBatDauHocKy => _ngayBatDauHocKy;
  static int get hocKy => _hocKy;
  static String get namHoc => _namHoc;
  static bool get isLoaded => _isLoaded;

  /// Load dữ liệu từ SharedPreferences cache khi khởi động
  static Future<void> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDateStr = prefs.getString(_prefKeyNgayBatDau);
      final savedHocKy = prefs.getInt(_prefKeyHocKy);
      final savedNamHoc = prefs.getString(_prefKeyNamHoc);

      if (savedDateStr != null && savedDateStr.isNotEmpty) {
        final date = DateTime.tryParse(savedDateStr);
        if (date != null) {
          _ngayBatDauHocKy = date;
        }
      }
      if (savedHocKy != null) {
        _hocKy = savedHocKy;
      }
      if (savedNamHoc != null && savedNamHoc.isNotEmpty) {
        _namHoc = savedNamHoc;
      }
      _isLoaded = true;
      debugPrint('  ✓ AcademicConfig loaded from cache: hocKy=$_hocKy, namHoc=$_namHoc, ngayBatDau=$_ngayBatDauHocKy');
    } catch (e) {
      debugPrint('  ✗ Error loading AcademicConfig from cache: $e');
    }
  }

  /// Tải thông tin học kỳ từ API back-end GET /api/v1/academic-term
  static Future<bool> fetchAcademicTerm() async {
    // Nếu chưa load cache thì load cache trước
    if (!_isLoaded) {
      await loadFromCache();
    }

    try {
      debugPrint('🌐 Fetching academic term from GET /academic-term...');
      final response = await AuthService.authenticatedRequestLichSinhVien(
        method: 'GET',
        endpoint: '/academic-term',
      );

      if (response != null && response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        Map<String, dynamic>? data;

        if (decoded is Map<String, dynamic>) {
          if (decoded['data'] is Map<String, dynamic>) {
            data = decoded['data'];
          } else {
            data = decoded;
          }
        }

        if (data != null) {
          final rawDate = data['ngayBatDauHocKy'] ?? data['ngay_bat_dau_hoc_ky'] ?? data['ngayBatDau'];
          final rawHocKy = data['hocKy'] ?? data['hoc_ky'];
          final rawNamHoc = data['namHoc'] ?? data['nam_hoc'];

          final parsedDate = _parseDate(rawDate);
          final parsedHocKy = _parseInt(rawHocKy);
          final parsedNamHoc = rawNamHoc?.toString();

          if (parsedDate != null) _ngayBatDauHocKy = parsedDate;
          if (parsedHocKy != null) _hocKy = parsedHocKy;
          if (parsedNamHoc != null && parsedNamHoc.isNotEmpty) _namHoc = parsedNamHoc;

          _isLoaded = true;
          debugPrint('  ✓ AcademicConfig fetched successfully: hocKy=$_hocKy, namHoc=$_namHoc, ngayBatDau=$_ngayBatDauHocKy');

          // Lưu cache vào SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefKeyNgayBatDau, _ngayBatDauHocKy.toIso8601String());
          await prefs.setInt(_prefKeyHocKy, _hocKy);
          await prefs.setString(_prefKeyNamHoc, _namHoc);

          return true;
        }
      } else {
        debugPrint('  ⚠️ AcademicConfig API status code: ${response?.statusCode}');
      }
    } catch (e) {
      debugPrint('  ✗ Error fetching AcademicConfig: $e');
    }

    return false;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty) return null;
    try {
      return DateTime.parse(str);
    } catch (_) {}
    try {
      final parts = str.split('/');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}
