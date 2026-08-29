# AI Learning Tracker

Aplikasi Flutter untuk membantu pengguna melacak aktivitas belajar, target, dan progres pembelajaran, dengan backend menggunakan Supabase.

## 📋 Prasyarat

Sebelum menjalankan project ini, pastikan sudah terinstall:

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (versi stabil terbaru)
- [Dart SDK](https://dart.dev/get-dart) (sudah termasuk dalam Flutter SDK)
- Android Studio / VS Code dengan plugin Flutter & Dart
- Akun [Supabase](https://supabase.com) (gratis) untuk backend

## 🔑 Setup Environment (WAJIB sebelum menjalankan app)

Project ini **tidak menyimpan credential Supabase langsung di dalam kode** demi keamanan. Kamu perlu membuat konfigurasi sendiri sebelum bisa menjalankan aplikasi ini.

### 1. Buat project Supabase (kalau belum punya)

1. Buka [supabase.com](https://supabase.com) → buat project baru
2. Masuk ke **Project Settings → API**
3. Catat dua nilai berikut:
   - **Project URL**
   - **anon public key**

### 2. Buat file `dart_define.json`

Di **root folder project** (sejajar dengan `pubspec.yaml`), buat file baru bernama `dart_define.json`:

```json
{
  "SUPABASE_URL": "https://xxxxx.supabase.co",
  "SUPABASE_ANON_KEY": "eyJhbGciOi..."
}
```

Ganti nilainya dengan URL dan anon key dari project Supabase kamu sendiri.

> ⚠️ File ini **sengaja tidak ikut di-upload ke repository** ini (ada di `.gitignore`) karena berisi credential. Setiap orang yang menjalankan project ini wajib membuat filenya sendiri.

### 3. Setup skema database

Import seluruh file SQL yang ada di folder `supabase/migrations/` ke project Supabase kamu secara berurutan (sesuai urutan tanggal di nama file), lewat **SQL Editor** di dashboard Supabase.

### 4. (Opsional) Setup Firebase untuk push notification

Kalau ingin fitur push notification (FCM) berfungsi, kamu perlu:
- Membuat project Firebase sendiri
- Menaruh `google-services.json` di `android/app/`
- Menaruh `GoogleService-Info.plist` di `ios/Runner/`

File-file ini juga tidak ikut di-upload karena berisi konfigurasi spesifik per project.

## 🚀 Menjalankan Aplikasi

Install dependencies:

```bash
flutter pub get
```

Jalankan aplikasi dengan menyertakan file konfigurasi:

```bash
flutter run --dart-define-from-file=dart_define.json
```

Untuk build APK release:

```bash
flutter build apk --dart-define-from-file=dart_define.json
```

> 💡 Kalau menjalankan tanpa flag `--dart-define-from-file`, aplikasi akan gagal terhubung ke Supabase karena URL dan key akan kosong.

## 📁 Struktur Project

```
lib/
├── core/           # Constants, providers, routing
├── features/       # Fitur-fitur aplikasi (auth, dashboard, goals, dll)
├── models/         # Model data
├── services/       # Service layer untuk komunikasi dengan Supabase
└── shared/         # Widget/tema yang dipakai bersama

supabase/
├── functions/      # Edge Functions (server-side logic)
└── migrations/     # Skema database (SQL)
```

## 🛠️ Tech Stack

- **Frontend**: Flutter
- **Backend**: Supabase (PostgreSQL, Auth, Edge Functions)
- **Push Notification**: Firebase Cloud Messaging (FCM)

## 📄 Lisensi

Project ini dibuat untuk keperluan tugas kuliah.
