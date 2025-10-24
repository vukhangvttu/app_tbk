import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppNotificationSettings {
  final bool enabled;
  final bool scheduleEnabled;
  final int scheduleHour;
  final int scheduleMinute;
  final bool examEnabled;
  final int examHour;
  final int examMinute;
  final int reminderMinutes;
  final int examReminderDays;

  AppNotificationSettings({
    required this.enabled,
    required this.scheduleEnabled,
    required this.scheduleHour,
    required this.scheduleMinute,
    required this.examEnabled,
    required this.examHour,
    required this.examMinute,
    required this.reminderMinutes,
    required this.examReminderDays,
  });

  String get scheduleTimeString => '$scheduleHour:${scheduleMinute.toString().padLeft(2, '0')}';
  String get examTimeString => '$examHour:${examMinute.toString().padLeft(2, '0')}';

  AppNotificationSettings copyWith({
    bool? enabled,
    bool? scheduleEnabled,
    int? scheduleHour,
    int? scheduleMinute,
    bool? examEnabled,
    int? examHour,
    int? examMinute,
    int? reminderMinutes,
    int? examReminderDays,
  }) {
    return AppNotificationSettings(
      enabled: enabled ?? this.enabled,
      scheduleEnabled: scheduleEnabled ?? this.scheduleEnabled,
      scheduleHour: scheduleHour ?? this.scheduleHour,
      scheduleMinute: scheduleMinute ?? this.scheduleMinute,
      examEnabled: examEnabled ?? this.examEnabled,
      examHour: examHour ?? this.examHour,
      examMinute: examMinute ?? this.examMinute,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      examReminderDays: examReminderDays ?? this.examReminderDays,
    );
  }

  factory AppNotificationSettings.fromJson(Map<String, dynamic> json) {
    return AppNotificationSettings(
      enabled: json['enabled'] ?? false,
      scheduleEnabled: json['scheduleEnabled'] ?? false,
      scheduleHour: json['scheduleHour'] ?? 8,
      scheduleMinute: json['scheduleMinute'] ?? 0,
      examEnabled: json['examEnabled'] ?? false,
      examHour: json['examHour'] ?? 8,
      examMinute: json['examMinute'] ?? 0,
      reminderMinutes: json['reminderMinutes'] ?? 0,
      examReminderDays: json['examReminderDays'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'scheduleEnabled': scheduleEnabled,
      'scheduleHour': scheduleHour,
      'scheduleMinute': scheduleMinute,
      'examEnabled': examEnabled,
      'examHour': examHour,
      'examMinute': examMinute,
      'reminderMinutes': reminderMinutes,
      'examReminderDays': examReminderDays,
    };
  }
}

class SmartNotificationService {
  static final SmartNotificationService _instance = SmartNotificationService._internal();
  factory SmartNotificationService() => _instance;
  SmartNotificationService._internal();

  static SmartNotificationService get instance => _instance;

  // Giá trị mặc định nếu API không trả về dữ liệu
  AppNotificationSettings get _defaultSettings => AppNotificationSettings(
    enabled: false,
    scheduleEnabled: true,
    scheduleHour: 8,
    scheduleMinute: 30,
    examEnabled: true,
    examHour: 6,
    examMinute: 0,
    reminderMinutes: 30,
    examReminderDays: 3,
  );

  Future<AppNotificationSettings> getSettings({String mssv = '7231620971'}) async {
    try {
      final response = await http.get(
        Uri.parse('http://192.168.0.9:8080/notification-service/api/users/get-settings/$mssv'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      print('🔍 API get-settings response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        return AppNotificationSettings.fromJson(jsonData);
      } else {
        print('⚠️ API error, using default settings');
        return _defaultSettings;
      }
    } catch (e) {
      print('❌ Error fetching settings: $e');
      return _defaultSettings;
    }
  }

  Future<void> saveSettings(AppNotificationSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notification_settings', jsonEncode(settings.toJson()));
    print('🔍 Saved settings locally: ${settings.toJson()}');
  }
}