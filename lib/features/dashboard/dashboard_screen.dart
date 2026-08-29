// lib/features/dashboard/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/dashboard_provider.dart';
import 'widgets/weekly_progress_card.dart';
import 'widgets/dashboard_cards.dart';

const _primaryPurple = Color(0xFF5C4DFF);
const _bgColor = Color(0xFFF5F7FA);

// Flag agar popup pengingat SRL Reassessment hanya muncul sekali per
// sesi aplikasi (tidak muncul berulang setiap kali Dashboard di-refresh).
final _reassessmentPopupShownProvider = StateProvider<bool>((ref) => false);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);

    return Scaffold(
      backgroundColor: _bgColor,
      body: state.when(
        loading: () => const _DashboardSkeleton(),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.read(dashboardProvider.notifier).refresh(),
        ),
        data: (data) {
          final popupShown = ref.watch(_reassessmentPopupShownProvider);
          if (!popupShown && (data.reassessmentGate?.isAvailable ?? false)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(_reassessmentPopupShownProvider.notifier).state = true;
              _showReassessmentReminder(context);
            });
          }
          return _DashboardContent(data: data, ref: ref);
        },
      ),
      floatingActionButton: _FabMenu(),
    );
  }

  // Popup: muncul sekali ketika 28 hari sejak Baseline sudah tercapai
  // dan SRL Reassessment (T2) belum diisi (BAB 3.4.1 hasil revisi).
  void _showReassessmentReminder(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.psychology_alt_rounded,
            color: _primaryPurple, size: 36),
        title: const Text('Evaluasi Perkembangan Siap Diisi',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: const Text(
          'Empat minggu sejak Penilaian Awal Anda telah selesai. Yuk isi Penilaian Ulang '
          'Regulasi Diri untuk melihat perkembanganmu.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Nanti Saja'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.push('/progress');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Isi Sekarang'),
          ),
        ],
      ),
    );
  }
}

// ── Content ────────────────────────────────────────────────────

class _DashboardContent extends StatelessWidget {
  final DashboardData data;
  final WidgetRef ref;
  const _DashboardContent({required this.data, required this.ref});

  String _greeting() {
    final h = DateTime.now().hour;
    // 04.00–10.59 Pagi, 11.00–14.59 Siang, 15.00–17.59 Sore,
    // sisanya (18.00–03.59, termasuk tengah malam/dini hari) Malam.
    if (h >= 4 && h < 11) return 'SELAMAT PAGI';
    if (h >= 11 && h < 15) return 'SELAMAT SIANG';
    if (h >= 15 && h < 18) return 'SELAMAT SORE';
    return 'SELAMAT MALAM';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _primaryPurple,
      onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
      child: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────
          SliverAppBar(
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1A1A2E)
                : Colors.white,
            elevation: 0,
            floating: true,
            snap: true,
            automaticallyImplyLeading: false,
            toolbarHeight: 70,
            title: Row(
              children: [
                // Avatar + today duration badge
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: _primaryPurple.withOpacity(0.1),
                      backgroundImage: data.avatarUrl != null
                          ? NetworkImage(data.avatarUrl!)
                          : null,
                      child: data.avatarUrl == null
                          ? Text(
                              data.userName.isNotEmpty
                                  ? data.userName[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: _primaryPurple,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            )
                          : null,
                    ),
                    if (data.todayDurationMinutes > 0)
                      Positioned(
                        bottom: 0,
                        right: -2,
                        child: Tooltip(
                          message:
                              'Total durasi belajar hari ini: ${data.todayDurationMinutes} menit',
                          triggerMode: TooltipTriggerMode.tap,
                          textStyle: const TextStyle(
                              fontSize: 12, color: Colors.white),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A2E),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A2E),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${data.todayDurationMinutes}M',
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5),
                    ),
                    Text(
                      'Halo, ${data.userName.split(' ').first} 👋',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : const Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.notifications_outlined,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF1A1A2E)),
                tooltip: 'Peringatan Progres',
                onPressed: () => context.push('/monitoring'),
              ),
              IconButton(
                icon: Icon(Icons.settings_outlined,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF1A1A2E)),
                onPressed: () => context.push('/settings'),
              ),
              const SizedBox(width: 4),
            ],
          ),

          // ── Body Cards ───────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 1. Weekly Progress (gradient card)
                WeeklyProgressCard(data: data),
                const SizedBox(height: 14),

                // 2. SRL Score
                SrlScoreCard(data: data),
                const SizedBox(height: 14),

                // 3. Persona Preview
                PersonaPreviewCard(data: data),
                const SizedBox(height: 14),

                // 4. Streak
                StreakCard(data: data),
                const SizedBox(height: 14),

                // 5. Today's Goals
                TodayGoalsCard(data: data),
                const SizedBox(height: 14),

                // 6. Quick Stats Row
                QuickStatsRow(data: data),
                const SizedBox(height: 14),

                // 7. Weekly Chart
                WeeklyChartCard(data: data),
                const SizedBox(height: 14),

                // 8. AI Insights
                if (data.aiInsights.isNotEmpty)
                  AiInsightsCardSimple(data: data),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── FAB ────────────────────────────────────────────────────────

class _FabMenu extends StatefulWidget {
  @override
  State<_FabMenu> createState() => _FabMenuState();
}

class _FabMenuState extends State<_FabMenu>
    with SingleTickerProviderStateMixin {
  bool _open = false;
  late final AnimationController _ctrl;
  late final Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _rotate = Tween<double>(begin: 0, end: 0.375)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_open) ...[
          _FabOption(
            icon: Icons.timer_outlined,
            label: 'Sesi Fokus',
            color: const Color(0xFF4ECDC4),
            onTap: () {
              _toggle();
              context.push('/focus-session');
            },
          ),
          const SizedBox(height: 10),
          _FabOption(
            icon: Icons.add_task_rounded,
            label: 'Tambah Aktivitas',
            color: _primaryPurple,
            onTap: () {
              _toggle();
              context.push('/activity/add');
            },
          ),
          const SizedBox(height: 10),
        ],
        FloatingActionButton(
          onPressed: _toggle,
          backgroundColor: _primaryPurple,
          elevation: 4,
          child: RotationTransition(
            turns: _rotate,
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }
}

class _FabOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _FabOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 22,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }
}

// ── Skeleton Loading ───────────────────────────────────────────

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
      child: Column(
        children: List.generate(
          4,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _Shimmer(height: i == 0 ? 220 : 100),
          ),
        ),
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  final double height;
  const _Shimmer({required this.height});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _anim = Tween<double>(begin: -1, end: 2)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value, 0),
            colors: const [
              Color(0xFFE5E7EB),
              Color(0xFFF3F4F6),
              Color(0xFFE5E7EB),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Error View ─────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat data',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Periksa koneksi internet dan coba lagi.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
