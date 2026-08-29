// lib/features/tam/tam_screen.dart
//
// TAM Evaluation — 10 item Likert 1-5:
//   item 1–5  : PEOU (Kemudahan Penggunaan yang Dirasakan)
//   item 6–10 : PU   (Kegunaan yang Dirasakan)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Definisi 10 item TAM ───────────────────────────────────────

class _Item {
  final String type;   // 'peou' | 'pu'
  final String label;  // badge label
  final Color  color;  // badge color
  final String text;   // pernyataan
  const _Item(this.type, this.label, this.color, this.text);
}

const _teal   = Color(0xFF4ECDC4);
const _amber  = Color(0xFFF59E0B);
const _purple = Color(0xFF5C4DFF);
const _bg     = Color(0xFFF5F7FA);

final _items = <_Item>[
  // PEOU (1–5) — teal
  _Item('peou', 'KEMUDAHAN PENGGUNAAN',   _teal,
      'Saya merasa mudah untuk mempelajari cara menggunakan AI Learning Tracker.'),
  _Item('peou', 'KEMUDAHAN PENGGUNAAN',   _teal,
      'Interaksi saya dengan AI Learning Tracker jelas dan mudah dipahami.'),
  _Item('peou', 'KEMUDAHAN PENGGUNAAN',   _teal,
      'Secara keseluruhan, AI Learning Tracker mudah digunakan.'),
  _Item('peou', 'KEMUDAHAN PENGGUNAAN',   _teal,
      'Saya dapat menggunakan AI Learning Tracker tanpa banyak memerlukan bantuan.'),
  _Item('peou', 'KEMUDAHAN PENGGUNAAN',   _teal,
      'Fitur-fitur dalam AI Learning Tracker mudah untuk dinavigasi.'),
  // PU (6–10) — amber
  _Item('pu',   'KEGUNAAN YANG DIRASAKAN', _amber,
      'Menggunakan AI Learning Tracker membantu saya mengelola regulasi diri belajar secara lebih terarah.'),
  _Item('pu',   'KEGUNAAN YANG DIRASAKAN', _amber,
      'AI Learning Tracker meningkatkan efektivitas belajar saya.'),
  _Item('pu',   'KEGUNAAN YANG DIRASAKAN', _amber,
      'AI Learning Tracker membantu saya memantau perkembangan regulasi diri secara nyata.'),
  _Item('pu',   'KEGUNAAN YANG DIRASAKAN', _amber,
      'Rekomendasi yang diberikan AI Learning Tracker berguna untuk meningkatkan strategi belajar saya.'),
  _Item('pu',   'KEGUNAAN YANG DIRASAKAN', _amber,
      'Secara keseluruhan, AI Learning Tracker bermanfaat untuk mendukung proses belajar saya.'),
];

const _scaleLabels = [
  'Sangat Tidak Setuju',
  'Tidak Setuju',
  'Netral',
  'Setuju',
  'Sangat Setuju',
];

// ── State + Provider ───────────────────────────────────────────

class TamState {
  final int currentIndex;
  final List<int?> answers; // 10 nullable ints
  final bool isSubmitting;
  final bool isSubmitted;
  final String? error;

  const TamState({
    this.currentIndex = 0,
    required this.answers,
    this.isSubmitting = false,
    this.isSubmitted = false,
    this.error,
  });

  int? get currentAnswer => answers[currentIndex];
  bool get isLast => currentIndex == 9;
  bool get allAnswered => answers.every((a) => a != null);
  double get progress => (currentIndex + 1) / 10.0;

  TamState copyWith({
    int? currentIndex, List<int?>? answers, bool? isSubmitting,
    bool? isSubmitted, String? error, bool clearError = false,
  }) => TamState(
    currentIndex: currentIndex ?? this.currentIndex,
    answers: answers ?? this.answers,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    isSubmitted: isSubmitted ?? this.isSubmitted,
    error: clearError ? null : (error ?? this.error),
  );
}

class TamNotifier extends StateNotifier<TamState> {
  TamNotifier() : super(TamState(answers: List.filled(10, null)));

  final _sb = Supabase.instance.client;

  void select(int score) {
    final upd = List<int?>.from(state.answers);
    upd[state.currentIndex] = score;
    state = state.copyWith(answers: upd, clearError: true);
  }

  void next() {
    if (state.currentAnswer != null && !state.isLast) {
      state = state.copyWith(currentIndex: state.currentIndex + 1);
    }
  }

  void prev() {
    if (state.currentIndex > 0) {
      state = state.copyWith(currentIndex: state.currentIndex - 1);
    }
  }

  Future<void> submit() async {
    if (!state.allAnswered) return;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final uid = _sb.auth.currentUser!.id;

      // Hapus data lama jika ada, lalu insert baru
      await _sb.from('tam_responses').delete().eq('user_id', uid);
      await _sb.from('tam_responses').insert({
        'user_id': uid,
        'peou_1': state.answers[0], 'peou_2': state.answers[1],
        'peou_3': state.answers[2], 'peou_4': state.answers[3],
        'peou_5': state.answers[4],
        'pu_1': state.answers[5],   'pu_2': state.answers[6],
        'pu_3': state.answers[7],   'pu_4': state.answers[8],
        'pu_5': state.answers[9],
      });
      state = state.copyWith(isSubmitting: false, isSubmitted: true);
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: 'Gagal menyimpan. Periksa koneksi.');
    }
  }
}

final tamProvider =
    StateNotifierProvider.autoDispose<TamNotifier, TamState>(
  (ref) => TamNotifier(),
);

// ── Screen ─────────────────────────────────────────────────────

class TamEvaluationScreen extends ConsumerWidget {
  const TamEvaluationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tamProvider);
    final notifier = ref.read(tamProvider.notifier);

    if (state.isSubmitted) return const _TamResultScreen();

    ref.listen<TamState>(tamProvider, (_, next) {
      // Tampilkan error jika gagal submit
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    });

    final item = _items[state.currentIndex];

    return PopScope(
      canPop: state.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && state.currentIndex > 0) { notifier.prev(); }
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white, elevation: 0, centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () {
              if (state.currentIndex > 0) notifier.prev();
              else context.pop();
            },
          ),
          title: const Text('KUESIONER EVALUASI TAM',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  letterSpacing: 1, color: _purple)),
          actions: [
            Padding(padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text('${state.currentIndex + 1}/10',
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))))),
          ],
        ),
        body: Column(children: [
          // Progress bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.progress,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(item.color),
                minHeight: 5,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type badge
                  _TypeBadge(label: item.label, color: item.color),
                  const SizedBox(height: 18),
                  // Statement
                  Text(item.text,
                      style: const TextStyle(fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E), height: 1.4)),
                  const SizedBox(height: 24),
                  // Options
                  ...List.generate(5, (i) {
                    final score = i + 1;
                    final isSelected = state.currentAnswer == score;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TamOption(
                        label: _scaleLabels[i], score: score,
                        isSelected: isSelected, color: item.color,
                        onTap: () => notifier.select(score),
                      ),
                    );
                  }),
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(state.error!,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFFEF4444))),
                    ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ]),
        bottomNavigationBar: _BottomBar(state: state, notifier: notifier),
      ),
    );
  }
}

// ── Bottom bar (Sebelumnya + Berikutnya) ──────────────────────

class _BottomBar extends StatelessWidget {
  final TamState state;
  final TamNotifier notifier;
  const _BottomBar({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final item = _items[state.currentIndex];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      color: Colors.white,
      child: Row(children: [
        // Sebelumnya
        if (state.currentIndex > 0)
          Expanded(
            child: OutlinedButton(
              onPressed: notifier.prev,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1A1A2E),
                side: BorderSide(color: Colors.grey[300]!),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                minimumSize: const Size(0, 52),
              ),
              child: const Text('< Sebelumnya',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          )
        else
          const Expanded(child: SizedBox()),
        const SizedBox(width: 12),
        // Berikutnya / Submit
        Expanded(
          child: ElevatedButton(
            onPressed: state.currentAnswer == null || state.isSubmitting
                ? null
                : () {
                    if (state.isLast) notifier.submit();
                    else notifier.next();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: item.color,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[200],
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              minimumSize: const Size(0, 52), elevation: 0,
            ),
            child: state.isSubmitting
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(state.isLast ? 'Kirim Evaluasi ✓' : 'Berikutnya >',
                    style: const TextStyle(fontWeight: FontWeight.w700,
                        fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final String label; final Color color;
  const _TypeBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.auto_awesome_outlined, size: 13, color: color),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 10,
          fontWeight: FontWeight.w800, color: color, letterSpacing: 0.7)),
    ]),
  );
}

class _TamOption extends StatelessWidget {
  final String label; final int score; final bool isSelected;
  final Color color; final VoidCallback onTap;
  const _TamOption({required this.label, required this.score,
    required this.isSelected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 58,
      decoration: BoxDecoration(
        color: isSelected ? color.withOpacity(0.06) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? color : Colors.grey[300]!, width: isSelected ? 2 : 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(child: Text(label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected ? color : const Color(0xFF1A1A2E)))),
        isSelected
            ? Container(width: 32, height: 32,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 18))
            : Container(width: 32, height: 32,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey[300]!)),
                child: Center(child: Text('$score',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500])))),
      ]),
    ),
  );
}

// ── TAM Result Screen ──────────────────────────────────────────

class _TamResultScreen extends ConsumerWidget {
  const _TamResultScreen();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tamProvider);

    // Hitung skor
    final peouSum = (state.answers[0]! + state.answers[1]! +
        state.answers[2]! + state.answers[3]! + state.answers[4]!);
    final puSum = (state.answers[5]! + state.answers[6]! +
        state.answers[7]! + state.answers[8]! + state.answers[9]!);
    final meanPeou = (peouSum / 5.0);
    final meanPu   = (puSum / 5.0);

    String _level(double v) {
      if (v >= 4.2) return 'Sangat Tinggi';
      if (v >= 3.4) return 'Tinggi';
      if (v >= 2.6) return 'Cukup';
      if (v >= 1.8) return 'Rendah';
      return 'Sangat Rendah';
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 16),
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline_rounded,
                  color: Color(0xFF10B981), size: 44),
            ),
            const SizedBox(height: 20),
            const Text('Evaluasi TAM Selesai!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            Text(
              'Terima kasih! Respons Anda sangat berharga\nuntuk penelitian ini. 🙏',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.6),
            ),
            const SizedBox(height: 28),

            // Hasil Skor
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10, offset: const Offset(0, 2))],
              ),
              child: Column(children: [
                const Text('Hasil Evaluasi Kamu',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E))),
                const SizedBox(height: 16),
                _ScoreRow(
                  label: 'Kemudahan Penggunaan (PEOU)',
                  score: meanPeou,
                  level: _level(meanPeou),
                  color: const Color(0xFF5C4DFF),
                ),
                const SizedBox(height: 12),
                _ScoreRow(
                  label: 'Kegunaan yang Dirasakan (PU)',
                  score: meanPu,
                  level: _level(meanPu),
                  color: const Color(0xFF10B981),
                ),
              ]),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: () => context.go('/dashboard'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('Kembali ke Beranda',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String label, level;
  final double score;
  final Color color;
  const _ScoreRow({required this.label, required this.score,
      required this.level, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(child: Text(label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)))),
        Text('${score.toStringAsFixed(1)}/5.0',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                color: color)),
      ]),
      const SizedBox(height: 6),
      LinearProgressIndicator(
        value: score / 5.0,
        backgroundColor: Colors.grey[200],
        color: color,
        minHeight: 6,
        borderRadius: BorderRadius.circular(4),
      ),
      const SizedBox(height: 4),
      Text(level, style: TextStyle(fontSize: 11, color: color,
          fontWeight: FontWeight.w600)),
    ]);
  }
}
