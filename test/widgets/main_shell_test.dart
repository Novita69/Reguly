// test/widgets/main_shell_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_learning_tracker/features/main_shell.dart';

/// Router uji minimal yang meniru struktur ShellRoute pada app_router.dart
/// asli, tapi dengan layar placeholder ringan (tanpa Supabase) supaya
/// MainShell bisa diuji terisolasi.
GoRouter _buildTestRouter({String initialLocation = '/dashboard'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const Text('Dashboard Screen'),
          ),
          GoRoute(
            path: '/activity',
            builder: (_, __) => const Text('Activity Screen'),
          ),
          GoRoute(
            path: '/goals',
            builder: (_, __) => const Text('Goals Screen'),
            routes: [
              GoRoute(
                path: 'add',
                builder: (_, __) => const Text('Add Goal Screen'),
              ),
            ],
          ),
          GoRoute(
            path: '/recommendation',
            builder: (_, __) => const Text('Recommendation Screen'),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const Text('Profile Screen'),
          ),
        ],
      ),
    ],
  );
}

Widget _buildApp({String initialLocation = '/dashboard'}) {
  return MaterialApp.router(
    routerConfig: _buildTestRouter(initialLocation: initialLocation),
  );
}

void main() {
  group('MainShell bottom navigation', () {
    testWidgets('menampilkan kelima label tab, termasuk "Goal" (bukan "Persona")',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Beranda'), findsOneWidget);
      expect(find.text('Aktivitas'), findsOneWidget);
      expect(find.text('Goal'), findsOneWidget);
      expect(find.text('Rekomendasi'), findsOneWidget);
      expect(find.text('Profil'), findsOneWidget);
      expect(find.text('Persona'), findsNothing);
    });

    testWidgets('menampilkan ikon target (track_changes) untuk tab Goal',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.track_changes_outlined), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome_outlined), findsNothing);
    });

    testWidgets('menekan tab Goal menavigasi ke layar Daftar Target (/goals)',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Dashboard Screen'), findsOneWidget);

      await tester.tap(find.text('Goal'));
      await tester.pumpAndSettle();

      expect(find.text('Goals Screen'), findsOneWidget);
      expect(find.text('Dashboard Screen'), findsNothing);
    });

    testWidgets('tab Goal tetap tersorot aktif pada sub-rute /goals/add',
        (tester) async {
      await tester.pumpWidget(_buildApp(initialLocation: '/goals/add'));
      await tester.pumpAndSettle();

      expect(find.text('Add Goal Screen'), findsOneWidget);

      final icon = tester.widget<Icon>(find.byIcon(Icons.track_changes_outlined));
      // _primaryPurple di main_shell.dart adalah Color(0xFF5C4DFF).
      expect(icon.color, const Color(0xFF5C4DFF));
    });

    testWidgets('menekan tab Aktivitas menavigasi ke /activity', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aktivitas'));
      await tester.pumpAndSettle();

      expect(find.text('Activity Screen'), findsOneWidget);
    });

    testWidgets('menekan tab Profil menavigasi ke /profile', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();

      expect(find.text('Profile Screen'), findsOneWidget);
    });
  });
}
