import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:app_tbk/features/check-in/models/event_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Vùng check-in hình chữ nhật (có thể xoay).
/// - widthMeters: chiều Đông–Tây khi chưa xoay
/// - heightMeters: chiều Bắc–Nam khi chưa xoay
/// - rotationDeg: xoay theo chiều kim đồng hồ so với hướng Bắc (0 = không xoay)
/// Đặt tại: lib/features/checkin/utils/geofence_rect.dart
class GeoRect {
  final double centerLat;
  final double centerLng;
  final double widthMeters;
  final double heightMeters;
  final double rotationDeg;

  const GeoRect({
    required this.centerLat,
    required this.centerLng,
    required this.widthMeters,
    required this.heightMeters,
    this.rotationDeg = 0,
  });

  static const double _mPerDegLat = 111320.0;
  double get _mPerDegLng => _mPerDegLat * math.cos(centerLat * math.pi / 180);
  double get _b => rotationDeg * math.pi / 180;

  /// Tọa độ (lat,lng) -> hệ trục của hình chữ nhật, đơn vị mét.
  Offset _toLocal(double lat, double lng) {
    final east = (lng - centerLng) * _mPerDegLng;
    final north = (lat - centerLat) * _mPerDegLat;
    final c = math.cos(_b), s = math.sin(_b);
    return Offset(east * c - north * s, east * s + north * c);
  }

  /// Khoảng cách (m) từ điểm đến mép hình chữ nhật. 0 nếu nằm trong.
  double outsideDistance(double lat, double lng) {
    final p = _toLocal(lat, lng);
    final dx = math.max(p.dx.abs() - widthMeters / 2, 0.0);
    final dy = math.max(p.dy.abs() - heightMeters / 2, 0.0);
    return math.sqrt(dx * dx + dy * dy);
  }

  bool contains(double lat, double lng) => outsideDistance(lat, lng) <= 0;

  /// 4 góc để vẽ Polygon trên bản đồ.
  List<LatLng> corners() {
    final c = math.cos(_b), s = math.sin(_b);
    LatLng at(double lx, double ly) {
      final east = lx * c + ly * s;
      final north = -lx * s + ly * c;
      return LatLng(centerLat + north / _mPerDegLat, centerLng + east / _mPerDegLng);
    }

    final hw = widthMeters / 2, hh = heightMeters / 2;
    return [at(-hw, -hh), at(hw, -hh), at(hw, hh), at(-hw, hh)];
  }
}

extension CheckInEventZone on CheckInEvent {
  /// Chỉ tạo GeoRect khi có truyền vào widthMeters hoặc heightMeters rõ ràng
  GeoRect? get zone {
    if (!hasGeofence) return null;
    if (widthMeters == null && heightMeters == null) return null;
    
    return GeoRect(
      centerLat: latitude!,
      centerLng: longitude!,
      widthMeters: widthMeters ?? radiusMeters * 2,
      heightMeters: heightMeters ?? radiusMeters * 2,
      rotationDeg: rotationDeg,
    );
  }
}