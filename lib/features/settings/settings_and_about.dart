// lib/features/settings/settings_and_about.dart
// Berisi: NotificationScreen, SettingsScreen, AboutScreen

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _purple = Color(0xFF5C4DFF);
const _bg     = Color(0xFFF5F7FA);

// ══════════════════════════════════════════════════════════════
// NOTIFICATION SCREEN
// ══════════════════════════════════════════════════════════════

class AppNotification {
  final String id, title, body, timeAgo;
  final IconData icon;
  final bool isRead;
  final Color iconColor;
  final String? route; // layar tujuan saat notifikasi ditekan (opsional)
  final int priority; // 0 = perlu aksi (ditampilkan lebih dulu), 1 = info saja

  const AppNotification({
    required this.id, required this.icon, required this.title,
    required this.body, required this.timeAgo, required this.isRead,
    required this.iconColor, this.route, this.priority = 1,
  });
}

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final sb  = Supabase.instance.client;
  final uid = sb.auth.currentUser!.id;
  final now = DateTime.now();
  final notifications = <AppNotification>[];

  // Setiap pengecekan dibungkus try-catch TERPISAH: kalau satu query
  // gagal (misal koneksi terputus/tabel kosong), pengecekan lain tetap
  // lanjut dan kotak masuk tidak jadi kosong/error total.

  // 1. Cek refleksi minggu ini
  try {
    final weekNum = _weekNumber(now);
    final refleksi = await sb.from('weekly_reflections')
        .select('id').eq('user_id', uid)
        .eq('week_year', now.year).eq('week_number', weekNum)
        .maybeSingle();
    if (refleksi == null) {
      notifications.add(const AppNotification(
        id: 'n1', icon: Icons.notifications_outlined, iconColor: _purple,
        title: 'Evaluasi Mingguan Siap',
        body: 'Yuk evaluasi belajarmu minggu ini dan tulis Refleksi Minggumu sekarang!',
        timeAgo: 'Hari ini', isRead: false, route: '/reflection', priority: 0,
      ));
    }
  } catch (e) {
    debugPrint('notificationsProvider - cek refleksi gagal: $e');
  }

  // 2. Cek persona aktif
  try {
    final persona = await sb.from('persona_history')
        .select('persona_label_id, assigned_at')
        .eq('user_id', uid).eq('is_current', true).maybeSingle();
    if (persona != null) {
      final labelId = persona['persona_label_id'] as String;
      final labelMap = {
        'consistent': 'Consistent Learner',
        'passive':    'Passive Learner',
        'seasonal':   'Seasonal Learner',
        'ambitious':  'Ambitious but Behind Learner',
      };
      final label = labelMap[labelId] ?? 'Persona Baru';
      final assigned = DateTime.parse(persona['assigned_at'] as String);
      final diff = now.difference(assigned).inDays;
      notifications.add(AppNotification(
        id: 'n2', icon: Icons.auto_awesome_outlined,
        iconColor: const Color(0xFF4ECDC4),
        title: 'Rekomendasi Persona Diperoleh',
        body: 'Selamat! Pola belajarmu kini sesuai dengan persona "$label".',
        timeAgo: diff == 0 ? 'Hari ini' : diff == 1 ? 'Kemarin' : '$diff hari lalu',
        isRead: true,
      ));
    }
  } catch (e) {
    debugPrint('notificationsProvider - cek persona gagal: $e');
  }

  // 3. Cek goal 50%+ (aktif maupun yang sudah benar-benar selesai)
  try {
    final goals = await sb.from('learning_goals')
        .select('id, title, actual_progress, status, created_at')
        .eq('user_id', uid)
        .inFilter('status', ['active', 'completed'])
        .gte('actual_progress', 50);
    for (final g in (goals as List).cast<Map<String, dynamic>>()) {
      final isDone = g['status'] == 'completed';
      final createdAt = DateTime.parse(g['created_at'] as String);
      final diff = now.difference(createdAt).inDays;
      final timeAgo = diff <= 0 ? 'Hari ini' : diff == 1 ? 'Kemarin' : '$diff hari lalu';
      final pct = (g['actual_progress'] as num).round();
      notifications.add(AppNotification(
        id: 'n3_${g['id']}',
        icon: isDone ? Icons.emoji_events_rounded : Icons.flag_outlined,
        iconColor: const Color(0xFF10B981),
        title: isDone ? 'Target Belajar Selesai' : 'Target Belajar Tercapai',
        body: isDone
            ? 'Yeay! Target "${g['title']}" telah selesai! 🎉'
            : 'Target "${g['title']}" sudah $pct% selesai, setengah jalan lebih!',
        timeAgo: timeAgo, isRead: true,
      ));
      break;
    }
  } catch (e) {
    debugPrint('notificationsProvider - cek goal gagal: $e');
  }

  // 4. Cek SRL Reassessment (T2) sudah boleh & belum diisi
  bool hasReassessed = false;
  try {
    final gateRow = await sb.from('v_reassessment_gate')
        .select('can_reassess, has_reassessed')
        .eq('user_id', uid).maybeSingle();
    final canReassess = gateRow?['can_reassess'] as bool? ?? false;
    hasReassessed = gateRow?['has_reassessed'] as bool? ?? false;
    if (canReassess && !hasReassessed) {
      notifications.add(const AppNotification(
        id: 'n4', icon: Icons.psychology_alt_rounded,
        iconColor: Color(0xFFF59E0B),
        title: 'Evaluasi Perkembangan Siap Diisi',
        body: 'Empat minggu sejak Penilaian Awal telah selesai. Yuk isi Penilaian Ulang '
            'Regulasi Diri (T2) sekarang.',
        timeAgo: 'Hari ini', isRead: false, route: '/progress', priority: 0,
      ));
    }
  } catch (e) {
    debugPrint('notificationsProvider - cek gate T2 gagal: $e');
  }

  // 5. Cek TAM belum diisi, padahal T2 sudah selesai
  try {
    if (hasReassessed) {
      final tam = await sb.from('tam_responses')
          .select('id').eq('user_id', uid).maybeSingle();
      if (tam == null) {
        notifications.add(const AppNotification(
          id: 'n5', icon: Icons.auto_awesome_outlined,
          iconColor: Color(0xFFF59E0B),
          title: 'Evaluasi Penerimaan Teknologi Menunggu',
          body: 'Satu langkah lagi! Isi Evaluasi Penerimaan Teknologi (TAM) '
              'untuk menyelesaikan rangkaian evaluasi.',
          timeAgo: 'Hari ini', isRead: false, route: '/tam', priority: 0,
        ));
      }
    }
  } catch (e) {
    debugPrint('notificationsProvider - cek TAM gagal: $e');
  }

  // 6. Cek rekomendasi metakognitif baru yang belum dilihat
  try {
    final unseenRec = await sb.from('recommendations')
        .select('id').eq('user_id', uid)
        .eq('is_dismissed', false)
        .isFilter('viewed_at', null)
        .limit(1).maybeSingle();
    if (unseenRec != null) {
      notifications.add(const AppNotification(
        id: 'n6', icon: Icons.lightbulb_outline_rounded,
        iconColor: Color(0xFF4ECDC4),
        title: 'Rekomendasi Metakognitif Tersedia',
        body: 'Ada rekomendasi baru berdasarkan pola belajarmu. Yuk lihat selengkapnya.',
        timeAgo: 'Hari ini', isRead: false, route: '/recommendation',
      ));
    }
  } catch (e) {
    debugPrint('notificationsProvider - cek rekomendasi gagal: $e');
  }

  // Urutkan: yang perlu aksi (priority 0) tampil lebih dulu dari yang
  // sifatnya cuma info (priority 1), supaya hal paling mendesak langsung
  // terlihat begitu kotak masuk dibuka.
  notifications.sort((a, b) => a.priority.compareTo(b.priority));
  return notifications;
});

int _weekNumber(DateTime d) {
  final dayOfYear = d.difference(DateTime(d.year, 1, 1)).inDays + 1;
  return ((dayOfYear - d.weekday + 10) / 7).floor();
}

class NotificationScreen extends ConsumerStatefulWidget {
  const NotificationScreen({super.key});
  @override
  ConsumerState<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends ConsumerState<NotificationScreen> {
  // Notifikasi di layar ini dihitung ulang tiap load (tidak disimpan ke
  // database), jadi status "sudah dibaca" cukup dilacak secara lokal di
  // sesi ini saja lewat kumpulan id berikut.
  final Set<String> _readIds = {};

  @override
  Widget build(BuildContext context) {
    final notifAsync = ref.watch(notificationsProvider);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('INFO & PENCAPAIAN',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E), letterSpacing: 0.5)),
        actions: [
          TextButton(
              onPressed: () {
                final notifs = notifAsync.value ?? const [];
                setState(() {
                  _readIds.addAll(notifs.map((n) => n.id));
                });
              },
              child: const Text('Baca Semua',
                  style: TextStyle(color: _purple, fontWeight: FontWeight.w600))),
        ],
      ),
      body: notifAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: _purple)),
          error: (_, __) => Center(child: Text('Gagal memuat notifikasi',
              style: TextStyle(color: Colors.grey[400]))),
          data: (notifs) => notifs.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.notifications_none_rounded, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text('Tidak ada notifikasi',
                      style: TextStyle(fontSize: 15, color: Colors.grey[400])),
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final n = notifs[i];
                    final effectivelyRead = n.isRead || _readIds.contains(n.id);
                    final displayNotif = effectivelyRead
                        ? AppNotification(id: n.id, icon: n.icon, iconColor: n.iconColor,
                            title: n.title, body: n.body, timeAgo: n.timeAgo,
                            isRead: true, route: n.route, priority: n.priority)
                        : n;
                    return GestureDetector(
                      onTap: n.route == null ? null : () {
                        setState(() => _readIds.add(n.id));
                        context.push(n.route!);
                      },
                      child: _NotifCard(notif: displayNotif),
                    );
                  },
                ),
      ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  final AppNotification notif;
  const _NotifCard({required this.notif});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: notif.isRead ? Colors.white : _purple.withOpacity(0.04),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: notif.isRead ? Colors.transparent : _purple.withOpacity(0.2))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 40, height: 40,
          decoration: BoxDecoration(color: notif.iconColor.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(notif.icon, color: notif.iconColor, size: 20)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(notif.title, style: const TextStyle(fontSize: 14,
            fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 3),
        Text(notif.body, style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.4)),
        const SizedBox(height: 6),
        Text(notif.timeAgo, style: const TextStyle(fontSize: 11,
            color: _purple, fontWeight: FontWeight.w500)),
      ])),
      if (notif.route != null)
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 2),
          child: Icon(Icons.chevron_right_rounded, color: Colors.grey[400], size: 20),
        ),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════
// SETTINGS SCREEN
// ══════════════════════════════════════════════════════════════

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _studyReminder = true,
       _reflectionReminder = true, _reassessmentReminder = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('Pengaturan Sesi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _sectionHeader('PENGINGAT BELAJAR'),
          _card(children: [
            _SwitchRow(icon: Icons.book_outlined, iconColor: const Color(0xFF4ECDC4),
                title: 'Sesi Belajar Harian', subtitle: 'Pengingat memulai sesi belajar.',
                value: _studyReminder, onChanged: (v) => setState(() => _studyReminder = v)),
            const Divider(height: 1),
            _SwitchRow(icon: Icons.edit_note_rounded, iconColor: _purple,
                title: 'Refleksi Mingguan', subtitle: 'Pengingat mengisi jurnal refleksi.',
                value: _reflectionReminder, onChanged: (v) => setState(() => _reflectionReminder = v)),
            const Divider(height: 1),
            _SwitchRow(icon: Icons.psychology_outlined, iconColor: const Color(0xFFF59E0B),
                title: 'Penilaian Ulang SRL', subtitle: 'Pengingat untuk isi reassessment.',
                value: _reassessmentReminder, onChanged: (v) => setState(() => _reassessmentReminder = v)),
          ]),
          const SizedBox(height: 16),
          _sectionHeader('AKUN'),
          _card(children: [
            _NavRow(icon: Icons.lock_outline_rounded, iconColor: Colors.grey,
                title: 'Ubah Kata Sandi', subtitle: 'Perbarui kata sandi akun Anda.',
                onTap: () => _showChangePwd(context)),
            const Divider(height: 1),
            _NavRow(icon: Icons.info_outline_rounded, iconColor: _purple,
                title: 'Tentang Aplikasi', subtitle: 'Versi 1.0.0 • Skripsi BINUS 2026',
                onTap: () => context.push('/about')),
          ]),
        ]),
      ),
    );
  }

  Widget _sectionHeader(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Align(alignment: Alignment.centerLeft,
      child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: Colors.grey[500], letterSpacing: 0.7))));

  Widget _card({required List<Widget> children}) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
    child: Column(children: children));

  void _showChangePwd(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ChangePwdDialog(),
    );
  }
}

// ── Dialog Ubah Kata Sandi dengan loading & notifikasi ─────────
class _ChangePwdDialog extends StatefulWidget {
  @override
  State<_ChangePwdDialog> createState() => _ChangePwdDialogState();
}

class _ChangePwdDialogState extends State<_ChangePwdDialog> {
  bool _isLoading = false;
  bool _isSent    = false;

  Future<void> _send() async {
    setState(() => _isLoading = true);
    try {
      final email = Supabase.instance.client.auth.currentUser?.email ?? '';
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      setState(() { _isLoading = false; _isSent = true; });
      // Tutup dialog otomatis setelah 2 detik
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal mengirim tautan. Coba lagi.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Icon(
            _isSent ? Icons.check_circle_rounded : Icons.lock_reset_rounded,
            color: _isSent ? const Color(0xFF10B981) : _purple,
            size: 24,
          ),
          const SizedBox(width: 8),
          Text(_isSent ? 'Tautan Terkirim!' : 'Ubah Kata Sandi'),
        ],
      ),
      content: Text(
        _isSent
            ? 'Tautan reset kata sandi sudah dikirim ke email terdaftar Anda. Periksa inbox atau folder spam.'
            : 'Tautan reset akan dikirim ke email terdaftar Anda.',
        style: TextStyle(
          color: _isSent ? const Color(0xFF10B981) : null,
        ),
      ),
      actionsPadding: _isSent
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: _isSent
          ? null  // Sembunyikan tombol setelah terkirim
          : [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _purple,
                    side: const BorderSide(color: _purple),
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
                  onPressed: _isLoading ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Kirim Tautan',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                ),
              ),
            ],
    );
  }
} // end _ChangePwdDialogState

class _SwitchRow extends StatelessWidget {
  final IconData icon; final Color iconColor;
  final String title, subtitle; final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.icon, required this.iconColor,
      required this.title, required this.subtitle,
      required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(children: [
      Container(width: 36, height: 36,
        decoration: BoxDecoration(color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor, size: 18)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14,
            fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
        Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ])),
      Switch(value: value, onChanged: onChanged, activeColor: _purple),
    ]));
}

class _NavRow extends StatelessWidget {
  final IconData icon; final Color iconColor;
  final String title, subtitle; final VoidCallback onTap;
  const _NavRow({required this.icon, required this.iconColor,
      required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: iconColor, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 14,
              fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
          Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ])),
        Icon(Icons.chevron_right_rounded, color: Colors.grey[400], size: 20),
      ])));
}

// ══════════════════════════════════════════════════════════════
// ABOUT SCREEN
// ══════════════════════════════════════════════════════════════

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('Tentang Aplikasi & Penelitian',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_purple, Color(0xFF3DBDB7)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              Container(width: 64, height: 64,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.psychology_outlined, color: Colors.white, size: 34)),
              const SizedBox(height: 14),
              const Text('AI Learning Tracker',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 4),
              Text('Versi 1.0.0 • Prototype Penelitian Skripsi',
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8))),
              const SizedBox(height: 8),
              Text('"Pantau, Refleksikan, dan Tingkatkan Regulasi Diri Belajarmu"',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.9),
                      fontStyle: FontStyle.italic)),
            ]),
          ),
          const SizedBox(height: 16),
          _infoCard([
            ('Judul', 'Pemantauan Regulasi Diri Mahasiswa melalui Pelacak Pembelajaran Berbasis Persona'),
            ('Peneliti', 'Novita — NIM 2802608990'),
            ('Program Studi', 'Computer Science'),
            ('Universitas', 'Universitas Bina Nusantara (BINUS Online)'),
            ('Tahun', '2026'),
            ('Instrumen', 'MSLQ — Subskala Metacognitive Self-Regulation'),
            ('Algoritma ML', 'K-Means Clustering'),
            ('Evaluasi', 'Black Box Testing + TAM'),
          ]),
          const SizedBox(height: 12),
          _infoCard([
            ('Backend', 'Supabase (PostgreSQL + Auth + Edge Functions)'),
            ('Frontend', 'Flutter 3.x (Dart)'),
            ('State Management', 'Riverpod 2.x'),
            ('Charts', 'fl_chart'),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Text(
              'Aplikasi ini merupakan prototipe penelitian ilmiah. '
              'Data yang dikumpulkan digunakan semata-mata untuk keperluan '
              'penelitian skripsi.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.5)),
          ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _infoCard(List<(String, String)> items) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
    child: Column(children: items.map((e) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(e.$1, style: TextStyle(fontSize: 12,
            color: Colors.grey[500], fontWeight: FontWeight.w500))),
        Expanded(child: Text(e.$2, style: const TextStyle(fontSize: 12,
            color: Color(0xFF1A1A2E), fontWeight: FontWeight.w600, height: 1.4))),
      ]))).toList()));
}