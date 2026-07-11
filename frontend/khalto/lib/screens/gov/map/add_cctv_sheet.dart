import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../../models/cctv_camera.dart';
import '../../../models/pothole.dart';
import '../../../services/gov_service.dart';
import '../../../theme/gov_colors.dart';

/// Opens the "Add CCTV camera" sheet at [location]. [nearbyReports] should
/// already be sorted nearest-first — that list is what "points to" picks
/// from, since a camera always targets an existing report. Returns true if
/// a camera was saved.
Future<bool?> showAddCctvSheet(
  BuildContext context, {
  required ll.LatLng location,
  required List<Pothole> nearbyReports,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _AddCctvSheet(location: location, reports: nearbyReports),
  );
}

class _AddCctvSheet extends StatefulWidget {
  final ll.LatLng location;
  final List<Pothole> reports;

  const _AddCctvSheet({required this.location, required this.reports});

  @override
  State<_AddCctvSheet> createState() => _AddCctvSheetState();
}

class _AddCctvSheetState extends State<_AddCctvSheet> {
  final _nameCtrl = TextEditingController(text: 'Camera');
  Pothole? _selectedReport;
  CctvAsset _asset = CctvAsset.cctv1;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.reports.isNotEmpty) _selectedReport = widget.reports.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final report = _selectedReport;
    if (report == null) {
      setState(() => _error = 'Select which report this camera points to');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await GovService.addCctvCamera(
        name: _nameCtrl.text.trim().isEmpty ? 'Camera' : _nameCtrl.text.trim(),
        latitude: widget.location.latitude,
        longitude: widget.location.longitude,
        potholeId: report.id,
        asset: _asset,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = 'Failed to add camera: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Add CCTV Camera',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: GovColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.location.latitude.toStringAsFixed(5)}, '
                '${widget.location.longitude.toStringAsFixed(5)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: GovColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              _label('Name'),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                decoration: _decoration('e.g. Koteshwor Cam 1'),
              ),
              const SizedBox(height: 16),
              _label('Points to'),
              const SizedBox(height: 8),
              if (widget.reports.isEmpty)
                Text(
                  'No nearby reports found',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                )
              else
                DropdownButtonFormField<Pothole>(
                  initialValue: _selectedReport,
                  isExpanded: true,
                  decoration: _decoration('Select a report'),
                  items: widget.reports
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            p.title ?? 'Report #${p.id}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedReport = v),
                ),
              const SizedBox(height: 16),
              _label('CCTV feed'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: CctvAsset.values.map((a) {
                  final selected = _asset == a;
                  return ChoiceChip(
                    label: Text(a.label),
                    selected: selected,
                    onSelected: (_) => setState(() => _asset = a),
                    selectedColor: GovColors.primary.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: selected
                          ? GovColors.primary
                          : GovColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    side: BorderSide(
                      color: selected ? GovColors.primary : GovColors.border,
                    ),
                  );
                }).toList(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GovColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Add Camera',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
  );

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: GovColors.chipBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}
