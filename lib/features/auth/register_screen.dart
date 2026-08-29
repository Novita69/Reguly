// lib/features/auth/register_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kPurple     = Color(0xFF5C4DFF);
const _kError      = Color(0xFFEF4444);
const _kSuccess    = Color(0xFF10B981);
const _kLabelColor = Color(0xFF6B7280);

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();

  final _nameFocus    = FocusNode();
  final _emailFocus   = FocusNode();
  final _passFocus    = FocusNode();
  final _confirmFocus = FocusNode();

  // Key yang menandai posisi blok "Konfirmasi Kata Sandi" di dalam form,
  // dipakai Scrollable.ensureVisible() untuk scroll TEPAT ke situ —
  // bukan ke paling bawah seperti maxScrollExtent.
  final _confirmSectionKey = GlobalKey();

  bool _loading  = false;
  bool _showPass = false;
  bool _showConf = false;

  @override
  void initState() {
    super.initState();
    _confirmFocus.addListener(_onConfirmFocus);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    _confirmFocus.removeListener(_onConfirmFocus);
    _confirmFocus.dispose();
    super.dispose();
  }

  // Saat kolom Konfirmasi Kata Sandi difokus, scroll ke posisinya secara
  // presisi memakai GlobalKey di atas — bukan ke ujung scroll.
  void _onConfirmFocus() {
    if (!_confirmFocus.hasFocus) return;
    // Tunggu 1 frame setelah keyboard animasi muncul baru hitung posisi,
    // supaya ukuran viewport yang dipakai sudah yang terbaru (sudah
    // memperhitungkan tinggi keyboard).
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final ctx = _confirmSectionKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        // 0.0 = tempel ke paling atas viewport yang terlihat,
        // sehingga kolom + tombol Buat Akun ikut kelihatan di bawahnya
        alignment: 0.0,
      );
    });
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _kError : _kSuccess,
      ));
  }

  String _parseError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('user already registered') ||
        msg.contains('already been registered'))
      return 'Email ini sudah terdaftar. Silakan login.';
    if (msg.contains('invalid email')) return 'Format email tidak valid.';
    if (msg.contains('password'))      return 'Kata sandi terlalu lemah.';
    if (msg.contains('network') || msg.contains('connection'))
      return 'Periksa koneksi internet kamu.';
    return 'Terjadi kesalahan: ${e.message}';
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final supabase = Supabase.instance.client;
      final resp = await supabase.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        data: {'full_name': _nameCtrl.text.trim()},
      );
      if (!mounted) return;
      if (resp.user == null) {
        _showSnack('Terjadi kesalahan saat mendaftar. Coba lagi.');
        return;
      }

      // Saat konfirmasi email aktif, Supabase dapat mengembalikan user
      // tersamarkan (fake/obfuscated user) untuk email yang sudah terdaftar,
      // bukan melempar AuthException. Ciri respons tersebut adalah daftar
      // identities kosong. Jangan arahkan pengguna ke layar OTP karena kode
      // verifikasi baru memang tidak dikirimkan.
      final identities = resp.user!.identities;
      if (identities == null || identities.isEmpty) {
        _showSnack(
          'Email ini sudah terdaftar. Silakan login atau gunakan email lain.',
        );
        return;
      }
      // Catatan: row di tabel `profiles` SUDAH otomatis dibuat oleh trigger
      // database `on_auth_user_created` (function `handle_new_user`) begitu
      // user baru tercipta di `auth.users`. Upsert dari client TIDAK
      // diperlukan lagi di sini — sebelumnya baris ini menyebabkan bug:
      // saat email confirmation aktif, `resp.session` masih null di titik
      // ini sehingga `auth.uid()` juga null, dan RLS policy pada tabel
      // `profiles` menolak upsert dari client. Error yang muncul
      // (PostgrestException) tertangkap oleh `catch (_)` generik di bawah
      // dan menampilkan pesan keliru "Periksa koneksi internet kamu."
      // padahal koneksi baik-baik saja.
      if (!mounted) return;
      if (resp.session == null) {
        context.push('/verify-otp', extra: {'email': _emailCtrl.text.trim()});
      } else {
        context.go('/baseline');
      }
    } on AuthException catch (e) {
      _showSnack(_parseError(e));
    } catch (_) {
      _showSnack('Terjadi kesalahan. Periksa koneksi internet kamu.');
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
      // true: biarkan Flutter resize body mengikuti keyboard secara normal.
      // Ini sekarang bekerja dengan benar karena keyboard "vivo secure" sudah
      // tidak dipicu lagi (lihat keyboardType: visiblePassword di bawah).
      resizeToAvoidBottomInset: true,
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
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Header ──────────────────────────────────────────
                Text('Buat Akun',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: textColor)),
                const SizedBox(height: 6),
                Text('Daftar untuk memulai perjalanan regulasi diri belajarmu',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                const SizedBox(height: 28),

                // ── Nama Lengkap ─────────────────────────────────────
                _FieldLabel('NAMA LENGKAP'),
                TextFormField(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  onFieldSubmitted: (_) => _emailFocus.requestFocus(),
                  decoration: _inputDeco('Nama lengkap kamu', Icons.person_outline),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Nama lengkap wajib diisi';
                    if (v.trim().length < 2) return 'Nama terlalu pendek';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Email ────────────────────────────────────────────
                _FieldLabel('EMAIL'),
                TextFormField(
                  controller: _emailCtrl,
                  focusNode: _emailFocus,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.emailAddress,
                  onFieldSubmitted: (_) => _passFocus.requestFocus(),
                  decoration: _inputDeco('email@kampus.ac.id', Icons.email_outlined),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email wajib diisi';
                    final re = RegExp(r'^[\w.+-]+@[\w-]+\.[a-z]{2,}$', caseSensitive: false);
                    if (!re.hasMatch(v.trim())) return 'Format email tidak valid';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Kata Sandi ───────────────────────────────────────
                _FieldLabel('KATA SANDI'),
                TextFormField(
                  controller: _passCtrl,
                  focusNode: _passFocus,
                  textInputAction: TextInputAction.next,
                  obscureText: !_showPass,
                  // visiblePassword: mencegah OS (Vivo dkk) memicu
                  // "secure keyboard" overlay yang tidak bisa dideteksi
                  // tinggi-nya oleh Flutter. Tampilan tetap ter-titik-titik
                  // karena obscureText di atas yang mengaturnya.
                  keyboardType: TextInputType.visiblePassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
                  decoration: _inputDeco('Minimal 8 karakter', Icons.lock_outline).copyWith(
                    suffixIcon: _VisibilityToggle(
                      visible: _showPass,
                      onTap: () => setState(() => _showPass = !_showPass),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Kata sandi wajib diisi';
                    if (v.length < 8) return 'Minimal 8 karakter';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Konfirmasi Kata Sandi ────────────────────────────
                // Dibungkus dengan key supaya Scrollable.ensureVisible()
                // tahu persis ke mana harus scroll.
                Container(
                  key: _confirmSectionKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('KONFIRMASI KATA SANDI'),
                      TextFormField(
                        controller: _confirmCtrl,
                        focusNode: _confirmFocus,
                        textInputAction: TextInputAction.done,
                        obscureText: !_showConf,
                        keyboardType: TextInputType.visiblePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        onFieldSubmitted: (_) => _register(),
                        decoration: _inputDeco('Ulangi kata sandi', Icons.lock_outline).copyWith(
                          suffixIcon: _VisibilityToggle(
                            visible: _showConf,
                            onTap: () => setState(() => _showConf = !_showConf),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Konfirmasi kata sandi wajib diisi';
                          if (v != _passCtrl.text) return 'Kata sandi tidak cocok';
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),

                      // ── Tombol Daftar ──────────────────────────────
                      // Ikut dimasukkan ke dalam Container yang sama supaya
                      // saat scroll ke kolom konfirmasi, tombol ini juga
                      // langsung kelihatan tanpa perlu scroll lagi.
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPurple,
                            disabledBackgroundColor: _kPurple.withOpacity(0.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _loading
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Buat Akun',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
                                ],
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Link ke Login ────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Sudah punya akun? ', style: TextStyle(color: Colors.grey[500])),
                    GestureDetector(
                      onTap: _loading ? null : () => context.pop(),
                      child: const Text('Masuk',
                        style: TextStyle(color: _kPurple, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Widget Helpers ───────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
        color: _kLabelColor, letterSpacing: 0.6)),
  );
}

class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({required this.visible, required this.onTap});
  final bool visible;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(
      visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      size: 20,
    ),
    onPressed: onTap,
  );
}

InputDecoration _inputDeco(String hint, IconData icon) =>
  InputDecoration(hintText: hint, prefixIcon: Icon(icon, size: 20));