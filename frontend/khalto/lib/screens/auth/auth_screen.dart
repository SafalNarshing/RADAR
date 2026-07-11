import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../gov/gov_home_shell.dart';
import '../home_shell.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late final AnimationController _dotsController;
  late final Animation<double> _dot1;
  late final Animation<double> _dot2;
  late final Animation<double> _dot3;

  Future<void> _continue(String role) async {
    setState(() => _loading = true);
    try {
      final response = await supabase.auth.signInAnonymously();
      final uid = response.user!.id;

      // full_name isn't collected here — it's asked for when submitting a
      // report instead (see ReportScreen), to keep sign-in to one tap.
      await supabase.from('profiles').upsert({
        'id': uid,
        'role': role,
      }, onConflict: 'id');

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                role == 'government' ? const GovHomeShell() : const HomeShell(),
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set up profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _dot1 = Tween(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(
        parent: _dotsController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
      ),
    );
    _dot2 = Tween(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(
        parent: _dotsController,
        curve: const Interval(0.2, 0.7, curve: Curves.easeInOut),
      ),
    );
    _dot3 = Tween(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(
        parent: _dotsController,
        curve: const Interval(0.4, 0.9, curve: Curves.easeInOut),
      ),
    );
  }

  @override
  void dispose() {
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const _navy = Color(0xFF0D1B3E);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const SizedBox(height: 18),
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Image.asset(
    'assets/Radarlogo.png',
    height: 180, // Increased from 120
    fit: BoxFit.contain,
    errorBuilder: (ctx, err, st) => const Icon(
      Icons.warning_amber_rounded,
      size: 180,
      color: Color(0xFFE53935),
    ),
  ),
),
                    const SizedBox(height: 8),
                    const Text(
                      'RADAR',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: _navy,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Road Assessment & Damage\nAccountability Reporter',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
              Text(
                'Continue as',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              _roleButton(
                label: 'Citizen',
                icon: Icons.person_outline,
                role: 'citizen',
                primary: true,
                navy: _navy,
              ),
              const SizedBox(height: 12),
              _roleButton(
                label: 'Government Body',
                icon: Icons.account_balance_outlined,
                role: 'government',
                primary: false,
                navy: _navy,
              ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleButton({
    required String label,
    required IconData icon,
    required String role,
    required bool primary,
    required Color navy,
  }) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _loading ? null : () => _continue(role),
        icon: _loading
            ? SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  color: primary ? Colors.white : navy,
                  strokeWidth: 2,
                ),
              )
            : Icon(icon, size: 20, color: primary ? Colors.white : navy),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: primary ? Colors.white : navy,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: primary ? navy : Colors.white,
          foregroundColor: primary ? Colors.white : navy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: primary
              ? BorderSide.none
              : BorderSide(color: Colors.grey.shade300),
          elevation: primary ? 0 : 0,
        ),
      ),
    );
  }
}
