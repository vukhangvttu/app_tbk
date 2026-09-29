import 'dart:async';
import 'dart:convert';
import 'package:app_tbk/features/auth/services/auth_service.dart';
import 'package:app_tbk/features/notification-setting/models/notification.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:app_tbk/features/notification-setting/screens/notification_dialog.dart';
import 'package:app_tbk/services/smart_notification_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:easy_localization/easy_localization.dart';
                                                                                                                                                      import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';



class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final _service = SmartNotificationService.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _playingSoundId;

  AppNotificationSettings? _settings;
  bool _loading = true;
  bool _isLoading = false;
  bool _hasUnsavedChanges = false;

  final List<Map<String, String>> _soundOptions = [
    {
      'id': 'system',
      'title': 'Theo hệ thống',
      'description': 'Mặc định theo cài đặt âm thanh điện thoại',
    },
    {
      'id': 'sound_gentle',
      'title': 'Âm 1: Nhẹ nhàng',
      'description': 'Âm báo êm dịu, nhẹ nhàng',
    },
    {
      'id': 'sound_energetic',
      'title': 'Âm 2: Sôi động',
      'description': 'Giai điệu vui tươi, năng động',
    },
    {
      'id': 'sound_bell',
      'title': 'Âm 3: Chuông báo',
      'description': 'Tiếng chuông cổ điển rõ ràng',
    },
  ];

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  @override
  void dispose() {
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final mssv = await AuthService.getSavedMssv() ?? '0';
      print('🔄 Đang gọi lấy Settings cho MSSV: $mssv');
      final settings = await _service.getSettings(mssv);
      
      print('✅ Đã load Settings: ${settings != null ? jsonEncode(settings.toJson()) : "NULL"}');

      if (mounted) {
        setState(() {
          _settings = settings ?? _service.defaultSettings;
          _loading = false;
          _hasUnsavedChanges = false;
        });
      }
    } catch (e) {
      print('❌ Lỗi _loadSettings: $e');
      if (mounted) {
        setState(() {
          _settings = _service.defaultSettings;
          _loading = false;
          _hasUnsavedChanges = false;
        });
      }
    }
  }

  void _onSettingsChanged(AppNotificationSettings newSettings) {
    setState(() {
      _settings = newSettings;
      _hasUnsavedChanges = true;
    });
  }

  String _getSoundTitle(String soundId) {
    final found = _soundOptions.firstWhere(
      (element) => element['id'] == soundId,
      orElse: () => _soundOptions.first,
    );
    return found['title'] ?? 'Theo hệ thống';
  }

  Future<void> _saveSettings() async {
    if (_settings == null) {
      showNotificationDialog(
        context,
        'Lỗi',
        'Không thể lưu cài đặt. Vui lòng thử lại.',
        isSuccess: false,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final mssv = await AuthService.getSavedMssv();
      if (mssv == null || mssv.isEmpty) {
        throw Exception('Không tìm thấy thông tin sinh viên');
      }

      String? idSinhVien = await AuthService.getIdSinhVien();
      if (idSinhVien == null || idSinhVien.isEmpty) {
        final token = await AuthService.getToken();
        if (token != null && token.isNotEmpty) {
          try {
            final decodedToken = JwtDecoder.decode(token);
            idSinhVien = decodedToken['id_sinh_vien']?.toString() ??
                decodedToken['idSinhVien']?.toString();
          } catch (e) {
            print('❌ Lỗi decode token lấy id_sinh_vien: $e');
          }
        }
      }

      if (idSinhVien == null || idSinhVien.isEmpty) {
        throw Exception('Không tìm thấy thông tin ID sinh viên');
      }

      final Map<String, dynamic> payload = {
        'mssv': mssv,
        'idsinhvien': idSinhVien,
        'enabled': _settings!.enabled,
        'schedule_enabled': _settings!.scheduleEnabled,
        'schedule_hour': _settings!.scheduleHour,
        'schedule_minute': _settings!.scheduleMinute,
        'exam_enabled': _settings!.examEnabled,
        'exam_hour': _settings!.examHour,
        'exam_minute': _settings!.examMinute,
        'reminder_minutes': _settings!.reminderMinutes,
        'exam_reminder_days': _settings!.examReminderDays,
        'notification_sound': _settings!.notificationSound,
      };



      print("Body gửi đi: ${jsonEncode(payload)}");

      final response = await AuthService.authenticatedRequestNotification(
        method: 'PUT',
        endpoint: '/users/$mssv/settings',
        body: payload,
      ).timeout(const Duration(seconds: 15));


      if (response != null && (response.statusCode == 200 || response.statusCode == 201)) {
        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
        if (jsonResponse['success'] == true) {
          setState(() {
            _settings = _settings!.copyWith(isDefaultSettings: false);
            _hasUnsavedChanges = false;
          });

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('notification_settings', jsonEncode(_settings!.toJson()));

          showNotificationDialog(
            context,
            'Thành công',
            'Cài đặt đã được lưu',
          );
        } else {
          throw Exception('Lưu thất bại');
        }
      } else {
        throw Exception('Lỗi kết nối');
      }
    } catch (error) {
      if (!mounted) return;
      final errorStr = error.toString();
      if (!errorStr.contains('Session hết hạn') &&
          !errorStr.contains('hết hạn') &&
          !errorStr.contains('401')) {
        showNotificationDialog(
          context,
          'Lỗi',
          'Không thể lưu cài đặt: $errorStr',
          isSuccess: false,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('notification_settings.title'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_settings == null) {
      return Scaffold(
        appBar: AppBar(title: Text('notification_settings.title'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Text('notification_settings.title'.tr()),
        elevation: 0,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Main Switch
              _buildMainToggle(isDark),

              const SizedBox(height: 24),

              // Schedule Settings
              _buildSection(
                isDark: isDark,
                title: '📚 Lịch học',
                enabled: _settings!.enabled,
                children: [
                  _buildSwitch(
                    title: 'Bật thông báo lịch học',
                    value: _settings!.scheduleEnabled && _settings!.enabled,
                    onChanged: _settings!.enabled
                        ? (v) => _onSettingsChanged(_settings!.copyWith(scheduleEnabled: v))
                        : null,
                    isDark: isDark,
                  ),
                  if (_settings!.scheduleEnabled && _settings!.enabled) ...[
                    const SizedBox(height: 12),
                    _buildTimePicker(
                      isDark: isDark,
                      label: 'Thời gian nhắc',
                      time: _settings!.scheduleTimeString,
                      onTap: _selectScheduleTime,
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 16),

              // Exam Settings
              _buildSection(
                isDark: isDark,
                title: '📝 Lịch thi',
                enabled: _settings!.enabled,
                children: [
                  _buildSwitch(
                    title: 'Bật thông báo lịch thi',
                    value: _settings!.examEnabled && _settings!.enabled,
                    onChanged: _settings!.enabled
                        ? (v) => _onSettingsChanged(_settings!.copyWith(examEnabled: v))
                        : null,
                    isDark: isDark,
                  ),
                  if (_settings!.examEnabled && _settings!.enabled) ...[
                    const SizedBox(height: 12),
                    _buildTimePicker(
                      isDark: isDark,
                      label: 'Thời gian nhắc',
                      time: _settings!.examTimeString,
                      onTap: _selectExamTime,
                    ),
                    const SizedBox(height: 12),
                    _buildSlider(
                      isDark: isDark,
                      label: 'Nhắc trước',
                      value: _settings!.examReminderDays.toDouble(),
                      max: 7,
                      divisions: 7,
                      displayValue: _settings!.examReminderDays == 0
                          ? 'Tắt'
                          : '${_settings!.examReminderDays} ngày',
                      onChanged: (v) => _onSettingsChanged(
                        _settings!.copyWith(examReminderDays: v.toInt()),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 16),

              // Reminder Settings
              if (_settings!.enabled &&
                  (_settings!.scheduleEnabled || _settings!.examEnabled))
                _buildSection(
                  isDark: isDark,
                  title: '⏰ Nhắc trước giờ học/thi',
                  enabled: _settings!.enabled,
                  children: [
                    _buildSlider(
                      isDark: isDark,
                      label: 'Nhắc trước',
                      value: _settings!.reminderMinutes.toDouble(),
                      max: 120,
                      divisions: 8,
                      displayValue: _settings!.reminderMinutes == 0
                          ? 'Tắt'
                          : '${_settings!.reminderMinutes} phút',
                      onChanged: (v) => _onSettingsChanged(
                        _settings!.copyWith(reminderMinutes: v.toInt()),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 16),

              // Cài đặt âm thanh
              if (_settings!.enabled)
                _buildSection(
                  isDark: isDark,
                  title: '🎵 Âm thanh thông báo',
                  enabled: _settings!.enabled,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Âm báo'),
                      subtitle: Text(_getSoundTitle(_settings!.notificationSound)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showSoundPickerBottomSheet,
                    ),
                  ],
                ),

              const SizedBox(height: 32),

              // Save Button
              _buildSaveButton(isDark),

              const SizedBox(height: 20),
            ],
          ),

          // Loading Overlay
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMainToggle(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _settings!.enabled
              ? [Colors.blue[600]!, Colors.blue[400]!]
              : [Colors.grey[600]!, Colors.grey[500]!],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (_settings!.enabled ? Colors.blue : Colors.grey).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            _settings!.enabled ? Icons.notifications_active : Icons.notifications_off,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bật thông báo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _settings!.enabled
                      ? 'Đang bật - Nhận thông báo tự động'
                      : 'Đang tắt - Không nhận thông báo',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          Switch(
            value: _settings!.enabled,
            onChanged: (v) => _onSettingsChanged(_settings!.copyWith(enabled: v)),
            activeTrackColor: Colors.white.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required bool isDark,
    required String title,
    required bool enabled,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: enabled
                  ? (isDark ? Colors.white : Colors.grey[900])
                  : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitch({
    required String title,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required bool isDark,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            color: onChanged != null
                ? (isDark ? Colors.white : Colors.grey[900])
                : Colors.grey[500],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _showSoundPickerBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Chọn âm thanh thông báo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _soundOptions.length,
                  itemBuilder: (context, index) {
                    final option = _soundOptions[index];
                    final isSelected = _settings!.notificationSound == option['id'];
                    final isPlaying = _playingSoundId == option['id'];

                    return ListTile(
                      leading: Icon(
                        option['id'] == 'system' ? Icons.notifications : Icons.music_note,
                        color: isSelected ? Colors.blue : null,
                      ),
                      title: Text(
                        option['title']!,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.blue : null,
                        ),
                      ),
                      subtitle: Text(option['description']!),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (option['id'] != 'system')
                            IconButton(
                              icon: Icon(
                                isPlaying ? Icons.stop_circle : Icons.play_circle_outline,
                                color: isPlaying ? Colors.red : Colors.grey,
                              ),
                              onPressed: () => _playSoundPreview(option['id']!),
                            ),
                          if (isSelected)
                            const Icon(Icons.check_circle, color: Colors.blue),
                        ],
                      ),
                      onTap: () {
                        _onSettingsChanged(_settings!.copyWith(notificationSound: option['id']!));
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      _audioPlayer.stop();
      if (mounted) {
        setState(() => _playingSoundId = null);
      }
    });
  }

  Future<void> _playSoundPreview(String soundId) async {
    if (soundId == 'system') return;

    if (_playingSoundId == soundId) {
      await _audioPlayer.stop();
      if (mounted) {
        setState(() => _playingSoundId = null);
      }
      return;
    }

    try {
      await _audioPlayer.stop();
      
      // Chơi file từ assets
      String assetPath = 'sounds/$soundId.mp3';
      await _audioPlayer.play(AssetSource(assetPath));
      
      if (mounted) {
        setState(() => _playingSoundId = soundId);
      }

      _audioPlayer.onPlayerComplete.listen((event) {
        if (mounted) {
          setState(() => _playingSoundId = null);
        }
      });
    } catch (e) {
      print('Lỗi khi phát âm thanh: $e');
      if (mounted) {
        setState(() => _playingSoundId = null);
      }
    }
  }

  Widget _buildTimePicker({
    required bool isDark,
    required String label,
    required String time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.blue, size: 20),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.grey[900],
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                time,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider({
    required bool isDark,
    required String label,
    required double value,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: value == 0 ? Colors.grey : Colors.blue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                displayValue,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: Colors.blue,
        ),
      ],
    );
  }

  Widget _buildSaveButton(bool isDark) {
    return ElevatedButton(
      onPressed: _hasUnsavedChanges && !_isLoading ? _saveSettings : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: _hasUnsavedChanges ? Colors.blue : Colors.grey,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: _hasUnsavedChanges ? 4 : 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_hasUnsavedChanges ? Icons.save : Icons.check_circle),
          const SizedBox(width: 12),
          Text(
            _hasUnsavedChanges ? 'Lưu thay đổi' : 'Đã lưu',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _selectScheduleTime() async {
    if (_settings == null) return;

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _settings!.scheduleHour,
        minute: _settings!.scheduleMinute,
      ),
    );

    if (picked != null && mounted) {
      _onSettingsChanged(_settings!.copyWith(
        scheduleHour: picked.hour,
        scheduleMinute: picked.minute,
      ));
    }
  }

  Future<void> _selectExamTime() async {
    if (_settings == null) return;

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _settings!.examHour,
        minute: _settings!.examMinute,
      ),
    );

    if (picked != null && mounted) {
      _onSettingsChanged(_settings!.copyWith(
        examHour: picked.hour,
        examMinute: picked.minute,
      ));
    }
  }
}
