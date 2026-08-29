// lib/features/reassessment/reassessment_screen.dart
//
// Hampir identik dengan BaselineScreen — perbedaan utama:
//   1. Judul AppBar: "PENILAIAN ULANG"
//   2. Warna tombol & badge dimensi: dark navy #1A1A2E
//   3. Setelah submit → navigate ke /progress (bukan /baseline/result)
//   4. Menggunakan reassessmentProvider (terpisah dari baselineProvider)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../baseline/providers/baseline_provider.dart';

// Provider terpisah agar tidak konflik dengan baseline flow
final reassessmentProvider =
    StateNotifierProvider.autoDispose<BaselineNotifier, BaselineState>(
  (ref) => BaselineNotifier(),
);

const _dark = Color(0xFF1A1A2E);
const _bg = Color(0xFFF5F7FA);

// Reuse label dari baseline screen
const _scaleLabels = [
  'Sangat Tidak Sesuai',
  'Tidak Sesuai',
  'Netral',
  'Sesuai',
  'Sangat Sesuai',
];

// Reuse pertanyaan dari baseline screen — sama persis 12 item MSLQ
const _questions = [
  ('Perencanaan', 'Sebelum mulai belajar, saya menetapkan tujuan yang ingin dicapai.'),
  ('Perencanaan', 'Saya merencanakan strategi belajar sebelum memulai suatu materi.'),
  ('Perencanaan', 'Saya menentukan target waktu belajar sebelum memulai kegiatan belajar.'),
  ('Perencanaan', 'Saya mempersiapkan sumber belajar yang diperlukan sebelum belajar.'),
  ('Pemantauan', 'Saya memantau apakah saya memahami materi yang sedang dipelajari.'),
  ('Pemantauan', 'Saya memeriksa kemajuan belajar saya terhadap target yang telah ditetapkan.'),
  ('Pemantauan', 'Saya menyadari ketika konsentrasi saya mulai menurun saat belajar.'),
  ('Pemantauan', 'Saya menyesuaikan strategi belajar ketika cara yang digunakan tidak efektif.'),
  ('Evaluasi', 'Setelah belajar, saya mengevaluasi apakah tujuan belajar telah tercapai.'),
  ('Evaluasi', 'Saya merefleksikan efektivitas strategi belajar yang telah digunakan.'),
  ('Evaluasi', 'Saya mengidentifikasi kesalahan atau kelemahan dalam proses belajar saya.'),
  ('Evaluasi', 'Saya merencanakan perbaikan untuk sesi belajar berikutnya berdasarkan hasil evaluasi sebelumnya.'),
];

Color _dimColor(String dim) {
  switch (dim) {
    case 'Perencanaan': return const Color(0xFF5C4DFF);
    case 'Pemantauan':  return const Color(0xFF4ECDC4);
    default:            return const Color(0xFFF59E0B);
  }
}

class ReassessmentScreen extends ConsumerWidget {
  const ReassessmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reassessmentProvider);
    final notifier = ref.read(reassessmentProvider.notifier);
    final (dim, qText) = _questions[state.currentIndex];
    final activeColor = _dimColor(dim);

    // Navigate langsung ke TAM Evaluation setelah T2 berhasil disimpan
    // (tanpa jeda tambahan — lihat BAB 3.5.2 hasil revisi: TAM diisi
    // selagi pengalaman memakai sistem masih segar di ingatan responden).
    ref.listen<BaselineState>(reassessmentProvider, (_, next) {
      if (next.result != null) context.go('/tam');
    });

    return PopScope(
      canPop: state.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && state.currentIndex > 0) { notifier.prevQuestion(); }
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white, elevation: 0, centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () {
              if (state.currentIndex > 0) notifier.prevQuestion();
              else context.pop();
            },
          ),
          title: const Text('PENILAIAN ULANG',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  letterSpacing: 1.2, color: _dark)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('${state.currentIndex + 1}/12',
                    style: const TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w700, color: _dark)),
              ),
            ),
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
                valueColor: const AlwaysStoppedAnimation<Color>(_dark),
                minHeight: 5,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Dimension badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: activeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: activeColor.withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.psychology_outlined, size: 14, color: activeColor),
                    const SizedBox(width: 6),
                    Text('DIMENSI: ${dim.toUpperCase()}',
                        style: TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w700, color: activeColor,
                            letterSpacing: 0.8)),
                  ]),
                ),
                const SizedBox(height: 20),

                // Question
                Text(qText,
                    style: const TextStyle(fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E), height: 1.4)),
                const SizedBox(height: 8),
                Text(
                  'Pilihlah opsi skala kesesuaian di bawah ini yang paling mewakili '
                  'perilaku belajar nyata Anda di lingkungan akademik kampus.',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF5C4DFF),
                      height: 1.4),
                ),
                const SizedBox(height: 20),

                // Likert options
                ...List.generate(5, (i) {
                  final score = i + 1;
                  final isSelected = state.currentAnswer == score;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onTap: () => notifier.selectAnswer(score),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 56,
                        decoration: BoxDecoration(
                          color: isSelected ? _dark.withOpacity(0.04) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? _dark : Colors.grey[300]!,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(children: [
                          Expanded(child: Text(_scaleLabels[i],
                              style: TextStyle(fontSize: 15,
                                  fontWeight: isSelected
                                      ? FontWeight.w700 : FontWeight.w400,
                                  color: isSelected ? _dark
                                      : const Color(0xFF1A1A2E)))),
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? _dark : Colors.grey[100],
                            ),
                            child: Center(child: Text('$score',
                                style: TextStyle(fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected ? Colors.white
                                        : Colors.grey[500]))),
                          ),
                        ]),
                      ),
                    ),
                  );
                }),

                if (state.error != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(state.error!,
                        style: const TextStyle(fontSize: 13,
                            color: Color(0xFFB91C1C))),
                  ),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ]),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          color: Colors.white,
          child: SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: state.currentAnswer != null && !state.isSubmitting
                  ? () {
                      if (state.isLastQuestion) {
                        notifier.submit(type: 'reassessment');
                      } else {
                        notifier.nextQuestion();
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _dark,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[200],
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: state.isSubmitting
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white,
                          strokeWidth: 2.5))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(state.isLastQuestion
                          ? 'Selesai & Lihat Hasil' : 'Selanjutnya',
                          style: const TextStyle(fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}
