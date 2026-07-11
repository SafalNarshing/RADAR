import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../models/pothole.dart';
import '../../services/location_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/damage_marker_icon.dart';
import '../../widgets/live_location_marker.dart';
import '../../widgets/map_legend.dart';
import '../driving/driving_mode_screen.dart';

const _navy = Color(0xFF0D1B3E);

// Kathmandu Durbar Square — used only as a map center when GPS/location
// permission isn't available yet.
const _fallbackLat = 27.7040;
const _fallbackLng = 85.3070;

class PotholesMapScreen extends StatefulWidget {
  const PotholesMapScreen({super.key});

  @override
  State<PotholesMapScreen> createState() => _PotholesMapScreenState();
}

class _PotholesMapScreenState extends State<PotholesMapScreen> {
  List<Pothole> _potholes = [];
  bool _loading = true;
  String? _error;
  ll.LatLng _center = const ll.LatLng(_fallbackLat, _fallbackLng);

  StreamSubscription<Position>? _positionSub;
  ll.LatLng? _myLocation;
  double _myHeading = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _startLiveLocation();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  /// Best-effort live location for the "you are here" marker. Failures are
  /// silent here — [_load] already surfaces a proper error if location is
  /// unavailable for centering the map, so this just skips the marker.
  Future<void> _startLiveLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_onPositionUpdate, onError: (_) {});
  }

  void _onPositionUpdate(Position position) {
    if (!mounted) return;

    final previous = _myLocation;
    final updated = ll.LatLng(position.latitude, position.longitude);

    double heading = _myHeading;
    if (position.heading >= 0 && position.headingAccuracy >= 0) {
      heading = position.heading;
    } else if (previous != null &&
        const ll.Distance().as(ll.LengthUnit.Meter, previous, updated) > 1) {
      heading = const ll.Distance().bearing(previous, updated);
    }

    setState(() {
      _myLocation = updated;
      _myHeading = heading;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pos = await LocationService.getCurrentLocation();
      final markers = await SupabaseService.getMapMarkers();
      if (!mounted) return;
      setState(() {
        _potholes = markers;
        if (pos != null) _center = ll.LatLng(pos.latitude, pos.longitude);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load map: $e';
      });
    }
  }

  void _showDetails(Pothole p) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.title ?? p.address ?? 'Pothole report',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _chip(
                  Pothole.severityLabel(p.severity),
                  Pothole.severityColor(p.severity),
                ),
                const SizedBox(width: 8),
                _chip(
                  Pothole.statusLabel(p.status),
                  Pothole.statusColor(p.status),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              p.timeAgo,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DrivingModeScreen(
                        destination: ll.LatLng(p.latitude, p.longitude),
                        destinationLabel: p.title ?? p.address,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.navigation),
                label: const Text('Navigate here'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Image.asset(
                'assets/Radarlogo.png',
                height: 24,
                errorBuilder: (ctx, err, st) =>
                    const SizedBox(width: 24, height: 24),
              ),
            ),
            const Text(
              'RADAR',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 14,
                    onLongPress: (_, point) => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DrivingModeScreen(destination: point),
                      ),
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.khalto',
                    ),
                    MarkerLayer(
                      markers: [
                        ..._potholes.map(
                          (p) => Marker(
                            point: ll.LatLng(p.latitude, p.longitude),
                            width: 40,
                            height: 40,
                            child: GestureDetector(
                              onTap: () => _showDetails(p),
                              child: DamageMarkerIcon(
                                type: p.damageType,
                                size: 36,
                              ),
                            ),
                          ),
                        ),
                        if (_myLocation != null)
                          Marker(
                            point: _myLocation!,
                            width: 46,
                            height: 46,
                            child: LiveLocationMarker(headingDegrees: _myHeading),
                          ),
                      ],
                    ),
                  ],
                ),
                const Positioned(right: 16, bottom: 16, child: MapLegend()),
              ],
            ),
    );
  }
}
