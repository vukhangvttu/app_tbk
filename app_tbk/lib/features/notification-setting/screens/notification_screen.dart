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

// ───────────────────────── Bảng màu ─────────────────────────

class _Tint {
  const _Tint(this.light, this.dark);
  final Color light;
  final Color dark;
}

class _P {
  const _P._({
    required this.dark,
    required this.bg,
    required this.card,
    required this.cardAlt,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.heroA,
    required this.heroB,
  });

  final bool dark;
  final Color bg, card, cardAlt, border, text, muted, accent, accentSoft;
  final Color heroA, heroB;

  static const _dark = _P._(
    dark: true,
    bg: Color(0xFF0B1020),
    card: Color(0xFF141B30),
    cardAlt: Color(0xFF1B2440),
    border: Color(0xFF232E4D),
    text: Color(0xFFEAEFFC),
    muted: Color(0xFF8E99B8),
    accent: Color(0xFF5B8CFF),
    accentSoft: Color(0xFF1E2D5E),
    heroA: Color(0xFF2A4BDB),
    heroB: Color(0xFF6C4DEB),
  );

  static const _light = _P._(
    dark: false,
    bg: Color(0xFFF3F5FA),
    card: Color(0xFFFFFFFF),
    cardAlt: Color(0xFFF3F6FC),
    border: Color(0xFFE4E9F3),
    text: Color(0xFF111827),
    muted: Color(0xFF6B7487),
    accent: Color(0xFF2F6BFF),
    accentSoft: Color(0xFFE6EEFF),
    heroA: Color(0xFF2F6BFF),
    heroB: Color(0xFF5B7CFA),
  );

  static _P of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  Color tint(_Tint t) => dark ? t.dark : t.light;
}

const _tintBlue = _Tint(Color(0xFF2F6BFF), Color(0xFF6C9BFF));
const _tintOrange = _Tint(Color(0xFFE8801A), Color(0xFFFFA94D));
const _tintPurple = _Tint(Color(0xFF7C5CE6), Color(0xFFB39DFF));
const _tintGreen = _Tint(Color(0xFF0E9F73), Color(0xFF3DDBA4));

// ───────────────────────── Màn hình ─────────────────────────

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _service = SmartNotificationService.instance;
  AudioPlayer? _audioPlayer;
  final ValueNotifier<String?> _playingSound = ValueNotifier<String?>(null);
  StreamSubscription<void>? _completeSub;

  AppNotificationSettings? _settings;
  bool _loading = true;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;

  static const List<int> _reminderMinutePresets = [0, 15, 30, 60, 90, 120];
  static const List<int> _examDayPresets = [0, 1, 2, 3, 5, 7];

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
    // Trì hoãn khởi tạo AudioPlayer để không làm khựng animation chuyển trang
    // Trì hoãn gọi API và Secure Storage cho đến khi animation chuyển trang hoàn tất (~300ms)
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _loadSettings();
      }
    });
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    _playingSound.dispose();
    super.dispose();
  }

  // ───────────────────────── Logic ─────────────────────────

  Future<void> _loadSettings() async {
    try {
      final mssv = await AuthService.getSavedMssv() ?? '0';
      debugPrint('🔄 Đang gọi lấy Settings cho MSSV: $mssv');
      final settings = await _service.getSettings(mssv);
      debugPrint(
          '✅ Đã load Settings: ${settings != null ? jsonEncode(settings.toJson()) : "NULL"}');

      if (!mounted) return;
      setState(() {
        _settings = settings ?? _service.defaultSettings;
        _loading = false;
        _hasUnsavedChanges = false;
      });
    } catch (e) {
      debugPrint('❌ Lỗi _loadSettings: $e');
      if (!mounted) return;
      setState(() {
        _settings = _service.defaultSettings;
        _loading = false;
        _hasUnsavedChanges = false;
      });
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
          (e) => e['id'] == soundId,
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

    setState(() => _isSaving = true);

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
            debugPrint('❌ Lỗi decode token lấy id_sinh_vien: $e');
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

      debugPrint('Body gửi đi: ${jsonEncode(payload)}');

      final response = await AuthService.authenticatedRequestNotification(
        method: 'PUT',
        endpoint: '/users/$mssv/settings',
        body: payload,
      ).timeout(const Duration(seconds: 15));

      if (response != null &&
          (response.statusCode == 200 || response.statusCode == 201)) {
        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
        if (jsonResponse['success'] == true) {
          if (!mounted) return;
          setState(() {
            _settings = _settings!.copyWith(isDefaultSettings: false);
            _hasUnsavedChanges = false;
          });

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              'notification_settings', jsonEncode(_settings!.toJson()));

          if (!mounted) return;
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
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickTime({
    required int hour,
    required int minute,
    required void Function(TimeOfDay) onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
    );
    if (picked != null && mounted) onPicked(picked);
  }

  Future<void> _selectScheduleTime() => _pickTime(
    hour: _settings!.scheduleHour,
    minute: _settings!.scheduleMinute,
    onPicked: (t) => _onSettingsChanged(_settings!
        .copyWith(scheduleHour: t.hour, scheduleMinute: t.minute)),
  );

  Future<void> _selectExamTime() => _pickTime(
    hour: _settings!.examHour,
    minute: _settings!.examMinute,
    onPicked: (t) => _onSettingsChanged(
        _settings!.copyWith(examHour: t.hour, examMinute: t.minute)),
  );

  void _initAudioPlayerIfNeeded() {
    if (_audioPlayer == null) {
      _audioPlayer = AudioPlayer();
      _completeSub = _audioPlayer!.onPlayerComplete.listen((_) {
        _playingSound.value = null;
      });
    }
  }

  Future<void> _playSoundPreview(String soundId) async {
    if (soundId == 'system') return;
    
    _initAudioPlayerIfNeeded();

    if (_playingSound.value == soundId) {
      await _audioPlayer!.stop();
      _playingSound.value = null;
      return;
    }

    try {
      await _audioPlayer!.stop();
      await _audioPlayer!.play(AssetSource('sounds/$soundId.mp3'));
      _playingSound.value = soundId;
    } catch (e) {
      debugPrint('Lỗi khi phát âm thanh: $e');
      _playingSound.value = null;
    }
  }

  // ───────────────────────── Build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = _P.of(context);

    final appBar = AppBar(
      title: Text('notification_settings.title'.tr()),
      centerTitle: false,
      backgroundColor: p.bg,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    );

    if (_loading || _settings == null) {
      return Scaffold(
        backgroundColor: p.bg,
        appBar: appBar,
        body: Center(child: CircularProgressIndicator(color: p.accent)),
      );
    }

    final s = _settings!;
    final masterOn = s.enabled;

    return Scaffold(
      backgroundColor: p.bg,
      appBar: appBar,
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 130),
            children: [
              _Hero(
                p: p,
                settings: s,
                onChanged: (v) => _onSettingsChanged(s.copyWith(enabled: v)),
              ),
              const SizedBox(height: 16),

              // Lịch học
              _FeatureCard(
                p: p,
                tint: _tintBlue,
                icon: Icons.menu_book_rounded,
                title: 'Lịch học',
                subtitle: 'Tổng hợp các tiết học trong ngày',
                enabled: masterOn,
                switchValue: s.scheduleEnabled && masterOn,
                onSwitch: (v) =>
                    _onSettingsChanged(s.copyWith(scheduleEnabled: v)),
                showBody: s.scheduleEnabled && masterOn,
                body: _TimeRow(
                  p: p,
                  label: 'Giờ nhắc mỗi ngày',
                  time: s.scheduleTimeString,
                  onTap: _selectScheduleTime,
                ),
              ),
              const SizedBox(height: 12),

              // Lịch thi
              _FeatureCard(
                p: p,
                tint: _tintOrange,
                icon: Icons.edit_calendar_rounded,
                title: 'Lịch thi',
                subtitle: 'Báo trước khi có môn thi sắp tới',
                enabled: masterOn,
                switchValue: s.examEnabled && masterOn,
                onSwitch: (v) =>
                    _onSettingsChanged(s.copyWith(examEnabled: v)),
                showBody: s.examEnabled && masterOn,
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TimeRow(
                      p: p,
                      label: 'Giờ nhắc',
                      time: s.examTimeString,
                      onTap: _selectExamTime,
                    ),
                    const SizedBox(height: 16),
                    _FieldLabel(p: p, text: 'Nhắc trước ngày thi'),
                    const SizedBox(height: 10),
                    _PillGroup(
                      p: p,
                      options: _withCurrent(_examDayPresets, s.examReminderDays),
                      selected: s.examReminderDays,
                      format: (d) => d == 0 ? 'Tắt' : '$d ngày',
                      onSelected: (v) => _onSettingsChanged(
                          s.copyWith(examReminderDays: v)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Nhắc trước giờ
              _FeatureCard(
                p: p,
                tint: _tintPurple,
                icon: Icons.alarm_rounded,
                title: 'Nhắc trước giờ bắt đầu',
                subtitle: 'Thêm một thông báo ngay trước tiết học hoặc buổi thi',
                enabled: masterOn && (s.scheduleEnabled || s.examEnabled),
                showBody: true,
                body: _PillGroup(
                  p: p,
                  options:
                  _withCurrent(_reminderMinutePresets, s.reminderMinutes),
                  selected: s.reminderMinutes,
                  format: _formatMinutes,
                  onSelected: (v) =>
                      _onSettingsChanged(s.copyWith(reminderMinutes: v)),
                ),
              ),
              const SizedBox(height: 12),

              // Âm thanh
              _FeatureCard(
                p: p,
                tint: _tintGreen,
                icon: Icons.music_note_rounded,
                title: 'Âm báo',
                subtitle: _getSoundTitle(s.notificationSound),
                enabled: masterOn,
                onTap: _showSoundPicker,
                trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
              ),
            ],
          ),

          // Thanh lưu: trượt lên khi có thay đổi
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              offset: _hasUnsavedChanges ? Offset.zero : const Offset(0, 1.3),
              child: _SaveBar(
                p: p,
                saving: _isSaving,
                onSave: _saveSettings,
                onDiscard: _isSaving ? null : _loadSettings,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<int> _withCurrent(List<int> presets, int current) {
    if (presets.contains(current)) return presets;
    return ([...presets, current]..sort());
  }

  String _formatMinutes(int m) {
    if (m == 0) return 'Tắt';
    if (m >= 60 && m % 60 == 0) return '${m ~/ 60} giờ';
    return '$m phút';
  }

  void _showSoundPicker() {
    final p = _P.of(context);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: p.card,
      // surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ValueListenableBuilder<String?>(
            valueListenable: _playingSound,
            builder: (_, playing, __) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                    child: Text(
                      'Chọn âm báo',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: p.text,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: _soundOptions.length,
                      itemBuilder: (_, index) {
                        final option = _soundOptions[index];
                        final id = option['id']!;
                        final isSelected = _settings!.notificationSound == id;
                        final isPlaying = playing == id;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Material(
                            color:
                            isSelected ? p.accentSoft : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                _onSettingsChanged(_settings!
                                    .copyWith(notificationSound: id));
                                Navigator.pop(sheetContext);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    _IconBadge(
                                      p: p,
                                      tint: _tintGreen,
                                      icon: id == 'system'
                                          ? Icons.phone_android_rounded
                                          : Icons.music_note_rounded,
                                      size: 40,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            option['title']!,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? p.accent
                                                  : p.text,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            option['description']!,
                                            style: TextStyle(
                                                fontSize: 13, color: p.muted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (id != 'system')
                                      IconButton(
                                        tooltip:
                                        isPlaying ? 'Dừng' : 'Nghe thử',
                                        icon: Icon(isPlaying
                                            ? Icons.stop_circle_rounded
                                            : Icons
                                            .play_circle_outline_rounded),
                                        color: isPlaying
                                            ? const Color(0xFFFF6B6B)
                                            : p.muted,
                                        onPressed: () =>
                                            _playSoundPreview(id),
                                      ),
                                    if (isSelected)
                                      Icon(Icons.check_circle_rounded,
                                          color: p.accent),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      _audioPlayer?.stop();
      _playingSound.value = null;
    });
  }
}

// ───────────────────────── Widgets ─────────────────────────

/// Thẻ chính: bật/tắt tổng và tóm tắt những gì đang được nhắc.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.p,
    required this.settings,
    required this.onChanged,
  });

  final _P p;
  final AppNotificationSettings settings;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final on = s.enabled;

    final fg = on ? Colors.white : p.text;
    final sub = on ? Colors.white.withValues(alpha: 0.78) : p.muted;

    final chips = <Widget>[
      if (on && s.scheduleEnabled)
        _HeroChip(icon: Icons.menu_book_rounded, text: s.scheduleTimeString),
      if (on && s.examEnabled)
        _HeroChip(
          icon: Icons.edit_calendar_rounded,
          text: s.examReminderDays == 0
              ? s.examTimeString
              : '${s.examTimeString}, trước ${s.examReminderDays} ngày',
        ),
      if (on && s.reminderMinutes > 0 && (s.scheduleEnabled || s.examEnabled))
        _HeroChip(
          icon: Icons.alarm_rounded,
          text: 'Báo trước ${s.reminderMinutes} phút',
        ),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: on
            ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.heroA, p.heroB],
        )
            : null,
        color: on ? null : p.card,
        borderRadius: BorderRadius.circular(28),
        border: on ? null : Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (on)
            Positioned(
              right: -40,
              top: -50,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: on
                            ? Colors.white.withValues(alpha: 0.18)
                            : p.cardAlt,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        on
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_off_rounded,
                        color: on ? Colors.white : p.muted,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Thông báo',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: fg,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            on
                                ? 'Đang bật'
                                : 'Đang tắt, bạn sẽ không nhận nhắc nhở nào',
                            style: TextStyle(fontSize: 13.5, color: sub),
                          ),
                        ],
                      ),
                    ),
                    _AppSwitch(
                      p: p,
                      value: on,
                      onChanged: onChanged,
                      onHero: on,
                    ),
                  ],
                ),
                if (on) ...[
                  const SizedBox(height: 16),
                  if (chips.isEmpty)
                    Text(
                      'Chưa có nhắc nhở nào. Bật lịch học hoặc lịch thi bên dưới.',
                      style: TextStyle(fontSize: 13.5, color: sub),
                    )
                  else
                    Wrap(spacing: 8, runSpacing: 8, children: chips),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.p,
    required this.tint,
    required this.icon,
    this.size = 44,
  });

  final _P p;
  final _Tint tint;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = p.tint(tint);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: p.dark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: c, size: size * 0.5),
    );
  }
}

class _AppSwitch extends StatelessWidget {
  const _AppSwitch({
    required this.p,
    required this.value,
    required this.onChanged,
    this.onHero = false,
  });

  final _P p;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final Color thumbOn = onHero ? p.heroA : Colors.white;
    final Color trackOn = onHero ? Colors.white : p.accent;
    final Color thumbOff = p.dark ? const Color(0xFF9AA4C0) : Colors.white;
    final Color trackOff =
    p.dark ? const Color(0xFF263250) : const Color(0xFFD3D9E6);

    return Switch(
      value: value,
      onChanged: onChanged,
      thumbColor: WidgetStateProperty.resolveWith(
            (states) =>
        states.contains(WidgetState.selected) ? thumbOn : thumbOff,
      ),
      trackColor: WidgetStateProperty.resolveWith(
            (states) =>
        states.contains(WidgetState.selected) ? trackOn : trackOff,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    );
  }
}

/// Thẻ một tính năng: icon màu, tiêu đề, công tắc và phần nội dung mở rộng.
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.p,
    required this.tint,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.switchValue,
    this.onSwitch,
    this.trailing,
    this.onTap,
    this.showBody = false,
    this.body,
  });

  final _P p;
  final _Tint tint;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitch;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showBody;
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    final hasSwitch = switchValue != null && onSwitch != null;

    final header = Row(
      children: [
        _IconBadge(p: p, tint: tint, icon: icon),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, height: 1.3, color: p.muted),
              ),
            ],
          ),
        ),
        if (hasSwitch) ...[
          const SizedBox(width: 8),
          _AppSwitch(p: p, value: switchValue!, onChanged: onSwitch),
        ],
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.4,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: p.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: onTap ??
                      (hasSwitch ? () => onSwitch!(!switchValue!) : null),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: header,
                  ),
                ),
                if (body != null)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: showBody
                        ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: body,
                      ),
                    )
                        : const SizedBox(width: double.infinity),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.p, required this.text});

  final _P p;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: p.muted,
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.p,
    required this.label,
    required this.time,
    required this.onTap,
  });

  final _P p;
  final String label;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: p.cardAlt,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 15, color: p.text),
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  time,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillGroup extends StatelessWidget {
  const _PillGroup({
    required this.p,
    required this.options,
    required this.selected,
    required this.format,
    required this.onSelected,
  });

  final _P p;
  final List<int> options;
  final int selected;
  final String Function(int) format;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          _Pill(
            p: p,
            label: format(o),
            selected: o == selected,
            onTap: () => onSelected(o),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.p,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final _P p;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? p.accent : p.cardAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? p.accent : p.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : p.text,
          ),
        ),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.p,
    required this.saving,
    required this.onSave,
    required this.onDiscard,
  });

  final _P p;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final barColor = p.dark ? const Color(0xFF1B2440) : const Color(0xFF111827);

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
        decoration: BoxDecoration(
          color: barColor,
          borderRadius: BorderRadius.circular(24),
          border: p.dark ? Border.all(color: p.border) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: p.dark ? 0.45 : 0.2),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Chưa lưu thay đổi',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            TextButton(
              onPressed: onDiscard,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.75),
              ),
              child: const Text('Hoàn tác'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: saving ? null : onSave,
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              child: saving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Text(
                'Lưu thay đổi',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}