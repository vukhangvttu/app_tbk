import 'package:get/get.dart';
import 'package:app_tbk/features/schedule/models/class_schedule.dart';
import 'package:app_tbk/services/api_service.dart';


class ScheduleController extends GetxController {
  var schedules = <ClassSchedule>[].obs;
  var isLoading = false.obs;

  Future<void> fetchSchedules(int idSinhVien, int hocKy, String namHoc) async {
    try {
      isLoading(true);
      final data = await ApiService.getSchedule(idSinhVien, hocKy, namHoc);
      schedules.assignAll(data.map((e) => ClassSchedule.fromJson(e)).toList());
    } finally {
      isLoading(false);
    }
  }
}
