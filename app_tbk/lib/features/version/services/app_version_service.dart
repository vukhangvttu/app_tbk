import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:app_tbk/config/api_constants.dart';
import 'package:app_tbk/features/auth/services/auth_service.dart';
import 'package:app_tbk/features/version/models/app_version_model.dart';
import 'package:app_tbk/features/version/widgets/app_update_dialog.dart';

class VersionCheckResult {
  final bool hasUpdate;
  final bool forceUpdate;
  final String currentVersion;
  final AppVersionModel? appVersion;
  final String? errorMessage;

  VersionCheckResult({
    required this.hasUpdate,
    required this.forceUpdate,
    required this.currentVersion,
    this.appVersion,
    this.errorMessage,
  });
}

class AppVersionService {
  static bool _hasCheckedVersionThisSession = false;
  static VersionCheckResult? _cachedResult;
  static Future<VersionCheckResult>? _ongoingCheckFuture;

  /// Đặt lại cờ kiểm tra và cache trong session
  static void resetSessionCheck() {
    _hasCheckedVersionThisSession = false;
    _cachedResult = null;
    _ongoingCheckFuture = null;
  }

  /// Tự động kiểm tra phiên bản và hiển thị Dialog nếu khác nhau / có bản mới
  static Future<void> checkAndShowUpdateDialog(BuildContext context) async {
    if (_hasCheckedVersionThisSession && _cachedResult != null) {
      if (_cachedResult!.hasUpdate && _cachedResult!.appVersion != null) {
        _showDialogIfMounted(context, _cachedResult!);
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final result = await checkVersion();
      if (!context.mounted) return;

      if (result.hasUpdate && result.appVersion != null) {
        _showDialogIfMounted(context, result);
      }
    });
  }

  static void _showDialogIfMounted(BuildContext context, VersionCheckResult result) {
    if (!context.mounted) return;
    debugPrint('🔔 [AppVersionService] Phát hiện phiên bản khác nhau! Đang hiển thị Dialog cảnh báo...');
    AppUpdateDialog.show(
      context,
      appVersion: result.appVersion!,
      currentVersion: result.currentVersion,
      forceUpdate: result.forceUpdate,
    );
  }

  /// So sánh 2 chuỗi version Semantic (e.g. "2.0.1" và "1.5.0")
  static int compareVersions(String v1, String v2) {
    if (v1.isEmpty || v2.isEmpty) return 0;
    final clean1 = v1.split('+').first.split('-').first.trim();
    final clean2 = v2.split('+').first.split('-').first.trim();

    final parts1 = clean1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = clean2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLength = parts1.length > parts2.length ? parts1.length : parts2.length;

    for (int i = 0; i < maxLength; i++) {
      final num1 = i < parts1.length ? parts1[i] : 0;
      final num2 = i < parts2.length ? parts2[i] : 0;

      if (num1 < num2) return -1;
      if (num1 > num2) return 1;
    }
    return 0;
  }

  /// Gọi API GET /api/v1/app-version?platform=android (hoặc ios)
  static Future<AppVersionModel?> getAppVersion({String? platform}) async {
    final targetPlatform = platform ?? (Platform.isAndroid ? 'android' : 'ios');
    final endpoint = '${ApiConstants.appVersion}?platform=$targetPlatform';
    final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');

    debugPrint('🔍 [AppVersionService] Requesting API: $uri');

    try {
      final token = await AuthService.getToken();
      http.Response response;

      if (token != null && token.isNotEmpty) {
        debugPrint('🔑 [AppVersionService] Gửi request có Bearer token...');
        final authResponse = await AuthService.authenticatedRequestLichSinhVien(
          method: 'GET',
          endpoint: endpoint,
        );

        if (authResponse != null) {
          response = authResponse;
        } else {
          response = await http.get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          ).timeout(const Duration(seconds: 10));
        }
      } else {
        debugPrint('🌐 [AppVersionService] Gửi request không có token...');
        response = await http.get(
          uri,
          headers: ApiGetToken.getBasicHeaders(),
        ).timeout(const Duration(seconds: 10));
      }

      debugPrint('📥 [AppVersionService] Response Status: ${response.statusCode}');
      debugPrint('📥 [AppVersionService] Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        if (body['success'] == true && body['data'] != null) {
          final model = AppVersionModel.fromJson(body['data']);
          debugPrint('✅ [AppVersionService] Parsed Version: ${model.version}, minVersion: ${model.minVersion}, forceUpdate: ${model.forceUpdate}');
          return model;
        } else {
          debugPrint('⚠️ [AppVersionService] API returned success=false or data is null');
        }
      } else {
        debugPrint('⚠️ [AppVersionService] Call app-version failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [AppVersionService] Error getting app version: $e');
    }
    return null;
  }

  /// Kiểm tra phiên bản hiện tại so với cấu hình trên server (Tránh gọi trùng API)
  static Future<VersionCheckResult> checkVersion({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      if (_cachedResult != null) {
        debugPrint('⚡ [AppVersionService] Dùng kết quả đã cache từ trước');
        return _cachedResult!;
      }
      if (_ongoingCheckFuture != null) {
        debugPrint('⏳ [AppVersionService] Đang có request kiểm tra phiên bản chạy ngầm, chờ kết quả...');
        return await _ongoingCheckFuture!;
      }
    }

    _ongoingCheckFuture = _performCheckVersion();
    try {
      final result = await _ongoingCheckFuture!;
      _cachedResult = result;
      _hasCheckedVersionThisSession = true;
      return result;
    } finally {
      _ongoingCheckFuture = null;
    }
  }

  static Future<VersionCheckResult> _performCheckVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      debugPrint('📱 [AppVersionService] Installed App Version: $currentVersion');

      final appVersion = await getAppVersion();
      if (appVersion == null) {
        debugPrint('⚠️ [AppVersionService] Could not fetch version from server.');
        return VersionCheckResult(
          hasUpdate: false,
          forceUpdate: false,
          currentVersion: currentVersion,
          errorMessage: 'Không thể kết nối máy chủ để kiểm tra phiên bản',
        );
      }

      final isDifferentVersion = currentVersion != appVersion.version;
      final isBelowMin = compareVersions(currentVersion, appVersion.minVersion) < 0;
      final isBelowLatest = compareVersions(currentVersion, appVersion.version) < 0;

      final forceUpdate = isBelowMin || (appVersion.forceUpdate && (isBelowLatest || isDifferentVersion));
      final hasUpdate = forceUpdate || isBelowLatest || isDifferentVersion;

      debugPrint('📊 [AppVersionService] Result: hasUpdate=$hasUpdate, forceUpdate=$forceUpdate (current=$currentVersion, server=${appVersion.version}, min=${appVersion.minVersion})');

      return VersionCheckResult(
        hasUpdate: hasUpdate,
        forceUpdate: forceUpdate,
        currentVersion: currentVersion,
        appVersion: appVersion,
      );
    } catch (e) {
      debugPrint('❌ [AppVersionService] Error in checkVersion: $e');
      return VersionCheckResult(
        hasUpdate: false,
        forceUpdate: false,
        currentVersion: '1.0.0',
        errorMessage: e.toString(),
      );
    }
  }
}
