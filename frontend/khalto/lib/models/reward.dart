import 'package:flutter/material.dart';

enum RewardType { manual, autoFixed, bonus }

class Reward {
  final int id;
  final int? potholeId;
  final String citizenId;
  final String givenBy;
  final int amount;
  final RewardType rewardType;
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
    return 'Rs. $buf';
  }
}
