/// A ledger entry tracking tax-credit points earned from a [Reward] whose
/// `reward_mode` isn't cash — accrued now, redeemed against a future tax
/// filing rather than paid out directly.
class TaxReward {
  final int id;
  final String citizenId;
  final int rewardId;
  final int points;
  final String? taxYear;
  final String status;
  final DateTime createdAt;

  TaxReward({
    required this.id,
    required this.citizenId,
    required this.rewardId,
    required this.points,
    this.taxYear,
    required this.status,
    required this.createdAt,
  });

  factory TaxReward.fromJson(Map<String, dynamic> json) {
    return TaxReward(
      id: json['id'],
      citizenId: json['citizen_id'],
      rewardId: json['reward_id'],
      points: json['points'],
      taxYear: json['tax_year'],
      status: json['status'] ?? 'pending',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
