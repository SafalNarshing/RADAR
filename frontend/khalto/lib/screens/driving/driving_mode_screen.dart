import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;

import '../../models/pothole.dart';
import '../../services/supabase_service.dart';
import '../../widgets/damage_marker_icon.dart';
import '../../widgets/live_location_marker.dart';

const _navy = Color(0xFF0D1B3E);
const _routeBlue = Color(0xFF2979FF);
const _danger = Color(0xFFE53935);

const _osrmBaseUrl = 'https://router.project-osrm.org/route/v1/driving';
const _navigationZoom = 17.5;
const _arrivalRadiusMeters = 30.0;

// OSRM's free public demo server only runs the driving profile — requesting
// "cycling"/"walking" silently returns the same car route. Bike/walk times
// are therefore estimated from the driving route's distance using typical
// average speeds rather than queried, since a second/third request would
// just return identical (wrong) numbers.
const _cyclingSpeedMetersPerSecond = 4.2; // ~15 km/h
const _walkingSpeedMetersPerSecond = 1.4; // ~5 km/h

const _stepAnnounceRadiusMeters = 40.0;
const _potholeAnnounceRadiusMeters = 100.0;

/// A turn-by-turn instruction derived from one OSRM route step, spoken once
/// the user gets within [_stepAnnounceRadiusMeters] of its maneuver point.
class _RouteStep {
  const _RouteStep({required this.location, required this.instruction});

  final ll.LatLng location;
  final String instruction;
}

String _instructionForStep(Map<String, dynamic> step) {
  final maneuver = step['maneuver'] as Map<String, dynamic>;
  final type = maneuver['type'] as String?;
  final modifier = maneuver['modifier'] as String?;
  final name = step['name'] as String?;
  final roadSuffix = (name != null && name.isNotEmpty) ? ' onto $name' : '';

  switch (type) {
    case 'depart':
      return 'Starting navigation';
    case 'arrive':
      return 'You have arrived at your destination';
    case 'roundabout':
    case 'rotary':
      return 'Enter the roundabout';
  }

  switch (modifier) {
    case 'left':
      return 'Turn left$roadSuffix';
    case 'right':
      return 'Turn right$roadSuffix';
    case 'sharp left':
      return 'Sharp left turn$roadSuffix';
    case 'sharp right':
      return 'Sharp right turn$roadSuffix';
    case 'slight left':
      return 'Bear left$roadSuffix';
    case 'slight right':
      return 'Bear right$roadSuffix';
    case 'uturn':
      return 'Make a U-turn';
    default:
      return 'Continue straight$roadSuffix';
  }
}

/// Full-screen turn-by-turn-style driving view.
///
/// Draws a route from the user's live location to [destination] using OSRM,
/// tracks GPS updates, and keeps the camera centered on the user while
/// "follow" mode is active.
class DrivingModeScreen extends StatefulWidget {
  const DrivingModeScreen({
    super.key,
    required this.destination,
    this.destinationLabel,
  });

  final ll.LatLng destination;
  final String? destinationLabel;

  @override
  State<DrivingModeScreen> createState() => _DrivingModeScreenState();
}

class _DrivingModeScreenState extends State<DrivingModeScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSub;

  ll.LatLng? _currentLocation;
  double _heading = 0;
  List<ll.LatLng> _routePoints = const [];
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;

  bool _isFollowing = true;
  bool _isLoadingRoute = true;
  bool _isFetchingLocation = true;
  bool _hasArrived = false;
  bool _mapReady = false;
  String? _errorMessage;
  VoidCallback? _errorAction;
  String? _errorActionLabel;

  List<Pothole> _potholes = [];

  final FlutterTts _tts = FlutterTts();
  bool _voiceGuidanceEnabled = false;
  List<_RouteStep> _routeSteps = const [];
  int _nextStepIndex = 0;
  final Set<int> _announcedPotholeIds = {};

  @override
  void initState() {
    super.initState();
    _initialize();
    _loadPotholes();
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
  }

  /// Reported potholes along the route, so they stay visible in driving mode
  /// instead of only existing on the main map screen. Best-effort: a failure
  /// here shouldn't block navigation, so it fails silently.
  Future<void> _loadPotholes() async {
    try {
      final potholes = await SupabaseService.getMapMarkers();
      if (!mounted) return;
      setState(() => _potholes = potholes);
    } catch (_) {
      // Navigation itself doesn't depend on this data — ignore.
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      _isFetchingLocation = true;
      _errorMessage = null;
    });

    final position = await _resolveInitialPosition();
    if (!mounted) return;
    if (position == null) {
      setState(() => _isFetchingLocation = false);
      return;
    }

    final start = ll.LatLng(position.latitude, position.longitude);
    setState(() {
      _currentLocation = start;
      _isFetchingLocation = false;
    });

    _moveCamera(start, _navigationZoom);
    await _fetchRoute(start, widget.destination);
    _startLocationStream();
  }

  /// Called once by [FlutterMap] via [MapOptions.onMapReady].
  ///
  /// [MapController.move] throws until the map has rendered at least once,
  /// so any move requested before that (e.g. from the initial GPS fix
  /// resolving faster than the first frame) is queued here instead of lost.
  void _onMapReady() {
    _mapReady = true;
    final loc = _currentLocation;
    if (loc != null) _mapController.move(loc, _navigationZoom);
  }

  void _moveCamera(ll.LatLng center, double zoom) {
    if (!_mapReady) return;
    _mapController.move(center, zoom);
  }

  /// Handles the service-enabled / permission dance and returns the first
  /// GPS fix, or null after setting an appropriate [_errorMessage].
  Future<Position?> _resolveInitialPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setError(
          'Location services are turned off. Enable GPS to start driving mode.',
          actionLabel: 'Open settings',
          action: () => Geolocator.openLocationSettings(),
        );
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _setError(
            'Location permission is required to navigate.',
            actionLabel: 'Retry',
            action: _initialize,
          );
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _setError(
          'Location permission is permanently denied. Enable it from app settings.',
          actionLabel: 'Open settings',
          action: () => Geolocator.openAppSettings(),
        );
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      ).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      _setError(
        'Could not get a GPS fix in time.',
        actionLabel: 'Retry',
        action: _initialize,
      );
      return null;
    } catch (e) {
      _setError(
        'Failed to get your location: $e',
        actionLabel: 'Retry',
        action: _initialize,
      );
      return null;
    }
  }

  void _startLocationStream() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen(_onPositionUpdate, onError: (Object e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Lost GPS signal: $e';
        _errorActionLabel = null;
        _errorAction = null;
      });
    });
  }

  void _onPositionUpdate(Position position) {
    if (!mounted) return;

    final previous = _currentLocation;
    final updated = ll.LatLng(position.latitude, position.longitude);

    double heading = _heading;
    if (position.heading >= 0 && position.headingAccuracy >= 0) {
      heading = position.heading;
    } else if (previous != null &&
        const ll.Distance().as(ll.LengthUnit.Meter, previous, updated) > 1) {
      heading = const ll.Distance().bearing(previous, updated);
    }

    setState(() {
      _currentLocation = updated;
      _heading = heading;
    });

    if (_isFollowing && _mapReady) {
      _mapController.move(updated, _mapController.camera.zoom);
    }

    _announceUpcomingStep(updated);
    _announceNearbyPotholes(updated);
    _checkArrival(updated);
  }

  void _checkArrival(ll.LatLng location) {
    if (_hasArrived) return;
    final distance =
        const ll.Distance().as(ll.LengthUnit.Meter, location, widget.destination);
    if (distance <= _arrivalRadiusMeters) {
      _hasArrived = true;
      _speak('You have arrived at your destination');
      _showArrivedDialog();
    }
  }

  void _announceUpcomingStep(ll.LatLng location) {
    if (!_voiceGuidanceEnabled || _nextStepIndex >= _routeSteps.length) return;
    final step = _routeSteps[_nextStepIndex];
    final distance = const ll.Distance().as(ll.LengthUnit.Meter, location, step.location);
    if (distance <= _stepAnnounceRadiusMeters) {
      _speak(step.instruction);
      _nextStepIndex++;
    }
  }

  void _announceNearbyPotholes(ll.LatLng location) {
    if (!_voiceGuidanceEnabled || _potholes.isEmpty) return;
    for (final p in _potholes) {
      if (_announcedPotholeIds.contains(p.id)) continue;
      final distance = const ll.Distance()
          .as(ll.LengthUnit.Meter, location, ll.LatLng(p.latitude, p.longitude));
      if (distance <= _potholeAnnounceRadiusMeters) {
        _announcedPotholeIds.add(p.id);
        _speak('${Pothole.damageLabel(p.damageType)} ahead');
      }
    }
  }

  void _speak(String text) {
    if (!_voiceGuidanceEnabled) return;
    _tts.speak(text);
  }

  Future<void> _toggleVoiceGuidance() async {
    final enabling = !_voiceGuidanceEnabled;
    setState(() => _voiceGuidanceEnabled = enabling);
    if (enabling) {
      await _tts.speak('Voice guidance on');
    } else {
      await _tts.stop();
    }
  }

  Future<void> _fetchRoute(ll.LatLng from, ll.LatLng to) async {
    setState(() {
      _isLoadingRoute = true;
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse(
        '$_osrmBaseUrl/${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson&steps=true',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('OSRM returned HTTP ${response.statusCode}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['code'] != 'Ok') {
        throw Exception(body['message'] ?? 'No route found');
      }

      final routes = body['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        throw Exception('No route found between these points');
      }

      final route = routes.first as Map<String, dynamic>;
      final coordinates =
          (route['geometry']['coordinates'] as List<dynamic>)
              .map((c) => ll.LatLng((c as List)[1] as double, c[0] as double))
              .toList();

      final steps = <_RouteStep>[];
      for (final leg in route['legs'] as List<dynamic>) {
        for (final step in (leg as Map<String, dynamic>)['steps'] as List<dynamic>) {
          final maneuver = (step as Map<String, dynamic>)['maneuver'] as Map<String, dynamic>;
          final location = maneuver['location'] as List<dynamic>;
          steps.add(
            _RouteStep(
              location: ll.LatLng((location[1] as num).toDouble(), (location[0] as num).toDouble()),
              instruction: _instructionForStep(step),
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _routePoints = coordinates;
        _routeDistanceMeters = (route['distance'] as num).toDouble();
        _routeDurationSeconds = (route['duration'] as num).toDouble();
        _routeSteps = steps;
        _nextStepIndex = 0;
        _isLoadingRoute = false;
      });
    } on TimeoutException {
      _setError(
        'Route request timed out. Check your connection.',
        actionLabel: 'Retry',
        action: () => _fetchRoute(from, to),
      );
      setState(() => _isLoadingRoute = false);
    } catch (e) {
      _setError(
        'Failed to load route: $e',
        actionLabel: 'Retry',
        action: () => _fetchRoute(from, to),
      );
      setState(() => _isLoadingRoute = false);
    }
  }

  void _setError(String message, {String? actionLabel, VoidCallback? action}) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _errorActionLabel = actionLabel;
      _errorAction = action;
    });
  }

  Future<void> _onRecenter() async {
    setState(() => _isFollowing = true);

    var loc = _currentLocation;
    if (loc == null) {
      // The automatic first fix never arrived (denied/timed out earlier) —
      // an explicit tap should retry rather than silently do nothing.
      final position = await _resolveInitialPosition();
      if (!mounted || position == null) return;
      loc = ll.LatLng(position.latitude, position.longitude);
      setState(() => _currentLocation = loc);
      if (_positionSub == null) _startLocationStream();
    }

    _moveCamera(loc, _navigationZoom);
  }

  void _showPotholeInfo(Pothole p) {
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
              p.title ?? p.address ?? Pothole.damageLabel(p.damageType),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                _infoChip(Pothole.severityLabel(p.severity), Pothole.severityColor(p.severity)),
                _infoChip(Pothole.statusLabel(p.status), Pothole.statusColor(p.status)),
              ],
            ),
            const SizedBox(height: 10),
            Text(p.timeAgo, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(String label, Color color) => Container(
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

  void _onMapEvent(MapEvent event) {
    if (event.source == MapEventSource.mapController) return;
    if (_isFollowing) setState(() => _isFollowing = false);
  }

  Future<void> _confirmCancelTrip() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel trip?'),
        content: const Text('This will end driving mode and stop navigation.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep driving'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End trip', style: TextStyle(color: _danger)),
          ),
        ],
      ),
    );
    if (shouldCancel == true && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _showArrivedDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('You have arrived'),
        content: Text(widget.destinationLabel ?? 'You reached your destination.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('End trip'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = _currentLocation ?? widget.destination;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: _navigationZoom,
              onMapEvent: _onMapEvent,
              onMapReady: _onMapReady,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.khalto',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: _routeBlue,
                      strokeWidth: 5,
                      borderColor: Colors.white,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  ..._potholes.map(
                    (p) => Marker(
                      point: ll.LatLng(p.latitude, p.longitude),
                      width: 36,
                      height: 36,
                      child: GestureDetector(
                        onTap: () => _showPotholeInfo(p),
                        child: DamageMarkerIcon(type: p.damageType, size: 32),
                      ),
                    ),
                  ),
                  Marker(
                    point: widget.destination,
                    width: 44,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: const _DestinationPin(),
                  ),
                  if (_currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 46,
                      height: 46,
                      child: LiveLocationMarker(headingDegrees: _heading),
                    ),
                ],
              ),
            ],
          ),

          if (_isFetchingLocation || (_isLoadingRoute && _errorMessage == null))
            const _LoadingOverlay(),

          if (_errorMessage != null)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _ErrorBanner(
                  message: _errorMessage!,
                  actionLabel: _errorActionLabel,
                  onAction: _errorAction,
                  onDismiss: () => setState(() => _errorMessage = null),
                ),
              ),
            )
          else if (_routeDistanceMeters != null && _routeDurationSeconds != null)
            Positioned(
              top: 12,
              right: 16,
              child: SafeArea(
                child: _RouteSummaryCard(
                  distanceMeters: _routeDistanceMeters!,
                  durationSeconds: _routeDurationSeconds!,
                  destinationLabel: widget.destinationLabel,
                ),
              ),
            ),

          if (_errorMessage == null)
            Positioned(
              left: 16,
              top: 12,
              child: SafeArea(
                child: _CircleButton(
                  icon: _voiceGuidanceEnabled ? Icons.volume_up : Icons.volume_off,
                  backgroundColor: _voiceGuidanceEnabled ? _navy : Colors.white,
                  iconColor: _voiceGuidanceEnabled ? Colors.white : _navy,
                  tooltip: _voiceGuidanceEnabled
                      ? 'Turn off voice guidance'
                      : 'Turn on voice guidance',
                  onPressed: _toggleVoiceGuidance,
                ),
              ),
            ),

          Positioned(
            left: 16,
            bottom: 32,
            child: _CircleButton(
              icon: _isFollowing ? Icons.navigation : Icons.my_location,
              backgroundColor: _isFollowing ? _navy : Colors.white,
              iconColor: _isFollowing ? Colors.white : _navy,
              tooltip: 'Recenter on my location',
              onPressed: _onRecenter,
            ),
          ),

          Positioned(
            right: 16,
            bottom: 32,
            child: _PillButton(
              icon: Icons.close,
              label: 'End trip',
              onPressed: _confirmCancelTrip,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteSummaryCard extends StatelessWidget {
  const _RouteSummaryCard({
    required this.distanceMeters,
    required this.durationSeconds,
    this.destinationLabel,
  });

  final double distanceMeters;
  final double durationSeconds;
  final String? destinationLabel;

  String get _distanceLabel => distanceMeters >= 1000
      ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
      : '${distanceMeters.round()} m';

  static String _formatDuration(double seconds) {
    final totalMinutes = (seconds / 60).round();
    if (totalMinutes < 1) return '<1 min';
    if (totalMinutes < 60) return '$totalMinutes min';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final cyclingSeconds = distanceMeters / _cyclingSpeedMetersPerSecond;
    final walkingSeconds = distanceMeters / _walkingSpeedMetersPerSecond;

    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ModeEta(icon: Icons.directions_car, label: _formatDuration(durationSeconds)),
              _ModeEta(icon: Icons.directions_bike, label: _formatDuration(cyclingSeconds)),
              _ModeEta(icon: Icons.directions_walk, label: _formatDuration(walkingSeconds)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _distanceLabel,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
          ),
          if (destinationLabel != null) ...[
            const SizedBox(height: 2),
            Text(
              destinationLabel!,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

/// One travel-mode's estimated time, shown as an icon over a label.
class _ModeEta extends StatelessWidget {
  const _ModeEta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _danger.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: _danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!, style: const TextStyle(color: _navy, fontWeight: FontWeight.bold)),
            )
          else
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onPressed,
    required this.backgroundColor,
    required this.iconColor,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color iconColor;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Icon(icon, color: iconColor, size: 24),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const StadiumBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _danger, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: _danger,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.25),
      child: const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: _navy),
                SizedBox(height: 12),
                Text('Finding your route…'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationPin extends StatelessWidget {
  const _DestinationPin();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.location_on, color: _danger, size: 44, shadows: [
      Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
    ]);
  }
}

