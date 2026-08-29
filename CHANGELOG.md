# AI Learning Tracker — Changelog v2.0

## Revisi dilakukan pada: Juni 2026

---

## 🔴 Bug Fix Kritis

### 1. Register → OTP Flow (Baru)
**Sebelum:** Setelah registrasi, user langsung diarahkan ke `/baseline` tanpa verifikasi email.  
**Sesudah:** Setelah registrasi, user diarahkan ke halaman `/verify-otp` dengan kode 6-digit. Akun hanya bisa digunakan setelah email diverifikasi.  
**File:** `lib/features/auth/register_screen.dart`, `lib/features/auth/otp_screen.dart` (baru), `lib/core/router/app_router.dart`

### 2. Router Auth Refresh
**Sebelum:** `GoRouter` tidak reaktif terhadap perubahan status autentikasi Supabase.  
**Sesudah:** Ditambahkan `_GoRouterRefreshStream` yang listen ke `onAuthStateChange` dan memanggil `notifyListeners()` → GoRouter otomatis re-evaluate redirect saat login/logout.  
**File:** `lib/core/router/app_router.dart`

### 3. Dashboard Query `target_sessions` Missing
**Sebelum:** Query `learning_goals` tidak menyertakan kolom `target_sessions`, menyebabkan null pointer saat menghitung konsistensi mingguan.  
**Sesudah:** Kolom `target_sessions` ditambahkan ke query.  
**File:** `lib/features/dashboard/providers/dashboard_provider.dart`

### 4. `WillPopScope` Deprecated
**Sebelum:** 5 screen menggunakan `WillPopScope` (deprecated di Flutter 3.12+), menyebabkan warning dan berpotensi break di Flutter terbaru.  
**Sesudah:** Semua diganti dengan `PopScope(canPop: ..., onPopInvokedWithResult: ...)`.  
**File:** `baseline_screen.dart`, `tam_screen.dart`, `focus_session_screen.dart`, `reassessment_screen.dart`, `weekly_reflection_screen.dart`

### 5. Notifikasi Bell Tidak Berfungsi
**Sebelum:** `onPressed: () {}` — tombol notifikasi tidak melakukan apa-apa.  
**Sesudah:** Navigasi ke `/reminders`.  
**File:** `lib/features/dashboard/dashboard_screen.dart`

---

## 🟠 Fitur Baru

### 6. Halaman OTP Verifikasi Email (Baru)
- Input 6-digit OTP dengan auto-focus antar kotak
- Auto-submit ketika digit ke-6 diisi
- Tombol "Kirim Ulang" memanggil `supabase.auth.resend()`
- Error message yang jelas
- Navigasi otomatis ke `/baseline` setelah verifikasi berhasil  
**File:** `lib/features/auth/otp_screen.dart`

### 7. Theme Provider — Mode Gelap Persisten (Baru)
- Preferensi tema disimpan ke `SharedPreferences`
- Toggle light/dark/system dari Settings
- Seluruh app langsung berubah tanpa restart  
**File:** `lib/core/providers/theme_provider.dart`

### 8. Remember Me pada Login
- Email disimpan ke `SharedPreferences` jika dicentang
- Otomatis diisi saat buka halaman login berikutnya  
**File:** `lib/features/auth/login_screen.dart`

---

## 🟡 Perbaikan Penting

### 9. Tema Aplikasi — Comprehensive Rewrite
**Sebelum:** Tema minim, tidak ada `inputDecorationTheme`, teks di TextField samar.  
**Sesudah:** Tema lengkap dengan:
- `inputDecorationTheme` yang proper (filled, borders, hint, label, prefix icon)
- Warna hint/label berbeda di light (`#ADB5BD`) vs dark mode (`rgba(255,255,255,0.38)`)
- `textTheme`, `cardTheme`, `chipTheme`, `snackBarTheme` yang konsisten
- Dark mode card color `#1A1A2E`, fill color `#252542`  
**File:** `lib/shared/themes/app_theme.dart`

### 10. Splash Screen — Animasi
**Sebelum:** Tampilan statis, tidak ada animasi.  
**Sesudah:** Animasi fade-in + scale (elastic out) dengan durasi 1400ms, lalu navigasi setelah 2400ms total.  
**File:** `lib/features/splash/splash_screen.dart`

### 11. Login Screen — Form Validation + UX
- Validasi email format (regex)
- Validasi field kosong
- Error message lebih deskriptif ("Email atau kata sandi salah." untuk `Invalid login`)
- Checkbox "Ingat saya" yang berfungsi
- Password visibility toggle  
**File:** `lib/features/auth/login_screen.dart`

### 12. Register Screen — Full Validation + Password Confirm
- Field konfirmasi kata sandi (match check)
- Validasi email format
- Validasi nama minimal 2 karakter
- Password visibility toggle untuk kedua field  
**File:** `lib/features/auth/register_screen.dart`

### 13. Bottom Navigation — Dark Mode
- Background adapts: `Colors.white` (light) / `#1A1A2E` (dark)
- Icon dan label warna menyesuaikan tema  
**File:** `lib/features/main_shell.dart`

### 14. Dashboard App Bar — Dark Mode
- `backgroundColor` adapts berdasarkan brightness
- Teks nama pengguna dan ikon adapts ke dark mode  
**File:** `lib/features/dashboard/dashboard_screen.dart`

### 15. Settings Screen — Dark Mode Toggle Berfungsi
**Sebelum:** Toggle dark mode adalah state lokal yang tidak melakukan apa-apa.  
**Sesudah:** Toggle memanggil `themeProvider.notifier.toggle()` — perubahan tema langsung berlaku dan persisten.  
**File:** `lib/features/settings/settings_and_about.dart`

### 16. Main — Theme Mode dari Provider
**Sebelum:** `themeMode: ThemeMode.system` hardcoded.  
**Sesudah:** `themeMode: ref.watch(themeProvider)` — bereaksi terhadap pilihan user.  
**File:** `lib/main.dart`

---

## 🗄️ Database (Supabase)

### 17. SQL Migration v2.0 (Baru)
File: `supabase/migrations/v2_schema.sql`

Berisi:
- Schema lengkap semua tabel (`profiles`, `assessment_results`, `learning_goals`, `learning_activities`, `clustering_runs`, `persona_history`, `recommendation_rules`, `recommendations`, `weekly_reflections`, `tam_responses`)
- **Tabel baru:** `reminder_settings`, `app_user_settings`
- **Kolom baru:** `has_completed_baseline` (profiles), `assessment_sequence`, `period_start/end`, `viewed_at/is_dismissed`, `is_latest`
- **Fix Bug:** `v_assessment_delta` — handle multiple T2 dengan `DISTINCT ON`
- **Fix Bug:** `v_weekly_activity_aggregates` — hapus Cartesian product
- RLS Policies untuk semua tabel
- Indexes untuk performa query
- Triggers: `handle_new_user`, `set_assessment_sequence`, `mark_baseline_completed`, `update_goal_progress`, `reset_latest_clustering_run`

---

## 📁 File Baru

| File | Deskripsi |
|------|-----------|
| `lib/features/auth/otp_screen.dart` | Halaman verifikasi OTP 6-digit |
| `lib/core/providers/theme_provider.dart` | Provider untuk dark/light mode |
| `supabase/migrations/v2_schema.sql` | Full SQL schema dengan semua fixes |

## 📝 File Diubah

| File | Perubahan Utama |
|------|----------------|
| `lib/main.dart` | Integrasi themeProvider |
| `lib/shared/themes/app_theme.dart` | Comprehensive rewrite |
| `lib/features/splash/splash_screen.dart` | Animasi fade + scale |
| `lib/features/auth/login_screen.dart` | Validation, remember me, dark mode |
| `lib/features/auth/register_screen.dart` | OTP flow, password confirm, validation |
| `lib/core/router/app_router.dart` | OTP route, auth refresh, error page |
| `lib/features/main_shell.dart` | Dark mode bottom nav |
| `lib/features/dashboard/dashboard_screen.dart` | Dark mode appbar, notif bell fix |
| `lib/features/dashboard/providers/dashboard_provider.dart` | Fix target_sessions query |
| `lib/features/settings/settings_and_about.dart` | Dark mode toggle berfungsi |
| `lib/features/baseline/baseline_screen.dart` | WillPopScope → PopScope |
| `lib/features/tam/tam_screen.dart` | WillPopScope → PopScope |
| `lib/features/activity/focus_session_screen.dart` | WillPopScope → PopScope |
| `lib/features/reassessment/reassessment_screen.dart` | WillPopScope → PopScope |
| `lib/features/reflection/weekly_reflection_screen.dart` | WillPopScope → PopScope |

---

## ⚙️ Setup Setelah Revisi

### 1. Konfigurasi Supabase
Edit file: `lib/core/constants/supabase_constants.dart`
```dart
static const String supabaseUrl     = 'https://YOUR_PROJECT.supabase.co';
static const String supabaseAnonKey = 'YOUR_ANON_KEY';
```

### 2. Jalankan SQL Migration
Buka Supabase Dashboard → SQL Editor → paste isi `supabase/migrations/v2_schema.sql` → Run

### 3. Konfigurasi Email OTP di Supabase
Dashboard → Authentication → Email Templates:
- Pastikan template "Confirm signup" menggunakan `{{ .Token }}` (bukan link)
- Atau di Authentication → Settings → aktifkan "Enable email confirmations"

### 4. Deploy Edge Function
```bash
supabase functions deploy run-kmeans
```

### 5. Jalankan Aplikasi
```bash
flutter pub get
flutter run
```

