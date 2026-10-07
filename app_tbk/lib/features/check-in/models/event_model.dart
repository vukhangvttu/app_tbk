class CheckInEvent {
  final String id;
  final String name;
  final DateTime date;
  final DateTime checkInStartTime;
  final DateTime checkInEndTime;
  final String? location;
  final double? latitude;
  final double? longitude;
  final double radiusMeters;
  final double? widthMeters;
  final double? heightMeters;
  final double rotationDeg;
  final bool isCheckedIn;

  bool get hasGeofence => latitude != null && longitude != null;

  CheckInEvent({
    required this.id,
    required this.name,
    required this.date,
    required this.checkInStartTime,
    required this.checkInEndTime,
    this.location,
    this.latitude,
    this.longitude,
    this.radiusMeters = 100,
    this.widthMeters,
    this.heightMeters,
    this.rotationDeg = 0,
    this.isCheckedIn = false,
  });

  factory CheckInEvent.fromJson(Map<String, dynamic> json) {
    return CheckInEvent(
      id: json['id'],
      name: json['name'],
      date: DateTime.parse(json['date']),
      checkInStartTime: DateTime.parse(json['checkInStartTime']),
      checkInEndTime: DateTime.parse(json['checkInEndTime']),
      location: json['location'],
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      radiusMeters: (json['radius_meters'] as num?)?.toDouble() ?? 100,
      widthMeters: (json['width_meters'] as num?)?.toDouble(),
      heightMeters: (json['height_meters'] as num?)?.toDouble(),
      rotationDeg: (json['rotation_deg'] as num?)?.toDouble() ?? 0,
      isCheckedIn: json['isCheckedIn'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'date': date.toIso8601String(),
      'checkInStartTime': checkInStartTime.toIso8601String(),
      'checkInEndTime': checkInEndTime.toIso8601String(),
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'width_meters': widthMeters,
      'height_meters': heightMeters,
      'rotation_deg': rotationDeg,
      'isCheckedIn': isCheckedIn,
    };
  }

  bool get canCheckIn {
    final now = DateTime.now();
    return !now.isBefore(checkInStartTime) && !now.isAfter(checkInEndTime);
  }

  Duration get timeUntilCheckIn {
    final now = DateTime.now();
    if (now.isBefore(checkInStartTime)) {
      return checkInStartTime.difference(now);
    }
    return Duration.zero;
  }
}

class CheckInData {
  final String eventId;
  final String faceImageBase64;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  CheckInData({
    required this.eventId,
    required this.faceImageBase64,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'faceImage': faceImageBase64,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}