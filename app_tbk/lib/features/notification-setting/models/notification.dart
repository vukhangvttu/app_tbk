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
  final bool isDefaultSettings; // Thêm flag để đánh dấu là settings mặc định

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
    this.isDefaultSettings = false,
  });

  String get scheduleTimeString =>
      '${scheduleHour.toString().padLeft(2, '0')}:${scheduleMinute.toString().padLeft(2, '0')}';
  String get examTimeString =>
      '${examHour.toString().padLeft(2, '0')}:${examMinute.toString().padLeft(2, '0')}';

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
    bool? isDefaultSettings,
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
      isDefaultSettings: isDefaultSettings ?? this.isDefaultSettings,
    );
  }

  factory AppNotificationSettings.fromJson(Map<String, dynamic> json, {bool isDefault = false}) {
    return AppNotificationSettings(
      enabled: json['enabled'] ?? false,
      scheduleEnabled: json['schedule_enabled'] ?? true,
      scheduleHour: json['schedule_hour'] ?? 8,
      scheduleMinute: json['schedule_minute'] ?? 30,
      examEnabled: json['exam_enabled'] ?? true,
      examHour: json['exam_hour'] ?? 6,
      examMinute: json['exam_minute'] ?? 0,
      reminderMinutes: json['reminder_minutes'] ?? 30,
      examReminderDays: json['exam_reminder_days'] ?? 3,
      isDefaultSettings: isDefault,
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
