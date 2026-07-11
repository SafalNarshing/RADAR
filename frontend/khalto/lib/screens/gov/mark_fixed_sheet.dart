import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/pothole.dart';
import '../../services/gov_service.dart';
import '../../theme/gov_colors.dart';

/// Shown whenever an officer changes a report's status to "fixed" — lets
/// them attach an after photo (optional but recommended, for transparency)
/// and notes before the status change is persisted. Returns true once the
/// report has actually been marked fixed, so the caller can refresh.
Future<bool?> showMarkFixedSheet(
  BuildContext context, {
  required Pothole pothole,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _MarkFixedSheet(pothole: pothole),
  );
}

class _MarkFixedSheet extends StatefulWidget {
  final Pothole pothole;

  const _MarkFixedSheet({required this.pothole});

  @override
  State<_MarkFixedSheet> createState() => _MarkFixedSheetState();
}

class _MarkFixedSheetState extends State<_MarkFixedSheet> {
  final _notesCtrl = TextEditingController();
  XFile? _photo;
  Uint8List? _photoBytes;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (mounted) {
      setState(() {
        _photo = picked;
        _photoBytes = bytes;
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await GovService.markFixed(
        potholeId: widget.pothole.id,
        photo: _photo,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = 'Failed to mark fixed: $e';
      });
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
                'Mark as Fixed',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: GovColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Upload a photo of the repaired road for transparency',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              _photoPicker(),
              const SizedBox(height: 16),
              const Text(
                'Notes (optional)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'e.g. Repaved and compacted',
                  filled: true,
                  fillColor: GovColors.chipBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GovColors.textSecondary,
                        side: const BorderSide(color: GovColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GovColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _photo == null
                                  ? 'Mark Fixed (no photo)'
                                  : 'Mark Fixed',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
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

  Widget _photoPicker() {
    if (_photoBytes != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(
              _photoBytes!,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                onPressed: () => setState(() {
                  _photo = null;
                  _photoBytes = null;
                }),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickPhoto(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined, size: 18),
            label: const Text('Camera'),
            style: OutlinedButton.styleFrom(
              foregroundColor: GovColors.primary,
              side: const BorderSide(color: GovColors.border),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickPhoto(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('Gallery'),
            style: OutlinedButton.styleFrom(
              foregroundColor: GovColors.primary,
              side: const BorderSide(color: GovColors.border),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
