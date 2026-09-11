import 'package:location/location.dart';
import 'package:safe_device/safe_device.dart';

/// File này chứa các ví dụ sử dụng SafeDevice plugin
/// Đây là tài liệu tham khảo, không cần copy vào project

class MockLocationChecker {
  static Future<bool> canMockLocation() async {
    try {
      final location = Location();
      final data = await location.getLocation();
      return data.isMock ?? false;
    } catch (e) {
      print('Error checking mock location: $e');
      return false;
    }
  }
}

class SafeDeviceExamples {

  /// Ví dụ 1: Kiểm tra cơ bản
  Future<void> basicCheck() async {
    // Kiểm tra thiết bị có bị jailbroken/rooted không
    bool isJailBroken = await SafeDevice.isJailBroken;
    print('Is JailBroken: $isJailBroken');

    // Kiểm tra có phải thiết bị thật không (không phải emulator)
    bool isRealDevice = await SafeDevice.isRealDevice;
    print('Is Real Device: $isRealDevice');

    // Kiểm tra development mode (Android)
    bool isDevelopmentMode = await SafeDevice.isDevelopmentModeEnable;
    print('Is Development Mode: $isDevelopmentMode');

    // Kiểm tra mock location (Android) - fake GPS
    bool canMockLocation = await MockLocationChecker.canMockLocation();
    print('Can Mock Location: $canMockLocation');
  }

  /// Ví dụ 2: Kiểm tra toàn diện
  Future<SecurityStatus> comprehensiveCheck() async {
    try {
      // Chạy tất cả các kiểm tra
      final results = await Future.wait([
        SafeDevice.isJailBroken,
        SafeDevice.isRealDevice,
        SafeDevice.isDevelopmentModeEnable,
        MockLocationChecker.canMockLocation(),
      ]);

      bool isJailBroken = results[0];
      bool isRealDevice = results[1];
      bool isDevelopmentMode = results[2];
      bool canMockLocation = results[3];

      // Đánh giá kết quả
      if (isJailBroken) {
        return SecurityStatus(
          isSafe: false,
          reason: 'Device is Jailbroken/Rooted',
        );
      }

      // Check thiết bị ảo
      // if (!isRealDevice) {
      //   return SecurityStatus(
      //     isSafe: false,
      //     reason: 'Running on Emulator/Simulator',
      //   );
      // }

      // Check mở nhà phát triển
      // if (isDevelopmentMode) {
      //   return SecurityStatus(
      //     isSafe: false,
      //     reason: 'Development Mode is Enabled',
      //   );
      // }

      if (canMockLocation) {
        return SecurityStatus(
          isSafe: false,
          reason: 'Mock Location is Enabled',
        );
      }

      return SecurityStatus(
        isSafe: true,
        reason: 'All security checks passed',
      );

    } catch (e) {
      return SecurityStatus(
        isSafe: false,
        reason: 'Error during security check: $e',
      );
    }
  }

  /// Ví dụ 3: Kiểm tra có điều kiện
  Future<void> conditionalCheck() async {
    // Chỉ block nếu là production build
    const bool isProduction = bool.fromEnvironment('dart.vm.product');

    if (isProduction) {
      bool isJailBroken = await SafeDevice.isJailBroken;
      if (isJailBroken) {
        // Block user
        print('Access Denied: Device is compromised');
      }
    } else {
      // Development mode - cho phép
      print('Development mode: Security check bypassed');
    }
  }

  /// Ví dụ 4: Kiểm tra kèm timeout
  Future<bool> checkWithTimeout() async {
    try {
      bool isJailBroken = await SafeDevice.isJailBroken
          .timeout(const Duration(seconds: 5));
      return isJailBroken;
    } catch (e) {
      print('Security check timeout: $e');
      // Xử lý timeout - có thể block hoặc cho phép tùy theo policy
      return false; // Giả định an toàn nếu timeout
    }
  }

  /// Ví dụ 5: Logging chi tiết
  Future<void> checkWithLogging() async {
    print('=== Starting Security Check ===');

    print('1. Checking JailBroken status...');
    bool isJailBroken = await SafeDevice.isJailBroken;
    print('   Result: ${isJailBroken ? "FAILED ❌" : "PASSED ✅"}');

    print('2. Checking Real Device...');
    bool isRealDevice = await SafeDevice.isRealDevice;
    print('   Result: ${isRealDevice ? "PASSED ✅" : "FAILED ❌"}');

    print('3. Checking Development Mode...');
    bool isDevelopmentMode = await SafeDevice.isDevelopmentModeEnable;
    print('   Result: ${isDevelopmentMode ? "WARNING ⚠️" : "PASSED ✅"}');

    print('4. Checking Mock Location...');
    bool canMockLocation = await MockLocationChecker.canMockLocation();
    print('   Result: ${canMockLocation ? "WARNING ⚠️" : "PASSED ✅"}');

    print('=== Security Check Complete ===');
  }

  /// Ví dụ 6: Kiểm tra theo level
  Future<SecurityLevel> getSecurityLevel() async {
    int riskScore = 0;

    if (await SafeDevice.isJailBroken) riskScore += 100; // Critical
    if (!await SafeDevice.isRealDevice) riskScore += 50; // High
    if (await SafeDevice.isDevelopmentModeEnable) riskScore += 30; // Medium
    if (await MockLocationChecker.canMockLocation()) riskScore += 20; // Low

    if (riskScore >= 100) return SecurityLevel.critical;
    if (riskScore >= 50) return SecurityLevel.high;
    if (riskScore >= 30) return SecurityLevel.medium;
    if (riskScore > 0) return SecurityLevel.low;
    return SecurityLevel.safe;
  }
}

/// Model cho kết quả kiểm tra
class SecurityStatus {
  final bool isSafe;
  final String reason;

  SecurityStatus({required this.isSafe, required this.reason});

  @override
  String toString() => 'SecurityStatus(isSafe: $isSafe, reason: $reason)';
}

/// Enum cho level bảo mật
enum SecurityLevel {
  safe,       // 0 điểm - An toàn hoàn toàn
  low,        // 1-29 điểm - Rủi ro thấp
  medium,     // 30-49 điểm - Rủi ro trung bình
  high,       // 50-99 điểm - Rủi ro cao
  critical,   // 100+ điểm - Rủi ro nghiêm trọng
}

/// Các use case thực tế

// Use Case 1: Banking App
class BankingAppSecurity {
  Future<bool> canAccessApp() async {
    // Banking app yêu cầu bảo mật cao nhất
    final isJailBroken = await SafeDevice.isJailBroken;
    final isRealDevice = await SafeDevice.isRealDevice;

    // Chỉ cho phép nếu cả 2 điều kiện đều pass
    return !isJailBroken && isRealDevice;
  }
}

// Use Case 2: Gaming App
class GamingAppSecurity {
  Future<bool> canPlay() async {
    // Gaming app block emulator và mock location để tránh cheat
    final isRealDevice = await SafeDevice.isRealDevice;
    final canMockLocation = await MockLocationChecker.canMockLocation();

    return isRealDevice && !canMockLocation;
  }
}

// Use Case 3: Social Media App
class SocialMediaAppSecurity {
  Future<bool> canPost() async {
    // Social media có thể cho phép, nhưng warning
    final isJailBroken = await SafeDevice.isJailBroken;

    if (isJailBroken) {
      // Show warning nhưng vẫn cho phép
      print('Warning: Device security may be compromised');
    }

    return true; // Vẫn cho phép
  }
}

// Use Case 4: Enterprise App
class EnterpriseAppSecurity {
  Future<AccessLevel> getAccessLevel() async {
    final isJailBroken = await SafeDevice.isJailBroken;
    final isRealDevice = await SafeDevice.isRealDevice;
    final isDevelopmentMode = await SafeDevice.isDevelopmentModeEnable;

    if (isJailBroken) {
      return AccessLevel.denied; // Không cho phép
    }

    if (!isRealDevice || isDevelopmentMode) {
      return AccessLevel.limited; // Hạn chế một số tính năng
    }

    return AccessLevel.full; // Toàn quyền
  }
}

enum AccessLevel {
  denied,   // Không cho phép truy cập
  limited,  // Hạn chế một số tính năng
  full,     // Toàn quyền
}