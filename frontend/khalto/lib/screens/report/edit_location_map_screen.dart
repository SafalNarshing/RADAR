import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../models/pothole.dart';
import '../../services/supabase_service.dart';
import '../../widgets/damage_marker_icon.dart';

const _navy = Color(0xFF0D1B3E);

/// Full-screen map picker built on flutter_map/OpenStreetMap (no API key or
/// billing account needed) — the pin stays fixed at the center of the
/// screen while the map pans underneath it, then returns the current
/// center coordinate as a (latitude, longitude) record on confirm.
///
/// Previously-reported potholes are plotted underneath (read-only, tap for
/// a quick peek) so a citizen can see there's already a report nearby
/// before submitting a duplicate.
class EditLocationMapScreen extends StatefulWidget {
  final double initialLatitude;
  final double initialLongitude;

  const EditLocationMapScreen({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
  });

  @override
  State<EditLocationMapScreen> createState() => _EditLocationMapScreenState();
}

class _EditLocationMapScreenState extends State<EditLocationMapScreen> {
  late final MapController _mapController;
  late ll.LatLng _center;
  List<Pothole> _existingReports = [];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _center = ll.LatLng(widget.initialLatitude, widget.initialLongitude);
    _loadExistingReports();
  }

  Future<void> _loadExistingReports() async {
    try {
      final markers = await SupabaseService.getMapMarkers();
      if (mounted) setState(() => _existingReports = markers);
    } catch (_) {
      // Silently skip — the picker still works without the overlay.
    }
  }

  void _previewExisting(Pothole p) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Already reported nearby: ${p.title ?? Pothole.damageLabel(p.damageType)} '
          '(${p.timeAgo})',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Location'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 16,
              onPositionChanged: (position, hasGesture) {
                _center = position.center;
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.khalto',
              ),
              MarkerLayer(
                markers: [
                  for (final p in _existingReports)
                    Marker(
                      point: ll.LatLng(p.latitude, p.longitude),
                      width: 30,
                      height: 30,
                      child: GestureDetector(
                        onTap: () => _previewExisting(p),
                        child: Opacity(
                          opacity: 0.75,
                          child: DamageMarkerIcon(type: p.damageType, size: 26),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const IgnorePointer(
            child: Padding(
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(Icons.location_pin, size: 48, color: _navy),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context)
                    .pop((_center.latitude, _center.longitude)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Confirm Location',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
