// directions_service.dart
//
// Dùng Google Routes API (mới) — endpoint `computeRoutes` — thay cho
// Directions API cũ. Routes API hỗ trợ travelMode "TWO_WHEELER" (xe máy)
// thực sự, thay vì phải giả lập bằng "driving" như Directions API cũ.
//
// Docs: https://developers.google.com/maps/documentation/routes/compute_route_directions
//
// Bật "Routes API" trong Google Cloud Console (khác với "Directions API").

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';

/// Travel mode của Routes API.
/// https://developers.google.com/maps/documentation/routes/reference/rest/v2/RouteTravelMode
enum RoutesTravelMode { drive, walk, bicycle, twoWheeler, transit }

extension RoutesTravelModeExtension on RoutesTravelMode {
  String get apiValue {
    switch (this) {
      case RoutesTravelMode.drive:
        return 'DRIVE';
      case RoutesTravelMode.walk:
        return 'WALK';
      case RoutesTravelMode.bicycle:
        return 'BICYCLE';
      case RoutesTravelMode.twoWheeler:
        return 'TWO_WHEELER'; // xe máy — chỉ Routes API mới có
      case RoutesTravelMode.transit:
        return 'TRANSIT';
    }
  }

  /// TWO_WHEELER và TRANSIT không hỗ trợ routingPreference TRAFFIC_AWARE*.
  bool get supportsTrafficAwareRouting =>
      this == RoutesTravelMode.drive || this == RoutesTravelMode.twoWheeler;
}

/// Một bước chỉ đường (rẽ trái/phải, đi thẳng...).
class DirectionStep {
  final String instruction; // "Rẽ phải vào Lê Thánh Tôn"
  final String distanceText; // "150 m"
  final String durationText; // "1 phút"
  final LatLng startLocation;
  final LatLng endLocation;
  final List<LatLng> points;
  final String maneuver; // "TURN_RIGHT", "STRAIGHT", ...

  DirectionStep({
    required this.instruction,
    required this.distanceText,
    required this.durationText,
    required this.startLocation,
    required this.endLocation,
    required this.points,
    required this.maneuver,
  });

  factory DirectionStep.fromJson(Map<String, dynamic> json) {
    final start = json['startLocation']?['latLng'];
    final end = json['endLocation']?['latLng'];
    final distanceMeters = (json['distanceMeters'] as num?)?.toInt() ?? 0;
    final durationSeconds = _parseSeconds(json['staticDuration'] as String?);
    final polyline = json['polyline']?['encodedPolyline'] as String?;

    return DirectionStep(
      instruction: (json['navigationInstruction']?['instructions'] as String?) ?? 'Tiếp tục',
      distanceText: formatDistance(distanceMeters),
      durationText: formatDuration(durationSeconds),
      startLocation: LatLng(
        (start?['latitude'] as num?)?.toDouble() ?? 0,
        (start?['longitude'] as num?)?.toDouble() ?? 0,
      ),
      endLocation: LatLng(
        (end?['latitude'] as num?)?.toDouble() ?? 0,
        (end?['longitude'] as num?)?.toDouble() ?? 0,
      ),
      points: polyline == null
          ? const []
          : decodePolyline(polyline).map((p) => LatLng(p[0].toDouble(), p[1].toDouble())).toList(),
      maneuver: (json['navigationInstruction']?['maneuver'] as String?) ?? '',
    );
  }
}

/// Kết quả một tuyến đường: polyline tổng, khoảng cách, thời gian, các bước.
class DirectionsResult {
  final List<LatLng> polylinePoints;
  final String distanceText;
  final String durationText;
  final List<DirectionStep> steps;

  DirectionsResult({
    required this.polylinePoints,
    required this.distanceText,
    required this.durationText,
    required this.steps,
  });
}

/// Parse chuỗi kiểu "1234s" (Routes API trả `duration` dạng Duration proto) -> giây.
int _parseSeconds(String? raw) {
  if (raw == null) return 0;
  final match = RegExp(r'^(\d+)s?$').firstMatch(raw.replaceAll('s', ''));
  return int.tryParse(match?.group(1) ?? '0') ?? 0;
}

/// Định dạng số giây -> "24 phút" / "1 giờ 45 phút".
String formatDuration(int seconds) {
  final totalMinutes = (seconds / 60).round();
  if (totalMinutes < 60) return '$totalMinutes phút';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return minutes == 0 ? '$hours giờ' : '$hours giờ $minutes phút';
}

/// Định dạng số mét -> "8,6 km" / "150 m".
String formatDistance(int meters) {
  if (meters < 1000) return '$meters m';
  final km = meters / 1000;
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

class DirectionsService {
  final String apiKey;
  DirectionsService(this.apiKey);

  static const _endpoint = 'https://routes.googleapis.com/directions/v2:computeRoutes';

  static final _fieldMask = [
    'routes.duration',
    'routes.distanceMeters',
    'routes.polyline.encodedPolyline',
    'routes.legs.steps.navigationInstruction',
    'routes.legs.steps.distanceMeters',
    'routes.legs.steps.staticDuration',
    'routes.legs.steps.polyline.encodedPolyline',
    'routes.legs.steps.startLocation',
    'routes.legs.steps.endLocation',
  ].join(',');

  /// Gọi Routes API (computeRoutes) và trả về [DirectionsResult] đã decode polyline.
  Future<DirectionsResult> getDirections({
    required LatLng origin,
    required LatLng destination,
    RoutesTravelMode mode = RoutesTravelMode.drive,
    String languageCode = 'vi',
  }) async {
    final body = <String, dynamic>{
      'origin': {
        'location': {
          'latLng': {'latitude': origin.latitude, 'longitude': origin.longitude}
        }
      },
      'destination': {
        'location': {
          'latLng': {'latitude': destination.latitude, 'longitude': destination.longitude}
        }
      },
      'travelMode': mode.apiValue,
      if (mode.supportsTrafficAwareRouting) 'routingPreference': 'TRAFFIC_AWARE',
      'computeAlternativeRoutes': false,
      'languageCode': languageCode,
      'units': 'METRIC',
    };

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': _fieldMask,
      },
      body: json.encode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Routes API HTTP ${response.statusCode}: ${response.body}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) {
      throw Exception('Routes API không trả về tuyến đường nào.');
    }

    final route = routes.first as Map<String, dynamic>;
    final distanceMeters = (route['distanceMeters'] as num?)?.toInt() ?? 0;
    final durationSeconds = _parseSeconds(route['duration'] as String?);
    final encodedPolyline = route['polyline']?['encodedPolyline'] as String?;

    final overviewPoints = encodedPolyline == null
        ? <LatLng>[]
        : decodePolyline(encodedPolyline).map((p) => LatLng(p[0].toDouble(), p[1].toDouble())).toList();

    final legs = (route['legs'] as List?) ?? const [];
    final steps = <DirectionStep>[];
    for (final leg in legs) {
      final legSteps = (leg['steps'] as List?) ?? const [];
      steps.addAll(legSteps.map((s) => DirectionStep.fromJson(s as Map<String, dynamic>)));
    }

    return DirectionsResult(
      polylinePoints: overviewPoints,
      distanceText: formatDistance(distanceMeters),
      durationText: formatDuration(durationSeconds),
      steps: steps,
    );
  }
}
