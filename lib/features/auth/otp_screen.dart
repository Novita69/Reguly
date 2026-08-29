// lib/features/auth/otp_screen.dart
//
// Layar verifikasi OTP yang dikirim ke email setelah registrasi.
// Menerima email via GoRouter extra (Map<String, String>).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _purple = Color(0xFF5C4DFF);
const _bg     = Color(0xFFF5F7FA);

class OtpScreen extends StatefulWidget {
  final String email;
  const OtpScreen({super.key, required this.email});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes   = List.generate(6, (_) => FocusNode());
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes)   f.dispose();
    super.dispose();
  }

  String get _otpCode =>
      _controllers.map((c) => c.text.trim()).join();

  Future<void> _verify() async {
    final code = _otpCode;
    if (code.length < 6) {
      setState(() => _error = 'Masukkan 6 digit kode OTP.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.auth.verifyOTP(
        email: widget.email,
        token: code,
        type: OtpType.signup,
      );
      if (!mounted) return;
      // After verification, check baseline status
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) { context.go('/login'); return; }
      try {
        final p = await Supabase.instance.client
            .from('profiles')
            .select('has_completed_baseline')
            .eq('id', uid)
            .single();
        final done = (p['has_completed_baseline'] as bool?) ?? false;
        if (!mounted) return;
        context.go(done ? '/dashboard' : '/baseline');
      } catch (_) {
        if (mounted) context.go('/baseline');
      }
    } on AuthException catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.message; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Kode tidak valid atau sudah kadaluarsa.'; });
    }
  }

  Future<void> _resend() async {
    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kode baru telah dikirim ke email Anda.')),
        );
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Gagal mengirim ulang. Coba lagi.'; });
    }
  }

  void _onOtpChanged(String val, int idx) {
    if (val.length == 1 && idx < 5) {
      _focusNodes[idx + 1].requestFocus();
    } else if (val.isEmpty && idx > 0) {
      _focusNodes[idx - 1].requestFocus();
    }
    // Auto-submit when all 6 filled
    if (_otpCode.length == 6 && !_loading) _verify();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0F1A) : _bg;
    final cardColor = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: textColor),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.mark_email_read_outlined,
                    color: _purple, size: 38),
              ),
              const SizedBox(height: 24),
              Text(
                'Verifikasi Email',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Kode OTP 6 digit telah dikirim ke',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 4),
              Text(
                widget.email,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _purple,
                ),
              ),
              const SizedBox(height: 36),
              // ── OTP Input ──────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) => _OtpBox(
                  controller: _controllers[i],
                  focusNode: _focusNodes[i],
                  cardColor: cardColor,
                  textColor: textColor,
                  onChanged: (v) => _onOtpChanged(v, i),
                )),
              ),
              // ── Error ──────────────────────────────────────────
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 32),
              // ── Verify Button ──────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Verifikasi Akun',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                            SizedBox(width: 8),
                            Icon(Icons.check_circle_outline_rounded, size: 18),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),
              // ── Resend ─────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Tidak menerima kode? ',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  GestureDetector(
                    onTap: _loading ? null : _resend,
                    child: const Text('Kirim Ulang',
                        style: TextStyle(
                            color: _purple,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Periksa folder Spam / Junk jika kode tidak diterima.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Single OTP digit box ─────────────────────────────────────

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color cardColor;
  final Color textColor;
  final ValueChanged<String> onChanged;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.cardColor,
    required this.textColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 56,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _purple, width: 2),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: onChanged,
      ),
    );
  }
}
