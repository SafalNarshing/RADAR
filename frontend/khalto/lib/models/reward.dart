import 'package:flutter/material.dart';

enum RewardType { manual, autoFixed, bonus }

/// How a reward is actually delivered. Cash (eSewa/Khalti) needs a real
/// payout transaction; tax_rebate/vehicle_tax just accrue as a points
/// ledger (see [TaxReward]) that's redeemed against tax filings later —
/// no direct government cash outflow.
enum RewardMode { cash, taxRebate, vehicleTax }

class Reward {
  final int id;
  final int? potholeId;
  final String citizenId;
  final String givenBy;
  final int amount;
  final RewardType rewardType;
  final RewardMode rewardMode;
  final String status;
  final String? reason;
  final String? transactionId;
  final DateTime createdAt;
  final DateTime? paidAt;
  final String? citizenName;
  final String? potholeTitle;

  Reward({
    required this.id,
    this.potholeId,
    required this.citizenId,
    required this.givenBy,
    required this.amount,
    required this.rewardType,
    this.rewardMode = RewardMode.taxRebate,
    required this.status,
    this.reason,
    this.transactionId,
    required this.createdAt,
    this.paidAt,
    this.citizenName,
    this.potholeTitle,
  });

  factory Reward.fromJson(Map<String, dynamic> json) {
    return Reward(
      id: json['id'],
      potholeId: json['pothole_id'],
      citizenId: json['citizen_id'],
      givenBy: json['given_by'],
      amount: json['amount'],
      rewardType: _typeFromDb(json['reward_type']),
      rewardMode: _modeFromDb(json['reward_mode']),
      status: json['status'] ?? 'pending',
      reason: json['reason'],
      transactionId: json['transaction_id'],
      createdAt: DateTime.parse(json['created_at']),
      paidAt: json['paid_at'] != null ? DateTime.parse(json['paid_at']) : null,
      citizenName: json['citizen']?['full_name'],
      potholeTitle: json['pothole']?['title'],
    );
  }

  static RewardType _typeFromDb(String? value) {
    switch (value) {
      case 'auto_fixed':
        return RewardType.autoFixed;
      case 'bonus':
        return RewardType.bonus;
      default:
        return RewardType.manual;
    }
  }

  static String typeToDb(RewardType type) {
    switch (type) {
      case RewardType.autoFixed:
        return 'auto_fixed';
      case RewardType.bonus:
        return 'bonus';
      case RewardType.manual:
        return 'manual';
    }
  }

  static String typeLabel(RewardType type) {
    switch (type) {
      case RewardType.autoFixed:
        return 'Auto (Fixed)';
      case RewardType.bonus:
        return 'Bonus';
      case RewardType.manual:
        return 'Manual';
    }
  }

  static RewardMode _modeFromDb(String? value) {
    switch (value) {
      case 'cash':
        return RewardMode.cash;
      case 'vehicle_tax':
        return RewardMode.vehicleTax;
      default:
        return RewardMode.taxRebate;
    }
  }

  static String modeToDb(RewardMode mode) {
    switch (mode) {
      case RewardMode.cash:
        return 'cash';
      case RewardMode.vehicleTax:
        return 'vehicle_tax';
      case RewardMode.taxRebate:
        return 'tax_rebate';
    }
  }

  static String modeLabel(RewardMode mode) {
    switch (mode) {
      case RewardMode.cash:
        return 'Cash';
      case RewardMode.vehicleTax:
        return 'Vehicle Tax Discount';
      case RewardMode.taxRebate:
        return 'Tax Rebate';
    }
  }

  static Color modeColor(RewardMode mode) {
    switch (mode) {
      case RewardMode.cash:
        return const Color(0xFF4CAF50);
      case RewardMode.vehicleTax:
        return const Color(0xFF7C4DFF);
      case RewardMode.taxRebate:
        return const Color(0xFF1E88E5);
    }
  }

  static Color statusColor(String status) {
    switch (status) {
      case 'approved':
        return const Color(0xFF2196F3);
      case 'paid':
        return const Color(0xFF4CAF50);
      case 'rejected':
        return const Color(0xFFF44336);
      default:
        return const Color(0xFFFF9800);
    }
  }

  static String statusLabel(String status) {
    return status[0].toUpperCase() + status.substring(1);
  }

  String get amountLabel {
    final s = amount.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return rewardMode == RewardMode.cash ? 'Rs. $buf' : '$buf pts';
  }
}
