class SubjectAttendance {
  final String tenMon;
  final int totalSessions;
  final int pastSessions;
  final int attendedSessions;
  final int absentSessions;

  final int totalPeriods;
  final int absentPeriods;
  final int allowedAbsentPeriods;

  final double absencePercentage;
  final bool isBanned;
  final bool isWarning;

  final List<dynamic> absentClasses;

  SubjectAttendance({
    required this.tenMon,
    required this.totalSessions,
    required this.pastSessions,
    required this.attendedSessions,
    required this.absentSessions,
    required this.totalPeriods,
    required this.absentPeriods,
    required this.allowedAbsentPeriods,
    required this.absencePercentage,
    required this.isBanned,
    required this.isWarning,
    required this.absentClasses,
  });

  @override
  String toString() {
    return 'SubjectAttendance{tenMon: $tenMon, totalSessions: $totalSessions, pastSessions: $pastSessions, absentSessions: $absentSessions, totalPeriods: $totalPeriods, absentPeriods: $absentPeriods, allowedAbsentPeriods: $allowedAbsentPeriods, isBanned: $isBanned, isWarning: $isWarning, absentClasses: ${absentClasses.length}}';
  }
}
