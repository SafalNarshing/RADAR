import 'package:flutter/material.dart';

class Pothole {
  final int id;
  final double latitude;
  final double longitude;
  final String? address;
  final String? title;
  final String? description;
  final int severity;
  final String status;
  final int upvotesCount;
  final String? reportedBy;
  final String? reporterName;
  final String? primaryImagePath;
  final DateTime createdAt;

  Pothole({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.address,
    this.title,
    this.description,
    required this.severity,
    required this.status,
    required this.upvotesCount,
    this.reportedBy,
    this.reporterName,
    this.primaryImagePath,
    required this.createdAt,
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
      upvotesCount: json['upvotes_count'] ?? 0,
      reportedBy: json['reported_by'],
      reporterName: json['reported_by_profile']?['full_name'],
      primaryImagePath: primary?['file_path'],
      createdAt: DateTime.parse(json['created_at']),
    );
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
}

