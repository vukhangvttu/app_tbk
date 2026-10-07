import 'package:shared_preferences/shared_preferences.dart';
import 'absence_data_service.dart';
import 'absence_calculator.dart';
import '../models/subject_attendance.dart';

class AbsenceWarningService {
  static final AbsenceDataService _dataService = AbsenceDataService();
  static const String _prefPrefix = 'absence_warn_';
  static const String _lastCheckKey = 'absence_last_check';

  static Future<List<SubjectAttendance>> checkAndWarn() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Throttling: tránh tính toán liên tục, ví dụ 5 phút 1 lần. 
    // Trừ khi cố tình gọi ép buộc.
    final lastCheckStr = prefs.getString(_lastCheckKey);
    if (lastCheckStr != null) {
      final lastCheck = DateTime.parse(lastCheckStr);
      if (DateTime.now().difference(lastCheck).inMinutes < 5) {
        // Có thể lấy cache nếu muốn, nhưng ở đây ta vẫn chạy để trả về data cho UI, 
        // chỉ là hàm này dùng chung cho background check và UI.
        // Để đơn giản, ta cứ gọi tải dữ liệu. API có thể chậm nhưng phục vụ cho UI.
      }
    }
    await prefs.setString(_lastCheckKey, DateTime.now().toIso8601String());

    try {
      final schedule = await _dataService.fetchSchedule();
      final history = await _dataService.fetchHistory();

      final results = AbsenceCalculator.calculate(schedule, history);

      // Đã loại bỏ phần gọi thông báo (push notification) theo yêu cầu.
      // Chỉ tính toán và trả về kết quả cho UI.
      
      return results;
    } catch (e) {
      print('Lỗi khi tính toán cảnh báo vắng học: \$e');
      return [];
    }
  }

  static Future<void> datLaiCanhBao() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (String key in keys) {
      if (key.startsWith(_prefPrefix)) {
        await prefs.remove(key);
      }
    }
    await prefs.remove(_lastCheckKey);
    print('Đã reset toàn bộ cờ cảnh báo chuyên cần.');
  }
}
