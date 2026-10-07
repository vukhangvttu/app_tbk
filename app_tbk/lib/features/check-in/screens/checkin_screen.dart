import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show FontFeature;

import 'package:app_tbk/features/absence-warning/services/absence_warning_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../security_checker_service.dart';
import '../../../utils/geofence_rect.dart';
import '../models/event_model.dart';
import '../providers/checkin_provider.dart';
import '../widgets/checkin_map_card.dart';
import '../widgets/face_camera_widget.dart';

/// Trạng thái vị trí. Nằm trong ValueNotifier nên mỗi điểm GPS mới chỉ
/// rebuild bản đồ + banner + nút, KHÔNG rebuild cả màn hình.
class _GeoState {
  final Position? position; // vị trí ĐÃ LỌC (điểm chốt)
  final bool inZone; // trạng thái vùng đã chốt (có hysteresis)
  final bool granted;
  final String? error;

  const _GeoState({
    this.position,
    this.inZone = false,
    this.granted = false,
    this.error,
  });

  _GeoState copyWith({
    Position? position,
    bool? inZone,
    bool? granted,
    String? error,
    bool clearError = false,
  }) {
    return _GeoState(
      position: position ?? this.position,
      inZone: inZone ?? this.inZone,
      granted: granted ?? this.granted,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Lý do chặn màn hình trước khi vào check-in.
enum _Gate { none, gpsOff, permDenied, permDeniedForever, checkFailed }

class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen>
    with WidgetsBindingObserver {
  // ---- Ngưỡng lọc GPS ----
  /// Lệch < 3m so với điểm đã chốt → nhiễu khi đứng yên, bỏ qua
  static const double _nguongNhieuDungYenM = 3.0;

  /// > 10m/s (≈36km/h) → nhảy ảo, bỏ qua
  static const double _nguongTocDoMS = 10.0;

  /// Sai số tối đa của các điểm sau
  static const double _doChinhXacToiDaM = 30.0;

  /// Lần fix đầu tiên được nới lỏng để banner có dữ liệu sớm (trong nhà)
  static const double _doChinhXacLanDauM = 50.0;

  /// Hysteresis biên vùng: đã trong vùng thì phải ra xa thêm 15m mới tính là ra
  static const double _hysteresisM = 15.0;

  /// Vị trí được coi là "còn mới" khi bấm check-in
  static const Duration _tuoiViTriToiDa = Duration(seconds: 10);

  bool _showCamera = false;
  bool _isCheckingIn = false;

  // ---- Bảo mật ----
  bool _isChecking = true;
  bool _isSecure = true;
  _Gate _gate = _Gate.none;
  String _gateDetail = '';
  final SafeDeviceExamples _securityChecker = SafeDeviceExamples();

  // ---- Vị trí ----
  final ValueNotifier<_GeoState> _geo = ValueNotifier(const _GeoState());
  StreamSubscription<Position>? _positionSub;
  DateTime? _lastValidTime; // lúc chốt điểm gần nhất (cho lớp lọc tốc độ)
  DateTime? _lastFixAt; // lúc nhận bản tin hợp lệ gần nhất (độ "tươi")
  bool _trackingStarting = false;

  Position? get _position => _geo.value.position;

  CheckInEvent? get _currentEvent {
    final p = context.read<CheckInProvider>();
    return p.selectedEvent ?? p.events.firstOrNull;
  }

  // =====================================================================
  // LIFECYCLE
  // =====================================================================
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// 1) Xin quyền vị trí TRƯỚC, tuần tự. Hai yêu cầu quyền chạy cùng lúc (ví dụ
  ///    bước kiểm tra bảo mật cũng đụng tới vị trí) có thể làm treo ở
  ///    "Đang kiểm tra thiết bị...". Bị từ chối → hiện màn hình báo lỗi cụ thể.
  /// 2) Kiểm tra bảo mật + tải sự kiện chạy song song.
  /// UI vẫn bị chặn bằng _isChecking / _gate / _isSecure nên không lộ dữ liệu.
  Future<void> _bootstrap() async {
    if (!mounted) return;
    final provider = context.read<CheckInProvider>();
    setState(() {
      _isChecking = true;
      _gate = _Gate.none;
    });

    final access = await _ensureLocationAccess();
    if (!mounted) return;
    if (access != _Gate.none) {
      setState(() {
        _isChecking = false;
        _gate = access;
      });
      return;
    }

    unawaited(_startLocationTracking());

    final loading = provider.loadEvents();
    await _performSecurityCheck();
    await loading;
    _evaluateZone(); // vị trí có thể đến trước sự kiện → tính lại vùng
  }

  /// Kiểm tra GPS + quyền vị trí. Trả về _Gate.none nếu dùng được.
  Future<_Gate> _ensureLocationAccess() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return _Gate.gpsOff;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        return _Gate.permDeniedForever;
      }
      if (perm == LocationPermission.denied) return _Gate.permDenied;
      return _Gate.none;
    } catch (_) {
      return _Gate.permDenied;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _positionSub?.pause(); // tiết kiệm pin khi ở nền
    } else if (state == AppLifecycleState.resumed) {
      // Hộp thoại xin quyền cũng làm app paused → resumed: đang kiểm tra thì
      // không can thiệp để tránh yêu cầu quyền chạy chồng.
      if (_isChecking) return;

      if (_gate != _Gate.none && _gate != _Gate.checkFailed) {
        _bootstrap(); // vừa quay lại từ cài đặt GPS / quyền
      } else if (_positionSub != null && _geo.value.granted) {
        _positionSub!.resume();
      } else {
        _startLocationTracking();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _geo.dispose();
    super.dispose();
  }

  // =====================================================================
  // THEO DÕI VỊ TRÍ — 3 lớp lọc chống trôi
  // =====================================================================
  Future<void> _startLocationTracking() async {
    if (_trackingStarting) return;
    _trackingStarting = true;

    try {
      await _positionSub?.cancel();
      _positionSub = null;

      if (!await Geolocator.isLocationServiceEnabled()) {
        _setGeoError('GPS đang tắt', granted: false);
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _setGeoError('Chưa cấp quyền vị trí', granted: false);
        return;
      }
      if (!mounted) return;
      _geo.value = _geo.value.copyWith(granted: true, clearError: true);

      // 1) Vị trí cache còn mới → hiện banner gần như tức thì
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null &&
            DateTime.now().difference(last.timestamp) <
                const Duration(seconds: 30)) {
          _xuLyViTriMoi(last);
        }
      } catch (_) {}

      // 2) Mở stream NGAY (không chờ fix đầu tiên như bản cũ)
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, // đủ cho geofence hàng chục mét
          distanceFilter: 2,
        ),
      ).listen(
        _xuLyViTriMoi,
        onError: (_) => _setGeoError('Không lấy được vị trí'),
      );

      // 3) Fix chính xác chạy nền, không chặn
      unawaited(
        Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        ).then(_xuLyViTriMoi).catchError((_) {}),
      );
    } catch (e) {
      _setGeoError('Lỗi vị trí: $e');
    } finally {
      _trackingStarting = false;
    }
  }

  void _setGeoError(String msg, {bool? granted}) {
    if (!mounted) return;
    _geo.value = _geo.value.copyWith(error: msg, granted: granted);
  }

  /// Xử lý 1 bản tin vị trí qua 3 lớp lọc. Chỉ điểm "sạch" mới được chốt.
  void _xuLyViTriMoi(Position pos) {
    if (!mounted) return;

    if (pos.isMocked) {
      _setGeoError('Phát hiện vị trí giả. Vui lòng tắt ứng dụng giả lập vị trí.');
      return;
    }

    final current = _position;

    // Lớp 1: bỏ tọa độ nhiễu nặng (lần đầu nới lỏng hơn)
    final maxAcc = current == null ? _doChinhXacLanDauM : _doChinhXacToiDaM;
    if (pos.accuracy > maxAcc) return;
    _lastFixAt = DateTime.now();

    if (current != null) {
      final lech = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        pos.latitude,
        pos.longitude,
      );

      // Lớp 2: chống trôi khi đứng yên. Ngoại lệ: bản tin chính xác hơn rõ rệt
      // thì vẫn nhận (để điểm fix thô đầu tiên được thay bằng điểm tốt hơn).
      final totHonNhieu = pos.accuracy + 10 < current.accuracy;
      if (lech < _nguongNhieuDungYenM && !totHonNhieu) return;

      // Lớp 3: chống nhảy đột ngột
      final last = _lastValidTime;
      if (last != null) {
        final giay = DateTime.now().difference(last).inMilliseconds / 1000.0;
        if (giay >= 0.5 && lech / giay > _nguongTocDoMS) return;
      }
    }

    _commit(pos);
  }

  /// Chốt điểm + đánh giá vùng (có hysteresis) → một lần thông báo duy nhất.
  void _commit(Position pos) {
    _lastValidTime = DateTime.now();
    final event = _currentEvent;
    var inZ = _geo.value.inZone;
    if (event != null && event.hasGeofence) {
      inZ = _xetVung(_edgeDistance(event, pos.latitude, pos.longitude), inZ);
    }
    _geo.value = _geo.value.copyWith(position: pos, inZone: inZ, clearError: true);
  }

  /// Tính lại vùng khi sự kiện đến sau vị trí.
  void _evaluateZone() {
    if (!mounted) return;
    final event = _currentEvent;
    final p = _position;
    if (event == null || !event.hasGeofence || p == null) return;
    final inZ = _xetVung(
        _edgeDistance(event, p.latitude, p.longitude), _geo.value.inZone);
    if (inZ != _geo.value.inZone) {
      _geo.value = _geo.value.copyWith(inZone: inZ);
    }
  }

  /// Khoảng cách (m) từ tọa độ đến *mép* vùng. <= 0 nghĩa là nằm trong.
  double _edgeDistance(CheckInEvent e, double lat, double lng) {
    final zone = e.zone;
    if (zone != null) return zone.outsideDistance(lat, lng);
    return Geolocator.distanceBetween(lat, lng, e.latitude!, e.longitude!) -
        e.radiusMeters;
  }

  /// Hysteresis biên vùng.
  bool _xetVung(double distanceToEdge, bool dangTrong) {
    if (dangTrong) return distanceToEdge <= _hysteresisM;
    return distanceToEdge <= 0;
  }

  bool _isInZone(CheckInEvent event, _GeoState geo) {
    if (!event.hasGeofence) return true;
    if (geo.position == null) return false;
    return geo.inZone;
  }

  /// Dùng lại vị trí đã có nếu còn mới, chỉ gọi GPS khi thật sự cần.
  /// (Bản cũ lấy vị trí 2 lần: ở _startCheckIn và ở _handleCapture.)
  Future<Position?> _getFreshPosition() async {
    final cached = _position;
    final at = _lastFixAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < _tuoiViTriToiDa) {
      return cached;
    }

    try {
      final fresh = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (fresh.isMocked) return fresh; // người gọi sẽ báo lỗi

      if (fresh.accuracy > _doChinhXacToiDaM) {
        // fresh nhiễu nhưng điểm chốt cũ đang tốt → dùng điểm cũ
        if (cached != null && cached.accuracy <= _doChinhXacToiDaM) {
          return cached;
        }
        return null;
      }
      _xuLyViTriMoi(fresh);
      return fresh;
    } catch (_) {
      return null;
    }
  }

  // =====================================================================
  // BẢO MẬT
  // =====================================================================
  Future<void> _performSecurityCheck() async {
    try {
      final result = await _securityChecker
          .comprehensiveCheck()
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _isSecure = result.isSafe;
      });
      if (!result.isSafe) _showSecurityWarningDialog(result.reason);
    } on TimeoutException {
      // Không để treo vô hạn ở "Đang kiểm tra thiết bị..."
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _gate = _Gate.checkFailed;
        _gateDetail =
        'Kiểm tra thiết bị quá thời gian phản hồi. Vui lòng thử lại.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _isSecure = false;
      });
      _showSecurityWarningDialog('Error: $e');
    }
  }

  void _showSecurityWarningDialog(String details) {
    final scheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.security, color: scheme.error, size: 30),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Cảnh báo bảo mật',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hệ thống phát hiện thiết bị của bạn có dấu hiệu không an toàn:',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        details,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ứng dụng sẽ tự động đóng khi bạn nhấn "OK".',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton.icon(
                onPressed: _closeApp,
                icon: const Icon(Icons.exit_to_app),
                label: const Text('OK',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _closeApp() {
    if (Platform.isAndroid) {
      SystemNavigator.pop();
    } else {
      exit(0);
    }
  }

  // =====================================================================
  // CHECK-IN
  // =====================================================================
  Future<void> _startCheckIn() async {
    final provider = context.read<CheckInProvider>();
    final event = _currentEvent;
    if (event == null) {
      _showError('Không tìm thấy sự kiện');
      return;
    }

    final permissions = await provider.checkPermissions();
    if (!permissions['camera']!) {
      _showError('Vui lòng cấp quyền Camera');
      return;
    }
    if (!permissions['location']!) {
      _showError('Vui lòng cấp quyền Vị trí');
      return;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      _showLocationDialog();
      return;
    }

    if (_positionSub == null) await _startLocationTracking();

    // Chặn ngoài vùng bằng vị trí mới + cùng hysteresis như banner
    if (event.hasGeofence) {
      final pos = await _getFreshPosition();
      if (pos == null) {
        _showError('Không xác định được vị trí hiện tại. Vui lòng thử lại.');
        return;
      }
      if (pos.isMocked) {
        _showError('Phát hiện vị trí giả. Vui lòng tắt ứng dụng giả lập vị trí.');
        return;
      }

      final d = _edgeDistance(event, pos.latitude, pos.longitude);
      if (!_xetVung(d, _geo.value.inZone)) {
        _showError(
            'Bạn đang ngoài khu vực (cách ${event.zone != null ? 'mép ' : ''}${d.round()}m). '
                'Độ chính xác GPS: ${pos.accuracy.toStringAsFixed(0)}m');
        return;
      }
      if (mounted) _geo.value = _geo.value.copyWith(inZone: true);
    }

    if (mounted) setState(() => _showCamera = true);
  }

  void _showLocationDialog() {
    final scheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.location_off, color: scheme.error, size: 32),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Bật vị trí',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gps_off,
                size: 72, color: scheme.error.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            const Text(
              'Vị trí đang bị tắt.\nVui lòng bật GPS để check-in.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          _PrimaryButton(
            label: 'Bật GPS',
            icon: Icons.location_on,
            height: 44,
            fontSize: 15,
            onPressed: () async {
              Navigator.pop(context);
              // Khi quay lại app, didChangeAppLifecycleState tự bật lại theo dõi
              await Geolocator.openLocationSettings();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleCapture(String base64Image, Uint8List imageBytes) async {
    setState(() {
      _showCamera = false;
      _isCheckingIn = true;
    });

    try {
      final provider = context.read<CheckInProvider>();
      final event = _currentEvent;
      if (event == null) {
        _showError('Không tìm thấy sự kiện');
        return;
      }

      // Dùng lại vị trí còn mới thay vì gọi GPS lần thứ hai
      final pos = await _getFreshPosition();
      if (pos == null) {
        _showError('Không thể lấy vị trí hiện tại. Vui lòng thử lại.');
        return;
      }
      if (pos.isMocked) {
        _showError('Phát hiện vị trí giả. Vui lòng tắt ứng dụng giả lập vị trí.');
        return;
      }

      // Kiểm tra vùng lần cuối bằng đúng tọa độ sẽ gửi lên server
      if (event.hasGeofence) {
        final d = _edgeDistance(event, pos.latitude, pos.longitude);
        if (!_xetVung(d, _geo.value.inZone)) {
          _showError(
              'Bạn đang ngoài khu vực check-in (cách ${event.zone != null ? 'mép ' : ''}${d.round()}m).');
          return;
        }
      }

      final checkInData = CheckInData(
        eventId: event.id,
        faceImageBase64: base64Image,
        latitude: pos.latitude,
        longitude: pos.longitude,
        timestamp: DateTime.now(),
      );

      debugPrint(
          '📦 Check-in: ${checkInData.eventId} - ${checkInData.latitude}, ${checkInData.longitude} - imgLen=${checkInData.faceImageBase64.length}');

      final response = await provider.submitCheckIn(checkInData);
      if (response.success) {
        provider.markAsCheckedIn(event.id);
        _showSuccess('Check-in thành công!');
        AbsenceWarningService.checkAndWarn();
      } else {
        _showError(response.message);
      }
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _isCheckingIn = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: TextStyle(color: scheme.onError)),
          backgroundColor: scheme.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF43A047),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  // =====================================================================
  // UI
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_showCamera) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: FaceCameraWidget(
          onCapture: _handleCapture,
          onCancel: () => setState(() => _showCamera = false),
        ),
      );
    }

    if (_isCheckingIn) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 5),
              SizedBox(height: 24),
              Text('Đang xử lý check-in...', style: TextStyle(fontSize: 18)),
            ],
          ),
        ),
      );
    }

    // Đang kiểm tra bảo mật: hiện loading thay vì "Không có sự kiện nào"
    if (_isChecking) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Đang kiểm tra thiết bị...'),
            ],
          ),
        ),
      );
    }
    // GPS tắt / bị từ chối quyền / kiểm tra thiết bị lỗi: báo lỗi cụ thể
    if (_gate != _Gate.none) return _buildGateScreen(scheme);

    // Không an toàn: dialog đã hiện, không lộ nội dung phía sau
    if (!_isSecure) return const Scaffold(body: SizedBox.shrink());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-in Sự kiện',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.transparent,
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: theme.brightness == Brightness.dark
                  ? [Colors.blue.shade900, Colors.purple.shade900]
                  : [Colors.blue.shade600, Colors.purple.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Consumer<CheckInProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.error != null) {
            return _buildErrorState(provider.error!, provider.loadEvents);
          }
          if (provider.events.isEmpty) {
            return const Center(
              child: Text('Không có sự kiện nào', style: TextStyle(fontSize: 18)),
            );
          }

          final event = provider.selectedEvent ?? provider.events.first;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              _buildEventCard(event, scheme),
              const SizedBox(height: 24),
              _buildCountdownTimer(event, scheme),
              if (event.hasGeofence) ...[
                const SizedBox(height: 24),
                // Chỉ khối này rebuild khi có điểm GPS mới
                ValueListenableBuilder<_GeoState>(
                  valueListenable: _geo,
                  builder: (_, geo, __) => Column(
                    children: [
                      RepaintBoundary(child: _buildMapSection(event, geo)),
                      const SizedBox(height: 12),
                      _buildZoneBanner(event, geo, scheme),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ValueListenableBuilder<_GeoState>(
                valueListenable: _geo,
                builder: (_, geo, __) => _buildCheckInButton(event, geo, scheme),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGateScreen(ColorScheme scheme) {
    final IconData icon;
    final String title;
    final String message;
    final String primaryLabel;
    final VoidCallback primaryAction;
    String? secondaryLabel;

    switch (_gate) {
      case _Gate.gpsOff:
        icon = Icons.gps_off;
        title = 'GPS đang tắt';
        message = 'Vui lòng bật GPS để xác định bạn có trong khu vực check-in.';
        primaryLabel = 'Bật GPS';
        primaryAction = () => Geolocator.openLocationSettings();
        secondaryLabel = 'Thử lại';
        break;
      case _Gate.permDenied:
        icon = Icons.location_off;
        title = 'Chưa cấp quyền vị trí';
        message =
        'Ứng dụng cần quyền vị trí để kiểm tra bạn có đang ở đúng khu vực check-in hay không.';
        primaryLabel = 'Cấp quyền';
        primaryAction = _bootstrap;
        break;
      case _Gate.permDeniedForever:
        icon = Icons.lock_outline_rounded;
        title = 'Quyền vị trí đang bị chặn';
        message =
        'Bạn đã từ chối quyền vị trí. Hãy mở Cài đặt > Quyền > Vị trí và chọn "Cho phép" để tiếp tục.';
        primaryLabel = 'Mở cài đặt';
        primaryAction = () => Geolocator.openAppSettings();
        secondaryLabel = 'Thử lại';
        break;
      case _Gate.checkFailed:
      case _Gate.none:
        icon = Icons.error_outline_rounded;
        title = 'Không thể kiểm tra thiết bị';
        message = _gateDetail;
        primaryLabel = 'Thử lại';
        primaryAction = _bootstrap;
        break;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Check-in Sự kiện')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 80, color: scheme.error.withValues(alpha: 0.8)),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: _PrimaryButton(
                  label: primaryLabel,
                  height: 52,
                  fontSize: 16,
                  onPressed: primaryAction,
                ),
              ),
              if (secondaryLabel != null) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: _bootstrap, child: Text(secondaryLabel)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapSection(CheckInEvent event, _GeoState geo) {
    final p = geo.position;
    return CheckInMapCard(
      eventLat: event.latitude!,
      eventLng: event.longitude!,
      radiusMeters: event.radiusMeters,
      zone: event.zone,
      inZone: _isInZone(event, geo),
      locationGranted: geo.granted,
      eventName: event.name,
      // Vị trí ĐÃ LỌC: chấm trên bản đồ đứng yên khi máy đứng yên
      userPosition: p == null ? null : LatLng(p.latitude, p.longitude),
    );
  }

  Widget _buildZoneBanner(CheckInEvent event, _GeoState geo, ColorScheme scheme) {
    if (geo.error != null) {
      return _zoneBanner(
        color: Colors.orange,
        icon: Icons.location_disabled,
        text: geo.error!,
        action: TextButton(
          onPressed: _startLocationTracking,
          child: const Text('Thử lại'),
        ),
      );
    }

    final p = geo.position;
    if (p == null) {
      return _zoneBanner(
        color: Colors.blueGrey,
        icon: Icons.my_location,
        text: 'Đang xác định vị trí của bạn...',
        loading: true,
      );
    }

    if (geo.inZone) {
      return _zoneBanner(
        color: Colors.green,
        icon: Icons.check_circle,
        text: 'Bạn đang trong khu vực check-in',
      );
    }

    final d = _edgeDistance(event, p.latitude, p.longitude);
    return _zoneBanner(
      color: Colors.orange,
      icon: Icons.wrong_location,
      text: 'Bạn đang ngoài khu vực, cách ${_formatDistance(d)} so với vùng check-in',
    );
  }

  Widget _zoneBanner({
    required Color color,
    required IconData icon,
    required String text,
    bool loading = false,
    Widget? action,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          loading
              ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
          )
              : Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: color, fontSize: 14),
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  String _formatDistance(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)}km' : '${m.round()}m';

  Widget _buildErrorState(String error, VoidCallback retry) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(error,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          _PrimaryButton(
            label: 'Thử lại',
            icon: Icons.refresh,
            height: 48,
            fontSize: 15,
            onPressed: retry,
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(CheckInEvent event, ColorScheme scheme) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final timeFormat = DateFormat('HH:mm');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.event_available,
                    color: scheme.onPrimaryContainer, size: 36),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.name,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(dateFormat.format(event.date),
                        style: TextStyle(
                            fontSize: 15, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (event.isCheckedIn)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: Colors.green.shade600, size: 18),
                      const SizedBox(width: 6),
                      Text('Đã check-in',
                          style: TextStyle(
                              color: Colors.green.shade600,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),
          const Divider(height: 32, thickness: 1),
          _buildInfoRow(
            scheme,
            Icons.access_time,
            'Giờ check-in',
            '${timeFormat.format(event.checkInStartTime)} - ${timeFormat.format(event.checkInEndTime)}',
          ),
          if (event.location != null) ...[
            const SizedBox(height: 12),
            _buildInfoRow(scheme, Icons.location_on, 'Địa điểm', event.location!),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(
      ColorScheme scheme, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 22, color: scheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(value,
                  style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownTimer(CheckInEvent event, ColorScheme scheme) {
    if (event.canCheckIn) {
      return _buildStatusCard('Sẵn sàng check-in', Icons.check_circle, Colors.green);
    }
    if (event.timeUntilCheckIn == Duration.zero) {
      return _buildStatusCard('Đã hết giờ check-in', Icons.cancel, scheme.error);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text('Check-in sau',
              style: TextStyle(
                  fontSize: 15,
                  color: scheme.primary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _CountdownDisplay(
            // Truyền MỐC THỜI GIAN đích → không bị reset mỗi lần rebuild
            target: event.checkInStartTime,
            onFinished: () {
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Text(text,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildCheckInButton(
      CheckInEvent event, _GeoState geo, ColorScheme scheme) {
    final inZone = _isInZone(event, geo);
    final timeOk = event.canCheckIn && !event.isCheckedIn;
    final enabled = timeOk && inZone;

    final String label;
    if (event.isCheckedIn) {
      label = 'Đã check-in';
    } else if (!event.canCheckIn) {
      label = 'Chưa đến giờ';
    } else if (!inZone) {
      label = 'Ngoài khu vực check-in';
    } else {
      label = 'Bắt đầu Check-in';
    }

    return _PrimaryButton(
      label: label,
      icon: event.isCheckedIn ? Icons.check_circle : Icons.camera_alt,
      height: 60,
      fontSize: 18,
      onPressed: enabled ? _startCheckIn : null,
    );
  }
}

// =====================================================================
// COUNTDOWN — tính từ mốc thời gian đích, không trôi / không bị reset
// =====================================================================
class _CountdownDisplay extends StatefulWidget {
  final DateTime target;
  final VoidCallback? onFinished;

  const _CountdownDisplay({required this.target, this.onFinished});

  @override
  State<_CountdownDisplay> createState() => _CountdownDisplayState();
}

class _CountdownDisplayState extends State<_CountdownDisplay> {
  Timer? _timer;
  late Duration _remaining;

  Duration _calc() {
    final r = widget.target.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  @override
  void initState() {
    super.initState();
    _remaining = _calc();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _CountdownDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _remaining = _calc();
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (_remaining == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFinished?.call();
      });
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final r = _calc();
      setState(() => _remaining = r);
      if (r == Duration.zero) {
        _timer?.cancel();
        widget.onFinished?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _remaining.inHours;
    final m = _remaining.inMinutes.remainder(60);
    final s = _remaining.inSeconds.remainder(60);
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _digit(h, 'GIỜ', scheme),
        _separator(scheme),
        _digit(m, 'PHÚT', scheme),
        _separator(scheme),
        _digit(s, 'GIÂY', scheme),
      ],
    );
  }

  Widget _digit(int value, String label, ColorScheme scheme) {
    return Column(
      children: [
        Container(
          width: 70,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade700, Colors.purple.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()], // số không "nhảy" độ rộng
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _separator(ColorScheme scheme) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Text(':',
        style: TextStyle(
            fontSize: 36, fontWeight: FontWeight.bold, color: scheme.primary)),
  );
}


// =====================================================================
// NÚT CHÍNH — gradient xanh/tím đồng bộ với AppBar, đúng cả light & dark
// =====================================================================
class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  final double fontSize;

  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 52,
    this.fontSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(16);

    // Dark: dùng tông đậm hơn để chữ trắng không bị chói, bóng đổ nhẹ hơn
    final gradient = LinearGradient(
      colors: isDark
          ? [Colors.blue.shade800, Colors.purple.shade800]
          : [Colors.blue.shade600, Colors.purple.shade600],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    final fg = enabled ? Colors.white : scheme.onSurface.withValues(alpha: 0.38);

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: Ink(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: enabled ? gradient : null,
            color: enabled
                ? null
                : scheme.onSurface.withValues(alpha: isDark ? 0.12 : 0.08),
            borderRadius: radius,
            border: enabled && isDark
                ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                : null,
            boxShadow: enabled
                ? [
              BoxShadow(
                color: (isDark ? Colors.black : Colors.blue.shade700)
                    .withValues(alpha: isDark ? 0.45 : 0.3),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ]
                : null,
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: fg, size: fontSize + 8),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}