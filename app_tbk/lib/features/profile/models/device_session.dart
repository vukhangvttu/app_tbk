// lib/features/profile/models/device_session.dart
class DeviceSession {
  final String id;
  final String userId;
  final String deviceId;
  final String deviceName;
  final String deviceType;
  final String os;
  final String osVersion;
  final String appVersion;
  final String browser;
  final String ipAddress;
  final String userAgent;
  final bool isActive;
  final DateTime loginAt;
  final DateTime lastActiveAt;
  final DateTime? logoutAt;
  final DateTime expiresAt;
  final DateTime createdAt;

  DeviceSession({
    required this.id,
    required this.userId,
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.os,
    required this.osVersion,
    required this.appVersion,
    required this.browser,
    required this.ipAddress,
    required this.userAgent,
    required this.isActive,
    required this.loginAt,
    required this.lastActiveAt,
    this.logoutAt,
    required this.expiresAt,
    required this.createdAt,
  });

  factory DeviceSession.fromJson(Map<String, dynamic> json) {
    return DeviceSession(
      id: json['id'],
      userId: json['user_id'],
      deviceId: json['device_id'],
      deviceName: json['device_name'],
      deviceType: json['device_type'],
      os: json['os'],
      osVersion: json['os_version'],
      appVersion: json['app_version'],
      browser: json['browser'] ?? '',
      ipAddress: json['ip_address'],
      userAgent: json['user_agent'],
      isActive: json['is_active'],
      loginAt: DateTime.parse(json['login_at']),
      lastActiveAt: DateTime.parse(json['last_active_at']),
      logoutAt: json['logout_at'] != null ? DateTime.parse(json['logout_at']) : null,
      expiresAt: DateTime.parse(json['expires_at']),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  bool get isCurrentDevice => deviceId == _currentDeviceId;
  static String? _currentDeviceId;

  static void setCurrentDeviceId(String deviceId) {
    _currentDeviceId = deviceId;
  }
}