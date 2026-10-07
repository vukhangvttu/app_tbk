import 'package:app_tbk/config/academic_config.dart';
import 'package:app_tbk/models/class_schedule.dart';
import 'package:app_tbk/services/api_service.dart';
import 'package:app_tbk/features/attendance/services/attendance_history_service.dart';
import 'package:app_tbk/features/auth/services/auth_service.dart';
import 'package:intl/intl.dart';

class AbsenceDataService {
  Future<List<LopHoc>> fetchSchedule() async {
    final idSinhVien = (await AuthService.getIdSinhVien())?.toString();
    if (idSinhVien == null || idSinhVien.isEmpty) {
      throw Exception('Không tìm thấy thông tin sinh viên');
    }

    await AcademicConfig.fetchAcademicTerm();

    final List<dynamic> data = await ApiService.getThoiKhoaBieu(
      idSinhVien: idSinhVien,
      hocKy: AcademicConfig.hocKy,
      namHoc: AcademicConfig.namHoc,
    );

    return data.map((json) => LopHoc.fromJson(json)).toList();
  }

  Future<List<dynamic>> fetchHistory() async {
    final idSinhVien = (await AuthService.getIdSinhVien())?.toString();
    if (idSinhVien == null || idSinhVien.isEmpty) {
      throw Exception('Không tìm thấy thông tin sinh viên');
    }

    await AcademicConfig.fetchAcademicTerm();
    
    // Tải lịch sử cho toàn bộ học kỳ
    final startDate = AcademicConfig.ngayBatDauHocKy;
    final endDate = DateTime.now(); 
    
    final tuNgay = DateFormat('yyyy-MM-dd').format(startDate);
    final denNgay = DateFormat('yyyy-MM-dd').format(endDate);

    final data = await AttendanceHistoryService.getAttendanceHistory(
      idSinhVien,
      tuNgay: tuNgay,
      denNgay: denNgay,
      soNgay: null,
    );

    return data;
  }
}
