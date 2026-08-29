// lib/features/profile/profile_screens.dart
//
// Berisi dua screen: ProfileScreen dan EditProfileScreen
// Dependencies: flutter_riverpod, go_router, supabase_flutter

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/assessment_service.dart';
import '../../services/push_notification_service.dart';

// ══════════════════════════════════════════════════════════════════
// CONSTANTS — ubah di sini, berlaku ke seluruh file
// ══════════════════════════════════════════════════════════════════

const _kPurple = Color(0xFF5C4DFF);
const _kSuccess = Color(0xFF10B981);
const _kError = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
const _kPink = Color(0xFFEC4899);
const _kBg = Color(0xFFF5F7FA);
const _kTextDark = Color(0xFF1A1A2E);
const _kLabelColor = Color(0xFF6B7280);

// ══════════════════════════════════════════════════════════════════
// DATA MODEL
// ══════════════════════════════════════════════════════════════════

class ProfileData {
  final String fullName;
  final String email;
  final String? institution;
  final String? studyProgram;
  final String? avatarUrl;
  final int? srlScore;
  final String? scoreCategory;
  final String? personaLabel;
  final bool hasReassessed;
  // Warning tier badge ('mandiri'|'responsif'|'jarang_warning'|'sering_warning')
  // -- REPLIKA persis logika computeWarningTier() yang sama dipakai
  // Dashboard (lib/features/dashboard/providers/dashboard_provider.dart)
  // dan Persona Pembelajaran (lib/features/persona/providers/persona_provider.dart):
  // COUNT(monitoring_alerts) 28 hari terakhir vs ambang 3. null kalau
  // persona belum terbentuk.
  final String? warningTier;

  const ProfileData({
    required this.fullName,
    required this.email,
    this.institution,
    this.studyProgram,
    this.avatarUrl,
    this.srlScore,
    this.scoreCategory,
    this.personaLabel,
    this.hasReassessed = false,
    this.warningTier,
  });

  // Label badge -- sama persis dengan DashboardData.warningTierDisplayLabel
  // dan PersonaInfo.warningTierDisplayLabel, supaya "Mandiri"/"Responsif"
  // konsisten di semua layar.
  String? get warningTierDisplayLabel {
    switch (warningTier) {
      case 'mandiri':
        return 'Mandiri';
      case 'responsif':
        return 'Responsif';
      case 'jarang_warning':
        return 'Mandiri';
      case 'sering_warning':
        return 'Responsif';
      default:
        return null;
    }
  }

  Color get warningTierColor {
    switch (warningTier) {
      case 'mandiri':
      case 'jarang_warning':
        return const Color(0xFF10B981); // hijau
      case 'responsif':
      case 'sering_warning':
        return const Color(0xFFF59E0B); // oranye
      default:
        return const Color(0xFF9CA3AF);
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDER
// autoDispose: data otomatis di-clear saat screen di-pop
// ══════════════════════════════════════════════════════════════════

String? _normalizePersonaLabel(dynamic value) {
  final normalized = value
      ?.toString()
      .trim()
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  switch (normalized) {
    case 'consistent':
    case 'consistent learner':
      return 'consistent';
    case 'passive':
    case 'passive learner':
      return 'passive';
    case 'seasonal':
    case 'seasonal learner':
      return 'seasonal';
    case 'ambitious':
    case 'ambitious behind':
    case 'ambitious behind learner':
    case 'ambitious but behind':
    case 'ambitious but behind learner':
      return 'ambitious';
    default:
      return null;
  }
}

final profileDataProvider =
    FutureProvider.autoDispose<ProfileData>((ref) async {
  final sb = Supabase.instance.client;
  final user = sb.auth.currentUser;
  if (user == null)
    throw Exception('User tidak ditemukan. Silakan login kembali.');

  // Ambil 3 data secara paralel agar lebih cepat
  final results = await Future.wait([
    sb.from('profiles').select().eq('id', user.id).single(),
    sb
        .from('assessment_results')
        .select('score_total')
        .eq('user_id', user.id)
        .order('completed_at', ascending: false)
        .limit(1),
    sb
        .from('persona_history')
        .select('persona_label_id')
        .eq('user_id', user.id)
        .eq('is_current', true)
        .maybeSingle(),
  ]);

  final gate = await AssessmentService().getReassessmentGate();

  final profile = results[0] as Map<String, dynamic>;
  final assessList = (results[1] as List).cast<Map<String, dynamic>>();
  final persona = results[2] as Map<String, dynamic>?;

  final score =
      assessList.isNotEmpty ? assessList.first['score_total'] as int? : null;

  String? scoreCategory;
  if (score != null) {
    scoreCategory = score >= 45
        ? 'Tinggi'
        : score >= 29
            ? 'Sedang'
            : 'Rendah';
  }

  const personaMap = {
    'consistent': 'Consistent Learner',
    'passive': 'Passive Learner',
    'seasonal': 'Seasonal Learner',
    'ambitious': 'Ambitious but Behind Learner',
  };

  final normalizedPersonaId =
      _normalizePersonaLabel(persona?['persona_label_id']);

  // Warning tier badge ("Mandiri"/"Responsif") -- REPLIKA persis
  // computeWarningTier() yang sama dipakai Dashboard (lihat komentar di
  // lib/features/dashboard/providers/dashboard_provider.dart):
  // COUNT(monitoring_alerts) 28 hari terakhir vs ambang 3. Query terpisah
  // (bukan reuse dari layar lain) karena ProfileScreen belum memuat data
  // monitoring_alerts sebelumnya. null kalau persona belum terbentuk --
  // warning_tier tidak bermakna tanpa persona aktif.
  //
  // Label tier SERAGAM 'mandiri'/'responsif' untuk KEEMPAT persona (revisi
  // per arahan dosen pembimbing) -- lihat catatan yang sama di
  // dashboard_provider.dart dan mapWarningTierLabel() di
  // generate_recommendations.ts.
  String? warningTier;
  if (normalizedPersonaId != null) {
    const warningWindowDays = 28;
    const warningThreshold = 3;
    final windowStart = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: warningWindowDays));
    final alertCountResponse = await sb
        .from('monitoring_alerts')
        .select('id')
        .eq('user_id', user.id)
        .gte('created_at', windowStart.toIso8601String())
        .catchError((_) => <dynamic>[]);
    final warningCount = (alertCountResponse as List).length;
    final isFrequent = warningCount >= warningThreshold;
    warningTier = isFrequent ? 'responsif' : 'mandiri';
  }

  return ProfileData(
    fullName: (profile['full_name'] as String?) ?? 'Pengguna',
    email: user.email ?? '',
    institution: profile['institution'] as String?,
    studyProgram: profile['study_program'] as String?,
    avatarUrl: profile['avatar_url'] as String?,
    srlScore: score,
    scoreCategory: scoreCategory,
    personaLabel: personaMap[normalizedPersonaId ?? ''],
    hasReassessed: gate.hasReassessed,
    warningTier: warningTier,
  );
});

// ══════════════════════════════════════════════════════════════════
// PROFILE SCREEN
// ══════════════════════════════════════════════════════════════════

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileDataProvider);

    return Scaffold(
      backgroundColor: _kBg,
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _kPurple),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded,
                    color: Colors.grey[400], size: 48),
                const SizedBox(height: 12),
                Text('Gagal memuat profil',
                    style: TextStyle(
                        color: Colors.grey[600], fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('$e',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => ref.refresh(profileDataProvider),
                  icon: const Icon(Icons.refresh_rounded, color: _kPurple),
                  label: const Text('Coba lagi',
                      style: TextStyle(color: _kPurple)),
                ),
              ],
            ),
          ),
        ),
        data: (profile) => _ProfileBody(profile: profile),
      ),
    );
  }
}

// ── Profile Body ─────────────────────────────────────────────────

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});
  final ProfileData profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(context)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(child: _buildStats()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          sliver: SliverToBoxAdapter(
            child: Text('MENU UTAMA PROFIL',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[500],
                    letterSpacing: 0.7)),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              _buildMenuItems(context, ref),
            ),
          ),
        ),
      ],
    );
  }

  // ── Header dengan gradient ──────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final initial =
        profile.fullName.isNotEmpty ? profile.fullName[0].toUpperCase() : 'U';
    final hasInstitution =
        profile.institution != null && profile.institution!.isNotEmpty;
    final hasStudyProgram =
        profile.studyProgram != null && profile.studyProgram!.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kPurple, Color(0xFF3DBDB7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 28),
      child: Column(children: [
        Stack(children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: Colors.white.withOpacity(0.2),
            backgroundImage: profile.avatarUrl != null
                ? NetworkImage(profile.avatarUrl!)
                : null,
            child: profile.avatarUrl == null
                ? Text(initial,
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: Colors.white))
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () => context.push('/profile/edit'),
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.settings_rounded,
                    color: _kPurple, size: 16),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text(profile.fullName,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
        const SizedBox(height: 4),
        Text(profile.email,
            style:
                TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8))),
        const SizedBox(height: 10),
        // Chip institusi & prodi
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.business_outlined, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                hasInstitution ? profile.institution! : 'Institusi belum diisi',
                style: const TextStyle(fontSize: 13, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasStudyProgram) ...[
              const SizedBox(width: 10),
              Container(
                  width: 1, height: 14, color: Colors.white.withOpacity(0.4)),
              const SizedBox(width: 10),
              const Icon(Icons.school_outlined, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  profile.studyProgram!,
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  // ── Stats row ───────────────────────────────────────────────────

  Widget _buildStats() => Row(children: [
        Expanded(
          child: _StatCard(
            label: 'SKOR REGULASI DIRI',
            value: profile.srlScore != null
                ? '${profile.srlScore}/60 (${profile.scoreCategory})'
                : 'Belum ada',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'PERSONA AKTIF',
            value: profile.personaLabel ?? 'Belum terbentuk',
            badgeLabel: profile.warningTierDisplayLabel,
            badgeColor: profile.warningTierColor,
          ),
        ),
      ]);

  // ── Menu items ──────────────────────────────────────────────────

  List<Widget> _buildMenuItems(BuildContext context, WidgetRef ref) => [
        _MenuItem(
          icon: Icons.person_outline_rounded,
          iconBg: const Color(0xFFEEEDFE),
          iconColor: _kPurple,
          title: 'Edit Profil',
          subtitle: 'Perbarui informasi akun Anda.',
          onTap: () => context.push('/profile/edit'),
        ),
        _MenuItem(
          icon: Icons.trending_up_rounded,
          iconBg: const Color(0xFFD1FAE5),
          iconColor: _kSuccess,
          title: 'Evaluasi Perkembangan',
          subtitle: 'Pantau perubahan dan kemajuan belajar.',
          onTap: () => context.push('/progress'),
        ),
        _MenuItem(
          icon: Icons.edit_note_rounded,
          iconBg: const Color(0xFFE0F7FA),
          iconColor: const Color(0xFF4ECDC4),
          title: 'Refleksi Mingguan',
          subtitle: 'Tulis dan lihat riwayat refleksi belajarmu.',
          onTap: () => context.push('/reflection'),
        ),
        _MenuItem(
          icon: Icons.auto_awesome_outlined,
          iconBg: const Color(0xFFFEF3C7),
          iconColor: _kAmber,
          title: 'Evaluasi Penerimaan Teknologi',
          subtitle: profile.hasReassessed
              ? 'Berikan penilaian terhadap aplikasi.'
              : 'Tersedia setelah Evaluasi Perkembangan (T2) diisi.',
          disabled: !profile.hasReassessed,
          onTap: profile.hasReassessed
              ? () => context.push('/tam')
              : () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Isi Evaluasi Perkembangan (Penilaian Ulang Regulasi Diri) terlebih dahulu.'))),
        ),
        _MenuItem(
          icon: Icons.notifications_outlined,
          iconBg: const Color(0xFFFCE7F3),
          iconColor: _kPink,
          title: 'Info & Pencapaian',
          subtitle: 'Evaluasi mingguan, persona, dan capaian goal-mu.',
          onTap: () => context.push('/reminders'),
        ),
        _MenuItem(
          icon: Icons.settings_outlined,
          iconBg: const Color(0xFFF1EFE8),
          iconColor: _kLabelColor,
          title: 'Pengaturan Sesi',
          subtitle: 'Kelola tema, notifikasi, dan akun.',
          onTap: () => context.push('/settings'),
        ),
        _MenuItem(
          icon: Icons.menu_book_outlined,
          iconBg: const Color(0xFFEEEDFE),
          iconColor: _kPurple,
          title: 'Tentang Aplikasi dan Penelitian',
          subtitle: 'Pelajari tujuan dan metode penelitian.',
          onTap: () => context.push('/about'),
        ),
        const SizedBox(height: 8),
        _LogoutButton(onTap: () => _showLogoutDialog(context)),
      ];

  // ── Logout dialog ───────────────────────────────────────────────
  // Tombol diletakkan di dalam content (Column), BUKAN di actions list,
  // agar SizedBox(width: double.infinity) bekerja dengan benar

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Keluar dari Akun?',
            style: TextStyle(fontWeight: FontWeight.w700, color: _kTextDark)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kamu akan keluar dari sesi ini.',
                style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(dialogCtx),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPurple,
                  side: const BorderSide(color: _kPurple),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Batal',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(dialogCtx);
                  await PushNotificationService().deactivateCurrentToken();
                  await Supabase.instance.client.auth.signOut();
                  if (context.mounted) context.go('/login');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kError,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Keluar',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
        // Kosongkan actions agar tidak ada padding/layout conflict
        actions: const [],
        actionsPadding: EdgeInsets.zero,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// EDIT PROFILE SCREEN
// ══════════════════════════════════════════════════════════════════

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  // ── Form ────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _instCtrl = TextEditingController();
  final _studyCtrl = TextEditingController();

  // ── FocusNodes — Next/Done keyboard navigation ──────────────────
  final _nameFocus = FocusNode();
  final _instFocus = FocusNode();
  final _studyFocus = FocusNode();

  // ── State ───────────────────────────────────────────────────────
  bool _saving = false;
  bool _initialized = false; // false = masih loading data awal

  // ── Lifecycle ───────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  /// Ambil data dari provider yang sudah ada (cache) — efisien, tidak perlu
  /// request Supabase baru jika ProfileScreen sudah memuatnya lebih dulu.
  Future<void> _loadInitialData() async {
    try {
      final profile = await ref.read(profileDataProvider.future);
      if (!mounted) return;
      _nameCtrl.text = profile.fullName;
      _instCtrl.text = profile.institution ?? '';
      _studyCtrl.text = profile.studyProgram ?? '';
      setState(() => _initialized = true);
    } catch (_) {
      // Provider gagal → fallback ke direct fetch
      await _directFetch();
    }
  }

  /// Fallback: fetch langsung dari Supabase jika provider error
  Future<void> _directFetch() async {
    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid == null) return;
      final data = await sb.from('profiles').select().eq('id', uid).single()
          as Map<String, dynamic>;
      if (!mounted) return;
      _nameCtrl.text = (data['full_name'] as String?) ?? '';
      _instCtrl.text = (data['institution'] as String?) ?? '';
      _studyCtrl.text = (data['study_program'] as String?) ?? '';
    } catch (_) {
      // Biarkan field kosong, user bisa isi manual
    } finally {
      if (mounted) setState(() => _initialized = true);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _instCtrl.dispose();
    _studyCtrl.dispose();
    _nameFocus.dispose();
    _instFocus.dispose();
    _studyFocus.dispose();
    super.dispose();
  }

  // ── Save Logic ──────────────────────────────────────────────────

  Future<void> _save() async {
    // Tutup keyboard sebelum proses
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid == null) throw Exception('User tidak ditemukan');

      await sb.from('profiles').update({
        'full_name': _nameCtrl.text.trim(),
        // Simpan null jika dikosongkan agar DB tidak menyimpan string kosong
        'institution':
            _instCtrl.text.trim().isEmpty ? null : _instCtrl.text.trim(),
        'study_program':
            _studyCtrl.text.trim().isEmpty ? null : _studyCtrl.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', uid);

      // Invalidate provider → ProfileScreen otomatis refresh
      ref.invalidate(profileDataProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Profil berhasil diperbarui!'),
          backgroundColor: _kSuccess,
        ));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Gagal menyimpan profil. Coba lagi.'),
          backgroundColor: _kError,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Tinggi keyboard — 0 jika tidak tampil
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: _kBg,
      // Scaffold menyusut otomatis saat keyboard muncul
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: _kTextDark),
          onPressed: () => context.pop(),
        ),
        title: const Text('Edit Profil Mahasiswa',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: _kTextDark)),
      ),
      body: !_initialized
          ? const Center(child: CircularProgressIndicator(color: _kPurple))
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                // Swipe ke bawah → tutup keyboard
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                // Padding bawah dinamis = tinggi keyboard + ruang ekstra
                // Ini yang mencegah tombol dan field terakhir ketutup keyboard
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: keyboardHeight + 32,
                ),
                child: Column(children: [
                  // ── Card 1: Identitas ─────────────────────────────
                  _ProfileCard(children: [
                    const _FieldLabel('NAMA MAHASISWA'),
                    TextFormField(
                      controller: _nameCtrl,
                      focusNode: _nameFocus,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      onFieldSubmitted: (_) => _instFocus.requestFocus(),
                      decoration: _fieldDeco('Nama lengkap'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Nama tidak boleh kosong';
                        }
                        if (v.trim().length < 2) return 'Nama terlalu pendek';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('EMAIL'),
                    // Email dari auth session — tidak bisa diedit di sini
                    _ReadOnlyField(value: email),
                  ]),
                  const SizedBox(height: 12),

                  // ── Card 2: Institusi & Prodi ─────────────────────
                  _ProfileCard(children: [
                    const _FieldLabel('INSTITUSI KAMPUS'),
                    TextFormField(
                      controller: _instCtrl,
                      focusNode: _instFocus,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _studyFocus.requestFocus(),
                      decoration: _fieldDeco('Misal: BINUS University'),
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('PROGRAM STUDI'),
                    TextFormField(
                      controller: _studyCtrl,
                      focusNode: _studyFocus,
                      textInputAction: TextInputAction.done,
                      // Tekan Done di keyboard → langsung simpan
                      onFieldSubmitted: (_) => _save(),
                      decoration: _fieldDeco('Misal: Computer Science'),
                    ),
                  ]),
                  const SizedBox(height: 24),

                  // ── Tombol Simpan ─────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPurple,
                        disabledBackgroundColor: _kPurple.withOpacity(0.5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Simpan Perubahan Profil',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// SHARED PRIVATE WIDGETS
// Dipisah agar build() kedua screen tetap bersih dan mudah dibaca
// ══════════════════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.badgeLabel,
    this.badgeColor,
  });
  final String label, value;
  // Badge opsional ("Mandiri"/"Responsif") -- ditampilkan di BAWAH value
  // (baris sendiri), bukan di sampingnya, supaya value seperti "Passive
  // Learner" tetap satu baris rapi (dengan ellipsis kalau kepanjangan)
  // alih-alih terdorong pecah jadi 2 baris karena berbagi ruang sempit
  // dengan badge di kartu selebar setengah layar ini. Kalau badgeLabel
  // null, tidak ada pill yang dirender sama sekali (bukan pill kosong),
  // supaya kartu SKOR REGULASI DIRI (yang tidak memanggil param ini) tetap
  // tampil apa adanya seperti sebelumnya.
  final String? badgeLabel;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: _kTextDark),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (badgeLabel != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (badgeColor ?? _kAmber).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeLabel!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: badgeColor ?? _kAmber,
                  ),
                ),
              ),
            ),
          ],
        ]),
      );
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.disabled = false,
  });
  final IconData icon;
  final Color iconBg, iconColor;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: disabled ? Colors.grey[200] : iconBg,
                  borderRadius: BorderRadius.circular(11)),
              child: Icon(icon,
                  color: disabled ? Colors.grey[400] : iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: disabled ? Colors.grey[400] : _kTextDark)),
                    Text(subtitle,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ]),
            ),
            Icon(
                disabled
                    ? Icons.lock_outline_rounded
                    : Icons.chevron_right_rounded,
                color: Colors.grey[400],
                size: disabled ? 18 : 20),
          ]),
        ),
      );
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: _kError.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.logout_rounded, color: _kError, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Keluar dari Akun',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _kError)),
                    Text('Keluar dari sesi ini.',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ]),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.grey[400], size: 20),
          ]),
        ),
      );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey[500],
                letterSpacing: 0.6)),
      );
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
            color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(
              child: Text(value,
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]))),
          Icon(Icons.lock_outline, size: 14, color: Colors.grey[400]),
        ]),
      );
}

/// Decoration konsisten untuk semua TextFormField di EditProfileScreen
InputDecoration _fieldDeco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
      filled: true,
      fillColor: const Color(0xFFF5F7FA),
      // Border states yang lengkap agar tidak ada visual glitch saat focus/error
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kPurple, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kError, width: 1.5)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kError, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      errorStyle: const TextStyle(fontSize: 11),
    );
