import 'package:flutter/material.dart';
import '../services/gov_service.dart';

class GovDashboardProvider extends ChangeNotifier {
  GovDashboardStats? stats;
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      stats = await GovService.getDashboardStats();
    } catch (e) {
      error = 'Failed to load dashboard: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
