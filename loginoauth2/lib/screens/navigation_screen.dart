import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/directions_service.dart';
import 'login_screen.dart';

enum TravelMode { car, motorbike, walk, bus }

extension TravelModeExtension on TravelMode {
  RoutesTravelMode get toRoutesMode {
    switch (this) {
      case TravelMode.car:
        return RoutesTravelMode.drive;
      case TravelMode.motorbike:
        return RoutesTravelMode.twoWheeler;
      case TravelMode.walk:
        return RoutesTravelMode.walk;
      case TravelMode.bus:
        return RoutesTravelMode.transit;
    }
  }
}

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  // TODO: Thay bằng API key thật của bạn (Bật Routes API & Maps SDK trong Cloud Console).
  static const String _apiKey = 'AIzaSyB_rzAF1x9c4sVbdYPR4v3Vv3BA2NYoQzo';

  final DirectionsService _directionsService = DirectionsService(_apiKey);
  GoogleMapController? _mapController;

  TravelMode _selectedMode = TravelMode.motorbike;

  static const LatLng _origin = LatLng(10.7889, 106.7000); // Vị trí mẫu
  static const LatLng _destination = LatLng(10.7952, 106.7218); // Landmark 81
  static const String _destinationLabel = 'Landmark 81, Vinhomes Ce...';

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(10.7920, 106.7100),
    zoom: 14.5,
  );

  bool _loading = true;
  String? _error;
  DirectionsResult? _route;
  Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {
    const Marker(markerId: MarkerId('origin'), position: _origin),
    Marker(
      markerId: const MarkerId('destination'),
      position: _destination,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: const InfoWindow(title: 'Landmark 81'),
    ),
  };

  @override
  void initState() {
    super.initState();
    _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _directionsService.getDirections(
        origin: _origin,
        destination: _destination,
        mode: _selectedMode.toRoutesMode,
      );

      setState(() {
        _route = result;
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            color: Colors.blue,
            width: 6,
            points: result.polylinePoints,
          ),
        };
        _loading = false;
      });

      if (_mapController != null && result.polylinePoints.isNotEmpty) {
        final bounds = _boundsFromPoints(result.polylinePoints);
        _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
      }
    } catch (e) {
      setState(() {
        _error = 'Không lấy được tuyến đường: $e';
        _loading = false;
      });
    }
  }

  LatLngBounds _boundsFromPoints(List<LatLng> points) {
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  void _onModeSelected(TravelMode mode) {
    if (mode == _selectedMode) return;
    setState(() => _selectedMode = mode);
    _fetchRoute();
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất khỏi ứng dụng?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    return Scaffold(
      body: Stack(
        children: [
          // ---------- BẢN ĐỒ ----------
          GoogleMap(
            initialCameraPosition: _initialCamera,
            onMapCreated: (c) {
              _mapController = c;
              if (_route != null) {
                _mapController!.animateCamera(
                  CameraUpdate.newLatLngBounds(
                    _boundsFromPoints(_route!.polylinePoints),
                    60,
                  ),
                );
              }
            },
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            padding: const EdgeInsets.only(bottom: 320),
          ),

          // ---------- THANH TÌM KIẾM TRÊN CÙNG ----------
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: _SearchBar(
              destinationLabel: _destinationLabel,
              userPhotoUrl: user?.photoUrl,
              userName: user?.displayName ?? user?.email,
              onSignOut: _confirmSignOut,
            ),
          ),

          // ---------- CHIP CHỌN PHƯƠNG TIỆN ----------
          Positioned(
            top: MediaQuery.of(context).padding.top + 8 + 130,
            left: 12,
            right: 12,
            child: _TravelModeRow(
              selected: _selectedMode,
              onSelected: _onModeSelected,
            ),
          ),

          // ---------- NÚT NỔI BÊN PHẢI ----------
          Positioned(
            right: 12,
            bottom: 340,
            child: Column(
              children: [
                const _RoundIconButton(icon: Icons.layers_outlined),
                const SizedBox(height: 10),
                const _RoundIconButton(icon: Icons.explore_outlined, tint: Colors.red),
                const SizedBox(height: 10),
                _RoundIconButton(
                  icon: Icons.my_location,
                  tint: Colors.blue,
                  onTap: () {
                    if (_mapController != null) {
                      _mapController!.animateCamera(
                        CameraUpdate.newCameraPosition(_initialCamera),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          // ---------- LOADING TOÀN MÀN HÌNH NHẸ ----------
          if (_loading)
            const Positioned(
              top: 220,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),

          // ---------- BẢNG THÔNG TIN CHUYẾN ĐI ----------
          _RouteInfoSheet(
            route: _route,
            loading: _loading,
            error: _error,
            onRetry: _fetchRoute,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Thanh tìm kiếm (điểm đi / điểm đến + Nút đăng xuất/Avatar)
// ============================================================
class _SearchBar extends StatelessWidget {
  final String destinationLabel;
  final String? userPhotoUrl;
  final String? userName;
  final VoidCallback onSignOut;

  const _SearchBar({
    required this.destinationLabel,
    this.userPhotoUrl,
    this.userName,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(20),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            GestureDetector(
              onTap: onSignOut,
              child: Tooltip(
                message: 'Đăng xuất (${userName ?? ""})',
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.blue.shade100,
                  backgroundImage: userPhotoUrl != null ? NetworkImage(userPhotoUrl!) : null,
                  child: userPhotoUrl == null
                      ? const Icon(Iconsax.logout, size: 18, color: Colors.blue)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                children: [
                  const _AddressPill(
                    icon: Icons.circle,
                    iconColor: Colors.blue,
                    label: 'Vị trí của bạn',
                  ),
                  const SizedBox(height: 6),
                  _AddressPill(
                    icon: Icons.location_on,
                    iconColor: Colors.red,
                    label: destinationLabel,
                    bold: true,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.swap_vert),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressPill extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool bold;

  const _AddressPill({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Hàng chip chọn phương tiện di chuyển
// ============================================================
class _TravelModeRow extends StatelessWidget {
  final TravelMode selected;
  final ValueChanged<TravelMode> onSelected;

  const _TravelModeRow({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final items = <_ModeData>[
      _ModeData(TravelMode.car, Icons.directions_car, 'Ô tô'),
      _ModeData(TravelMode.motorbike, Icons.two_wheeler, 'Xe máy'),
      _ModeData(TravelMode.walk, Icons.directions_walk, 'Đi bộ'),
      _ModeData(TravelMode.bus, Icons.directions_bus, 'Xe buýt'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items.map((m) {
          final isSelected = m.mode == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: isSelected,
              onSelected: (_) => onSelected(m.mode),
              backgroundColor: Colors.white,
              selectedColor: const Color(0xFFD3E3FD),
              labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? Colors.blue : Colors.transparent,
                ),
              ),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(m.icon, size: 18, color: isSelected ? Colors.blue[800] : Colors.black87),
                  const SizedBox(width: 4),
                  Text(
                    m.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.blue[800] : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ModeData {
  final TravelMode mode;
  final IconData icon;
  final String label;
  _ModeData(this.mode, this.icon, this.label);
}

// ============================================================
// Nút tròn nổi (layers / compass / locate)
// ============================================================
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final VoidCallback? onTap;

  const _RoundIconButton({
    required this.icon,
    this.tint = Colors.black87,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: const CircleBorder(),
      elevation: 3,
      color: Colors.white,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap ?? () {},
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: tint, size: 22),
        ),
      ),
    );
  }
}

// ============================================================
// Bảng thông tin chuyến đi kéo lên/xuống (bottom sheet)
// ============================================================
class _RouteInfoSheet extends StatelessWidget {
  final DirectionsResult? route;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  const _RouteInfoSheet({
    required this.route,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.42,
      minChildSize: 0.28,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2)),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (error != null) ...[
                Text(error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: onRetry, child: const Text('Thử lại')),
              ] else if (loading || route == null) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(color: Colors.black, fontSize: 26, fontWeight: FontWeight.bold),
                          children: [
                            TextSpan(text: route!.durationText, style: const TextStyle(color: Color(0xFF1E8E3E))),
                            TextSpan(
                              text: '  (${route!.distanceText})',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F4EA),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.sensors, size: 16, color: Color(0xFF1E8E3E)),
                          SizedBox(width: 4),
                          Text(
                            'Giao thông thông\nthoáng',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Color(0xFF1E8E3E), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tuyến đường nhanh nhất',
                  style: TextStyle(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B7A3D),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                        icon: const Icon(Icons.navigation),
                        label: const Text('Bắt đầu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue[800],
                          backgroundColor: const Color(0xFFD3E3FD),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                        icon: const Icon(Icons.share_location),
                        label: const Text('Chia sẻ', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Material(
                      shape: const CircleBorder(),
                      color: Colors.white,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {},
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const Icon(Icons.remove_red_eye_outlined, color: Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 32),
                ...route!.steps.map(
                  (step) => _DirectionStepWidget(
                    icon: _iconForManeuver(step.maneuver),
                    title: step.instruction,
                    subtitle: '${step.distanceText} • ${step.durationText}',
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  IconData _iconForManeuver(String maneuver) {
    switch (maneuver) {
      case 'TURN_RIGHT':
      case 'TURN_SLIGHT_RIGHT':
      case 'TURN_SHARP_RIGHT':
        return Icons.turn_right;
      case 'TURN_LEFT':
      case 'TURN_SLIGHT_LEFT':
      case 'TURN_SHARP_LEFT':
        return Icons.turn_left;
      case 'UTURN_LEFT':
      case 'UTURN_RIGHT':
        return Icons.u_turn_left;
      case 'ROUNDABOUT_LEFT':
      case 'ROUNDABOUT_RIGHT':
        return Icons.roundabout_left;
      case 'MERGE':
        return Icons.merge;
      case 'RAMP_LEFT':
      case 'RAMP_RIGHT':
      case 'FORK_LEFT':
      case 'FORK_RIGHT':
        return Icons.fork_right;
      case 'FERRY':
      case 'FERRY_TRAIN':
        return Icons.directions_boat;
      default:
        return Icons.arrow_upward;
    }
  }
}

class _DirectionStepWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _DirectionStepWidget({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFEDEDED),
            child: Icon(icon, size: 18, color: Colors.blue[800]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
