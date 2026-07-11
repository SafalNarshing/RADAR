import 'package:flutter/material.dart';

enum DamageType { pothole, crack, missingManhole }

class Pothole {
  final int id;
  final double latitude;
  final double longitude;
  final String? address;
  final String? title;
  final String? description;
  final int severity;
  final String status;
  final DamageType damageType;
  final int upvotesCount;
  final String? reportedBy;
  final String? reporterName;
  final String? primaryImagePath;
  final List<String> mediaPaths;
  final DateTime createdAt;
  final bool rewardGiven;
  final String? fixedImagePath;
  final DateTime? fixedAt;
  final String? fixedBy;
  final String? fixedNotes;

  Pothole({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.address,
    this.title,
    this.description,
    required this.severity,
    required this.status,
    this.damageType = DamageType.pothole,
    required this.upvotesCount,
    this.reportedBy,
    this.reporterName,
    this.primaryImagePath,
    this.mediaPaths = const [],
    required this.createdAt,
    this.rewardGiven = false,
    this.fixedImagePath,
    this.fixedAt,
    this.fixedBy,
    this.fixedNotes,
  });

  factory Pothole.fromJson(Map<String, dynamic> json) {
    final mediaList = json['pothole_media'] as List?;
    final primary = mediaList?.firstWhere(
      (m) => m['is_primary'] == true,
      orElse: () => mediaList.isNotEmpty ? mediaList.first : null,
    );

    return Pothole(
      id: json['id'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'],
      title: json['title'],
      description: json['description'],
      severity: json['severity'] ?? 3,
      status: json['status'] ?? 'reported',
      damageType: _damageTypeFromDb(json['damage_type']),
      upvotesCount: json['upvotes_count'] ?? 0,
      reportedBy: json['reported_by'],
      reporterName: json['reported_by_profile']?['full_name'],
      primaryImagePath: primary?['file_path'],
      mediaPaths: mediaList
              ?.map((m) => m['file_path'] as String?)
              .whereType<String>()
              .toList() ??
          const [],
      createdAt: DateTime.parse(json['created_at']),
      rewardGiven: json['reward_given'] ?? false,
      fixedImagePath: json['fixed_image_path'],
      fixedAt: json['fixed_at'] != null
          ? DateTime.parse(json['fixed_at'])
          : null,
      fixedBy: json['fixed_by'],
      fixedNotes: json['fixed_notes'],
    );
  }

  static DamageType _damageTypeFromDb(String? value) {
    switch (value) {
      case 'crack': return DamageType.crack;
      case 'missing_manhole': return DamageType.missingManhole;
      default: return DamageType.pothole;
    }
  }

  static String damageTypeToDb(DamageType type) {
    switch (type) {
      case DamageType.crack: return 'crack';
      case DamageType.missingManhole: return 'missing_manhole';
      case DamageType.pothole: return 'pothole';
    }
  }

  static Color damageColor(DamageType type) {
    switch (type) {
      case DamageType.crack: return const Color(0xFFF57C00);
      case DamageType.missingManhole: return const Color(0xFF1E88E5);
      case DamageType.pothole: return const Color(0xFFE53935);
    }
  }

  static String damageLabel(DamageType type) {
    switch (type) {
      case DamageType.crack: return 'Crack';
      case DamageType.missingManhole: return 'Missing Manhole';
      case DamageType.pothole: return 'Pothole';
    }
  }

  static Color severityColor(int severity) {
    switch (severity) {
      case 1: return const Color(0xFF4CAF50);
      case 2: return const Color(0xFF8BC34A);
      case 3: return const Color(0xFFFFC107);
      case 4: return const Color(0xFFFF9800);
      default: return const Color(0xFFF44336);
    }
  }

  static String severityLabel(int severity) {
    switch (severity) {
      case 1: return 'Low';
      case 2: return 'Minor';
      case 3: return 'Medium';
      case 4: return 'High';
      default: return 'Critical';
    }
  }

  static Color statusColor(String status) {
    switch (status) {
      case 'verified': return const Color(0xFF2196F3);
      case 'in_progress': return const Color(0xFFFF9800);
      case 'fixed': return const Color(0xFF4CAF50);
      case 'rejected': return const Color(0xFFF44336);
      default: return const Color(0xFF9E9E9E);
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'in_progress': return 'In Progress';
      default: return status[0].toUpperCase() + status.substring(1);
    }
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  String get postedAtLabel {
    final now = DateTime.now();
    final isToday = createdAt.year == now.year &&
        createdAt.month == now.month &&
        createdAt.day == now.day;
    final hour12 = createdAt.hour % 12 == 0 ? 12 : createdAt.hour % 12;
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final period = createdAt.hour >= 12 ? 'PM' : 'AM';
    final time = '$hour12:$minute $period';
    if (isToday) return 'Today $time';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[createdAt.month - 1]} ${createdAt.day}, $time';
  }

  String? get fixedAtLabel {
    final at = fixedAt;
    if (at == null) return null;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[at.month - 1]} ${at.day}, ${at.year}';
  }
}

