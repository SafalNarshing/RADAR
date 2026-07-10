import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../home_shell.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _loading = false;

  Future<void> _continue(String role) async {
    setState(() => _loading = true);
    try {
      final response = await supabase.auth.signInAnonymously();
      final uid = response.user!.id;

      await supabase.from('profiles').upsert({
        'id': uid,
        'role': role,
      }, onConflict: 'id');

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeShell()),
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
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(Icons.warning_amber_rounded,
                  size: 72, color: Color(0xFFE53935)),
              const SizedBox(height: 16),
              const Text(
                'RADAR',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Road Assessment & Damage\nAccountability Reporter',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
              ),
              const Spacer(),
              const Text(
                'Continue as',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 20),
              _roleButton(
                label: 'Citizen',
                icon: Icons.person_outline,
                role: 'citizen',
                primary: true,
              ),
              const SizedBox(height: 14),
              _roleButton(
                label: 'Government Body',
                icon: Icons.account_balance_outlined,
                role: 'government',
                primary: false,
              ),
              const SizedBox(height: 48),
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
  }) {
    return SizedBox(
      height: 60,
      child: ElevatedButton.icon(
        onPressed: _loading ? null : () => _continue(role),
        icon: _loading
            ? const SizedBox(
                height: 18,
                width: 18,
                child:
                    CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Icon(icon, size: 22),
        label: Text(label,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              primary ? const Color(0xFFE53935) : const Color(0xFF2A2A2A),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: primary
              ? BorderSide.none
              : const BorderSide(color: Color(0xFF444444)),
        ),
      ),
    );
  }
}
