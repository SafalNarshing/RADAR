import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../../models/cctv_camera.dart';
import '../../../models/pothole.dart';
import '../../../services/location_service.dart';
import '../../../services/gov_service.dart';
import '../../../services/supabase_service.dart';
import '../../../theme/gov_colors.dart';
import '../../../widgets/damage_marker_icon.dart';
import '../../../widgets/gov/status_picker.dart';
import '../../../widgets/radar_brand_title.dart';
import '../../../widgets/live_location_marker.dart';
import '../../../widgets/map_legend.dart';
import '../../driving/driving_mode_screen.dart';
import 'add_cctv_sheet.dart';
import 'cctv_feed_dialog.dart';

// Kathmandu Durbar Square — used only as a map center when GPS/location
// permission isn't available yet.
const _fallbackLat = 27.7040;
const _fallbackLng = 85.3070;

const _iconSize = 36.0;
const _markerWidth = 78.0;
const _markerHeight = 56.0; // label + spacing + icon

const _reportStatusOptions = [
  StatusOption('reported', 'Reported', Color(0xFF9E9E9E)),
  StatusOption('verified', 'Verified', Color(0xFF2196F3)),
  StatusOption('in_progress', 'In Progress', Color(0xFFFF9800)),
  StatusOption('fixed', 'Fixed', Color(0xFF4CAF50)),
  StatusOption('rejected', 'Rejected', Color(0xFFF44336)),
];

String _markerLabel(String status) {
  switch (status) {
    case 'reported':
      return 'New';
    case 'verified':
      return 'Verified';
    case 'in_progress':
      return 'On Review';
    case 'fixed':
      return 'Fixed';
    default:
      return Pothole.statusLabel(status);
  }
}

/// Government/police map tab. Unlike the citizen map, rejected reports are
/// hidden, each marker carries a small status label above it, and tapping a
/// marker opens a small info card anchored beside it (rather than a
/// full-screen bottom sheet) — showing who reported it, the photo, and the
/// location. Tapping anywhere else shrinks it away; a maximize control on
/// the card expands it in place to review details and change the status.
class GovMapScreen extends StatefulWidget {
  const GovMapScreen({super.key});

  @override
  State<GovMapScreen> createState() => _GovMapScreenState();
}

class _GovMapScreenState extends State<GovMapScreen> {
  final _mapController = MapController();

  List<Pothole> _potholes = [];
  bool _loading = true;
  String? _error;
  ll.LatLng _center = const ll.LatLng(_fallbackLat, _fallbackLng);

  StreamSubscription<Position>? _positionSub;
  ll.LatLng? _myLocation;
  double _myHeading = 0;

  // _selected drives the popup's open/closed target; _displayed keeps the
  // last report rendered until the close animation finishes, so the card
  // shrinks away instead of vanishing instantly.
  Pothole? _selected;
  Pothole? _displayed;
  bool _maximized = false;

  List<CctvCamera> _cameras = [];
  bool _addingCamera = false;

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
      final results = await Future.wait([
        GovService.getMapReports(),
        GovService.getCctvCameras(),
      ]);
      if (!mounted) return;
      setState(() {
        _potholes = results[0] as List<Pothole>;
        _cameras = results[1] as List<CctvCamera>;
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

  // Re-fetches reports and cameras without flipping _loading, so an open
  // popup/panel stays on screen while a status change is reflected.
  Future<void> _refreshReports() async {
    try {
      final results = await Future.wait([
        GovService.getMapReports(),
        GovService.getCctvCameras(),
      ]);
      if (mounted) {
        setState(() {
          _potholes = results[0] as List<Pothole>;
          _cameras = results[1] as List<CctvCamera>;
        });
      }
    } catch (_) {}
  }

  // A camera's polyline/marker only render once the report it was pointed
  // at when added still exists (and isn't rejected, which is hidden from
  // this map entirely).
  Pothole? _linkedPothole(CctvCamera camera) {
    if (camera.potholeId == null) return null;
    for (final p in _potholes) {
      if (p.id == camera.potholeId) return p;
    }
    return null;
  }

  void _toggleAddCamera() {
    setState(() => _addingCamera = !_addingCamera);
    if (_addingCamera) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tap a spot on the map to place the camera'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _placeCamera(ll.LatLng point) async {
    const distance = ll.Distance();
    final nearby = List<Pothole>.from(_potholes)
      ..sort((a, b) {
        final da = distance.as(
          ll.LengthUnit.Meter,
          point,
          ll.LatLng(a.latitude, a.longitude),
        );
        final db = distance.as(
          ll.LengthUnit.Meter,
          point,
          ll.LatLng(b.latitude, b.longitude),
        );
        return da.compareTo(db);
      });

    final saved = await showAddCctvSheet(
      context,
      location: point,
      nearbyReports: nearby.take(8).toList(),
    );
    if (!mounted) return;
    setState(() => _addingCamera = false);
    if (saved == true) await _refreshReports();
  }

  Future<void> _openCctvFeed(CctvCamera camera) async {
    final deleted = await showCctvFeedDialog(
      context,
      camera: camera,
      pothole: _linkedPothole(camera),
    );
    if (deleted == true) await _refreshReports();
  }

  void _select(Pothole p) {
    setState(() {
      _selected = p;
      _displayed = p;
      _maximized = false;
    });
  }

  void _deselect() {
    if (_selected == null) return;
    setState(() {
      _selected = null;
      _maximized = false;
    });
  }

  Future<void> _updateStatus(Pothole p, String status) async {
    await GovService.setReportStatus(p.id, status);
    await _refreshReports();
    if (!mounted) return;

    Pothole? updated;
    for (final r in _potholes) {
      if (r.id == p.id) {
        updated = r;
        break;
      }
    }
    setState(() {
      _displayed = updated;
      _selected = updated;
      // Newly-rejected reports drop off the map entirely, so there's
      // nothing left to keep expanded.
      if (updated == null) _maximized = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: GovColors.textPrimary,
        elevation: 0,
        title: const RadarBrandTitle(textColor: GovColors.textPrimary),
        actions: [
          IconButton(
            onPressed: _toggleAddCamera,
            tooltip: _addingCamera ? 'Cancel' : 'Add CCTV camera',
            icon: Icon(
              _addingCamera ? Icons.close_rounded : Icons.videocam_outlined,
              color: _addingCamera ? Colors.red : GovColors.textPrimary,
            ),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _center,
                        initialZoom: 14,
                        onTap: (_, point) =>
                            _addingCamera ? _placeCamera(point) : _deselect(),
                        onMapEvent: (_) {
                          if (_selected != null) setState(() {});
                        },
                        onLongPress: (_, point) => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                DrivingModeScreen(destination: point),
                          ),
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.khalto',
                        ),
                        PolylineLayer(
                          polylines: [
                            // Each connection is drawn twice — a wider black
                            // "casing" line underneath, then the solid amber
                            // line on top — so it reads clearly against any
                            // tile color, not just a thin dashed hairline.
                            for (final camera in _cameras)
                              if (_linkedPothole(camera)
                                  case final linked?) ...[
                                Polyline(
                                  points: [
                                    camera.location,
                                    ll.LatLng(
                                      linked.latitude,
                                      linked.longitude,
                                    ),
                                  ],
                                  color: Colors.black,
                                  strokeWidth: 5,
                                ),
                                Polyline(
                                  points: [
                                    camera.location,
                                    ll.LatLng(
                                      linked.latitude,
                                      linked.longitude,
                                    ),
                                  ],
                                  color: const Color(0xFFFFC107),
                                  strokeWidth: 2.5,
                                ),
                              ],
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            ..._potholes.map(
                              (p) => Marker(
                                point: ll.LatLng(p.latitude, p.longitude),
                                width: _markerWidth,
                                height: _markerHeight,
                                alignment: Marker.computePixelAlignment(
                                  width: _markerWidth,
                                  height: _markerHeight,
                                  left: _markerWidth / 2,
                                  top: _markerHeight - _iconSize / 2,
                                ),
                                child: GestureDetector(
                                  onTap: () => _select(p),
                                  behavior: HitTestBehavior.opaque,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _MarkerStatusLabel(status: p.status),
                                      const SizedBox(height: 2),
                                      DamageMarkerIcon(
                                        type: p.damageType,
                                        size: _iconSize,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (_myLocation != null)
                              Marker(
                                point: _myLocation!,
                                width: 46,
                                height: 46,
                                child: LiveLocationMarker(
                                  headingDegrees: _myHeading,
                                ),
                              ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            for (final camera in _cameras)
                              if (_linkedPothole(camera) != null)
                                Marker(
                                  point: camera.location,
                                  width: 34,
                                  height: 34,
                                  child: GestureDetector(
                                    onTap: () => _openCctvFeed(camera),
                                    child: const _CctvMarkerIcon(),
                                  ),
                                ),
                          ],
                        ),
                      ],
                    ),
                    const Positioned(right: 16, bottom: 16, child: MapLegend()),
                    if (_addingCamera)
                      Positioned(
                        left: 16,
                        right: 16,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: GovColors.primary,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Tap a spot on the map to place the camera',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_displayed != null && !_maximized)
                      _popupCard(_displayed!, constraints),
                    if (_displayed != null && _maximized)
                      _maximizedPanel(_displayed!),
                  ],
                );
              },
            ),
    );
  }

  Widget _popupCard(Pothole p, BoxConstraints constraints) {
    const cardWidth = 240.0;
    const cardHeight = 260.0;

    final anchor = _mapController.camera.latLngToScreenOffset(
      ll.LatLng(p.latitude, p.longitude),
    );

    double left = (anchor.dx + 28).clamp(
      8.0,
      (constraints.maxWidth - cardWidth - 8).clamp(8.0, double.infinity),
    );
    double top = (anchor.dy - cardHeight / 2).clamp(
      8.0,
      (constraints.maxHeight - cardHeight - 8).clamp(8.0, double.infinity),
    );

    return Positioned(
      left: left,
      top: top,
      child: AnimatedScale(
        scale: _selected == p ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        onEnd: () {
          if (_selected != p && mounted) setState(() => _displayed = null);
        },
        child: _ReportPopup(
          pothole: p,
          width: cardWidth,
          onNavigate: () => _navigate(p),
          onMaximize: () => setState(() => _maximized = true),
        ),
      ),
    );
  }

  Widget _maximizedPanel(Pothole p) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: _MaximizedReportPanel(
        pothole: p,
        onMinimize: () => setState(() => _maximized = false),
        onClose: _deselect,
        onNavigate: () => _navigate(p),
        onStatusChange: (status) => _updateStatus(p, status),
        onDelete: () => _confirmDelete(p),
      ),
    );
  }

  void _navigate(Pothole p) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrivingModeScreen(
          destination: ll.LatLng(p.latitude, p.longitude),
          destinationLabel: p.title ?? p.address,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Pothole p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this report?'),
        content: Text(
          'This permanently removes "${p.title ?? 'this report'}" and its '
          'photos, comments, and upvotes. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await GovService.deleteReport(p.id);
    if (!mounted) return;
    _deselect();
    await _refreshReports();
  }
}

class _CctvMarkerIcon extends StatelessWidget {
  const _CctvMarkerIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D29),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Center(
            child: Icon(Icons.videocam_rounded, color: Colors.white, size: 18),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkerStatusLabel extends StatelessWidget {
  final String status;

  const _MarkerStatusLabel({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = Pothole.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        _markerLabel(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ReportPopup extends StatelessWidget {
  final Pothole pothole;
  final double width;
  final VoidCallback onNavigate;
  final VoidCallback onMaximize;

  const _ReportPopup({
    required this.pothole,
    required this.width,
    required this.onNavigate,
    required this.onMaximize,
  });

  @override
  Widget build(BuildContext context) {
    final p = pothole;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: GovColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.primaryImagePath != null)
              Image.network(
                SupabaseService.getImageUrl(p.primaryImagePath!),
                height: 100,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, st) => Container(
                  height: 100,
                  color: GovColors.chipBg,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              )
            else
              Container(
                height: 60,
                width: double.infinity,
                color: GovColors.chipBg,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.grey.shade400,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.title ?? 'Road damage report',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: GovColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: onMaximize,
                        borderRadius: BorderRadius.circular(16),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.open_in_full_rounded,
                            size: 16,
                            color: GovColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 13,
                        color: GovColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          p.reporterName ?? 'Unknown reporter',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: GovColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: GovColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          p.address ??
                              '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: GovColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _chip(
                        Pothole.statusLabel(p.status),
                        Pothole.statusColor(p.status),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: onNavigate,
                        borderRadius: BorderRadius.circular(16),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.navigation_outlined,
                            size: 18,
                            color: GovColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

/// Expanded in-map view opened via the popup's maximize control — shows
/// full report details and lets an officer change status without leaving
/// the map.
class _MaximizedReportPanel extends StatelessWidget {
  final Pothole pothole;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final VoidCallback onNavigate;
  final ValueChanged<String> onStatusChange;
  final VoidCallback onDelete;

  const _MaximizedReportPanel({
    required this.pothole,
    required this.onMinimize,
    required this.onClose,
    required this.onNavigate,
    required this.onStatusChange,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = pothole;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          color: GovColors.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (p.primaryImagePath != null)
                Image.network(
                  SupabaseService.getImageUrl(p.primaryImagePath!),
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, st) => Container(
                    height: 160,
                    color: GovColors.chipBg,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.title ?? 'Road damage report',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: GovColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: onMinimize,
                          icon: const Icon(
                            Icons.close_fullscreen_rounded,
                            size: 18,
                          ),
                          tooltip: 'Minimize',
                          color: GovColors.textSecondary,
                        ),
                        IconButton(
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded, size: 20),
                          tooltip: 'Close',
                          color: GovColors.textSecondary,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 15,
                          color: GovColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Reported by ${p.reporterName ?? 'Unknown'}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: GovColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 15,
                          color: GovColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            p.address ??
                                '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: GovColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (p.description != null && p.description!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        p.description!,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: GovColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _chip(
                          Pothole.severityLabel(p.severity),
                          Pothole.severityColor(p.severity),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => showStatusPicker(
                            context: context,
                            title: 'Update status',
                            current: p.status,
                            options: _reportStatusOptions,
                            onSelected: onStatusChange,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Pothole.statusColor(
                                p.status,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Pothole.statusColor(
                                  p.status,
                                ).withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  Pothole.statusLabel(p.status),
                                  style: TextStyle(
                                    color: Pothole.statusColor(p.status),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.unfold_more,
                                  size: 13,
                                  color: Pothole.statusColor(p.status),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onNavigate,
                            icon: const Icon(
                              Icons.navigation_outlined,
                              size: 18,
                            ),
                            label: const Text('Navigate here'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: GovColors.primary,
                              side: const BorderSide(color: GovColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: onDelete,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
