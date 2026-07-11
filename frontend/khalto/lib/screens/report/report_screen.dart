import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/pothole.dart';
import '../../services/damage_detection_service.dart';
import '../../services/location_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/damage_marker_icon.dart';
import '../../widgets/dashed_border_box.dart';
import '../../widgets/detection_dialogs.dart';
import 'damage_scan_camera_screen.dart';
import 'edit_location_map_screen.dart';

const _navy = Color(0xFF0D1B3E);
const _lavender = Color(0xFFF7F9FB);

const _linkBlue = Color(0xFF3B5BFB);
// const _pageBg = Color(FFFFF);

// Kathmandu Durbar Square — used only as a map-picker starting point when
// GPS hasn't resolved a location yet.
const _fallbackLat = 27.7040;
const _fallbackLng = 85.3070;

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _nameCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  late final TapGestureRecognizer _browseRecognizer;

  final List<XFile> _images = [];
  final Map<XFile, double> _progress = {};
  final Map<XFile, bool> _paused = {};
  final Map<XFile, int> _sizes = {};
  final Map<XFile, Uint8List> _thumbBytes = {};
  Timer? _progressTimer;

  double? _lat;
  double? _lng;
  ResolvedAddress? _address;
  bool _locating = false;
  bool _submitting = false;

  final DamageDetectionService _detectionService =
      SimulatedDamageDetectionService();
  DamageType? _damageType;
  bool _detecting = false;

  @override
  void initState() {
    super.initState();
    _browseRecognizer = TapGestureRecognizer()..onTap = _showImageSourceSheet;
    _fetchLocation();
    _prefillName();
  }

  Future<void> _prefillName() async {
    final profile = await SupabaseService.getCurrentProfile();
    final name = profile?['full_name'] as String?;
    if (mounted && name != null && name.trim().isNotEmpty) {
      _nameCtrl.text = name;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _browseRecognizer.dispose();
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    setState(() {
      _locating = true;
      _address = null;
    });
    try {
      final pos = await LocationService.getCurrentLocation();
      if (pos != null) {
        final address = await LocationService.reverseGeocode(
          pos.latitude,
          pos.longitude,
        );
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          _address = address;
        });
      }
    } catch (_) {
      // Leave last-known location in place; UI falls back to "unavailable".
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _editOnMap() async {
    final result = await Navigator.of(context).push<(double, double)>(
      MaterialPageRoute(
        builder: (_) => EditLocationMapScreen(
          initialLatitude: _lat ?? _fallbackLat,
          initialLongitude: _lng ?? _fallbackLng,
        ),
      ),
    );
    if (result == null) return;

    final (lat, lng) = result;
    setState(() {
      _lat = lat;
      _lng = lng;
      _address = null;
      _locating = true;
    });
    final address = await LocationService.reverseGeocode(lat, lng);
    if (mounted) {
      setState(() {
        _address = address;
        _locating = false;
      });
    }
  }

  Future<void> _showImageSourceSheet() async {
    if (_images.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can add up to 5 photos')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Scan with camera'),
              onTap: () {
                Navigator.pop(ctx);
                _scanWithCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImages(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the on-device AI scan camera (draws bounding boxes on capture)
  /// instead of a plain image_picker camera shot, so the model's detection
  /// runs at capture time rather than after the fact.
  Future<void> _scanWithCamera() async {
    final result = await Navigator.of(context).push<(XFile, DamageType?)>(
      MaterialPageRoute(builder: (_) => const DamageScanCameraScreen()),
    );
    if (result == null) return;
    final (image, damageType) = result;
    await _addScannedImage(image, damageType);
  }

  Future<void> _addScannedImage(XFile file, DamageType? damageType) async {
    if (_images.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can add up to 5 photos')),
      );
      return;
    }

    final size = await file.length();
    final bytes = await file.readAsBytes();

    setState(() {
      _images.add(file);
      _progress[file] = 0;
      _paused[file] = false;
      _sizes[file] = size;
      _thumbBytes[file] = bytes;
      if (damageType != null) _damageType = damageType;
    });
    _startProgressTicker();

    // The scan screen already ran real detection — only fall back to
    // manual classification when it found nothing confident, instead of
    // also running the simulated detector on top of a real result.
    if (damageType == null && mounted) {
      final selected = await showManualDamageTypeDialog(context);
      if (!mounted) return;
      if (selected != null) setState(() => _damageType = selected);
    }
  }

  Future<void> _pickImages(ImageSource source) async {
    final picker = ImagePicker();
    List<XFile> picked = [];
    if (source == ImageSource.gallery) {
      picked = await picker.pickMultiImage(imageQuality: 80);
    } else {
      final single = await picker.pickImage(source: source, imageQuality: 80);
      if (single != null) picked = [single];
    }
    if (picked.isEmpty) return;

    final wasEmpty = _images.isEmpty;
    final remainingSlots = 5 - _images.length;
    final toAdd = picked.take(remainingSlots).toList();

    // Read size/bytes via XFile's async, cross-platform API — dart:io's
    // File.lengthSync()/Image.file() cannot run on Flutter Web at all.
    final sizes = <XFile, int>{};
    final bytes = <XFile, Uint8List>{};
    for (final f in toAdd) {
      sizes[f] = await f.length();
      bytes[f] = await f.readAsBytes();
    }

    setState(() {
      for (final f in toAdd) {
        _images.add(f);
        _progress[f] = 0;
        _paused[f] = false;
        _sizes[f] = sizes[f]!;
        _thumbBytes[f] = bytes[f]!;
      }
    });
    _startProgressTicker();

    // Classify once per report, using the first photo added — extra
    // angles of the same damage don't need re-classification.
    if (wasEmpty && toAdd.isNotEmpty) {
      _runDetection(toAdd.first);
    }
  }

  Future<void> _runDetection(XFile image) async {
    setState(() => _detecting = true);
    DetectionResult result;
    try {
      result = await _detectionService.detect(image);
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
    if (!mounted) return;

    if (result.isConfident) {
      final confirmed = await showDetectionConfirmDialog(
        context,
        type: result.type!,
        confidence: result.confidence,
      );
      if (!mounted) return;
      if (confirmed == true) {
        setState(() => _damageType = result.type);
      } else if (confirmed == false) {
        _retakeImages();
      }
    } else {
      final selected = await showManualDamageTypeDialog(context);
      if (!mounted) return;
      if (selected != null) setState(() => _damageType = selected);
    }
  }

  void _retakeImages() {
    setState(() {
      for (final f in List<XFile>.from(_images)) {
        _progress.remove(f);
        _paused.remove(f);
        _sizes.remove(f);
        _thumbBytes.remove(f);
      }
      _images.clear();
      _damageType = null;
    });
    _showImageSourceSheet();
  }

  void _startProgressTicker() {
    _progressTimer ??= Timer.periodic(const Duration(milliseconds: 150), (t) {
      if (!mounted || _images.isEmpty) {
        t.cancel();
        _progressTimer = null;
        return;
      }
      setState(() {
        for (final f in _images) {
          if (_paused[f] == true) continue;
          final p = (_progress[f] ?? 0) + 0.08;
          _progress[f] = p > 1 ? 1 : p;
        }
      });
    });
  }

  void _removeImage(XFile f) {
    setState(() {
      _images.remove(f);
      _progress.remove(f);
      _paused.remove(f);
      _sizes.remove(f);
      _thumbBytes.remove(f);
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _submit() async {
    if (_lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location is required to submit a report'),
        ),
      );
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your name to submit a report')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await SupabaseService.updateFullName(_nameCtrl.text.trim());
      await SupabaseService.submitReport(
        latitude: _lat!,
        longitude: _lng!,
        address: _address?.full,
        title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        images: _images,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Image.asset(
                      'assets/Radarlogo.png',
                      height: 24,
                      errorBuilder: (ctx, err, st) =>
                          const SizedBox(width: 24, height: 24),
                    ),
                  ),
                  const Text(
                    'RADAR',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close, color: _navy),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Upload Photos',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 8),
              _photosCard(),
              const SizedBox(height: 20),
              _locationCard(),
              const SizedBox(height: 20),
              _optionalDetails(),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _navy,
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: (_submitting || _detecting) ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _navy,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Upload',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );

  Widget _photosCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: _showImageSourceSheet,
            child: DashedBorderBox(
              color: Colors.grey.shade400,
              borderRadius: 16,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _lavender,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.photo_library_rounded,
                        color: _navy,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 16),
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                        children: [
                          const TextSpan(text: 'Drop your image here, or '),
                          TextSpan(
                            text: 'browse',
                            style: const TextStyle(
                              color: _linkBlue,
                              fontWeight: FontWeight.w600,
                            ),
                            recognizer: _browseRecognizer,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Supports: PNG, JPG, JPEG, WEBP',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_images.isNotEmpty) ...[
            const SizedBox(height: 16),
            ..._images.map(_imageRow),
            const SizedBox(height: 4),
            _classificationStatus(),
          ],
        ],
      ),
    );
  }

  Widget _classificationStatus() {
    if (_detecting) {
      return Row(
        children: [
          const SizedBox(
            height: 14,
            width: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Analyzing photo...',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
          ),
        ],
      );
    }
    if (_damageType == null) return const SizedBox.shrink();

    return Row(
      children: [
        DamageMarkerIcon(type: _damageType!, size: 22),
        const SizedBox(width: 10),
        Text(
          'Classified as ${Pothole.damageLabel(_damageType!)}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _imageRow(XFile f) {
    final progress = _progress[f] ?? 0;
    final paused = _paused[f] ?? false;
    final pct = (progress * 100).round();
    final bytes = _thumbBytes[f];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: bytes != null
                ? Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover)
                : Container(width: 56, height: 56, color: Colors.grey.shade200),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _paused[f] = !paused),
                      child: Icon(
                        paused
                            ? Icons.play_circle_outline
                            : Icons.pause_circle_outline,
                        size: 20,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _removeImage(f),
                      child: const Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _formatSize(_sizes[f] ?? 0),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$pct%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _navy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    color: _navy,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Location Details',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _navy,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _locating ? null : _editOnMap,
                child: const Text(
                  'Edit on Map',
                  style: TextStyle(
                    color: _linkBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_locating)
            Row(
              children: [
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Getting location...',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            )
          else if (_lat == null)
            Text(
              'Location unavailable',
              style: TextStyle(color: Colors.grey.shade600),
            )
          else ...[
            Text(
              (_address?.primaryLine.isNotEmpty ?? false)
                  ? _address!.primaryLine
                  : '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Colors.black87,
              ),
            ),
            if (_address?.secondaryLine.isNotEmpty ?? false) ...[
              const SizedBox(height: 2),
              Text(
                _address!.secondaryLine,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _optionalDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your Name',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: _navy,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Shown to officers reviewing this report',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          decoration: _fieldDecoration('e.g. Ramesh Shrestha'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Title (optional)',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: _navy,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _titleCtrl,
          decoration: _fieldDecoration('e.g. Large pothole near KFC'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Description (optional)',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: _navy,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: _fieldDecoration('Any additional details...'),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _navy, width: 1.5),
    ),
  );
}
