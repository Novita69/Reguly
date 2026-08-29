// lib/services/activity_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/learning_activity.dart';

/// Dilempar saat durasi aktivitas berada di luar batas bisnis yang
/// diizinkan. Dipisah dari error jaringan/Supabase lain supaya provider
/// bisa menampilkan pesannya langsung ke pengguna, mengikuti pola yang
/// sama dengan GoalValidationException di goal_service.dart.
class ActivityValidationException implements Exception {
  final String message;
  ActivityValidationException(this.message);
  @override
  String toString() => message;
}

class ActivityService {
  final _sb = Supabase.instance.client;
  String get _uid => _sb.auth.currentUser!.id;

  // Harus tetap sinkron dengan:
  //  - batas UI di AddActivityScreen (add_activity_screen.dart)
  //  - CHECK constraint di migration
  //    20260727100000_activity_duration_and_single_active_goal.sql
  static const int kMinDurationMinutes = 1;
  static const int kMaxDurationMinutes = 120;

  /// Validasi sisi klien (fail-fast, sebelum panggilan network) sebagai
  /// lapisan pertahanan kedua di luar batas form UI. Validasi final &
  /// tidak bisa dilewati tetap ada di server (CHECK constraint DB).
  void _validateDuration(int durationMinutes) {
    if (durationMinutes < kMinDurationMinutes ||
        durationMinutes > kMaxDurationMinutes) {
      throw ActivityValidationException(
          'Durasi aktivitas harus di antara $kMinDurationMinutes dan '
          '$kMaxDurationMinutes menit (nilai: $durationMinutes). Jika '
          'aktivitasmu lebih lama, catat sebagai aktivitas terpisah.');
    }
  }

  // ── Ambil riwayat dengan filter ────────────────────────────
  Future<List<LearningActivity>> getActivities({
    String filter = 'all', // 'all'|'today'|'week'|'month'
    String? search,
    String? category,
  }) async {
    var query = _sb
        .from('learning_activities')
        .select()
        .eq('user_id', _uid);

    final now = DateTime.now();
    if (filter == 'today') {
      query = query.eq('activity_date', _dateStr(now));
    } else if (filter == 'week') {
      final monday = now.subtract(Duration(days: now.weekday - 1));
      query = query
          .gte('activity_date', _dateStr(monday))
          .lte('activity_date', _dateStr(now));
    } else if (filter == 'month') {
      final firstDay = DateTime(now.year, now.month, 1);
      query = query
          .gte('activity_date', _dateStr(firstDay))
          .lte('activity_date', _dateStr(now));
    }

    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }

    final res = await query.order('created_at', ascending: false);
    var list = (res as List).map((e) => LearningActivity.fromMap(e)).toList();

    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      list = list.where((a) =>
          a.activityName.toLowerCase().contains(q) ||
          (a.notes?.toLowerCase().contains(q) ?? false)).toList();
    }
    return list;
  }

  // ── Simpan aktivitas baru ──────────────────────────────────
  Future<LearningActivity> saveActivity({
    String? goalId,
    required String activityName,
    required String category,
    required DateTime activityDate,
    String? startTime,
    required int durationMinutes,
    required int focusScore,
    required double progressPercent,
    String? notes,
    String sourceType = 'manual',
  }) async {
    _validateDuration(durationMinutes);
    final res = await _sb.from('learning_activities').insert({
      'user_id': _uid,
      if (goalId != null) 'goal_id': goalId,
      'activity_name': activityName,
      'category': category,
      'activity_date': _dateStr(activityDate),
      if (startTime != null) 'start_time': startTime,
      'duration_minutes': durationMinutes,
      'focus_score': focusScore,
      'progress_percent': progressPercent,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'source_type': sourceType,
    }).select().single();
    return LearningActivity.fromMap(res);
  }

  Future<void> deleteActivity(String id) async {
    await _sb.from('learning_activities')
        .delete()
        .eq('id', id)
        .eq('user_id', _uid);
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
