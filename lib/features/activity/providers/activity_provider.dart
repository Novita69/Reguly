// lib/features/activity/providers/activity_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/learning_activity.dart';
import '../../../services/activity_service.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../goals/providers/goal_provider.dart';

/// Menerjemahkan error simpan aktivitas jadi pesan yang bisa dibaca
/// pengguna. Mengikuti pola _friendlyGoalError di goal_provider.dart:
/// ActivityValidationException datang dari validasi klien
/// (activity_service.dart) dan sudah berisi pesan yang aman ditampilkan
/// langsung, sedangkan error lain (jaringan, dll) dibalas dengan pesan
/// umum supaya tidak membocorkan detail teknis ke pengguna.
String _friendlyActivityError(Object e) {
  if (e is ActivityValidationException) return e.message;
  return 'Gagal menyimpan aktivitas. Coba lagi.';
}

// ── Filter state ───────────────────────────────────────────────
class ActivityFilter {
  final String period; // 'all'|'today'|'week'|'month'
  final String search;
  final String? category;
  const ActivityFilter({
    this.period = 'all',
    this.search = '',
    this.category,
  });
  ActivityFilter copyWith({
    String? period, String? search, String? category, bool clearCategory = false,
  }) => ActivityFilter(
    period: period ?? this.period,
    search: search ?? this.search,
    category: clearCategory ? null : (category ?? this.category),
  );
}

// ── History state ──────────────────────────────────────────────
class ActivityHistoryState {
  final List<LearningActivity> activities;
  final ActivityFilter filter;
  final bool isLoading;
  final String? error;
  const ActivityHistoryState({
    this.activities = const [],
    this.filter = const ActivityFilter(),
    this.isLoading = false,
    this.error,
  });
  ActivityHistoryState copyWith({
    List<LearningActivity>? activities, ActivityFilter? filter,
    bool? isLoading, String? error, bool clearError = false,
  }) => ActivityHistoryState(
    activities: activities ?? this.activities,
    filter: filter ?? this.filter,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
  );

  int get totalMinutes =>
      activities.fold(0, (s, a) => s + a.durationMinutes);
  double get avgFocus => activities.isEmpty
      ? 0
      : activities.fold(0.0, (s, a) => s + a.focusScore) / activities.length;
}

class ActivityHistoryNotifier extends StateNotifier<ActivityHistoryState> {
  ActivityHistoryNotifier() : super(const ActivityHistoryState(isLoading: true)) {
    load();
  }
  final _service = ActivityService();

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final acts = await _service.getActivities(
        filter: state.filter.period,
        search: state.filter.search.isEmpty ? null : state.filter.search,
        category: state.filter.category,
      );
      state = state.copyWith(activities: acts, isLoading: false);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'Gagal memuat riwayat aktivitas.');
    }
  }

  void setPeriodFilter(String period) {
    state = state.copyWith(filter: state.filter.copyWith(period: period));
    load();
  }

  void setSearch(String q) {
    state = state.copyWith(filter: state.filter.copyWith(search: q));
    load();
  }

  void setCategoryFilter(String? category) {
    state = state.copyWith(
      filter: category == null
          ? state.filter.copyWith(clearCategory: true)
          : state.filter.copyWith(category: category),
    );
    load();
  }

  Future<void> deleteActivity(String id) async {
    await _service.deleteActivity(id);
    state = state.copyWith(
      activities: state.activities.where((a) => a.id != id).toList(),
    );
  }

  void addToList(LearningActivity activity) {
    state = state.copyWith(activities: [activity, ...state.activities]);
  }
}

final activityHistoryProvider = StateNotifierProvider.autoDispose<
    ActivityHistoryNotifier, ActivityHistoryState>(
  (ref) => ActivityHistoryNotifier(),
);

// ── Add Activity / Focus Session form state ────────────────────
class AddActivityState {
  final bool isSaving;
  final bool isSaved;
  final String? error;
  const AddActivityState({
    this.isSaving = false,
    this.isSaved = false,
    this.error,
  });
  AddActivityState copyWith({
    bool? isSaving, bool? isSaved, String? error, bool clearError = false,
  }) => AddActivityState(
    isSaving: isSaving ?? this.isSaving,
    isSaved: isSaved ?? this.isSaved,
    error: clearError ? null : (error ?? this.error),
  );
}

class AddActivityNotifier extends StateNotifier<AddActivityState> {
  AddActivityNotifier(this._ref) : super(const AddActivityState());
  final Ref _ref;
  final _service = ActivityService();

  Future<LearningActivity?> save({
    String? goalId, required String activityName, required String category,
    required DateTime activityDate, String? startTime,
    required int durationMinutes, required int focusScore,
    required double progressPercent, String? notes,
    String sourceType = 'manual',
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final act = await _service.saveActivity(
        goalId: goalId, activityName: activityName, category: category,
        activityDate: activityDate, startTime: startTime,
        durationMinutes: durationMinutes, focusScore: focusScore,
        progressPercent: progressPercent, notes: notes,
        sourceType: sourceType,
      );
      state = state.copyWith(isSaving: false, isSaved: true);
      // Mencatat aktivitas selalu mengubah ringkasan Dashboard (durasi hari
      // ini, total minggu ini, streak). Kalau terhubung ke target (goalId
      // terisi), itu juga menambah sesi target tersebut di belakang layar —
      // jadi Daftar Target ikut perlu di-refresh. Invalidate di sini supaya
      // kedua layar tidak menampilkan data basi setelah kembali dari layar
      // Tambah Aktivitas.
      _ref.invalidate(dashboardProvider);
      if (goalId != null) {
        _ref.invalidate(goalProvider);
      }
      return act;
    } catch (e) {
      state = state.copyWith(
          isSaving: false, error: _friendlyActivityError(e));
      return null;
    }
  }
}

final addActivityProvider =
    StateNotifierProvider.autoDispose<AddActivityNotifier, AddActivityState>(
  (ref) => AddActivityNotifier(ref),
);
