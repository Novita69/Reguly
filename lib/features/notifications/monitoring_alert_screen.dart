// lib/features/notifications/monitoring_alert_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/monitoring_alert_provider.dart';
import '../../models/monitoring_alert.dart';

const _purple = Color(0xFF5C4DFF);
const _teal = Color(0xFF4ECDC4);
const _bg = Color(0xFFF5F7FA);
const _amber = Color(0xFFFFA726);
const _red = Color(0xFFEF5350);

class MonitoringAlertScreen extends ConsumerWidget {
  const MonitoringAlertScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(monitoringAlertProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Peringatan Progres',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
        ),
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () => ref.read(monitoringAlertProvider.notifier).markAllAsRead(),
              child: const Text(
                'Tandai semua dibaca',
                style: TextStyle(color: _purple, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator(color: _purple))
          : RefreshIndicator(
              color: _purple,
              onRefresh: () => ref.read(monitoringAlertProvider.notifier).load(),
              child: state.alerts.isEmpty
                  ? const _EmptyAlerts()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: state.alerts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) => _AlertCard(
                        alert: state.alerts[i],
                        onTap: () async {
                          final alert = state.alerts[i];
                          await ref.read(monitoringAlertProvider.notifier).markAsClicked(alert.id);
                          if (context.mounted) context.push(alert.deepLink);
                        },
                      ),
                    ),
            ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final MonitoringAlert alert;
  final VoidCallback onTap;
  const _AlertCard({required this.alert, required this.onTap});

  ({IconData icon, Color color}) get _visual {
    switch (alert.ruleCode) {
      case 'W1_DAILY':
        return (icon: Icons.notifications_active_rounded, color: _teal);
      case 'W1_STREAK':
        return (icon: Icons.bedtime_rounded, color: _amber);
      case 'W2':
        return (icon: Icons.hourglass_bottom_rounded, color: _amber);
      case 'W3':
        return (icon: Icons.event_busy_rounded, color: _red);
      case 'W4':
        return (icon: Icons.trending_down_rounded, color: _amber);
      case 'W5':
        return (icon: Icons.timeline_rounded, color: _amber);
      default:
        return (icon: Icons.info_outline_rounded, color: _purple);
    }
  }

  // Pemetaan rule -> dua opsi aksi yang ditawarkan di kartu notifikasi.
  //
  // Kenapa ada, dan kenapa DUA tombol (bukan satu):
  //   Kondisi pemicu W1_DAILY/W1_STREAK adalah "tidak ada aktivitas
  //   TERCATAT", bukan "tidak ada aktivitas". Sistem tidak bisa membedakan
  //   mahasiswa yang benar-benar belum mengerjakan skripsinya dari yang
  //   sudah mengerjakan tapi lupa mencatat. Satu kalimat/tombol tunggal
  //   yang mengarah ke salah satu aksi berisiko salah sasaran untuk
  //   separuh kemungkinan. Dua tombol membiarkan mahasiswa sendiri yang
  //   memilih sesuai kondisi nyatanya, tanpa sistem menebak.
  //
  //   W2/W4/W5 (goal aktif tapi tertinggal pace) TIDAK memakai pola yang
  //   sama: goal-nya sudah jelas dan sudah berjalan, yang diperlukan
  //   adalah melanjutkan pengerjaan -- baik lewat pencatatan manual
  //   maupun sesi terjadwal -- sehingga label tombolnya "Catat progres" /
  //   "Lanjutkan sesi", bukan "Mulai belajar" (yang tersirat "belum
  //   pernah mulai", padahal goal ini sudah berjalan).
  //
  //   W3 (goal sudah lewat deadline) tidak dua tombol -- kebutuhannya
  //   bukan mencatat atau mengerjakan, tapi memutuskan ulang jadwal
  //   goal-nya, sehingga cukup satu tombol yang mengarah ke goal terkait
  //   (sudah dilayani deep_link default -> alert.deepLink).
  List<({String label, IconData icon, String route})> get _quickActions {
    switch (alert.ruleCode) {
      case 'W1_DAILY':
      case 'W1_STREAK':
        return const [
          (label: 'Catat progres', icon: Icons.edit_note_rounded, route: '/activity/add'),
          (label: 'Mulai belajar', icon: Icons.play_circle_outline_rounded, route: '/focus-session'),
        ];
      case 'W2':
      case 'W4':
      case 'W5':
        return const [
          (label: 'Catat progres', icon: Icons.edit_note_rounded, route: '/activity/add'),
          (label: 'Lanjutkan sesi', icon: Icons.play_circle_outline_rounded, route: '/focus-session'),
        ];
      default:
        // W3 dan rule tak dikenal di masa depan: tidak ada quick action,
        // cukup andalkan tap kartu (-> alert.deepLink) seperti semula.
        return const [];
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    return '${diff.inDays} hari lalu';
  }

  @override
  Widget build(BuildContext context) {
    final v = _visual;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: alert.isUnread ? _purple.withOpacity(0.25) : Colors.black12,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: v.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(v.icon, color: v.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            alert.title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: alert.isUnread ? FontWeight.w700 : FontWeight.w600,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                        ),
                        if (alert.isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6, top: 2),
                            decoration: const BoxDecoration(color: _purple, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.body,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280), height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _relativeTime(alert.createdAt),
                      style: const TextStyle(fontSize: 11, color: Color(0xFFB0B4BD)),
                    ),
                    if (_quickActions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (var i = 0; i < _quickActions.length; i++) ...[
                            Expanded(
                              child: _QuickActionButton(action: _quickActions[i], color: v.color),
                            ),
                            if (i < _quickActions.length - 1) const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tombol aksi cepat di dalam kartu notifikasi.
///
/// Dibungkus Material+InkWell TERSENDIRI (bukan cuma GestureDetector di
/// dalam InkWell kartu induk) supaya ketukan pada tombol ini tidak ikut
/// diteruskan sebagai tap pada kartu (yang akan menavigasi ke
/// alert.deepLink dan menandai alert sebagai clicked/read secara keliru
/// -- perilaku "tap kartu" tetap harus hanya terjadi kalau area DI LUAR
/// tombol yang ditekan).
class _QuickActionButton extends StatelessWidget {
  final ({String label, IconData icon, String route}) action;
  final Color color;
  const _QuickActionButton({required this.action, required this.color});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push(action.route),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 15, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  action.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAlerts extends StatelessWidget {
  const _EmptyAlerts();
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        const Icon(Icons.notifications_none_rounded, size: 56, color: Color(0xFFB0B4BD)),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Belum ada notifikasi',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
          ),
        ),
        const SizedBox(height: 4),
        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Kalau ada peringatan tentang ritme belajarmu, akan muncul di sini.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Color(0xFFB0B4BD)),
            ),
          ),
        ),
      ],
    );
  }
}
