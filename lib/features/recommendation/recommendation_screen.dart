// lib/features/recommendation/recommendation_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/persona_and_recommendation.dart';
import 'providers/recommendation_provider.dart';

const _purple = Color(0xFF5C4DFF);
const _teal = Color(0xFF4ECDC4);
const _amber = Color(0xFFF59E0B);
const _bg = Color(0xFFF5F7FA);

class RecommendationScreen extends ConsumerWidget {
  const RecommendationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recommendationProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('Rekomendasi Metakognitif',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _purple),
            onPressed: () => ref.read(recommendationProvider.notifier).load(),
          ),
        ],
      ),
      body: Column(children: [
        // Info banner
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: _purple),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Rekomendasi belajar disusun berdasarkan data regulasi diri Anda. '
                'Anda dapat menandai sebagai selesai jika strategi telah diterapkan secara disiplin.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4),
              ),
            ),
          ]),
        ),

        // Filter chips
        _DimensionFilter(
          selected: state.filterDimension,
          onSelect: (d) => ref.read(recommendationProvider.notifier).setFilter(d),
          completedCount: state.completedCount,
          totalCount: state.totalCount,
        ),

        // List
        Expanded(
          child: state.isLoading
              ? const Center(child: CircularProgressIndicator(color: _purple))
              : state.error != null
                  ? _ErrorState(
                      message: state.error!,
                      onRetry: () => ref.read(recommendationProvider.notifier).load(),
                    )
                  : state.filtered.isEmpty
                  ? const _EmptyRecommendations()
                  : RefreshIndicator(
                      color: _purple,
                      onRefresh: () => ref.read(recommendationProvider.notifier).load(),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: state.filtered.length,
                        itemBuilder: (ctx, i) => _RecommendationCard(
                          rec: state.filtered[i],
                          onMarkDone: () => ref
                              .read(recommendationProvider.notifier)
                              .markCompleted(state.filtered[i].id),
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }
}

// ── Dimension Filter ───────────────────────────────────────────

class _DimensionFilter extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  final int completedCount, totalCount;
  const _DimensionFilter({
    required this.selected, required this.onSelect,
    required this.completedCount, required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final filters = [
      ('all', 'Semua', null),
      ('planning', 'Perencanaan', _purple),
      ('monitoring', 'Pemantauan', _teal),
      ('evaluating', 'Evaluasi', _amber),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Row(children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: filters.map((f) {
                final isActive = selected == f.$1;
                final activeColor = f.$3 ?? _purple;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => onSelect(f.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive ? activeColor : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: isActive ? activeColor : Colors.grey[300]!),
                      ),
                      child: Text(f.$2,
                          style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: isActive ? Colors.white : Colors.grey[600],
                          )),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Text('$completedCount/$totalCount',
              style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
        ),
      ]),
    );
  }
}

// ── Recommendation Card ────────────────────────────────────────

class _RecommendationCard extends StatelessWidget {
  final Recommendation rec;
  final VoidCallback onMarkDone;
  const _RecommendationCard({required this.rec, required this.onMarkDone});

  Color get _dimColor {
    switch (rec.msrDimension) {
      case 'planning':   return _purple;
      case 'monitoring': return _teal;
      case 'evaluating': return _amber;
      default: return Colors.grey;
    }
  }

  Color get _priorityColor {
    switch (rec.priority) {
      case 1: return const Color(0xFFEF4444);
      case 2: return const Color(0xFFF59E0B);
      default: return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: rec.isCompleted
            ? Border.all(color: const Color(0xFF10B981).withOpacity(0.4))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Tag row: dimension + priority + action
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8, runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Pill(label: rec.dimensionDisplay, color: _dimColor, outlined: true),
                    _Pill(label: rec.priorityDisplay, color: _priorityColor, outlined: true),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _CompleteButton(isCompleted: rec.isCompleted, onTap: onMarkDone),
            ],
          ),
          const SizedBox(height: 12),

          // Title
          Text(rec.title,
              style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800,
                color: rec.isCompleted ? Colors.grey[400] : const Color(0xFF1A1A2E),
                decoration: rec.isCompleted ? TextDecoration.lineThrough : null,
              )),
          const SizedBox(height: 12),

          // Content card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // AI Insight
              if (rec.aiInsight != null) ...[
                _ContentLabel('WAWASAN AI:'),
                const SizedBox(height: 4),
                Text('"${rec.aiInsight}"',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600],
                        fontStyle: FontStyle.italic, height: 1.5)),
                const SizedBox(height: 12),
              ],

              // Strategi
              _ContentLabel('STRATEGI BELAJAR:'),
              const SizedBox(height: 4),
              Text(rec.strategy,
                  style: const TextStyle(fontSize: 13,
                      color: Color(0xFF1A1A2E), height: 1.5)),
              const SizedBox(height: 12),

              // Tindakan
              _ContentLabel('TINDAKAN DISARANKAN:'),
              const SizedBox(height: 4),
              Text(rec.action,
                  style: const TextStyle(fontSize: 13,
                      color: Color(0xFF1A1A2E), height: 1.5)),

              // Pertanyaan refleksi
              if (rec.reflectionQuestion != null) ...[
                const SizedBox(height: 12),
                _ContentLabel('PERTANYAAN REFLEKSI:'),
                const SizedBox(height: 4),
                Text('"${rec.reflectionQuestion}"',
                    style: const TextStyle(fontSize: 13, color: _purple,
                        fontStyle: FontStyle.italic, height: 1.5)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ContentLabel extends StatelessWidget {
  final String text;
  const _ContentLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
        color: Colors.grey[400], letterSpacing: 0.7));
}

class _Pill extends StatelessWidget {
  final String label; final Color color; final bool outlined;
  const _Pill({required this.label, required this.color, this.outlined = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: outlined ? color.withOpacity(0.08) : color,
      borderRadius: BorderRadius.circular(20),
      border: outlined ? Border.all(color: color.withOpacity(0.3)) : null,
    ),
    child: Text(label, style: TextStyle(fontSize: 10,
        fontWeight: FontWeight.w700,
        color: outlined ? color : Colors.white)),
  );
}

class _CompleteButton extends StatelessWidget {
  final bool isCompleted;
  final VoidCallback onTap;
  const _CompleteButton({required this.isCompleted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_rounded, size: 13, color: Color(0xFF10B981)),
          SizedBox(width: 4),
          Text('Selesai Dilakukan',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: Color(0xFF10B981))),
        ]),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('Tandai Selesai',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
    );
  }
}

// ── Error State ────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline_rounded, size: 56, color: Colors.red[300]),
        const SizedBox(height: 16),
        Text('Gagal memuat rekomendasi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: Colors.grey[700])),
        const SizedBox(height: 8),
        Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: onRetry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: _purple,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('Coba Lagi',
                style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ),
      ]),
    ),
  );
}

// ── Empty State ────────────────────────────────────────────────

class _EmptyRecommendations extends StatelessWidget {
  const _EmptyRecommendations();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey[300]),
      const SizedBox(height: 16),
      Text('Rekomendasi belum tersedia',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
              color: Colors.grey[400])),
      const SizedBox(height: 8),
      Text(
        'Rekomendasi akan muncul setelah\npersona belajarmu terbentuk.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Colors.grey[400]),
      ),
      const SizedBox(height: 20),
      GestureDetector(
        onTap: () => context.go('/persona'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: _purple.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text('Lihat Persona',
              style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w600, color: _purple)),
        ),
      ),
    ]),
  );
}
