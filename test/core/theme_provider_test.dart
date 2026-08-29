// test/core/theme_provider_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_learning_tracker/core/providers/theme_provider.dart';

// Key ini harus sama persis dengan _kThemeKey privat di theme_provider.dart
const _kThemeKey = 'app_theme_mode';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ThemeNotifier memulai _load() secara async langsung di constructor-nya,
  // tapi provider Riverpod itu LAZY — ThemeNotifier baru benar-benar dibuat
  // saat pertama kali di-`read`/`watch`, bukan saat ProviderContainer()
  // dipanggil. Jadi urutannya harus: (1) baca provider dulu supaya
  // constructor-nya jalan dan _load() mulai, BARU (2) pumpEventQueue() untuk
  // menunggu Future itu selesai — sebelum `addTearDown` men-dispose
  // container. Kalau urutannya terbalik (pump dulu baru baca), _load() belum
  // sempat mulai sama sekali saat kita "menunggu", dan racing terhadap
  // dispose tetap terjadi ("Bad state: Tried to use ThemeNotifier after
  // `dispose` was called").
  Future<ProviderContainer> createSettledContainer() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(themeProvider); // memicu constructor + _load() mulai jalan
    await pumpEventQueue(); // tunggu _load() benar-benar selesai
    return container;
  }

  test('state awal adalah ThemeMode.system sebelum preferensi dimuat', () async {
    SharedPreferences.setMockInitialValues({});
    final container = await createSettledContainer();

    expect(container.read(themeProvider), ThemeMode.system);
  });

  test('memuat ThemeMode.dark dari SharedPreferences yang tersimpan', () async {
    SharedPreferences.setMockInitialValues({_kThemeKey: 'dark'});
    final container = await createSettledContainer();

    expect(container.read(themeProvider), ThemeMode.dark);
  });

  test('memuat ThemeMode.light dari SharedPreferences yang tersimpan', () async {
    SharedPreferences.setMockInitialValues({_kThemeKey: 'light'});
    final container = await createSettledContainer();

    expect(container.read(themeProvider), ThemeMode.light);
  });

  test('nilai tersimpan yang tidak dikenal jatuh ke ThemeMode.system', () async {
    SharedPreferences.setMockInitialValues({_kThemeKey: 'sesuatu_yang_aneh'});
    final container = await createSettledContainer();

    expect(container.read(themeProvider), ThemeMode.system);
  });

  test('setTheme memperbarui state dan menyimpannya ke SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final container = await createSettledContainer();

    await container.read(themeProvider.notifier).setTheme(ThemeMode.dark);

    expect(container.read(themeProvider), ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_kThemeKey), 'dark');
  });

  test('toggle membalik antara dark dan light', () async {
    SharedPreferences.setMockInitialValues({});
    final container = await createSettledContainer();

    await container.read(themeProvider.notifier).setTheme(ThemeMode.light);
    await container.read(themeProvider.notifier).toggle();
    expect(container.read(themeProvider), ThemeMode.dark);

    await container.read(themeProvider.notifier).toggle();
    expect(container.read(themeProvider), ThemeMode.light);
  });

  test('toggle dari ThemeMode.system (default) berpindah ke dark', () async {
    SharedPreferences.setMockInitialValues({});
    final container = await createSettledContainer();

    // state awal system (bukan dark) -> toggle akan menghasilkan dark
    await container.read(themeProvider.notifier).toggle();
    expect(container.read(themeProvider), ThemeMode.dark);
  });
}
