// lib/features/recommendation/providers/recommendation_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/persona_and_recommendation.dart';
import '../../../services/persona_recommendation_service.dart';

class RecommendationState {
  final List<Recommendation> items;
  final bool isLoading;
  final String? error;
  final String filterDimension;

  const RecommendationState({
    this.items = const [], this.isLoading = false,
    this.error, this.filterDimension = 'all',
  });

  RecommendationState copyWith({
    List<Recommendation>? items, bool? isLoading,
    String? error, bool clearError = false, String? filterDimension,
  }) => RecommendationState(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
    filterDimension: filterDimension ?? this.filterDimension,
  );

  List<Recommendation> get filtered =>
      filterDimension == 'all' ? items
          : items.where((r) => r.msrDimension == filterDimension).toList();
  int get completedCount => items.where((r) => r.isCompleted).length;
  int get totalCount => items.length;
}

class RecommendationNotifier extends StateNotifier<RecommendationState> {
  RecommendationNotifier() : super(const RecommendationState(isLoading: true)) { load(); }
  final _service = RecommendationService();

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _service.getRecommendations();
      for (final r in items.where((r) => r.viewedAt == null)) { _service.markViewed(r.id); }
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Gagal memuat rekomendasi.');
    }
  }

  Future<void> markCompleted(String id) async {
    await _service.markCompleted(id);
    state = state.copyWith(items: state.items.map((r) => r.id == id
        ? r.copyWith(isCompleted: true, completedAt: DateTime.now()) : r).toList());
  }

  void setFilter(String d) => state = state.copyWith(filterDimension: d);
}

final recommendationProvider = StateNotifierProvider.autoDispose<RecommendationNotifier, RecommendationState>(
  (ref) => RecommendationNotifier(),
);
