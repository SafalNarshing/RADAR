import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class ResolvedAddress {
  final String primaryLine;
  final String secondaryLine;

  const ResolvedAddress({
    required this.primaryLine,
    required this.secondaryLine,
  });

  String get full => [primaryLine, secondaryLine]
      .where((s) => s.isNotEmpty)
      .join(', ');
}

class LocationService {
  static Future<Position?> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  static Future<ResolvedAddress?> reverseGeocode(
      double latitude, double longitude) async {
    try {
      final placemarks =
          await Geocoding().placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;

      final primary = [p.locality, p.subLocality]
          .where((s) => s != null && s.isNotEmpty)
          .join(', ');
      final secondary = [p.thoroughfare, p.subThoroughfare]
          .where((s) => s != null && s.isNotEmpty)
          .join(', ');

      if (primary.isEmpty && secondary.isEmpty) return null;
      return ResolvedAddress(
        primaryLine: primary,
        secondaryLine: secondary.isEmpty ? (p.name ?? '') : secondary,
      );
    } catch (_) {
      return null;
    }
  }
}
