import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  // Kiểm tra và yêu cầu quyền camera
  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.status;

    if (status.isGranted) {
      return true;
    }

    if (status.isDenied) {
      final result = await Permission.camera.request();
      return result.isGranted;
    }

    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return false;
  }

  // Kiểm tra và yêu cầu quyền vị trí
  Future<bool> requestLocationPermission() async {
    final status = await Permission.location.status;

    if (status.isGranted) {
      return true;
    }

    if (status.isDenied) {
      final result = await Permission.location.request();
      return result.isGranted;
    }

    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return false;
  }

  // Kiểm tra và yêu cầu tất cả quyền cần thiết
  Future<Map<String, bool>> requestAllPermissions() async {
    final cameraGranted = await requestCameraPermission();
    final locationGranted = await requestLocationPermission();

    return {
      'camera': cameraGranted,
      'location': locationGranted,
      'all': cameraGranted && locationGranted,
    };
  }

  // Kiểm tra trạng thái quyền
  Future<bool> checkAllPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final locationStatus = await Permission.location.status;

    return cameraStatus.isGranted && locationStatus.isGranted;
  }
}