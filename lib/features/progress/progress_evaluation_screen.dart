// lib/features/progress/progress_evaluation_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/assessment_result.dart';
import '../../services/assessment_service.dart';
import 'providers/progress_provider.dart';

const _purple = Color(0xFF5C4DFF);
const _teal   = Color(0xFF4ECDC4);
const _amber  = Color(0xFFF59E0B);
const _bg     = Color(0xFFF5F7FA);

class ProgressEvaluationScreen extends ConsumerWidget {
  const ProgressEvaluationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(progressProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('Evaluasi Perkembangan',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _purple),
            onPressed: () => ref.read(progressProvider.notifier).load(),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator(color: _purple))
          : RefreshIndicator(
              color: _purple,
              onRefresh: () => ref.read(progressProvider.notifier).load(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _HeaderCard(),
                  const SizedBox(height: 16),
                  _sectionLabel('RIWAYAT PENILAIAN REGULASI DIRI'),
                  const SizedBox(height: 10),
                  if (state.assessments.isEmpty)
                    _emptyCard('Belum ada riwayat penilaian.\nSelesaikan Penilaian Awal terlebih dahulu.')
                  else
                    ...state.assessments.map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _AssessmentCard(assessment: a),
                    )),
                  if (state.hasDelta) ...[
                    const SizedBox(height: 16),
                    _sectionLabel('WAWASAN TREN SAAT INI'),
                    const SizedBox(height: 10),
                    _TrendRow(state: state),
                  ],
                  const SizedBox(height: 20),
                  _ReassessmentButton(gate: state.gate),
                  const SizedBox(height: 24),
                ]),
              ),
            ),
    );
  }

  Widget _sectionLabel(String t) => Align(
    alignment: Alignment.centerLeft,
    child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
        color: Colors.grey[500], letterSpacing: 0.7)),
  );

  Widget _emptyCard(String msg) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(16)),
    child: Text(msg, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Colors.grey[400], height: 1.5)),
  );
}

// ── Tombol Penilaian Ulang (3 kondisi: terkunci / aktif / selesai) ──
//
// Sesuai desain single-cycle hasil revisi BAB 3.4.1: tombol terkunci
// sampai 28 hari sejak Baseline (assessed_at), dan begitu T2 diisi,
// tidak terbuka lagi (bukan "minggu depan lagi").

class _ReassessmentButton extends StatelessWidget {
  final ReassessmentGate? gate;
  const _ReassessmentButton({required this.gate});

  @override
  Widget build(BuildContext context) {
    // Data gate belum siap (masih loading) — tampilkan tombol nonaktif
    // sementara sebagai fallback aman, bukan aktif secara default.
    if (gate == null) {
      return _lockedButton('Memuat status...');
    }

    if (gate!.hasReassessed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFD1FAE5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF065F46), size: 20),
          const SizedBox(width: 8),
          const Flexible(
            child: Text(
              'Penilaian Ulang Regulasi Diri sudah diselesaikan.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: Color(0xFF065F46)),
            ),
          ),
        ]),
      );
    }

    if (!gate!.canReassess) {
      final days = gate!.daysRemaining ?? 28;
      return _lockedButton(days > 0
          ? 'Tersedia dalam $days hari lagi'
          : 'Belum tersedia');
    }

    // Sudah lewat 28 hari & belum pernah diisi → tombol aktif
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton(
        onPressed: () => context.push('/reassessment'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _purple, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: const Text('Lakukan Penilaian Ulang Regulasi Diri',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _lockedButton(String label) => SizedBox(
    width: double.infinity, height: 52,
    child: ElevatedButton.icon(
      onPressed: null,
      icon: const Icon(Icons.lock_outline_rounded, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        disabledBackgroundColor: Colors.grey[200],
        disabledForegroundColor: Colors.grey[500],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
    ),
  );
}

// ── Header Card ────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
          colors: [_purple, Color(0xFF3DBDB7)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20)),
        child: const Text('EVALUASI METAKOGNITIF',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: Colors.white, letterSpacing: 0.8)),
      ),
      const SizedBox(height: 10),
      const Text('Pantau Pertumbuhan Belajar',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
              color: Colors.white)),
      const SizedBox(height: 6),
      Text('Bandingkan skor penilaian regulasi diri Anda secara progresif.',
          style: TextStyle(fontSize: 13,
              color: Colors.white.withOpacity(0.85), height: 1.4)),
    ]),
  );
}

// ── Assessment History Card ────────────────────────────────────

class _AssessmentCard extends StatelessWidget {
  final AssessmentResult assessment;
  const _AssessmentCard({required this.assessment});

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    final isBaseline = assessment.assessmentType == 'baseline';
    final color = isBaseline ? _purple : _teal;
    final label = isBaseline
        ? 'T${assessment.assessmentSequence} (Baseline)'
        : 'T${assessment.assessmentSequence} (Reassessment)';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(_fmt(assessment.completedAt),
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('Skor Total: ', style: TextStyle(fontSize: 15,
              fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
          Text('${assessment.scoreTotal}/60',
              style: const TextStyle(fontSize: 17,
                  fontWeight: FontWeight.w800, color: _purple)),
          const Spacer(),
          _Chip(assessment.category),
        ]),
        const SizedBox(height: 4),
        Text('(Plan: ${assessment.scorePlanning} • '
            'Monitor: ${assessment.scoreMonitoring} • '
            'Eval: ${assessment.scoreEvaluating})',
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        const SizedBox(height: 10),
        _Bar('Perencanaan', assessment.planningPercent, _purple),
        const SizedBox(height: 4),
        _Bar('Pemantauan', assessment.monitoringPercent, _teal),
        const SizedBox(height: 4),
        _Bar('Evaluasi', assessment.evaluatingPercent, _amber),
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  final String label; final double value; final Color color;
  const _Bar(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 6, height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 6),
    SizedBox(width: 80, child: Text(label,
        style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
    Expanded(child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        backgroundColor: Colors.grey[200],
        valueColor: AlwaysStoppedAnimation<Color>(color),
        minHeight: 6,
      ),
    )),
    const SizedBox(width: 6),
    Text('${(value * 20).round()}/20',
        style: TextStyle(fontSize: 11, color: Colors.grey[500])),
  ]);
}

class _Chip extends StatelessWidget {
  final String cat;
  const _Chip(this.cat);
  Color get _bgColor {
    switch (cat) {
      case 'Tinggi': return const Color(0xFFD1FAE5);
      case 'Sedang': return const Color(0xFFFEF3C7);
      default:       return const Color(0xFFFEE2E2);
    }
  }
  Color get _fgColor {
    switch (cat) {
      case 'Tinggi': return const Color(0xFF065F46);
      case 'Sedang': return const Color(0xFF92400E);
      default:       return const Color(0xFF991B1B);
    }
  }
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: _bgColor,
        borderRadius: BorderRadius.circular(20)),
    child: Text(cat, style: TextStyle(fontSize: 12,
        fontWeight: FontWeight.w700, color: _fgColor)),
  );
}

// ── Trend Row ──────────────────────────────────────────────────

class _TrendRow extends StatelessWidget {
  final ProgressState state;
  const _TrendRow({required this.state});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(16)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _TC('Perencanaan', state.trendFor('planning')),
      _TC('Pemantauan', state.trendFor('monitoring')),
      _TC('Evaluasi', state.trendFor('evaluating')),
    ]),
  );
}

class _TC extends StatelessWidget {
  final String label, trend;
  const _TC(this.label, this.trend);

  Color get _color {
    switch (trend) {
      case 'Meningkat': return const Color(0xFF10B981);
      case 'Menurun':   return const Color(0xFFEF4444);
      default:          return const Color(0xFFF59E0B);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
    const SizedBox(height: 6),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(trend, style: TextStyle(fontSize: 12,
          fontWeight: FontWeight.w700, color: _color)),
    ),
  ]);
}
