import 'package:geolocator/geolocator.dart';

class LocationService {
  // Lấy vị trí hiện tại
  Future<Position?> getCurrentLocation() async {
    try {
      // Kiểm tra dịch vụ vị trí có bật không
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Dịch vụ vị trí chưa được bật');
      }

      // Kiểm tra quyền
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Quyền truy cập vị trí bị từ chối');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Quyền truy cập vị trí bị từ chối vĩnh viễn');
      }

      // Lấy vị trí
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      return position;
    } catch (e) {
      print('Lỗi lấy vị trí: $e');
      return null;
    }
  }

  // Kiểm tra độ chính xác vị trí
  bool isLocationAccurate(Position position) {
    // Kiểm tra độ chính xác < 50m
    return position.accuracy < 50;
  }

  // Tính khoảng cách giữa 2 điểm
  double calculateDistance(
      double lat1,
      double lon1,
      double lat2,
      double lon2,
      ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  // Kiểm tra có trong phạm vi cho phép không
  bool isWithinRange(
      Position currentPosition,
      double targetLat,
      double targetLon,
      double maxDistance,
      ) {
    final distance = calculateDistance(
      currentPosition.latitude,
      currentPosition.longitude,
      targetLat,
      targetLon,
    );
    return distance <= maxDistance;
  }
}