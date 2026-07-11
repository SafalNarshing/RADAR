import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/cctv_camera.dart';
import '../models/pothole.dart';
import '../models/reward.dart';

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
    String? reason,
  }) async {
    final officerId = supabase.auth.currentUser!.id;
    await supabase.from('rewards').insert({
      'pothole_id': potholeId,
      'citizen_id': citizenId,
      'given_by': officerId,
      'amount': amount,
      'reward_type': Reward.typeToDb(rewardType),
      'reason': reason,
    });
  }

  static Future<List<CctvCamera>> getCctvCameras() async {
    final data = await supabase
        .from('cctv_cameras')
        .select()
        .order('created_at', ascending: false);
    return (data as List).map((e) => CctvCamera.fromJson(e)).toList();
  }

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
    }
  }
}
