// lib/features/reflection/providers/reflection_provider.dart
// File ini berisi: WeeklyReflection model, ReflectionService, dan ReflectionNotifier

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ══════════════════════════════════════════════════════════════
// MODEL: WeeklyReflection
// ══════════════════════════════════════════════════════════════

class WeeklyReflection {
  final String id;
  final String userId;
  final int weekYear;
  final int weekNumber;
  final String? q1Achievements;
  final String? q2Challenges;
  final String? q3Strategies;
  final String? q4Improvements;
  final String? q5Insights;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WeeklyReflection({
    required this.id, required this.userId,
    required this.weekYear, required this.weekNumber,
    this.q1Achievements, this.q2Challenges, this.q3Strategies,
    this.q4Improvements, this.q5Insights,
    required this.createdAt, required this.updatedAt,
  });

  factory WeeklyReflection.fromMap(Map<String, dynamic> m) => WeeklyReflection(
    id: m['id'] as String, userId: m['user_id'] as String,
    weekYear: m['week_year'] as int, weekNumber: m['week_number'] as int,
    q1Achievements: m['q1_achievements'] as String?,
    q2Challenges:   m['q2_challenges']   as String?,
    q3Strategies:   m['q3_strategies']   as String?,
    q4Improvements: m['q4_improvements'] as String?,
    q5Insights:     m['q5_insights']     as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
  );

  String get weekLabel => 'Minggu $weekNumber, $weekYear';

  int get filledCount => [
    q1Achievements, q2Challenges, q3Strategies, q4Improvements, q5Insights,
  ].where((s) => s != null && s.trim().isNotEmpty).length;
}

// ══════════════════════════════════════════════════════════════
// SERVICE: ReflectionService
// ══════════════════════════════════════════════════════════════

class ReflectionService {
  final _sb = Supabase.instance.client;
  String get _uid => _sb.auth.currentUser!.id;

  static int _weekNum(DateTime d) {
    final dayOfYear = d.difference(DateTime(d.year, 1, 1)).inDays + 1;
    return ((dayOfYear - d.weekday + 10) / 7).floor();
  }

  Future<List<WeeklyReflection>> getHistory() async {
    final res = await _sb.from('weekly_reflections').select()
        .eq('user_id', _uid)
        .order('week_year', ascending: false)
        .order('week_number', ascending: false);
    return (res as List).map((e) => WeeklyReflection.fromMap(e)).toList();
  }

  Future<WeeklyReflection?> getThisWeek() async {
    final now = DateTime.now();
    final res = await _sb.from('weekly_reflections').select()
        .eq('user_id', _uid)
        .eq('week_year', now.year)
        .eq('week_number', _weekNum(now))
        .maybeSingle();
    if (res == null) return null;
    return WeeklyReflection.fromMap(res);
  }

  Future<WeeklyReflection> upsert({
    String? q1, String? q2, String? q3, String? q4, String? q5,
  }) async {
    final now = DateTime.now();
    final res = await _sb.from('weekly_reflections').upsert({
      'user_id': _uid,
      'week_year': now.year,
      'week_number': _weekNum(now),
      if (q1 != null) 'q1_achievements': q1,
      if (q2 != null) 'q2_challenges':   q2,
      if (q3 != null) 'q3_strategies':   q3,
      if (q4 != null) 'q4_improvements': q4,
      if (q5 != null) 'q5_insights':     q5,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,week_year,week_number').select().single();
    return WeeklyReflection.fromMap(res);
  }
}

// ══════════════════════════════════════════════════════════════
// STATE + NOTIFIER: Reflection
// ══════════════════════════════════════════════════════════════

class ReflectionState {
  final int currentStep;
  final List<String> answers;
  final bool isSaving, isSaved;
  final WeeklyReflection? saved;
  final List<WeeklyReflection> history;
  final bool isLoadingHistory;
  final String? error;

  const ReflectionState({
    this.currentStep = 0, required this.answers,
    this.isSaving = false, this.isSaved = false,
    this.saved, this.history = const [],
    this.isLoadingHistory = false, this.error,
  });

  bool get isLastStep => currentStep == 4;
  double get progress => (currentStep + 1) / 5.0;
  String? get currentAnswer =>
      answers[currentStep].isEmpty ? null : answers[currentStep];

  ReflectionState copyWith({
    int? currentStep, List<String>? answers,
    bool? isSaving, bool? isSaved,
    WeeklyReflection? saved, List<WeeklyReflection>? history,
    bool? isLoadingHistory, String? error, bool clearError = false,
  }) => ReflectionState(
    currentStep: currentStep ?? this.currentStep,
    answers: answers ?? this.answers,
    isSaving: isSaving ?? this.isSaving,
    isSaved: isSaved ?? this.isSaved,
    saved: saved ?? this.saved,
    history: history ?? this.history,
    isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
    error: clearError ? null : (error ?? this.error),
  );
}

class ReflectionNotifier extends StateNotifier<ReflectionState> {
  ReflectionNotifier() : super(ReflectionState(answers: List.filled(5, ''))) {
    _init();
  }
  final _service = ReflectionService();

  static int _weekNum(DateTime d) {
    final dayOfYear = d.difference(DateTime(d.year, 1, 1)).inDays + 1;
    return ((dayOfYear - d.weekday + 10) / 7).floor();
  }

  Future<void> _init() async {
    state = state.copyWith(isLoadingHistory: true);
    try {
      final history = await _service.getHistory();
      final thisWeek = history.isNotEmpty &&
          history.first.weekNumber == _weekNum(DateTime.now())
          ? history.first : null;

      List<String> prefilled = List.filled(5, '');
      if (thisWeek != null) {
        prefilled = [
          thisWeek.q1Achievements ?? '', thisWeek.q2Challenges ?? '',
          thisWeek.q3Strategies ?? '', thisWeek.q4Improvements ?? '',
          thisWeek.q5Insights ?? '',
        ];
      }
      state = state.copyWith(answers: prefilled, saved: thisWeek,
          history: history, isLoadingHistory: false);
    } catch (_) {
      state = state.copyWith(isLoadingHistory: false);
    }
  }

  void updateAnswer(String text) {
    final upd = List<String>.from(state.answers);
    upd[state.currentStep] = text;
    state = state.copyWith(answers: upd, isSaved: false);
  }

  void goNext() {
    if (!state.isLastStep) state = state.copyWith(currentStep: state.currentStep + 1);
  }
  void goPrev() {
    if (state.currentStep > 0) state = state.copyWith(currentStep: state.currentStep - 1);
  }

  Future<void> saveAll() async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final saved = await _service.upsert(
        q1: state.answers[0].isEmpty ? null : state.answers[0],
        q2: state.answers[1].isEmpty ? null : state.answers[1],
        q3: state.answers[2].isEmpty ? null : state.answers[2],
        q4: state.answers[3].isEmpty ? null : state.answers[3],
        q5: state.answers[4].isEmpty ? null : state.answers[4],
      );
      final history = await _service.getHistory();
      state = state.copyWith(isSaving: false, isSaved: true,
          saved: saved, history: history);
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Gagal menyimpan.');
    }
  }

  Future<void> autoSave() async {
    if (state.answers.every((a) => a.isEmpty)) return;
    try {
      await _service.upsert(
        q1: state.answers[0].isEmpty ? null : state.answers[0],
        q2: state.answers[1].isEmpty ? null : state.answers[1],
        q3: state.answers[2].isEmpty ? null : state.answers[2],
        q4: state.answers[3].isEmpty ? null : state.answers[3],
        q5: state.answers[4].isEmpty ? null : state.answers[4],
      );
      state = state.copyWith(isSaved: true);
    } catch (_) {}
  }
}

final reflectionProvider =
    StateNotifierProvider.autoDispose<ReflectionNotifier, ReflectionState>(
  (ref) => ReflectionNotifier(),
);
