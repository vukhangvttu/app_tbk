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
  void createTestEvent() {
    final now = DateTime.now();
    final testEvent = CheckInEvent(
      id: 'test-001',
      name: 'Sự kiện Check-in Test',
      date: now,
      checkInStartTime: now.add(const Duration(seconds: 5)), // Đếm ngược 5 giây
      checkInEndTime: now.add(const Duration(hours: 2)),
      location: 'Văn phòng công ty',
      latitude: 10.762622, // Tọa độ mẫu - Sài Gòn
      longitude: 106.660172,
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

      // Test mode: tạo sự kiện test
      createTestEvent();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Không thể tải sự kiện: $e';
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

  // Lấy vị trí hiện tại
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
          'message': 'Vị trí không chính xác (độ chính xác: ${position.accuracy.toStringAsFixed(1)}m)',
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

  // Đánh dấu đã check-in
  void markAsCheckedIn(String eventId) {
    final index = _events.indexWhere((e) => e.id == eventId);
    if (index != -1) {
      _events[index] = CheckInEvent(
        id: _events[index].id,
        name: _events[index].name,
        date: _events[index].date,
        checkInStartTime: _events[index].checkInStartTime,
        checkInEndTime: _events[index].checkInEndTime,
        location: _events[index].location,
        latitude: _events[index].latitude,
        longitude: _events[index].longitude,
        isCheckedIn: true,
      );

      if (_selectedEvent?.id == eventId) {
        _selectedEvent = _events[index];
      }

      notifyListeners();
    }
  }
}