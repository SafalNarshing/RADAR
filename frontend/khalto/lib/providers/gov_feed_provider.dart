import 'package:flutter/material.dart';
import '../models/pothole.dart';
import '../services/gov_service.dart';

/// null filter means "all statuses".
class GovFeedProvider extends ChangeNotifier {
  List<Pothole> reports = [];
  bool loading = false;
  String? error;
  String? filter;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      reports = await GovService.getReportsForReview(status: filter);
    } catch (e) {
      error = 'Failed to load reports: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> setFilter(String? status) async {
    filter = status;
    await load();
  }

  Future<void> updateStatus(int potholeId, String status) async {
    await GovService.setReportStatus(potholeId, status);
    // Refresh from the server rather than patching locally — Pothole's
    // fields are all final, so there's no in-place update to apply.
    await load();
  }

  Future<void> deleteReport(int potholeId) async {
    await GovService.deleteReport(potholeId);
    await load();
  }
}
