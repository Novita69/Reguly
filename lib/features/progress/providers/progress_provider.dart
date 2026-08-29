// lib/features/progress/providers/progress_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/assessment_result.dart';
import '../../../services/assessment_service.dart';

class ProgressState {
  final List<AssessmentResult> assessments;
  final Map<String, dynamic>? delta;
  final ReassessmentGate? gate;
  final bool isLoading;
  final String? error;

  const ProgressState({
    this.assessments = const [],
    this.delta,
    this.gate,
    this.isLoading = false,
    this.error,
  });

  bool get hasDelta => delta != null;

  String trendFor(String dimension) {
    if (delta == null) return 'Stabil';
    final val = delta!['delta_$dimension'] as int?;
    if (val == null || val == 0) return 'Stabil';
    return val > 0 ? 'Meningkat' : 'Menurun';
  }

  ProgressState copyWith({
    List<AssessmentResult>? assessments, Map<String, dynamic>? delta,
    ReassessmentGate? gate,
    bool? isLoading, String? error, bool clearError = false, bool clearDelta = false,
  }) => ProgressState(
    assessments: assessments ?? this.assessments,
    delta: clearDelta ? null : (delta ?? this.delta),
    gate: gate ?? this.gate,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
  );
}

class ProgressNotifier extends StateNotifier<ProgressState> {
  ProgressNotifier() : super(const ProgressState(isLoading: true)) { load(); }

  final _sb = Supabase.instance.client;
  final _assessmentService = AssessmentService();
  String get _uid => _sb.auth.currentUser!.id;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _sb.from('assessment_results').select()
            .eq('user_id', _uid).order('completed_at', ascending: true),
        _sb.from('v_assessment_delta').select()
            .eq('user_id', _uid).maybeSingle(),
      ]);
      final assessList = (results[0] as List)
          .map((e) => AssessmentResult.fromMap(e as Map<String, dynamic>)).toList();
      final delta = results[1] as Map<String, dynamic>?;
      final gate = await _assessmentService.getReassessmentGate();
      state = state.copyWith(
        assessments: assessList, delta: delta, gate: gate, isLoading: false,
        clearDelta: delta == null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Gagal memuat data evaluasi.');
    }
  }
}

final progressProvider =
    StateNotifierProvider.autoDispose<ProgressNotifier, ProgressState>(
  (ref) => ProgressNotifier(),
);
