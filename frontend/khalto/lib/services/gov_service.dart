import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/cctv_camera.dart';
import '../models/pothole.dart';
import '../models/reward.dart';
import 'supabase_service.dart';

class GovDashboardStats {
  final int totalReports;
  final int activeReports;
  final int fixedThisMonth;
  final int totalRewardsDistributed;

  GovDashboardStats({
    required this.totalReports,
    required this.activeReports,
    required this.fixedThisMonth,
    required this.totalRewardsDistributed,
  });
}

const _activeStatuses = ['reported', 'verified', 'in_progress'];

class GovService {
  static Future<GovDashboardStats> getDashboardStats() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String();

    final totalRes = await supabase
        .from('potholes')
        .select('id')
        .count(CountOption.exact);

    final activeRes = await supabase
        .from('potholes')
        .select('id')
        .inFilter('status', _activeStatuses)
        .count(CountOption.exact);

    // potholes has no separate "resolved_at" column, so "this month" is
    // approximated against created_at for reports currently marked fixed.
    final fixedRes = await supabase
        .from('potholes')
        .select('id')
        .eq('status', 'fixed')
        .gte('created_at', startOfMonth)
        .count(CountOption.exact);

    final paidRewards = await supabase
        .from('rewards')
        .select('amount')
        .eq('status', 'paid');
    final totalRewards = (paidRewards as List)
        .fold<int>(0, (sum, r) => sum + (r['amount'] as int));

    return GovDashboardStats(
      totalReports: totalRes.count,
      activeReports: activeRes.count,
      fixedThisMonth: fixedRes.count,
      totalRewardsDistributed: totalRewards,
    );
  }

  static Future<List<Pothole>> getReportsForReview({String? status}) async {
    var query = supabase.from('potholes').select('''
          *,
          reported_by_profile:profiles!reported_by(full_name, avatar_url),
          pothole_media(file_path, is_primary, media_type)
        ''');

    final data = await (status != null
            ? query.eq('status', status)
            : query)
        .order('created_at', ascending: false);

    return (data as List).map((e) => Pothole.fromJson(e)).toList();
  }

  // Full report data (reporter, image, address) for the map tab, minus
  // rejected reports — those are hidden from the map, not just filtered.
  static Future<List<Pothole>> getMapReports() async {
    final data = await supabase
        .from('potholes')
        .select('''
          *,
          reported_by_profile:profiles!reported_by(full_name, avatar_url),
          pothole_media(file_path, is_primary, media_type)
        ''')
        .neq('status', 'rejected')
        .order('created_at', ascending: false);

    return (data as List).map((e) => Pothole.fromJson(e)).toList();
  }

  static Future<void> setReportStatus(int potholeId, String status) async {
    await supabase.from('potholes').update({'status': status}).eq(
      'id',
      potholeId,
    );
  }

  // Marks a report fixed with an optional after-photo (uploaded to the same
  // pothole_media bucket as report photos, under a fixed_ prefix so it
  // never collides with `is_primary` report images) and notes. Sets
  // status/fixed_at/fixed_by in one update so there's no separate write to
  // clobber — a plain setReportStatus('fixed') call elsewhere afterwards
  // still only touches the status column.
  static Future<void> markFixed({
    required int potholeId,
    XFile? photo,
    String? notes,
  }) async {
    final officerId = supabase.auth.currentUser!.id;
    String? photoPath;

    if (photo != null) {
      final ext = photo.name.split('.').last.toLowerCase();
      photoPath =
          '$potholeId/fixed_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final bytes = await photo.readAsBytes();
      await supabase.storage.from('pothole_media').uploadBinary(
        photoPath,
        bytes,
      );
    }

    await supabase
        .from('potholes')
        .update({
          'status': 'fixed',
          'fixed_at': DateTime.now().toIso8601String(),
          'fixed_by': officerId,
          if (photoPath != null) 'fixed_image_path': photoPath,
          if (notes != null && notes.isNotEmpty) 'fixed_notes': notes,
        })
        .eq('id', potholeId);
  }

  // Deletes dependent rows explicitly rather than relying on each table's
  // FK behavior (unknown/inconsistent across comments, upvotes,
  // pothole_media) — only `rewards.pothole_id` is documented as
  // ON DELETE SET NULL, so that one's left to the DB.
  static Future<void> deleteReport(int potholeId) async {
    await supabase.from('comments').delete().eq('pothole_id', potholeId);
    await supabase.from('upvotes').delete().eq('pothole_id', potholeId);
    await supabase.from('pothole_media').delete().eq('pothole_id', potholeId);
    await supabase.from('potholes').delete().eq('id', potholeId);
  }

  // Reports that are fixed but haven't had a reward issued yet — the
  // candidate pool shown when an officer starts the "Give reward" flow.
  static Future<List<Pothole>> getRewardableReports() async {
    final data = await supabase
        .from('potholes')
        .select('''
          *,
          reported_by_profile:profiles!reported_by(full_name, avatar_url),
          pothole_media(file_path, is_primary, media_type)
        ''')
        .eq('reward_given', false)
        .order('created_at', ascending: false);

    return (data as List).map((e) => Pothole.fromJson(e)).toList();
  }

  static Future<List<Reward>> getRewards({String? status}) async {
    var query = supabase.from('rewards').select('''
          *,
          citizen:profiles!citizen_id(full_name),
          pothole:potholes(title)
        ''');

    final data = await (status != null ? query.eq('status', status) : query)
        .order('created_at', ascending: false);

    return (data as List).map((e) => Reward.fromJson(e)).toList();
  }

  static Future<void> giveReward({
    int? potholeId,
    required String citizenId,
    required int amount,
    required RewardType rewardType,
    RewardMode rewardMode = RewardMode.taxRebate,
    String? reason,
  }) async {
    final officerId = supabase.auth.currentUser!.id;
    final inserted = await supabase
        .from('rewards')
        .insert({
          'pothole_id': potholeId,
          'citizen_id': citizenId,
          'given_by': officerId,
          'amount': amount,
          'reward_type': Reward.typeToDb(rewardType),
          'reward_mode': Reward.modeToDb(rewardMode),
          'reason': reason,
        })
        .select()
        .single();

    // Cash still goes through pending -> approved -> paid (real payout).
    // Tax-mode rewards have no payout step — the points ledger entry is
    // what the citizen actually sees and eventually redeems.
    if (rewardMode != RewardMode.cash) {
      await supabase.from('tax_rewards').insert({
        'citizen_id': citizenId,
        'reward_id': inserted['id'],
        'points': amount,
        'tax_year': _currentTaxYear(),
        'status': 'pending',
      });
    }
  }

  // Nepal's fiscal year runs mid-July to mid-July — this approximates it
  // from the Gregorian calendar (no BS calendar conversion) purely as a
  // human-readable label for the ledger, e.g. "2026/27".
  static String _currentTaxYear() {
    final now = DateTime.now();
    final startYear = now.month >= 7 ? now.year : now.year - 1;
    return '$startYear/${(startYear + 1).toString().substring(2)}';
  }

  static Future<List<CctvCamera>> getCctvCameras() =>
      SupabaseService.getCctvCameras();

  static Future<void> addCctvCamera({
    required String name,
    required double latitude,
    required double longitude,
    required int potholeId,
    required CctvAsset asset,
  }) async {
    final officerId = supabase.auth.currentUser!.id;
    await supabase.from('cctv_cameras').insert({
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'pothole_id': potholeId,
      'asset_key': asset.name,
      'created_by': officerId,
    });
  }

  static Future<void> deleteCctvCamera(int id) async {
    await supabase.from('cctv_cameras').delete().eq('id', id);
  }

  static Future<void> updateRewardStatus(Reward reward, String status) async {
    final update = <String, dynamic>{'status': status};
    if (status == 'paid') {
      update['paid_at'] = DateTime.now().toIso8601String();
    }
    await supabase.from('rewards').update(update).eq('id', reward.id);

    if (status == 'paid') {
      final profile = await supabase
          .from('profiles')
          .select('total_rewards')
          .eq('id', reward.citizenId)
          .single();
      final current = (profile['total_rewards'] as int?) ?? 0;
      await supabase
          .from('profiles')
          .update({'total_rewards': current + reward.amount})
          .eq('id', reward.citizenId);

      if (reward.potholeId != null) {
        await supabase
            .from('potholes')
            .update({'reward_given': true})
            .eq('id', reward.potholeId!);
      }

      if (reward.rewardMode != RewardMode.cash) {
        await supabase
            .from('tax_rewards')
            .update({'status': 'applied'})
            .eq('reward_id', reward.id);
      }
    }
  }
}
