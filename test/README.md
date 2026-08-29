# Test suite — AI Learning Tracker

Test ini dibuat dari nol (project sebelumnya belum punya folder `test/`).

## Cara menjalankan

```
flutter test
```

## Isi

### `test/models/` — unit test murni (tanpa Flutter widget, tanpa Supabase)
- `learning_activity_test.dart` — parsing `fromMap`, default value, emoji/label fokus, format tanggal.
- `learning_goal_test.dart` — parsing `fromMap`, `sessionProgressFraction`, `isCompleted`, `isOverdue`, `progressLabel`.
- `assessment_result_test.dart` — parsing 12 item jawaban, kategori skor (Tinggi/Sedang/Rendah), dimensi terkuat/terlemah, teks interpretasi & saran strategis.
- `persona_info_test.dart` — parsing `fromMap`, konten tampilan (nama, deskripsi, ciri, kekuatan, tips AI, warna) untuk tiap label persona.
- `recommendation_test.dart` — parsing `fromMap`, `dimensionDisplay`, `priorityDisplay`, `copyWith`.

### `test/core/`
- `theme_provider_test.dart` — `ThemeNotifier` (Riverpod): state awal, memuat preferensi tersimpan, `setTheme`, `toggle`. Pakai `SharedPreferences.setMockInitialValues`, tidak butuh Supabase.

### `test/widgets/`
- `main_shell_test.dart` — bottom navigation bar: label & ikon kelima tab (termasuk perubahan Persona → Goal, ikon `track_changes_outlined`), navigasi tab (termasuk Goal → `/goals`), highlight tab aktif di sub-rute `/goals/add`.
- `add_activity_screen_test.dart` — **regression test** untuk bug overflow dropdown "Hubungkan dengan Target Belajar" yang sudah diperbaiki. Mensimulasikan lebar layar sempit (360dp, seperti di screenshot bug) dan memastikan tidak ada exception overflow saat teks default panjang ditampilkan.

## Catatan penting

- `add_activity_screen_test.dart` meng-inisialisasi `Supabase.initialize()` dengan kredensial dummy di `setUpAll`, karena `AddActivityScreen` membaca `Supabase.instance.client` lewat provider-nya walau tidak melakukan panggilan jaringan apa pun selama test ini berjalan (tidak ada aksi simpan/login yang dipicu).
- Saya tidak punya akses Flutter/Dart SDK di lingkungan kerja saya untuk menjalankan `flutter test` secara langsung, jadi test ini belum saya verifikasi jalan 100% mulus di mesin kamu. Kalau ada test yang gagal saat dijalankan, kirim pesan errornya ke saya dan saya bantu perbaiki.
