import 'package:flutter/foundation.dart';
import '../models/event_model.dart';
import '../services/api_service.dart';
import '../services/permission_service.dart';
import '../services/location_service.dart';

class CheckInProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final PermissionService _permissionService = PermissionService();
  final LocationService _locationService = LocationService();

  List<CheckInEvent> _events = [];
  bool _isLoading = false;
  String? _error;
  CheckInEvent? _selectedEvent;

  List<CheckInEvent> get events => _events;
  bool get isLoading => _isLoading;
  String? get error => _error;
  CheckInEvent? get selectedEvent => _selectedEvent;

  // Tạo sự kiện test
  void createTestEvent({
    bool useRectangle = true,
    double radiusMeters = 100, // Dùng cho hình tròn
    double widthMeters = 200, // Dùng cho hình chữ nhật
    double heightMeters = 100, // Dùng cho hình chữ nhật
    double rotationDeg = 30, // Góc xoay hình chữ nhật
  }) {
    final now = DateTime.now();
    final testEvent = CheckInEvent(
      id: 'test-001',
      name: 'Sự kiện Check-in Test',
      date: now,
      checkInStartTime: now.add(const Duration(seconds: 30)), // Đếm ngược 5 giây
      checkInEndTime: now.add(const Duration(hours: 2)),
      location: 'Trường Đại Học Võ Trường Toản',
      latitude: 9.959298488110594, // Tọa độ mẫu
      longitude: 105.7372332911886,
      radiusMeters: radiusMeters,
      widthMeters: useRectangle ? widthMeters : null,
      heightMeters: useRectangle ? heightMeters : null,
      rotationDeg: rotationDeg,
      isCheckedIn: false,
    );

    _events = [testEvent];
    _selectedEvent = testEvent;
    notifyListeners();
  }

  // Tải danh sách sự kiện
  Future<void> loadEvents() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Trong môi trường thực tế, uncomment dòng này
      // _events = await _apiService.getEvents();

      // Test mode: tạo sự kiện test. Đổi useRectangle = false để xài hình tròn
      createTestEvent(useRectangle: true);
    } catch (e) {
      _error = 'Không thể tải sự kiện: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Chọn sự kiện
  void selectEvent(CheckInEvent event) {
    _selectedEvent = event;
    notifyListeners();
  }

  // Kiểm tra quyền
  Future<Map<String, bool>> checkPermissions() async {
    return await _permissionService.requestAllPermissions();
  }

  // Lấy vị trí hiện tại (giữ lại cho tương thích; CheckInScreen giờ tự lấy
  // qua Geolocator để đi qua cùng bộ lọc 3 lớp)
  Future<Map<String, dynamic>> getCurrentLocation() async {
    try {
      final position = await _locationService.getCurrentLocation();

      if (position == null) {
        return {
          'success': false,
          'message': 'Không thể lấy vị trí hiện tại',
        };
      }

      if (!_locationService.isLocationAccurate(position)) {
        return {
          'success': false,
          'message':
          'Vị trí không chính xác (độ chính xác: ${position.accuracy.toStringAsFixed(1)}m)',
        };
      }

      return {
        'success': true,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Lỗi lấy vị trí: $e',
      };
    }
  }

  // Submit check-in
  Future<CheckInResponse> submitCheckIn(CheckInData data) async {
    return await _apiService.submitCheckIn(data);
  }

  // Đánh dấu đã check-in.
  // FIX: bản cũ dựng lại CheckInEvent mà làm rơi radiusMeters/widthMeters/
  // heightMeters/rotationDeg → hasGeofence tính lại sai, cụm bản đồ + banner
  // vùng biến mất ngay sau khi check-in thành công. Bản này giữ nguyên mọi
  // field, chỉ lật isCheckedIn.
  // (Nếu CheckInEvent có copyWith thì thay toàn bộ bằng old.copyWith(isCheckedIn: true))
  void markAsCheckedIn(String eventId) {
    final index = _events.indexWhere((e) => e.id == eventId);
    if (index == -1) return;

    final old = _events[index];
    _events[index] = CheckInEvent(
      id: old.id,
      name: old.name,
      date: old.date,
      checkInStartTime: old.checkInStartTime,
      checkInEndTime: old.checkInEndTime,
      location: old.location,
      latitude: old.latitude,
      longitude: old.longitude,
      radiusMeters: old.radiusMeters,
      widthMeters: old.widthMeters,
      heightMeters: old.heightMeters,
      rotationDeg: old.rotationDeg,
      isCheckedIn: true,
    );

    if (_selectedEvent?.id == eventId) {
      _selectedEvent = _events[index];
    }

    notifyListeners();
  }
}
