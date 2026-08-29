import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  final _supabase = Supabase.instance.client;

  // Ambil profil berdasarkan user ID yang sedang login
  Future<Map<String, dynamic>?> getProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final response =
        await _supabase.from('profiles').select().eq('id', userId).single();

    return response;
  }

  // Update profil — hanya kolom yang ada di tabel profiles
  Future<void> updateProfile({
    required String fullName,
    String? institution,
    String? studyProgram,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User belum login');

    await _supabase.from('profiles').upsert({
      'id': userId,
      'full_name': fullName,
      'institution': institution,
      'study_program': studyProgram,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // Email diambil dari sesi auth, BUKAN dari tabel profiles
  String? getCurrentEmail() {
    return _supabase.auth.currentUser?.email;
  }
}
