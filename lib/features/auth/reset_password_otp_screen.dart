// lib/features/auth/reset_password_otp_screen.dart
//
// Layar reset password TANPA link email — pengguna memasukkan kode OTP
// 6 digit yang dikirim ke email, lalu langsung mengatur password baru
// di dalam aplikasi. Ini menggantikan alur "klik link di email" yang
// tidak bisa berfungsi di aplikasi mobile ini karena belum ada deep
// link handler (lihat AndroidManifest.xml / pubspec.yaml — tidak ada
// konfigurasi app_links/uni_links).
//
// Alur: verifikasi OTP (type: recovery) -> sesi sementara terbentuk ->
// tampilkan form password baru -> updateUser() -> signOut() -> /login.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/router/app_router.dart';
import '../../services/push_notification_service.dart';

const _purple = Color(0xFF5C4DFF);
const _bg     = Color(0xFFF5F7FA);

class ResetPasswordOtpScreen extends StatefulWidget {
  final String email;
  const ResetPasswordOtpScreen({super.key, required this.email});

  @override
  State<ResetPasswordOtpScreen> createState() => _ResetPasswordOtpScreenState();
}

class _ResetPasswordOtpScreenState extends State<ResetPasswordOtpScreen> {
  // ── Step 1: OTP ──────────────────────────────────────────────
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes   = List.generate(6, (_) => FocusNode());
  bool _otpVerified = false;

  // ── Step 2: Password baru ────────────────────────────────────
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePass = true, _obscureConfirm = true;

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Nyalakan saklar blokir-redirect selama di layar ini. Ini mencegah
    // GoRouter melempar ke Dashboard begitu sesi recovery terbentuk
    // setelah verifyOTP() sukses.
    kIsPasswordRecoveryInProgress = true;
  }

  @override
  void dispose() {
    // Jaring pengaman: kalau pengguna keluar dari layar ini tanpa
    // menyelesaikan (misal tekan tombol back), saklar tetap dimatikan
    // supaya navigasi normal berfungsi lagi setelahnya.
    kIsPasswordRecoveryInProgress = false;
    for (final c in _otpControllers) c.dispose();
    for (final f in _otpFocusNodes)   f.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String get _otpCode => _otpControllers.map((c) => c.text.trim()).join();

  Future<void> _verifyOtp() async {
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
        type: OtpType.recovery,
      );
      debugPrint('[RESET-OTP] verifyOTP sukses. mounted=$mounted');
      if (!mounted) return;
      setState(() { _otpVerified = true; _loading = false; });
      debugPrint('[RESET-OTP] setState _otpVerified=true selesai.');
    } on AuthException catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.message; });
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Kode tidak valid atau sudah kadaluarsa.';
      });
    }
  }

  Future<void> _resendOtp() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Untuk tipe recovery, kirim ulang lewat resetPasswordForEmail lagi
      // (bukan auth.resend, yang hanya untuk signup/emailChange).
      await Supabase.instance.client.auth.resetPasswordForEmail(widget.email);
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kode baru telah dikirim ke email Anda.')),
        );
      }
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Gagal mengirim ulang. Coba lagi.';
      });
    }
  }

  Future<void> _submitNewPassword() async {
    final pass = _passCtrl.text;
    final confirm = _confirmCtrl.text;
    if (pass.length < 6) {
      setState(() => _error = 'Password minimal 6 karakter.');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = 'Konfirmasi password tidak cocok.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: pass),
      );
      await PushNotificationService().deactivateCurrentToken();
      await Supabase.instance.client.auth.signOut();
      kIsPasswordRecoveryInProgress = false;
      if (!mounted) return;
      context.go('/login');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password berhasil diubah. Silakan masuk kembali.')),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.message; });
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Gagal mengubah password. Coba lagi.';
      });
    }
  }

  void _onOtpChanged(String val, int idx) {
    if (val.length == 1 && idx < 5) {
      _otpFocusNodes[idx + 1].requestFocus();
    } else if (val.isEmpty && idx > 0) {
      _otpFocusNodes[idx - 1].requestFocus();
    }
    if (_otpCode.length == 6 && !_loading) _verifyOtp();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: Color(0xFF1A1A2E)),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _otpVerified ? _buildPasswordForm() : _buildOtpForm(),
        ),
      ),
    );
  }

  // ── Tampilan Step 1: input OTP ─────────────────────────────────
  Widget _buildOtpForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: _purple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.lock_reset_rounded, color: _purple, size: 38),
        ),
        const SizedBox(height: 24),
        const Text('Masukkan Kode OTP',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E))),
        const SizedBox(height: 8),
        Text('Kode 6 digit untuk reset password telah dikirim ke',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        const SizedBox(height: 4),
        Text(widget.email, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _purple)),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) => _OtpBox(
            controller: _otpControllers[i],
            focusNode: _otpFocusNodes[i],
            onChanged: (v) => _onOtpChanged(v, i),
          )),
        ),
        if (_error != null) _errorBanner(),
        const SizedBox(height: 28),
        SizedBox(width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: _loading ? null : _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0),
            child: _loading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('Verifikasi Kode',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Tidak menerima kode? ', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          GestureDetector(
            onTap: _loading ? null : _resendOtp,
            child: const Text('Kirim Ulang',
                style: TextStyle(color: _purple, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ]),
      ],
    );
  }

  // ── Tampilan Step 2: password baru ──────────────────────────────
  Widget _buildPasswordForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.check_circle_outline_rounded,
              color: Color(0xFF10B981), size: 38),
        ),
        const SizedBox(height: 24),
        const Text('Buat Password Baru',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E))),
        const SizedBox(height: 8),
        Text('Kode terverifikasi. Masukkan password baru untuk akunmu.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        const SizedBox(height: 28),
        Align(alignment: Alignment.centerLeft, child: _fieldLabel('PASSWORD BARU')),
        const SizedBox(height: 6),
        TextField(
          controller: _passCtrl, obscureText: _obscurePass,
          decoration: _passwordDeco(
            obscure: _obscurePass,
            onToggle: () => setState(() => _obscurePass = !_obscurePass),
          ),
        ),
        const SizedBox(height: 16),
        Align(alignment: Alignment.centerLeft, child: _fieldLabel('KONFIRMASI PASSWORD')),
        const SizedBox(height: 6),
        TextField(
          controller: _confirmCtrl, obscureText: _obscureConfirm,
          decoration: _passwordDeco(
            obscure: _obscureConfirm,
            onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
        ),
        if (_error != null) _errorBanner(),
        const SizedBox(height: 28),
        SizedBox(width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: _loading ? null : _submitNewPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0),
            child: _loading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('Simpan Password Baru',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) => Text(text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: Color(0xFF6B7280), letterSpacing: 0.5));

  InputDecoration _passwordDeco({required bool obscure, required VoidCallback onToggle}) =>
      InputDecoration(
        filled: true, fillColor: Colors.white,
        prefixIcon: Icon(Icons.lock_outline_rounded, color: Colors.grey[400]),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: Colors.grey[400]),
          onPressed: onToggle,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _purple)),
      );

  Widget _errorBanner() => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(_error!,
            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13))),
      ]),
    ),
  );
}

// ── Single OTP digit box (identik dengan pola di otp_screen.dart) ──
class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _OtpBox({
    required this.controller, required this.focusNode, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 46, height: 56,
    child: TextField(
      controller: controller, focusNode: focusNode,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      maxLength: 1,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
          color: Color(0xFF1A1A2E)),
      decoration: InputDecoration(
        counterText: '',
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.withOpacity(0.2))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.withOpacity(0.2))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _purple, width: 2)),
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: onChanged,
    ),
  );
}
