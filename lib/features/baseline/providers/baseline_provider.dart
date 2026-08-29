// lib/features/baseline/providers/baseline_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/assessment_result.dart';
import '../../../services/assessment_service.dart';

// ── State ──────────────────────────────────────────────────────

class BaselineState {
  final int currentIndex;        // 0–11
  final List<int?> answers;      // 12 jawaban, null = belum dijawab
  final bool isSubmitting;
  final AssessmentResult? result;
  final String? error;

  const BaselineState({
    this.currentIndex = 0,
    required this.answers,
    this.isSubmitting = false,
    this.result,
    this.error,
  });

  // Jawaban soal saat ini (bisa null)
  int? get currentAnswer => answers[currentIndex];

  // Sudah di soal terakhir?
  bool get isLastQuestion => currentIndex == 11;

  // Semua soal sudah dijawab?
  bool get allAnswered => answers.every((a) => a != null);

  // Progress bar 0.0–1.0
  double get progress => (currentIndex + 1) / 12.0;

  BaselineState copyWith({
    int? currentIndex,
    List<int?>? answers,
    bool? isSubmitting,
    AssessmentResult? result,
    String? error,
    bool clearError = false,
    bool clearResult = false,
  }) {
    return BaselineState(
      currentIndex: currentIndex ?? this.currentIndex,
      answers: answers ?? this.answers,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      result: clearResult ? null : (result ?? this.result),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ── Notifier ───────────────────────────────────────────────────

class BaselineNotifier extends StateNotifier<BaselineState> {
  BaselineNotifier()
      : super(BaselineState(answers: List.filled(12, null)));

  final _service = AssessmentService();

  // Pilih jawaban untuk soal saat ini
  void selectAnswer(int score) {
    final updated = List<int?>.from(state.answers);
    updated[state.currentIndex] = score;
    state = state.copyWith(answers: updated, clearError: true);
  }

  // Maju ke soal berikutnya
  void nextQuestion() {
    if (state.currentAnswer == null) return;
    if (state.isLastQuestion) return;
    state = state.copyWith(currentIndex: state.currentIndex + 1);
  }

  // Kembali ke soal sebelumnya
  void prevQuestion() {
    if (state.currentIndex == 0) return;
    state = state.copyWith(
      currentIndex: state.currentIndex - 1,
      clearError: true,
    );
  }

  // Submit semua jawaban ke Supabase
  Future<void> submit({String type = 'baseline'}) async {
    if (!state.allAnswered) {
      state = state.copyWith(error: 'Harap jawab semua pertanyaan terlebih dahulu.');
      return;
    }

    state = state.copyWith(isSubmitting: true, clearError: true);

    try {
      final result = await _service.submitAssessment(
        answers: state.answers.map((a) => a!).toList(),
        type: type,
      );
      state = state.copyWith(isSubmitting: false, result: result);
    } catch (e) {
      // Pesan dari AssessmentService (mis. REASSESSMENT_LOCKED) sudah
      // ramah-pengguna, tampilkan apa adanya; selain itu pakai pesan umum.
      final msg = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(
        isSubmitting: false,
        error: msg.isNotEmpty
            ? msg
            : 'Gagal menyimpan asesmen. Coba lagi dalam beberapa saat.',
      );
    }
  }

  // Reset provider (untuk reassessment)
  void reset() {
    state = BaselineState(answers: List.filled(12, null));
  }
}

// ── Provider ───────────────────────────────────────────────────

final baselineProvider =
    StateNotifierProvider.autoDispose<BaselineNotifier, BaselineState>(
  (ref) => BaselineNotifier(),
);
