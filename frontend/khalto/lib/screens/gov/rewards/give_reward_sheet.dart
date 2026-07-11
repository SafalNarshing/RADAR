import 'package:flutter/material.dart';
import '../../../models/pothole.dart';
import '../../../models/reward.dart';
import '../../../services/gov_service.dart';
import '../../../theme/gov_colors.dart';

/// Opens the "Give reward" bottom sheet. If [report] is passed, the reward
/// is pre-scoped to that pothole/citizen (e.g. from the feed's "Give Reward"
/// action); otherwise the officer first picks a rewardable report.
Future<void> showGiveRewardSheet(
  BuildContext context, {
  Pothole? report,
  VoidCallback? onDone,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _GiveRewardSheet(initialReport: report, onDone: onDone),
  );
}

class _GiveRewardSheet extends StatefulWidget {
  final Pothole? initialReport;
  final VoidCallback? onDone;

  const _GiveRewardSheet({this.initialReport, this.onDone});

  @override
  State<_GiveRewardSheet> createState() => _GiveRewardSheetState();
}

class _GiveRewardSheetState extends State<_GiveRewardSheet> {
  Pothole? _selected;
  List<Pothole> _candidates = [];
  bool _loadingCandidates = false;
  bool _submitting = false;
  String? _error;

  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  RewardType _type = RewardType.manual;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialReport;
    if (_selected == null) _loadCandidates();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    setState(() => _loadingCandidates = true);
    try {
      _candidates = await GovService.getRewardableReports();
    } catch (e) {
      _error = 'Failed to load reports: $e';
    } finally {
      if (mounted) setState(() => _loadingCandidates = false);
    }
  }

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null || selected.reportedBy == null) {
      setState(() => _error = 'Select a report first');
      return;
    }
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid reward amount');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await GovService.giveReward(
        potholeId: selected.id,
        citizenId: selected.reportedBy!,
        amount: amount,
        rewardType: _type,
        reason: _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onDone?.call();
      }
    } catch (e) {
      setState(() => _error = 'Failed to give reward: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                'Give Reward',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: GovColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              if (widget.initialReport == null) ...[
                const Text(
                  'Report',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                _reportPicker(),
                const SizedBox(height: 16),
              ] else
                _selectedReportSummary(widget.initialReport!),
              const SizedBox(height: 16),
              _label('Amount (NPR)'),
              const SizedBox(height: 8),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration('e.g. 500'),
              ),
              const SizedBox(height: 16),
              _label('Reward type'),
              const SizedBox(height: 8),
              _typePicker(),
              const SizedBox(height: 16),
              _label('Reason (optional)'),
              const SizedBox(height: 8),
              TextField(
                controller: _reasonCtrl,
                maxLines: 2,
                decoration: _inputDecoration(
                  'e.g. High quality report with clear photos',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
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
                      : const Text(
                          'Give Reward',
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

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: GovColors.chipBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );

  Widget _selectedReportSummary(Pothole p) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GovColors.chipBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        p.title ?? 'Report #${p.id}',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
    );
  }

  Widget _reportPicker() {
    if (_loadingCandidates) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator(color: GovColors.primary)),
      );
    }
    if (_candidates.isEmpty) {
      return Text(
        'No fixed reports awaiting a reward',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
      );
    }
    return SizedBox(
      height: 44,
      child: DropdownButtonFormField<Pothole>(
        initialValue: _selected,
        isExpanded: true,
        decoration: _inputDecoration('Select a report'),
        items: _candidates
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
        onChanged: (v) => setState(() => _selected = v),
      ),
    );
  }

  Widget _typePicker() {
    return Wrap(
      spacing: 8,
      children: RewardType.values.map((t) {
        final selected = _type == t;
        return ChoiceChip(
          label: Text(Reward.typeLabel(t)),
          selected: selected,
          onSelected: (_) => setState(() => _type = t),
          selectedColor: GovColors.primary.withValues(alpha: 0.15),
          labelStyle: TextStyle(
            color: selected ? GovColors.primary : GovColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
          side: BorderSide(
            color: selected ? GovColors.primary : GovColors.border,
          ),
        );
      }).toList(),
    );
  }
}
