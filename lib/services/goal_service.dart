// lib/services/goal_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/learning_goal.dart';

/// Dilempar saat target goal berada di luar batas bisnis yang diizinkan.
/// Dipisah dari error jaringan/Supabase lain supaya provider bisa
/// menampilkan pesannya langsung ke pengguna (lihat goal_provider.dart).
class GoalValidationException implements Exception {
  final String message;
  GoalValidationException(this.message);
  @override
  String toString() => message;
}

class GoalService {
  final _sb = Supabase.instance.client;
  String get _uid => _sb.auth.currentUser!.id;

  // Harus tetap sinkron dengan:
  //  - batas UI di AddGoalScreen (goal_list_screen.dart)
  //  - trigger + CHECK constraint di migration
  //    20260724090000_goal_target_limits.sql
  static const int kMaxTargetSessions = 7;
  static const int kMinTargetSessions = 1;
  static const int kMaxTargetDurationMinutes = 120;
  static const int kMinTargetDurationMinutes = 5;

  /// Validasi sisi klien (fail-fast, sebelum panggilan network) sebagai
  /// lapisan pertahanan kedua di luar batas stepper UI. Ini melindungi dari
  /// kasus seperti pemanggilan GoalService dari jalur lain (mis. test,
  /// deep link, refactor UI di masa depan) yang lupa memakai stepper yang
  /// sudah dibatasi. Validasi final & tidak bisa dilewati tetap ada di
  /// server (trigger) dan database (CHECK constraint).
  void _validateTargets({
    required int targetSessions,
    required int targetDurationMinutes,
  }) {
    if (targetSessions < kMinTargetSessions ||
        targetSessions > kMaxTargetSessions) {
      throw GoalValidationException(
          'Target sesi harus di antara $kMinTargetSessions dan '
          '$kMaxTargetSessions (nilai: $targetSessions).');
    }
    if (targetDurationMinutes < kMinTargetDurationMinutes ||
        targetDurationMinutes > kMaxTargetDurationMinutes) {
      throw GoalValidationException(
          'Target durasi harus di antara $kMinTargetDurationMinutes dan '
          '$kMaxTargetDurationMinutes menit (nilai: $targetDurationMinutes).');
    }
  }

  Future<List<LearningGoal>> getActiveGoals() async {
    final res = await _sb
        .from('learning_goals')
        .select()
        .eq('user_id', _uid)
        .eq('status', 'active')
        .order('created_at', ascending: false);
    return (res as List).map((e) => LearningGoal.fromMap(e)).toList();
  }

  /// Cek apakah user masih punya Goal yang belum selesai (status != 'completed'
  /// DAN actual_progress belum 100%). Dipakai sebagai pagar SEBELUM createGoal
  /// dipanggil, supaya user tidak bisa membuat banyak Goal aktif sekaligus --
  /// mencegah data tumpang tindih/bias saat dianalisis (lihat permintaan
  /// perbaikan: satu Goal harus selesai dulu baru boleh membuat Goal baru).
  ///
  /// "Selesai" di sini didefinisikan sebagai status data (completed / progress
  /// 100%), BUKAN soal periode/deadline sudah lewat atau belum -- goal yang
  /// overdue tapi belum ditandai selesai tetap dianggap "belum selesai".
  Future<LearningGoal?> getBlockingActiveGoal() async {
    final res = await _sb
        .from('learning_goals')
        .select()
        .eq('user_id', _uid)
        .eq('status', 'active')
        .order('created_at', ascending: false);
    final goals = (res as List).map((e) => LearningGoal.fromMap(e)).toList();
    for (final g in goals) {
      if (!g.isCompleted) return g;
    }
    return null;
  }

  Future<List<LearningGoal>> getAllGoals() async {
    final res = await _sb
        .from('learning_goals')
        .select()
        .eq('user_id', _uid)
        .order('created_at', ascending: false);
    return (res as List).map((e) => LearningGoal.fromMap(e)).toList();
  }

  Future<LearningGoal> createGoal({
    required String title,
    required String category,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int targetSessions,
    required int targetDurationMinutes,
    double targetProgress = 100.0,
  }) async {
    _validateTargets(
      targetSessions: targetSessions,
      targetDurationMinutes: targetDurationMinutes,
    );

    // Pagar utama: tolak pembuatan Goal baru selama masih ada Goal aktif
    // yang belum selesai. Ini mencegah user menumpuk banyak Goal berjalan
    // sekaligus, yang bisa membuat data progres tumpang tindih dan bias
    // saat dianalisis/di-cluster.
    final blocking = await getBlockingActiveGoal();
    if (blocking != null) {
      throw GoalValidationException(
          'Selesaikan dulu target "${blocking.title}" '
          '(${blocking.progressLabel}) sebelum membuat target baru.');
    }

    final res = await _sb.from('learning_goals').insert({
      'user_id': _uid,
      'title': title,
      'category': category,
      'period_start': _dateStr(periodStart),
      'period_end': _dateStr(periodEnd),
      'target_sessions': targetSessions,
      'target_duration': targetDurationMinutes,
      'target_progress': targetProgress,
    }).select().single();
    return LearningGoal.fromMap(res);
  }

  Future<void> updateGoal({
    required String goalId,
    required String title,
    required String category,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int targetSessions,
    required int targetDurationMinutes,
  }) async {
    _validateTargets(
      targetSessions: targetSessions,
      targetDurationMinutes: targetDurationMinutes,
    );
    await _sb.from('learning_goals').update({
      'title': title,
      'category': category,
      'period_start': _dateStr(periodStart),
      'period_end': _dateStr(periodEnd),
      'target_sessions': targetSessions,
      'target_duration': targetDurationMinutes,
    }).eq('id', goalId).eq('user_id', _uid);
  }

  Future<void> markCompleted(String goalId) async {
    await _sb.from('learning_goals').update({
      'status': 'completed',
      'actual_progress': 100.0,
    }).eq('id', goalId).eq('user_id', _uid);
  }

  Future<void> deleteGoal(String goalId) async {
    await _sb.from('learning_goals')
        .delete()
        .eq('id', goalId)
        .eq('user_id', _uid);
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}