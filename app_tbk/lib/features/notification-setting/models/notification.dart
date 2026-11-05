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
  final String notificationSound; // 'system', 'sound_gentle', 'sound_energetic', 'sound_bell'
  final bool isDefaultSettings; // Thêm flag để đánh dấu là settings mặc định
  final bool attendanceInEnabled;
  final int attendanceInMinutes;
  final bool attendanceOutEnabled;
  final int attendanceOutMinutes;


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
    this.notificationSound = 'system',
    this.isDefaultSettings = false,
    required this.attendanceInEnabled,
    required this.attendanceInMinutes,
    required this.attendanceOutEnabled,
    required this.attendanceOutMinutes
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
    String? notificationSound,
    bool? isDefaultSettings,
    bool? attendanceInEnabled,
    int? attendanceInMinutes,
    bool? attendanceOutEnabled,
    int? attendanceOutMinutes
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
      notificationSound: notificationSound ?? this.notificationSound,
      isDefaultSettings: isDefaultSettings ?? this.isDefaultSettings,
        attendanceInEnabled: attendanceInEnabled ?? this.attendanceInEnabled,
      attendanceInMinutes: attendanceInMinutes ?? this.attendanceInMinutes,
        attendanceOutEnabled: attendanceOutEnabled ?? this.attendanceOutEnabled,
        attendanceOutMinutes: attendanceOutMinutes ?? this.attendanceOutMinutes

    );
  }

  factory AppNotificationSettings.fromJson(Map<String, dynamic> json, {bool isDefault = false}) {
    return AppNotificationSettings(
      enabled: json['enabled'] ?? false,
      scheduleEnabled: json['schedule_enabled'] ?? json['scheduleEnabled'] ?? true,
      scheduleHour: json['schedule_hour'] ?? json['scheduleHour'] ?? 8,
      scheduleMinute: json['schedule_minute'] ?? json['scheduleMinute'] ?? 30,
      examEnabled: json['exam_enabled'] ?? json['examEnabled'] ?? true,
      examHour: json['exam_hour'] ?? json['examHour'] ?? 8,
      examMinute: json['exam_minute'] ?? json['examMinute'] ?? 0,
      reminderMinutes: json['reminder_minutes'] ?? json['reminderMinutes'] ?? 30,
      examReminderDays: json['exam_reminder_days'] ?? json['examReminderDays'] ?? 3,
      notificationSound: json['notification_sound'] ?? json['notificationSound'] ?? 'system',
      isDefaultSettings: isDefault,
      attendanceInEnabled: json['attendance_in_enabled'] ?? true,
      attendanceInMinutes: json['attendance_in_minutes'] ?? 5,
      attendanceOutEnabled: json['attendance_out_enabled'] ?? true,
      attendanceOutMinutes: json['attendance_out_minutes'] ?? 5,

    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'schedule_enabled': scheduleEnabled,
      'schedule_hour': scheduleHour,
      'schedule_minute': scheduleMinute,
      'exam_enabled': examEnabled,
      'exam_hour': examHour,
      'exam_minute': examMinute,
      'reminder_minutes': reminderMinutes,
      'exam_reminder_days': examReminderDays,
      'notification_sound': notificationSound,
    };
  }
}
