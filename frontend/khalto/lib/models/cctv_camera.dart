import 'package:latlong2/latlong.dart' as ll;

/// The 3 bundled demo camera-feed videos (assets/cctv1.mp4 etc.) an officer
/// picks from when adding a camera to the map.
enum CctvAsset {
  cctv1,
  cctv2,
  cctv3;

  String get assetPath => 'assets/$name.mp4';

  String get label {
    switch (this) {
      case CctvAsset.cctv1:
        return 'CCTV 1';
      case CctvAsset.cctv2:
        return 'CCTV 2';
      case CctvAsset.cctv3:
        return 'CCTV 3';
    }
  }

  static CctvAsset fromKey(String key) => CctvAsset.values.firstWhere(
    (a) => a.name == key,
    orElse: () => CctvAsset.cctv1,
  );
}

/// A monitoring camera plotted on the government map, pointing at whichever
/// pothole report it was linked to when added. Backed by the `cctv_cameras`
/// table — there's no real CCTV integration, so this is officer-placed demo
/// data rather than a live feed.
class CctvCamera {
  final int id;
  final String name;
  final ll.LatLng location;
  final int? potholeId;
  final CctvAsset asset;

  const CctvCamera({
    required this.id,
    required this.name,
    required this.location,
    required this.potholeId,
    required this.asset,
  });

  factory CctvCamera.fromJson(Map<String, dynamic> json) {
    return CctvCamera(
      id: json['id'],
      name: json['name'] ?? 'Camera',
      location: ll.LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
      potholeId: json['pothole_id'],
      asset: CctvAsset.fromKey(json['asset_key'] ?? 'cctv1'),
    );
  }
}
