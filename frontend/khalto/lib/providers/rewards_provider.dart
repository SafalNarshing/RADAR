import 'package:flutter/material.dart';
import '../models/reward.dart';
import '../services/gov_service.dart';

class RewardsProvider extends ChangeNotifier {
  List<Reward> rewards = [];
  bool loading = false;
  String? error;
  String? filter;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      rewards = await GovService.getRewards(status: filter);
    } catch (e) {
      error = 'Failed to load rewards: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> setFilter(String? status) async {
    filter = status;
    await load();
  }

  Future<void> give({
    int? potholeId,
    required String citizenId,
    required int amount,
    required RewardType rewardType,
    String? reason,
  }) async {
    await GovService.giveReward(
      potholeId: potholeId,
      citizenId: citizenId,
      amount: amount,
      rewardType: rewardType,
      reason: reason,
    );
    await load();
  }

  Future<void> updateStatus(Reward reward, String status) async {
    await GovService.updateRewardStatus(reward, status);
    await load();
  }
}
