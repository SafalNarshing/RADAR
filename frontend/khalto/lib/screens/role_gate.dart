import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'gov/gov_home_shell.dart';
import 'home_shell.dart';

/// Routes an already-authenticated session to the citizen or government
/// shell based on the signed-in user's `profiles.role`.
class RoleGate extends StatefulWidget {
  const RoleGate({super.key});

  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  late final Future<Map<String, dynamic>?> _profile;

  @override
  void initState() {
    super.initState();
    _profile = SupabaseService.getCurrentProfile();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final role = snapshot.data?['role'];
        return role == 'government' ? const GovHomeShell() : const HomeShell();
      },
    );
  }
}
