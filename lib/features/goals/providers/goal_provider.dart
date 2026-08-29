// lib/features/goals/providers/goal_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/learning_goal.dart';
import '../../../services/goal_service.dart';
import '../../dashboard/providers/dashboard_provider.dart';

/// Menerjemahkan error simpan/ubah goal jadi pesan yang bisa dibaca
/// pengguna. GoalValidationException datang dari validasi klien
/// (goal_service.dart); PostgrestException code 23514 datang dari
/// trigger/CHECK constraint di server (bisa terjadi walau validasi klien
/// lolos, mis. panggilan API di luar aplikasi ini, atau race condition
/// dua request createGoal yang lolos cek klien nyaris bersamaan) —
/// keduanya sengaja ditulis dengan pesan senada di sisi server (lihat
/// migration 20260724090000_goal_target_limits.sql dan
/// 20260727100000_activity_duration_and_single_active_goal.sql) supaya
/// aman ditampilkan langsung ke pengguna.
String _friendlyGoalError(Object e) {
  if (e is GoalValidationException) return e.message;
  if (e is PostgrestException && e.code == '23514') {
    return e.message; // pesan RAISE EXCEPTION dari trigger DB
  }
  return 'Gagal menyimpan target. Periksa koneksi.';
}

class GoalState {
  final List<LearningGoal> goals;
  final bool isLoading;
  final bool isSaving;
  final String? error;
  const GoalState({
    this.goals = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.error,
  });
  GoalState copyWith({
    List<LearningGoal>? goals, bool? isLoading,
    bool? isSaving, String? error, bool clearError = false,
  }) => GoalState(
    goals: goals ?? this.goals,
    isLoading: isLoading ?? this.isLoading,
    isSaving: isSaving ?? this.isSaving,
    error: clearError ? null : (error ?? this.error),
  );
  int get activeCount => goals.where((g) => !g.isCompleted).length;
  int get completedCount => goals.where((g) => g.isCompleted).length;

  /// Goal aktif (status == 'active') yang belum selesai (progress < 100%).
  /// Selama goal ini ada, pembuatan Goal baru harus diblokir -- dipakai UI
  /// (tombol "Tambah Target") untuk menampilkan pesan yang jelas SEBELUM
  /// masuk ke form, tanpa perlu menunggu submit gagal dulu. Sumber
  /// kebenaran tetap di GoalService.getBlockingActiveGoal() (server-aware),
  /// ini hanya salinan cepat dari state yang sudah di-load di memory.
  LearningGoal? get blockingActiveGoal {
    for (final g in goals) {
      if (g.status == 'active' && !g.isCompleted) return g;
    }
    return null;
  }
}

class GoalNotifier extends StateNotifier<GoalState> {
  GoalNotifier(this._ref) : super(const GoalState(isLoading: true)) {
    load();
  }
  final Ref _ref;
  final _service = GoalService();

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final goals = await _service.getAllGoals();
      state = state.copyWith(goals: goals, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false,
          error: 'Gagal memuat target. Coba lagi.');
    }
  }

  Future<bool> addGoal({
    required String title, required String category,
    required DateTime periodStart, required DateTime periodEnd,
    required int targetSessions, required int targetDurationMinutes,
    double targetProgress = 100.0,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final goal = await _service.createGoal(
        title: title, category: category,
        periodStart: periodStart, periodEnd: periodEnd,
        targetSessions: targetSessions,
        targetDurationMinutes: targetDurationMinutes,
        targetProgress: targetProgress,
      );
      state = state.copyWith(
        goals: [goal, ...state.goals], isSaving: false,
      );
      _ref.invalidate(dashboardProvider);
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: _friendlyGoalError(e));
      return false;
    }
  }

  Future<bool> updateGoal({
    required String goalId,
    required String title, required String category,
    required DateTime periodStart, required DateTime periodEnd,
    required int targetSessions, required int targetDurationMinutes,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _service.updateGoal(
        goalId: goalId,
        title: title, category: category,
        periodStart: periodStart, periodEnd: periodEnd,
        targetSessions: targetSessions,
        targetDurationMinutes: targetDurationMinutes,
      );
      await load();
      state = state.copyWith(isSaving: false);
      _ref.invalidate(dashboardProvider);
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: _friendlyGoalError(e));
      return false;
    }
  }

  Future<void> markCompleted(String goalId) async {
    await _service.markCompleted(goalId);
    await load();
    // Dashboard bisa saja masih hidup di belakang layar Goals (karena
    // dibuka lewat context.push), jadi providernya tidak otomatis
    // dispose/refresh. Invalidate manual di sini supaya data dashboard
    // (centang/coret target) langsung ikut update begitu kembali ke Beranda.
    _ref.invalidate(dashboardProvider);
  }

  Future<void> deleteGoal(String goalId) async {
    await _service.deleteGoal(goalId);
    state = state.copyWith(
      goals: state.goals.where((g) => g.id != goalId).toList(),
    );
    _ref.invalidate(dashboardProvider);
  }
}

final goalProvider =
    StateNotifierProvider.autoDispose<GoalNotifier, GoalState>(
  (ref) => GoalNotifier(ref),
);

// Provider aktif saja — dipakai di dropdown Add Activity
// Catatan: filter tidak cukup hanya `status == 'active'`, karena status itu
// hanya berubah lewat aksi manual "Tandai Selesai" (markCompleted). Target
// yang progressnya sudah mencapai 100% secara otomatis (isCompleted == true)
// tetap harus dikeluarkan dari daftar aktif walau status di DB belum sempat
// diubah ke selesai.
final activeGoalsProvider = Provider.autoDispose<List<LearningGoal>>((ref) {
  return ref.watch(goalProvider).goals
      .where((g) => g.status == 'active' && !g.isCompleted).toList();
});