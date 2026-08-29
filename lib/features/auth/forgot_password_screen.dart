// lib/features/auth/forgot_password_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _purple = Color(0xFF5C4DFF);

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override State<ForgotPasswordScreen> createState() => _ForgotState();
}
class _ForgotState extends State<ForgotPasswordScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false, _sent = false;
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _send() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(_ctrl.text.trim());
      if (mounted) setState(() { _sent = true; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(backgroundColor: const Color(0xFFF5F7FA), elevation: 0,
          title: const Text('Lupa Kata Sandi',
              style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _sent
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.mark_email_read_outlined, color: _purple, size: 64),
                const SizedBox(height: 16),
                const Text('Kode Terkirim!', style: TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 8),
                Text('Cek inbox ${_ctrl.text} untuk kode OTP 6 digit reset password.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500])),
                const SizedBox(height: 28),
                SizedBox(width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: () => context.push('/reset-password-otp',
                        extra: {'email': _ctrl.text.trim()}),
                    style: ElevatedButton.styleFrom(backgroundColor: _purple,
                        foregroundColor: Colors.white, elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16))),
                    child: const Text('Masukkan Kode OTP',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  )),
                const SizedBox(height: 12),
                TextButton(onPressed: () => context.pop(),
                    child: const Text('Kembali ke Login',
                        style: TextStyle(color: _purple, fontWeight: FontWeight.w600))),
              ]))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Masukkan email terdaftar. Kami akan kirimkan kode OTP reset password.',
                    style: TextStyle(color: Colors.grey[500])),
                const SizedBox(height: 24),
                TextField(controller: _ctrl, keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'email@kampus.ac.id',
                    prefixIcon: Icon(Icons.email_outlined, color: Colors.grey[400]),
                    filled: true, fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _purple)),
                  )),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _send,
                    style: ElevatedButton.styleFrom(backgroundColor: _purple,
                        elevation: 0, shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16))),
                    child: _loading
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Text('Kirim Kode OTP',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  )),
              ]),
      ),
    );
  }
}