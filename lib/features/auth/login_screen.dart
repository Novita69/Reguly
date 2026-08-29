// lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _purple = Color(0xFF5C4DFF);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _loading   = false;
  bool _showPass  = false;
  bool _remember  = true;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_email');
    if (saved != null && mounted) {
      setState(() {
        _emailCtrl.text = saved;
        _remember = true;
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _snack(String m, {bool isError = true}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(m),
          backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        ),
      );

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      // Save email if remember is checked
      final prefs = await SharedPreferences.getInstance();
      if (_remember) {
        await prefs.setString('saved_email', _emailCtrl.text.trim());
      } else {
        await prefs.remove('saved_email');
      }
      if (!mounted) return;
      // Check baseline status
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) { context.go('/login'); return; }
      try {
        final p = await Supabase.instance.client
            .from('profiles')
            .select('has_completed_baseline')
            .eq('id', uid)
            .single();
        final done = (p['has_completed_baseline'] as bool?) ?? false;
        if (mounted) context.go(done ? '/dashboard' : '/baseline');
      } catch (_) {
        if (mounted) context.go('/dashboard');
      }
    } on AuthException catch (e) {
      if (mounted) {
        final msg = e.message.contains('Invalid login')
            ? 'Email atau kata sandi salah.'
            : e.message.contains('Email not confirmed')
                ? 'Email belum diverifikasi. Periksa inbox Anda.'
                : e.message;
        _snack(msg);
      }
    } catch (_) {
      if (mounted) _snack('Terjadi kesalahan. Periksa koneksi internet.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final bgColor   = isDark ? const Color(0xFF0F0F1A) : const Color(0xFFF5F7FA);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 48),
                // ── Logo ────────────────────────────────────
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _purple.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.psychology_outlined,
                      color: _purple, size: 40),
                ),
                const SizedBox(height: 22),
                Text(
                  'Masuk Akun',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pantau dan tingkatkan regulasi diri belajarmu',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[500],
                      height: 1.5),
                ),
                const SizedBox(height: 36),

                // ── Email ──────────────────────────────────
                _label('EMAIL'),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _deco('email@kampus.ac.id', Icons.email_outlined),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email wajib diisi';
                    final re = RegExp(r'^[\w.+-]+@[\w-]+\.[a-z]{2,}$', caseSensitive: false);
                    if (!re.hasMatch(v.trim())) return 'Format email tidak valid';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Password ───────────────────────────────
                _label('KATA SANDI'),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: !_showPass,
                  decoration: _deco('••••••••', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPass
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _showPass = !_showPass),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Kata sandi wajib diisi' : null,
                ),

                // ── Forgot Password ───────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push('/forgot-password'),
                    child: const Text(
                      'Lupa Kata Sandi?',
                      style: TextStyle(color: _purple, fontSize: 13),
                    ),
                  ),
                ),

                // ── Remember Me ───────────────────────────
                Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _remember,
                        activeColor: _purple,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                        onChanged: (v) => setState(() => _remember = v ?? true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('Ingat saya',
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Login Button ───────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Masuk Aplikasi',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 18),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Register Link ──────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Belum memiliki akun? ',
                        style: TextStyle(color: Colors.grey[500])),
                    GestureDetector(
                      onTap: () => context.push('/register'),
                      child: const Text(
                        'Daftar Sekarang',
                        style: TextStyle(
                            color: _purple, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6B7280),
          letterSpacing: 0.6,
        ),
      ),
    ),
  );

  InputDecoration _deco(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, size: 20),
  );
}
