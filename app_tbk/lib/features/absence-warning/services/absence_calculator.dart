import 'package:app_tbk/models/class_schedule.dart';
import '../models/subject_attendance.dart';
import '../absence_config.dart';
import 'package:intl/intl.dart';

class AbsenceCalculator {
  static String normalizeName(String name) {
    return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static List<SubjectAttendance> calculate(List<LopHoc> scheduleData, List<dynamic> historyData) {
    // scheduleData is actually a List<LopHoc>, we need to group by subject name.
    // Wait, the caller can pass List<LopHoc>. Let's type it dynamically or require List<LopHoc>.
    
    // Group schedule by normalized subject name
    Map<String, List<dynamic>> scheduleBySubject = {};
    for (var session in scheduleData) {
      if (session.nhomThi == true) continue; // Skip exams
      String normName = normalizeName(session.tenMon);
      if (!scheduleBySubject.containsKey(normName)) {
        scheduleBySubject[normName] = [];
      }
      scheduleBySubject[normName]!.add(session);
    }

    // Process history data
    // Create a Set of "normalized_name_yyyy-MM-dd" for fast lookup
    Set<String> attendedSessions = {};
    for (var record in historyData) {
      String tenMon = record['tenmon']?.toString() ??
          record['TENMON']?.toString() ??
          record['tenMon']?.toString() ??
          '';
      String thoigianBdStr = record['THOIGIANBD']?.toString() ??
          record['thoigianbd']?.toString() ??
          record['thoigianBd']?.toString() ??
          '';
      if (tenMon.isEmpty || thoigianBdStr.isEmpty) continue;

      try {
        DateTime dt = DateTime.parse(thoigianBdStr).toLocal();
        String dateStr = DateFormat('yyyy-MM-dd').format(dt);
        String normName = normalizeName(tenMon);
        attendedSessions.add('${normName}_$dateStr');
      } catch (e) {
        // ignore parse error
      }
    }

    List<SubjectAttendance> results = [];
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    scheduleBySubject.forEach((normName, sessions) {
      int totalSessions = sessions.length;
      int pastSessions = 0;
      int absentSessions = 0;
      int totalPeriods = 0;
      int absentPeriods = 0;
      String originalName = sessions.first.tenMon;
      List<dynamic> absentClasses = [];

      for (var session in sessions) {
        int periods = session.soTiet > 0 ? session.soTiet : 1;
        totalPeriods += periods;

        DateTime sessionDate = session.ngayBd;
        DateTime sessionDay = DateTime(sessionDate.year, sessionDate.month, sessionDate.day);
        
        bool isPast = false;
        if (sessionDay.isBefore(today)) {
          isPast = true;
        } else if (sessionDay.isAtSameMomentAs(today)) {
          // Tính là đã qua nếu thời gian hiện tại lớn hơn giờ kết thúc của môn học
          try {
            List<String> parts = session.gioKt.split(':');
            if (parts.length >= 2) {
              int h = int.parse(parts[0]);
              int m = int.parse(parts[1]);
              DateTime endTime = DateTime(today.year, today.month, today.day, h, m);
              if (now.isAfter(endTime)) {
                isPast = true;
              }
            } else {
              isPast = true; // fallback
            }
          } catch (e) {
            isPast = true; // fallback
          }
        }
        
        if (isPast) {
          pastSessions++;
          String dateKey = DateFormat('yyyy-MM-dd').format(sessionDay);
          String matchKey = '${normName}_$dateKey';
          
          bool isOnline = session.tenPhong.toLowerCase().contains('online');

          if (!attendedSessions.contains(matchKey)) {
            if (!isOnline) {
              absentSessions++;
              absentPeriods += periods;
            }
            absentClasses.add(session);
          }
        }
      }

      int attended = pastSessions - absentSessions;
      double absencePercentage = totalPeriods > 0 ? (absentPeriods / totalPeriods) : 0.0;
      
      int allowedAbsentPeriods = (totalPeriods * AbsenceConfig.maxAbsencePercentage).floor();
      bool isBanned = absentPeriods > allowedAbsentPeriods;
      
      int avgPeriodsPerSession = totalSessions > 0 ? (totalPeriods / totalSessions).ceil() : 0;
      bool isWarning = !isBanned && (absentPeriods > 0 || (absentPeriods + avgPeriodsPerSession > allowedAbsentPeriods));

      results.add(SubjectAttendance(
        tenMon: originalName,
        totalSessions: totalSessions,
        pastSessions: pastSessions,
        attendedSessions: attended,
        absentSessions: absentSessions,
        totalPeriods: totalPeriods,
        absentPeriods: absentPeriods,
        allowedAbsentPeriods: allowedAbsentPeriods,
        absencePercentage: absencePercentage,
        isBanned: isBanned,
        isWarning: isWarning,
        absentClasses: absentClasses,
      ));
    });

    return results;
  }
}
