// lib/features/reflection/weekly_reflection_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/reflection_provider.dart';

const _purple = Color(0xFF5C4DFF);
const _bg = Color(0xFFF5F7FA);

// ── Definisi 5 pertanyaan ──────────────────────────────────────

class _Q {
  final String title;
  final String hint;
  final String placeholder;
  const _Q({required this.title, required this.hint, required this.placeholder});
}

const _questions = [
  _Q(
    title: '1. Apa saja perkembangan atau pencapaian belajar yang berjalan baik minggu ini?',
    hint: 'Tuliskan materi yang berhasil dipahami, durasi belajar yang terlampaui, atau motivasi yang meningkat.',
    placeholder: 'Misal: Saya sangat puas karena berhasil menyelesaikan bab 1 penulisan skripsi dan belajar Hadoop...',
  ),
  _Q(
    title: '2. Apa saja kendala atau hambatan belajar yang kamu hadapi minggu ini?',
    hint: 'Ceritakan kesulitan teknis, gangguan, atau tantangan dalam proses belajar.',
    placeholder: 'Misal: Sulit fokus karena notifikasi HP terus muncul dan menguras energi...',
  ),
  _Q(
    title: '3. Strategi apa yang kamu gunakan untuk mengatasi hambatan tersebut?',
    hint: 'Metode, teknik, atau pendekatan yang membantumu tetap produktif.',
    placeholder: 'Misal: Menggunakan Sesi Fokus mode Pomodoro dan mematikan notifikasi...',
  ),
  _Q(
    title: '4. Apa yang akan kamu lakukan berbeda atau lebih baik di minggu berikutnya?',
    hint: 'Rencana konkret, perubahan kebiasaan, atau target yang lebih spesifik.',
    placeholder: 'Misal: Menetapkan target harian sebelum mulai belajar dan review di akhir hari...',
  ),
  _Q(
    title: '5. Apa wawasan atau pelajaran terbaru yang kamu dapatkan minggu ini?',
    hint: 'Insight tentang cara belajarmu, diri sendiri, atau bidang studi.',
    placeholder: 'Misal: Saya menyadari belajar di pagi hari jauh lebih efektif untuk saya...',
  ),
];

// ── Screen ─────────────────────────────────────────────────────

class WeeklyReflectionScreen extends ConsumerStatefulWidget {
  const WeeklyReflectionScreen({super.key});
  @override
  ConsumerState<WeeklyReflectionScreen> createState() =>
      _WeeklyReflectionScreenState();
}

class _WeeklyReflectionScreenState
    extends ConsumerState<WeeklyReflectionScreen> {
  final _ctrl = TextEditingController();
  bool _synced = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Sync controller ketika state berubah (step pindah)
  void _syncController(ReflectionState state) {
    final text = state.answers[state.currentStep];
    if (_ctrl.text != text) {
      _ctrl.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  Future<void> _onNext(ReflectionNotifier notifier, bool isLast) async {
    // Auto-save dan lanjut ke soal berikutnya
    await notifier.autoSave();
    if (isLast) {
      await notifier.saveAll();
    } else {
      notifier.goNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reflectionProvider);
    final notifier = ref.read(reflectionProvider.notifier);

    // Sync text controller saat pertama kali atau step berubah
    if (!_synced || _ctrl.text != state.answers[state.currentStep]) {
      _syncController(state);
      _synced = true;
    }

    return PopScope(
      canPop: state.currentStep == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && state.currentStep > 0) { notifier.goPrev(); }
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white, elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () {
              if (state.currentStep > 0) notifier.goPrev();
              else Navigator.of(context).maybePop();
            },
          ),
          title: const Text('Refleksi Belajar Mingguan',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E))),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  state.isSaving ? 'Menyimpan...'
                      : state.isSaved ? 'Tersimpan' : '',
                  style: TextStyle(
                    fontSize: 12,
                    color: state.isSaved
                        ? const Color(0xFF10B981) : Colors.grey[400],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: CustomScrollView(
          slivers: [
            // ── Pertanyaan aktif ───────────────────────────────
            SliverToBoxAdapter(
              child: _QuestionCard(
                state: state,
                controller: _ctrl,
                onChanged: notifier.updateAnswer,
                onNext: () => _onNext(notifier, state.isLastStep),
              ),
            ),

            // ── Riwayat ───────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text('RIWAYAT REFLEKSI BELAJAR',
                    style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[500],
                        letterSpacing: 0.7)),
              ),
            ),
            if (state.isLoadingHistory)
              const SliverToBoxAdapter(
                child: Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: _purple),
                )),
              )
            else if (state.history.isEmpty)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14)),
                  child: Center(
                    child: Text(
                      'Belum ada jurnal refleksi mingguan yang Anda submit sebelumnya.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: _purple,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _HistoryCard(reflection: state.history[i]),
                    childCount: state.history.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Question Card ──────────────────────────────────────────────

class _QuestionCard extends StatelessWidget {
  final ReflectionState state;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onNext;

  const _QuestionCard({
    required this.state,
    required this.controller,
    required this.onChanged,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final q = _questions[state.currentStep];
    final step = state.currentStep;
    final pct = ((step + 1) / 5 * 100).round();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Progress header
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: _purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('PERTANYAAN ${step + 1} DARI 5',
                  style: const TextStyle(fontSize: 10,
                      fontWeight: FontWeight.w800, color: _purple,
                      letterSpacing: 0.5)),
            ),
            const Spacer(),
            Text('$pct%',
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700, color: _purple)),
          ]),
          const SizedBox(height: 10),

          // Progress bar (5 segments)
          Row(children: List.generate(5, (i) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < 4 ? 4 : 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: i < step ? 1.0 : i == step ? 0.5 : 0.0,
                  backgroundColor: Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(_purple),
                  minHeight: 5,
                ),
              ),
            ),
          ))),
          const SizedBox(height: 18),

          // Question title
          Text(q.title,
              style: const TextStyle(fontSize: 17,
                  fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E),
                  height: 1.4)),
          const SizedBox(height: 6),
          Text(q.hint,
              style: const TextStyle(fontSize: 12,
                  color: _purple, height: 1.4)),
          const SizedBox(height: 14),

          // Text area
          TextField(
            controller: controller,
            maxLines: 5,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: q.placeholder,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13,
                  height: 1.5),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[200]!)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[200]!)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _purple)),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 16),

          // Button
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: state.isSaving ? null : onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: state.isSaving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white,
                          strokeWidth: 2))
                  : Text(
                      state.isLastStep ? 'Simpan Refleksi ✓' : 'Selanjutnya',
                      style: const TextStyle(fontSize: 15,
                          fontWeight: FontWeight.w700)),
            ),
          ),

          if (state.isSaved && state.isLastStep) ...[
            const SizedBox(height: 10),
            Center(
              child: Text('✅ Refleksi minggu ini berhasil disimpan!',
                  style: TextStyle(fontSize: 13,
                      color: const Color(0xFF10B981),
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── History Card ───────────────────────────────────────────────

class _HistoryCard extends StatefulWidget {
  final WeeklyReflection reflection;
  const _HistoryCard({required this.reflection});
  @override State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final r = widget.reflection;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: _purple.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_note_rounded, color: _purple, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.weekLabel,
                      style: const TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E))),
                  Text('${r.filledCount}/5 pertanyaan dijawab',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              )),
              Icon(_expanded ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey[400]),
            ]),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(children: [
              if (r.q1Achievements?.isNotEmpty == true)
                _AnswerRow(label: 'Pencapaian', text: r.q1Achievements!),
              if (r.q2Challenges?.isNotEmpty == true)
                _AnswerRow(label: 'Kendala', text: r.q2Challenges!),
              if (r.q3Strategies?.isNotEmpty == true)
                _AnswerRow(label: 'Strategi', text: r.q3Strategies!),
              if (r.q4Improvements?.isNotEmpty == true)
                _AnswerRow(label: 'Rencana', text: r.q4Improvements!),
              if (r.q5Insights?.isNotEmpty == true)
                _AnswerRow(label: 'Wawasan', text: r.q5Insights!),
            ]),
          ),
      ]),
    );
  }
}

class _AnswerRow extends StatelessWidget {
  final String label, text;
  const _AnswerRow({required this.label, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 10,
          fontWeight: FontWeight.w700, color: Colors.grey[400],
          letterSpacing: 0.5)),
      const SizedBox(height: 3),
      Text(text, style: TextStyle(fontSize: 13,
          color: Colors.grey[700], height: 1.4)),
      const Divider(height: 16),
    ]),
  );
}
