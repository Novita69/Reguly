// lib/features/persona/providers/persona_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/persona_and_recommendation.dart';
import '../../../models/assessment_result.dart';
import '../../../services/persona_recommendation_service.dart';
import '../../../services/assessment_service.dart';

class PersonaState {
  final PersonaInfo? current;
  final List<PersonaInfo> history;
  final List<RuleWarningCount> warningBreakdown;
  final AssessmentResult? latestAssessment;
  final bool isLoading, isTriggering;
  final String? error, trendLabel, feedbackMessage;
  final bool feedbackIsError;

  const PersonaState({
    this.current,
    this.history = const [],
    this.warningBreakdown = const [],
    this.latestAssessment,
    this.isLoading = false,
    this.isTriggering = false,
    this.error,
    this.trendLabel,
    this.feedbackMessage,
    this.feedbackIsError = false,
  });

  PersonaState copyWith({
    PersonaInfo? current,
    List<PersonaInfo>? history,
    List<RuleWarningCount>? warningBreakdown,
    AssessmentResult? latestAssessment,
    bool? isLoading,
    bool? isTriggering,
    String? error,
    bool clearError = false,
    String? trendLabel,
    String? feedbackMessage,
    bool clearFeedback = false,
    bool? feedbackIsError,
  }) =>
      PersonaState(
        current: current ?? this.current,
        history: history ?? this.history,
        warningBreakdown: warningBreakdown ?? this.warningBreakdown,
        latestAssessment: latestAssessment ?? this.latestAssessment,
        isLoading: isLoading ?? this.isLoading,
        isTriggering: isTriggering ?? this.isTriggering,
        error: clearError ? null : (error ?? this.error),
        trendLabel: trendLabel ?? this.trendLabel,
        feedbackMessage:
            clearFeedback ? null : (feedbackMessage ?? this.feedbackMessage),
        feedbackIsError: feedbackIsError ?? this.feedbackIsError,
      );
}

class PersonaNotifier extends StateNotifier<PersonaState> {
  PersonaNotifier() : super(const PersonaState(isLoading: true)) {
    load();
  }
  final _service = PersonaService();
  final _assessmentService = AssessmentService();

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final history = await _service.getPersonaHistory();
      var current = history.where((p) => p.isCurrent).firstOrNull;
      final warningBreakdown = await _service
          .getWarningBreakdown()
          .catchError((_) => <RuleWarningCount>[]);

      // Warning tier badge ("Mandiri"/"Responsif") -- REPLIKA persis logika
      // computeWarningTier() yang juga dipakai Dashboard
      // (lib/features/dashboard/providers/dashboard_provider.dart, lihat
      // komentar di sana): COUNT(monitoring_alerts) 28 hari terakhir vs
      // ambang 3. warningBreakdown di atas SUDAH di-query dengan window 28
      // hari yang sama (lihat getWarningBreakdown() di
      // persona_recommendation_service.dart), jadi total count-nya di sini
      // dipakai ulang alih-alih query monitoring_alerts sekali lagi --
      // menjaga satu sumber data untuk satu window waktu yang sama, bukan
      // duplikasi query. null kalau belum ada persona (current null),
      // karena warning_tier tidak bermakna tanpa persona aktif.
      //
      // Label tier SERAGAM 'mandiri'/'responsif' untuk KEEMPAT persona
      // (revisi per arahan dosen pembimbing) -- lihat catatan yang sama
      // di dashboard_provider.dart dan mapWarningTierLabel() di
      // generate_recommendations.ts.
      if (current != null) {
        const warningThreshold = 3;
        final warningCount =
            warningBreakdown.fold<int>(0, (sum, w) => sum + w.count);
        final isFrequent = warningCount >= warningThreshold;
        final tier = isFrequent ? 'responsif' : 'mandiri';
        current = current.copyWithWarningTier(tier);
      }
      // Skor SRL terbaru -- reassessment (T2) kalau sudah ada, kalau belum
      // fallback ke baseline (T1). Dua panggilan terpisah yang SUDAH ADA di
      // AssessmentService (tidak menduplikasi query logic baru), murni
      // dikombinasikan di sini: reassessment diutamakan karena mencerminkan
      // kondisi TERKINI, baseline dipakai kalau user belum sempat T2.
      final latestAssessment = await _assessmentService
              .getLatestReassessment()
              .catchError((_) => null) ??
          await _assessmentService.getBaseline().catchError((_) => null);
      String trend = 'Stabil';
      if (history.length >= 2) {
        final c = (history[0].featureValues['x4'] ?? 0) +
            (history[0].featureValues['x5'] ?? 0);
        final p = (history[1].featureValues['x4'] ?? 0) +
            (history[1].featureValues['x5'] ?? 0);
        if (c > p + 5)
          trend = 'Meningkat';
        else if (c < p - 5) trend = 'Menurun';
      }
      state = state.copyWith(
        current: current,
        history: history.where((p) => !p.isCurrent).toList(),
        warningBreakdown: warningBreakdown,
        latestAssessment: latestAssessment,
        isLoading: false,
        trendLabel: trend,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Gagal memuat persona.');
    }
  }

  Future<void> triggerAnalysis() async {
    state = state.copyWith(
      isTriggering: true,
      clearError: true,
      clearFeedback: true,
    );

    final result = await _service.triggerKMeans();

    state = state.copyWith(
      isTriggering: false,
      feedbackMessage: result.message,
      feedbackIsError: result.isTechnicalError,
    );

    if (result.success) {
      await load();
      state = state.copyWith(
        feedbackMessage: result.message,
        feedbackIsError: false,
      );
    }
  }

  void clearFeedback() {
    state = state.copyWith(clearFeedback: true);
  }
}

final personaProvider =
    StateNotifierProvider.autoDispose<PersonaNotifier, PersonaState>(
  (ref) => PersonaNotifier(),
);