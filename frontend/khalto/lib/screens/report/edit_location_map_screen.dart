import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

const _navy = Color(0xFF0D1B3E);

/// Full-screen map picker built on flutter_map/OpenStreetMap (no API key or
/// billing account needed) — the pin stays fixed at the center of the
/// screen while the map pans underneath it, then returns the current
/// center coordinate as a (latitude, longitude) record on confirm.
///
/// Uses the same tile-layer/marker model this app will reuse later for
/// showing potholes and directions on a map.
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

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _center = ll.LatLng(widget.initialLatitude, widget.initialLongitude);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FB),
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
                onPressed: () => Navigator.of(
                  context,
                ).pop((_center.latitude, _center.longitude)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Confirm Location',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
