// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/splash/splash_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/auth/reset_password_otp_screen.dart';
import '../../features/baseline/baseline_screen.dart';
import '../../features/baseline/baseline_result_screen.dart';
import '../../features/main_shell.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/goals/goal_list_screen.dart';
import '../../models/learning_goal.dart';
import '../../features/activity/add_activity_screen.dart';
import '../../features/activity/focus_session_screen.dart';
import '../../features/persona/persona_screen.dart';
import '../../features/recommendation/recommendation_screen.dart';
import '../../features/reflection/weekly_reflection_screen.dart';
import '../../features/reassessment/reassessment_screen.dart';
import '../../features/progress/progress_evaluation_screen.dart';
import '../../features/tam/tam_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/notifications/notification_screen.dart';
import '../../features/notifications/monitoring_alert_screen.dart';
import '../../features/settings/settings_and_about.dart';

// Saklar global: selama proses reset password (OTP -> password baru)
// berlangsung, SEMUA logika redirect di bawah diblokir total, apa pun
// state login yang terdeteksi. Ini lebih pasti dibanding mengandalkan
// pencocokan `state.matchedLocation`, karena tidak bergantung pada
// timing/urutan evaluasi redirect GoRouter sama sekali.
bool kIsPasswordRecoveryInProgress = false;

// ── Auth-change listenable so GoRouter refreshes on auth events ──

class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _GoRouterRefreshStream();

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshListenable,
    redirect: (context, state) async {
      // Cek paling pertama, sebelum apa pun lain dievaluasi.
      if (kIsPasswordRecoveryInProgress) {
        debugPrint('[ROUTER] Blokir total: proses reset password sedang berlangsung.');
        return null;
      }

      final sb         = Supabase.instance.client;
      final session    = sb.auth.currentSession;
      final isLoggedIn = session != null;
      final loc        = state.matchedLocation;

      final onAuth   = loc == '/login' || loc == '/register' ||
                       loc == '/forgot-password' || loc == '/verify-otp';
      final onSplash = loc == '/splash';
      final isResetPasswordFlow = loc == '/reset-password-otp';

      debugPrint('[ROUTER] loc=$loc isLoggedIn=$isLoggedIn '
          'isResetPasswordFlow=$isResetPasswordFlow onAuth=$onAuth');

      if (onSplash) return null;
      if (isResetPasswordFlow) {
        debugPrint('[ROUTER] Mengecualikan /reset-password-otp, tidak redirect.');
        return null;
      }

      // 1. Belum login → ke Login
      if (!isLoggedIn && !onAuth) return '/login';

      // 2. Sudah login
      if (isLoggedIn) {
        try {
          final rows = await sb
              .from('assessment_results')
              .select('id')
              .eq('user_id', session.user.id)
              .eq('assessment_type', 'baseline')
              .limit(1);
          final done = (rows as List).isNotEmpty;

          // Di halaman auth (login/register/otp) → arahkan sesuai status baseline
          if (onAuth) return done ? '/dashboard' : '/baseline';

          // Di halaman lain selain baseline → pastikan baseline sudah diisi
          if (!loc.startsWith('/baseline') && !done) return '/baseline';

          // Guard tambahan: /reassessment hanya boleh diakses jika gerbang
          // 7-hari sudah terbuka DAN belum pernah diisi (single-cycle).
          // Ini lapisan kedua di sisi klien; validasi definitif tetap ada
          // di trigger DB (validate_reassessment_timing, migrasi v3),
          // jadi percobaan bypass lewat deep-link tetap akan ditolak DB.
          if (loc == '/reassessment') {
            try {
              final gateRow = await sb
                  .from('v_reassessment_gate')
                  .select('can_reassess, has_reassessed')
                  .eq('user_id', session.user.id)
                  .maybeSingle();
              final canReassess = gateRow?['can_reassess'] as bool? ?? false;
              final hasReassessed = gateRow?['has_reassessed'] as bool? ?? false;
              if (!canReassess || hasReassessed) return '/progress';
            } catch (_) {
              // Kalau gagal cek gate, biarkan lolos ke UI — trigger DB
              // tetap akan menolak insert yang tidak sah.
            }
          }

        } catch (e) {
          // Session tidak valid → sign out → ke login
          final errStr = e.toString().toLowerCase();
          if (errStr.contains('jwt') || errStr.contains('invalid') ||
              errStr.contains('unauthorized') || errStr.contains('not found')) {
            await sb.auth.signOut();
            return '/login';
          }
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash',          builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login',           builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register',        builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/reset-password-otp',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final email = extra?['email'] as String? ?? '';
          return ResetPasswordOtpScreen(email: email);
        },
      ),
      GoRoute(
        path: '/verify-otp',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final email = extra?['email'] as String? ?? '';
          return OtpScreen(email: email);
        },
      ),
      GoRoute(
        path: '/baseline',
        builder: (_, __) => const BaselineScreen(),
        routes: [
          GoRoute(path: 'result', builder: (_, __) => const BaselineResultScreen()),
        ],
      ),
      ShellRoute(
        builder: (ctx, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (_, __) => const NoTransitionPage(child: DashboardScreen()),
          ),
          GoRoute(
            path: '/activity',
            pageBuilder: (_, __) => const NoTransitionPage(child: ActivityHistoryScreen()),
            routes: [
              GoRoute(path: 'add', builder: (_, __) => const AddActivityScreen()),
            ],
          ),
          GoRoute(path: '/focus-session', builder: (_, __) => const FocusSessionScreen()),
          GoRoute(
            path: '/goals',
            builder: (_, __) => const GoalListScreen(),
            routes: [
              GoRoute(path: 'add', builder: (_, __) => const AddGoalScreen()),
              GoRoute(
                path: 'edit',
                builder: (_, state) =>
                    AddGoalScreen(goal: state.extra as LearningGoal?),
              ),
            ],
          ),
          GoRoute(
            path: '/persona',
            pageBuilder: (_, __) => const NoTransitionPage(child: PersonaScreen()),
          ),
          GoRoute(
            path: '/recommendation',
            pageBuilder: (_, __) => const NoTransitionPage(child: RecommendationScreen()),
          ),
          GoRoute(path: '/reflection',   builder: (_, __) => const WeeklyReflectionScreen()),
          GoRoute(path: '/reassessment', builder: (_, __) => const ReassessmentScreen()),
          GoRoute(path: '/progress',     builder: (_, __) => const ProgressEvaluationScreen()),
          GoRoute(path: '/tam',          builder: (_, __) => const TamEvaluationScreen()),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, __) => const NoTransitionPage(child: ProfileScreen()),
            routes: [
              GoRoute(path: 'edit', builder: (_, __) => const EditProfileScreen()),
            ],
          ),
          GoRoute(path: '/reminders', builder: (_, __) => const NotificationScreen()),
          GoRoute(path: '/monitoring', builder: (_, __) => const MonitoringAlertScreen()),
          GoRoute(path: '/settings',  builder: (_, __) => const SettingsScreen()),
          GoRoute(path: '/about',     builder: (_, __) => const AboutScreen()),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Halaman tidak ditemukan: ${state.uri}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Kembali ke Beranda'),
            ),
          ],
        ),
      ),
    ),
  );
});