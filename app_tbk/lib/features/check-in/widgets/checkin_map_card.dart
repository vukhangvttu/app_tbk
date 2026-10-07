import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../utils/geofence_rect.dart';

/// Bản đồ hiển thị vùng check-in (vòng tròn hoặc đa giác) + vị trí ĐÃ LỌC của thiết bị.
/// Đặt tại: lib/features/checkin/widgets/checkin_map_card.dart
class CheckInMapCard extends StatefulWidget {
  final double eventLat;
  final double eventLng;
  final double radiusMeters;
  final GeoRect? zone;
  final bool inZone;
  final bool locationGranted;
  /// Không còn dùng để vẽ (chấm xanh native tự di chuyển). Giữ lại để
  /// tương thích với nơi gọi; có thể xóa cùng tham số bên CheckInScreen.
  final LatLng? userPosition;
  final String eventName;

  const CheckInMapCard({
    super.key,
    required this.eventLat,
    required this.eventLng,
    required this.radiusMeters,
    this.zone,
    required this.inZone,
    required this.locationGranted,
    required this.eventName,
    this.userPosition,
  });

  @override
  State<CheckInMapCard> createState() => _CheckInMapCardState();
}

class _CheckInMapCardState extends State<CheckInMapCard> {
  // Cho phép kéo/zoom bản đồ bên trong ListView (tạo 1 lần, dùng lại)
  static final Set<Factory<OneSequenceGestureRecognizer>> _gestures = {
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  GoogleMapController? _controller;

  late double _zoom;
  late Set<Polygon> _polygons;
  late Set<Circle> _circles;
  late Set<Marker> _eventMarkers;

  LatLng get _eventPoint => LatLng(widget.eventLat, widget.eventLng);

  @override
  void initState() {
    super.initState();
    _rebuildStatic();
  }

  @override
  void didUpdateWidget(covariant CheckInMapCard old) {
    super.didUpdateWidget(old);
    // Overlay chỉ dựng lại khi dữ liệu vùng thật sự đổi, KHÔNG dựng lại
    // mỗi lần có điểm GPS mới.
    if (old.inZone != widget.inZone ||
        old.zone != widget.zone ||
        old.radiusMeters != widget.radiusMeters ||
        old.eventLat != widget.eventLat ||
        old.eventLng != widget.eventLng ||
        old.eventName != widget.eventName) {
      _rebuildStatic();
    }
  }

  void _rebuildStatic() {
    final r = widget.radiusMeters.clamp(20, 5000);
    _zoom = (17.5 - math.log(r / 100) / math.ln2).clamp(12.0, 19.0);

    final color = widget.inZone ? Colors.green : Colors.red;
    final fill = color.withValues(alpha: 0.18);

    _eventMarkers = {
      Marker(
        markerId: const MarkerId('event'),
        position: _eventPoint,
        infoWindow: InfoWindow(title: widget.eventName),
      ),
    };

    final zone = widget.zone;
    _polygons = zone != null
        ? {
      Polygon(
        polygonId: const PolygonId('zone_rect'),
        points: zone.corners(),
        strokeWidth: 2,
        strokeColor: color,
        fillColor: fill,
      ),
    }
        : const {};

    _circles = zone == null
        ? {
      Circle(
        circleId: const CircleId('zone_circle'),
        center: _eventPoint,
        radius: widget.radiusMeters,
        strokeWidth: 2,
        strokeColor: color,
        fillColor: fill,
      ),
    }
        : const {};
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _focusEvent() {
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(_eventPoint, _zoom));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 260,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition:
              CameraPosition(target: _eventPoint, zoom: _zoom),
              onMapCreated: (c) => _controller = c,
              // Chấm xanh native: tự di chuyển theo thiết bị
              myLocationEnabled: widget.locationGranted,
              myLocationButtonEnabled: widget.locationGranted,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              markers: _eventMarkers,
              polygons: _polygons,
              circles: _circles,
              gestureRecognizers: _gestures,
            ),
            Positioned(
              left: 12,
              top: 12,
              child: _mapButton(
                scheme,
                icon: Icons.place,
                color: Colors.redAccent,
                tooltip: 'Về vùng check-in',
                onTap: _focusEvent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapButton(
      ColorScheme scheme, {
        required IconData icon,
        required Color color,
        required String tooltip,
        required VoidCallback onTap,
      }) {
    return Material(
      color: scheme.surface,
      elevation: 3,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }
}