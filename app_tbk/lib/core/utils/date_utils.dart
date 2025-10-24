// Hàm tiện ích (format date, validate, v.v.)

import 'package:intl/intl.dart';

String formatDateVN(DateTime date) {
  final weekdayNames = ["Chủ nhật", "Thứ 2", "Thứ 3", "Thứ 4", "Thứ 5", "Thứ 6", "Thứ 7"];
  final dayName = weekdayNames[date.weekday % 7];
  return "$dayName, ${DateFormat('dd/MM/yyyy').format(date)}";
}
