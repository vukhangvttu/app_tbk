class AbsenceConfig {
  /// Ngưỡng cấm thi (vắng quá 20%)
  static const double maxAbsencePercentage = 0.20;

  /// Số buổi báo vàng trước khi cấm thi (ví dụ: còn 1 buổi nữa là cấm thi)
  static const int warningMargin = 1;

  /// Thời gian tối thiểu giữa các lần tính toán (để tránh spam)
  static const int minMinutesBetweenCalculations = 5;
}
