// lib/core/constants/supabase_constants.dart
//
// ⚠️  WAJIB DIISI sebelum flutter run!
// Cara dapat nilai:
//   Supabase Dashboard → Project Settings → API
//   - Project URL  → isi ke supabaseUrl
//   - anon public  → isi ke supabaseAnonKey

class SupabaseConstants {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  // contoh: 'https://abcdefgh.supabase.co'

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  // contoh: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'
}
