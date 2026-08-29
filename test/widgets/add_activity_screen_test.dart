// test/widgets/add_activity_screen_test.dart
//
// Catatan: AddActivityScreen mem-watch `addActivityProvider`, yang notifier-nya
// membuat instance ActivityService() secara langsung. ActivityService membaca
// Supabase.instance.client sebagai field, sehingga Supabase HARUS sudah
// di-inisialisasi (walau dengan kredensial dummy, tanpa memanggil jaringan
// sama sekali) sebelum widget ini bisa di-build di lingkungan test.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_learning_tracker/features/activity/add_activity_screen.dart';
import 'package:ai_learning_tracker/features/goals/providers/goal_provider.dart';
import 'package:ai_learning_tracker/models/learning_goal.dart';

final _fakeActiveGoal = LearningGoal(
  id: 'goal-1',
  userId: 'user-1',
  title: 'Selesaikan Bab 3 Skripsi',
  category: 'Penelitian',
  periodStart: DateTime(2026, 7, 1),
  periodEnd: DateTime(2026, 7, 31),
  targetSessions: 10,
  targetDurationMinutes: 300,
  targetProgress: 100,
  status: 'active',
  actualSessions: 2,
  actualProgress: 20,
  createdAt: DateTime(2026, 7, 1),
);

Widget _buildScreen() => ProviderScope(
      overrides: [
        activeGoalsProvider.overrideWithValue([_fakeActiveGoal]),
      ],
      child: const MaterialApp(home: AddActivityScreen()),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // Kredensial dummy — tidak pernah melakukan panggilan jaringan nyata
    // karena test ini tidak memicu aksi simpan/login apa pun.
    await Supabase.initialize(
      url: 'https://dummy-project.supabase.co',
      anonKey: 'dummy-anon-key-for-widget-test',
    );
  });

  group('AddActivityScreen — dropdown "Hubungkan dengan Target Belajar"', () {
    testWidgets(
        'tidak overflow saat menampilkan teks default panjang di lebar layar sempit',
        (tester) async {
      // Meniru lebar layar HP di screenshot bug (~360dp) — bug lama hanya
      // muncul saat lebar terbatas, layar test default (800px) terlalu lebar
      // untuk mereproduksinya.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('-- Tidak Ada Hubungan Target --'), findsOneWidget);
      // Ini adalah inti regression test-nya: sebelum diperbaiki, baris di atas
      // memicu error "RenderFlex overflowed" karena dropdown tidak
      // isExpanded dan teksnya tidak diberi overflow ellipsis.
      expect(tester.takeException(), isNull);
    });

    testWidgets('menampilkan target belajar aktif sebagai pilihan di dropdown',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('-- Tidak Ada Hubungan Target --'));
      await tester.pumpAndSettle();

      expect(find.text('Selesaikan Bab 3 Skripsi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
