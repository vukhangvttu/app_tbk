import 'dart:async';
import 'package:flutter/foundation.dart';
import '../features/auth/services/auth_service.dart';

class NotificationTrackingService {
  static final Set<String> _reportedDelivered = {};
  static final Set<String> _reportedOpened = {};

  /// Gửi callback báo thông báo đã DELIVERED về Go Server
  static Future<void> reportDelivered(String? notificationId) async {
    if (notificationId == null || notificationId.trim().isEmpty) return;
    final id = notificationId.trim();

    // Chống gửi trùng lặp trong cùng phiên làm việc
    if (_reportedDelivered.contains(id)) {
      debugPrint('⏭️ Notification $id already reported DELIVERED in this session');
      return;
    }

    _reportedDelivered.add(id);

    try {
      debugPrint('🚀 Reporting DELIVERED for notification_id: $id');
      final response = await AuthService.authenticatedRequestNotification(
        method: 'POST',
        endpoint: '/notifications/$id/delivered',
      );

      if (response != null && (response.statusCode == 200 || response.statusCode == 204)) {
        debugPrint('✅ Callback DELIVERED success for notification_id: $id');
      } else {
        debugPrint('⚠️ Callback DELIVERED failed for $id: ${response?.statusCode} - ${response?.body}');
        _reportedDelivered.remove(id);
      }
    } catch (e) {
      debugPrint('❌ Error reporting DELIVERED for $id: $e');
      _reportedDelivered.remove(id);
    }
  }

  /// Gửi callback báo người dùng đã OPENED thông báo về Go Server
  static Future<void> reportOpened(String? notificationId) async {
    if (notificationId == null || notificationId.trim().isEmpty) return;
    final id = notificationId.trim();

    if (_reportedOpened.contains(id)) {
      debugPrint('⏭️ Notification $id already reported OPENED in this session');
      return;
    }

    _reportedOpened.add(id);

    try {
      debugPrint('🚀 Reporting OPENED for notification_id: $id');
      final response = await AuthService.authenticatedRequestNotification(
        method: 'POST',
        endpoint: '/notifications/$id/opened',
      );

      if (response != null && (response.statusCode == 200 || response.statusCode == 204)) {
        debugPrint('✅ Callback OPENED success for notification_id: $id');
      } else {
        debugPrint('⚠️ Callback OPENED failed for $id: ${response?.statusCode} - ${response?.body}');
        _reportedOpened.remove(id);
      }
    } catch (e) {
      debugPrint('❌ Error reporting OPENED for $id: $e');
      _reportedOpened.remove(id);
    }
  }

  /// Helper lấy notification_id từ message data
  static String? extractNotificationId(Map<String, dynamic> data) {
    if (data.containsKey('notification_id') && data['notification_id'] != null) {
      return data['notification_id'].toString();
    }
    if (data.containsKey('id') && data['id'] != null) {
      return data['id'].toString();
    }
    return null;
  }

  /// Helper lấy event_key từ message data
  static String? extractEventKey(Map<String, dynamic> data) {
    if (data.containsKey('event_key') && data['event_key'] != null) {
      final key = data['event_key'].toString().trim();
      if (key.isNotEmpty) return key;
    }
    return null;
  }

  /// Helper lấy unique key để deduplicate (ưu tiên event_key, sau đó đến notification_id)
  static String? getDedupKey(Map<String, dynamic> data) {
    final eventKey = extractEventKey(data);
    if (eventKey != null) return 'event:$eventKey';
    final notifId = extractNotificationId(data);
    if (notifId != null) return 'id:$notifId';
    return null;
  }
}
