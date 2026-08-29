// lib/features/baseline/baseline_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/baseline_provider.dart';

// ── Data soal ──────────────────────────────────────────────────

class _Question {
  final String dimension;
  final String text;
  final Color color;
  const _Question(this.dimension, this.text, this.color);
}

const _primaryPurple = Color(0xFF5C4DFF);
const _teal = Color(0xFF4ECDC4);
const _amber = Color(0xFFF59E0B);
const _bgColor = Color(0xFFF5F7FA);

final _questions = <_Question>[
  // Planning (1–4) — ungu
  _Question('Perencanaan', 'Sebelum mulai belajar, saya menetapkan tujuan yang ingin dicapai.', _primaryPurple),
  _Question('Perencanaan', 'Saya merencanakan strategi belajar sebelum memulai suatu materi.', _primaryPurple),
  _Question('Perencanaan', 'Saya menentukan target waktu belajar sebelum memulai kegiatan belajar.', _primaryPurple),
  _Question('Perencanaan', 'Saya mempersiapkan sumber belajar yang diperlukan sebelum belajar.', _primaryPurple),
  // Monitoring (5–8) — teal
  _Question('Pemantauan', 'Saya memantau apakah saya memahami materi yang sedang dipelajari.', _teal),
  _Question('Pemantauan', 'Saya memeriksa kemajuan belajar saya terhadap target yang telah ditetapkan.', _teal),
  _Question('Pemantauan', 'Saya menyadari ketika konsentrasi saya mulai menurun saat belajar.', _teal),
  _Question('Pemantauan', 'Saya menyesuaikan strategi belajar ketika cara yang digunakan tidak efektif.', _teal),
  // Evaluating (9–12) — amber
  _Question('Evaluasi', 'Setelah belajar, saya mengevaluasi apakah tujuan belajar telah tercapai.', _amber),
  _Question('Evaluasi', 'Saya merefleksikan efektivitas strategi belajar yang telah digunakan.', _amber),
  _Question('Evaluasi', 'Saya mengidentifikasi kesalahan atau kelemahan dalam proses belajar saya.', _amber),
  _Question('Evaluasi', 'Saya merencanakan perbaikan untuk sesi belajar berikutnya berdasarkan hasil evaluasi sebelumnya.', _amber),
];

const _scaleLabels = [
  'Sangat Tidak Sesuai',
  'Tidak Sesuai',
  'Netral',
  'Sesuai',
  'Sangat Sesuai',
];

// ── Screen ─────────────────────────────────────────────────────

class BaselineScreen extends ConsumerWidget {
  const BaselineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(baselineProvider);
    final notifier = ref.read(baselineProvider.notifier);
    final q = _questions[state.currentIndex];

    // Navigasi ke hasil setelah submit berhasil
    ref.listen<BaselineState>(baselineProvider, (_, next) {
      if (next.result != null) {
        context.go('/baseline/result');
      }
    });

    return PopScope(
      canPop: state.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && state.currentIndex > 0) {
          notifier.prevQuestion();
        }
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: _buildAppBar(context, state, notifier),
        body: Column(
          children: [
            _ProgressBar(progress: state.progress, color: q.color),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DimensionBadge(label: 'DIMENSI: ${q.dimension.toUpperCase()}', color: q.color),
                    const SizedBox(height: 20),
                    _QuestionText(text: q.text),
                    const SizedBox(height: 8),
                    Text(
                      'Pilih skala yang paling sesuai dengan kondisi belajarmu:',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 20),
                    ..._buildOptions(state, notifier, q.color),
                    if (state.error != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(message: state.error!),
                    ],
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(context, state, notifier, q.color),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    BaselineState state,
    BaselineNotifier notifier,
  ) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () {
          if (state.currentIndex > 0) {
            notifier.prevQuestion();
          } else {
            context.pop();
          }
        },
      ),
      title: const Text(
        'PENILAIAN AWAL',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: Color(0xFF5C4DFF),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: Text(
              '${state.currentIndex + 1}/12',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildOptions(
    BaselineState state,
    BaselineNotifier notifier,
    Color activeColor,
  ) {
    return List.generate(5, (i) {
      final score = i + 1;
      final isSelected = state.currentAnswer == score;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _LikertOption(
          label: _scaleLabels[i],
          score: score,
          isSelected: isSelected,
          activeColor: activeColor,
          onTap: () => notifier.selectAnswer(score),
        ),
      );
    });
  }

  Widget _buildBottomBar(
    BuildContext context,
    BaselineState state,
    BaselineNotifier notifier,
    Color color,
  ) {
    final hasAnswer = state.currentAnswer != null;
    final isLast = state.isLastQuestion;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      color: Colors.white,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: hasAnswer && !state.isSubmitting
              ? () {
                  if (isLast) {
                    notifier.submit();
                  } else {
                    notifier.nextQuestion();
                  }
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey[200],
            disabledForegroundColor: Colors.grey[400],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: state.isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isLast ? 'Selesai & Lihat Hasil' : 'Selanjutnya',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Subwidget: Progress Bar ────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final double progress;
  final Color color;
  const _ProgressBar({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 5,
        ),
      ),
    );
  }
}

// ── Subwidget: Dimension Badge ─────────────────────────────────

class _DimensionBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _DimensionBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.psychology_outlined, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Subwidget: Question Text ───────────────────────────────────

class _QuestionText extends StatelessWidget {
  final String text;
  const _QuestionText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1A2E),
        height: 1.4,
      ),
    );
  }
}

// ── Subwidget: Likert Option ───────────────────────────────────

class _LikertOption extends StatelessWidget {
  final String label;
  final int score;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  const _LikertOption({
    required this.label,
    required this.score,
    required this.isSelected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 56,
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? activeColor
                        : const Color(0xFF1A1A2E),
                  ),
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? activeColor : Colors.grey[100],
                ),
                child: Center(
                  child: Text(
                    '$score',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Subwidget: Error Banner ────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFEF4444), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFB91C1C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
