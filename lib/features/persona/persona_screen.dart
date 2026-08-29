// lib/features/persona/persona_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/persona_and_recommendation.dart';
import '../../models/assessment_result.dart';
import '../../services/persona_recommendation_service.dart';
import '../recommendation/providers/recommendation_provider.dart';
import 'providers/persona_provider.dart';

const _bg = Color(0xFFF5F7FA);

class PersonaScreen extends ConsumerWidget {
  const PersonaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(personaProvider);

    ref.listen<String?>(
      personaProvider.select((value) => value.feedbackMessage),
      (previous, next) {
        if (next == null || next == previous) return;

        final latestState = ref.read(personaProvider);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(next),
              behavior: SnackBarBehavior.floating,
              backgroundColor: latestState.feedbackIsError
                  ? const Color(0xFFB91C1C)
                  : const Color(0xFF374151),
              action: SnackBarAction(
                label: 'Tutup',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );

        Future.microtask(
          () => ref.read(personaProvider.notifier).clearFeedback(),
        );
      },
    );

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Persona Pembelajaran',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
        actions: [
          if (state.isTriggering)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF5C4DFF))),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF5C4DFF)),
              tooltip: 'Perbarui Analisis',
              onPressed: () async {
                // triggerAnalysis() memanggil edge function run-kmeans, yang
                // (selain menghitung ulang persona) juga MEREGENERASI teks
                // rekomendasi/wawasan AI (kolom ai_insight) di backend --
                // termasuk angka "X peringatan" yang dikutip di dalamnya.
                // recommendationProvider punya cache-nya SENDIRI yang tidak
                // otomatis tahu ada data baru, jadi tanpa invalidate ini,
                // layar Rekomendasi akan terus menampilkan angka peringatan
                // yang sudah usang (mis. "3 peringatan") walau layar Persona
                // di sini sudah menunjukkan angka real-time yang baru (mis.
                // "4 peringatan") -- itulah sumber ketidaksinkronan yang
                // terlihat oleh pengguna. Invalidate di sini memaksa
                // recommendationProvider memuat ulang dari DB saat
                // berikutnya dibuka, sehingga kedua layar konsisten.
                await ref.read(personaProvider.notifier).triggerAnalysis();
                if (!context.mounted) return;
                if (!ref.read(personaProvider).feedbackIsError) {
                  ref.invalidate(recommendationProvider);
                }
              },
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF5C4DFF)))
          : RefreshIndicator(
              color: const Color(0xFF5C4DFF),
              onRefresh: () => ref.read(personaProvider.notifier).load(),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // Current persona
                        if (state.current != null)
                          _ActivePersonaCard(persona: state.current!)
                        else
                          const _NoPersonaCard(),
                        const SizedBox(height: 16),

                        // Breakdown jenis peringatan (28 hari terakhir)
                        if (state.warningBreakdown.isNotEmpty) ...[
                          _WarningBreakdownCard(items: state.warningBreakdown),
                          const SizedBox(height: 16),
                        ],

                        // Skor SRL (planning/monitoring/evaluating) --
                        // ditampilkan BERDAMPINGAN dengan breakdown warning
                        // di atas, TANPA kalimat yang mengklaim satu
                        // menyebabkan yang lain -- itu klaim kausal yang
                        // butuh uji statistik lintas banyak pengguna, bukan
                        // sesuatu yang bisa disimpulkan sistem dari data
                        // SATU pengguna saja. Pembaca (pengguna atau peneliti
                        // yang membaca skripsi) yang menyimpulkan sendiri
                        // dari pola yang terlihat.
                        if (state.latestAssessment != null) ...[
                          _SrlScoreBreakdownCard(
                              assessment: state.latestAssessment!),
                          const SizedBox(height: 16),
                        ],

                        // History personas
                        if (state.history.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text('Riwayat Persona',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[500])),
                          ),
                          ...state.history.map((p) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _HistoryPersonaCard(persona: p),
                              )),
                        ],

                        // Bottom info note
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '* Kategori Persona diperbarui secara cerdas oleh model '
                            'sistem regulasi setiap minggu berdasarkan keteraturan '
                            'pengisian target dan durasi sesi aktif.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                                height: 1.5,
                                fontStyle: FontStyle.italic),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ── Active Persona Card ────────────────────────────────────────

class _ActivePersonaCard extends StatelessWidget {
  final PersonaInfo persona;
  const _ActivePersonaCard({required this.persona});

  @override
  Widget build(BuildContext context) {
    final c = persona.color;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.3), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header: ikon + label kecil "PERSONA AKTIF ANDA" di baris atas,
        // lalu nama persona SENDIRIAN di baris penuhnya sendiri (supaya
        // tidak pernah terpotong 2 baris hanya karena berbagi ruang dengan
        // badge), dan badge warning tier ("Mandiri"/"Responsif") di baris
        // rapi di bawah nama. Badge tren dihapus atas permintaan pengguna
        // -- dianggap tidak informatif dan membingungkan, cukup satu badge
        // warning tier saja yang ditampilkan di sini.
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: c.withOpacity(0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.auto_awesome_outlined, color: c, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('PERSONA AKTIF ANDA',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: c,
                        letterSpacing: 0.5)),
              ),
              const SizedBox(height: 6),
              Text(persona.displayName,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: Color(0xFF1A1A2E))),
              // Badge warning tier ("Mandiri"/"Responsif") -- sama gaya
              // dengan pill di Dashboard. Hilang otomatis (bukan pill
              // kosong) kalau warningTierDisplayLabel null.
              if (persona.warningTierDisplayLabel != null) ...[
                const SizedBox(height: 6),
                _Pill(
                  label: persona.warningTierDisplayLabel!,
                  color: persona.warningTierColor,
                ),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 14),

        Text(persona.shortDescription,
            style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF374151),
                fontWeight: FontWeight.w500)),
        const Divider(height: 24),

        // Karakteristik
        const Text('Karakteristik Utama:',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
        const SizedBox(height: 8),
        ...persona.characteristics
            .map((t) => _BulletText(text: t, color: const Color(0xFF5C4DFF))),
        const Divider(height: 24),

        // Kekuatan + Saran AI (2 kolom)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: _TwoColSection(
            title: 'Kekuatan:',
            titleColor: const Color(0xFF10B981),
            items: persona.strengths,
          )),
          const SizedBox(width: 12),
          Expanded(
              child: _TwoColSection(
            title: 'Saran Tindakan AI:',
            titleColor: const Color(0xFF5C4DFF),
            items: persona.aiTips,
          )),
        ]),

        // Feature values
        if (persona.featureValues.isNotEmpty) ...[
          const Divider(height: 24),
          _FeatureValues(values: persona.featureValues),
        ],
      ]),
    );
  }
}

// ── History Persona Card ───────────────────────────────────────

// ── Warning Breakdown Card ─────────────────────────────────────

class _WarningBreakdownCard extends StatelessWidget {
  final List<RuleWarningCount> items;
  const _WarningBreakdownCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final maxCount = items.map((e) => e.count).reduce((a, b) => a > b ? a : b);
    final totalCount = items.fold<int>(0, (sum, e) => sum + e.count);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Jenis Peringatan (28 Hari Terakhir)',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E))),
          const SizedBox(height: 2),
          Text('Total $totalCount peringatan — ini yang paling sering muncul',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 16),
          for (var i = 0; i < items.length; i++) ...[
            _WarningBreakdownRow(item: items[i], maxCount: maxCount),
            if (i < items.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _WarningBreakdownRow extends StatelessWidget {
  final RuleWarningCount item;
  final int maxCount;
  const _WarningBreakdownRow({required this.item, required this.maxCount});

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount == 0 ? 0.0 : item.count / maxCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(item.displayLabel,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E))),
            ),
            Text('${item.count}x',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5C4DFF))),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: Colors.grey[100],
            valueColor: const AlwaysStoppedAnimation(Color(0xFF5C4DFF)),
          ),
        ),
        const SizedBox(height: 4),
        Text(item.description,
            style:
                TextStyle(fontSize: 11, color: Colors.grey[500], height: 1.4)),
      ],
    );
  }
}

// ── SRL Score Breakdown Card ────────────────────────────────────

class _SrlDimensionSpec {
  final String key; // 'planning' | 'monitoring' | 'evaluating'
  final String label;
  final String description; // ringkasan makna dimensi, dari teks kuesioner asli
  final Color color;
  const _SrlDimensionSpec(this.key, this.label, this.description, this.color);
}

// Deskripsi tiap dimensi dirangkum dari teks 12-item kuesioner ASLI (lihat
// _questions di reassessment_screen.dart) -- bukan interpretasi bebas,
// supaya konsisten dengan instrumen yang benar-benar dipakai mengukur
// skor ini.
//
// Warna didefinisikan LOKAL di file ini (bukan impor dari dashboard_cards.dart)
// supaya persona_screen.dart tidak bergantung ke file lain di luar
// kebutuhannya sendiri -- nilai hex sama persis dengan _primaryPurple/_teal/
// _amber di dashboard_cards.dart supaya identitas warna tetap konsisten
// terlihat di seluruh app.
const _srlPlanningColor = Color(0xFF5C4DFF);
const _srlMonitoringColor = Color(0xFF4ECDC4);
const _srlEvaluatingColor = Color(0xFFF59E0B);

const _srlDimensions = [
  _SrlDimensionSpec(
      'planning',
      'Perencanaan',
      'Menetapkan tujuan, strategi, target waktu, dan sumber belajar sebelum mulai belajar.',
      _srlPlanningColor),
  _SrlDimensionSpec(
      'monitoring',
      'Pemantauan',
      'Memantau pemahaman dan kemajuan, serta menyesuaikan strategi selama belajar berlangsung.',
      _srlMonitoringColor),
  _SrlDimensionSpec(
      'evaluating',
      'Evaluasi',
      'Mengevaluasi pencapaian tujuan dan merefleksikan strategi setelah belajar selesai.',
      _srlEvaluatingColor),
];

class _SrlScoreBreakdownCard extends StatelessWidget {
  final AssessmentResult assessment;
  const _SrlScoreBreakdownCard({required this.assessment});

  int _scoreFor(String key) {
    switch (key) {
      case 'planning':
        return assessment.scorePlanning;
      case 'monitoring':
        return assessment.scoreMonitoring;
      case 'evaluating':
        return assessment.scoreEvaluating;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tiap dimensi terdiri 4 item, skala 1-5 per item -> rentang skor 4-20.
    const minScore = 4;
    const maxScore = 20;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Skor Regulasi Diri per Dimensi',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E))),
          const SizedBox(height: 2),
          Text(
            assessment.assessmentType == 'reassessment'
                ? 'Dari asesmen ulang (T2) terakhirmu'
                : 'Dari asesmen awal (T1) — isi asesmen ulang setelah 28 hari untuk melihat perkembangan',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _srlDimensions.length; i++) ...[
            _SrlDimensionRow(
              spec: _srlDimensions[i],
              score: _scoreFor(_srlDimensions[i].key),
              minScore: minScore,
              maxScore: maxScore,
            ),
            if (i < _srlDimensions.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _SrlDimensionRow extends StatelessWidget {
  final _SrlDimensionSpec spec;
  final int score;
  final int minScore;
  final int maxScore;
  const _SrlDimensionRow({
    required this.spec,
    required this.score,
    required this.minScore,
    required this.maxScore,
  });

  @override
  Widget build(BuildContext context) {
    final fraction =
        ((score - minScore) / (maxScore - minScore)).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(spec.label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E))),
            ),
            Text('$score/$maxScore',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: spec.color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: Colors.grey[100],
            valueColor: AlwaysStoppedAnimation(spec.color),
          ),
        ),
        const SizedBox(height: 4),
        Text(spec.description,
            style:
                TextStyle(fontSize: 11, color: Colors.grey[500], height: 1.4)),
      ],
    );
  }
}

class _HistoryPersonaCard extends StatefulWidget {
  final PersonaInfo persona;
  const _HistoryPersonaCard({required this.persona});
  @override
  State<_HistoryPersonaCard> createState() => _HistoryPersonaCardState();
}

class _HistoryPersonaCardState extends State<_HistoryPersonaCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.persona.color;
    final weekStr = _fmtWeek(widget.persona.weekStart);
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        // Header (always visible)
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.auto_awesome_outlined, color: c, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.persona.displayName,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E))),
                      Text('Minggu: $weekStr',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ]),
              ),
              Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey[400]),
            ]),
          ),
        ),
        // Expanded content
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.persona.shortDescription,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[600], height: 1.5)),
              const SizedBox(height: 10),
              ...widget.persona.characteristics
                  .map((t) => _BulletText(text: t, color: c, fontSize: 12)),
              if (widget.persona.featureValues.isNotEmpty) ...[
                const SizedBox(height: 10),
                _FeatureValues(
                    values: widget.persona.featureValues, small: true),
              ],
            ]),
          ),
      ]),
    );
  }

  String _fmtWeek(DateTime d) {
    final end = d.add(const Duration(days: 6));
    return '${d.day}/${d.month} – ${end.day}/${end.month}/${end.year}';
  }
}

// ── No Persona Card ────────────────────────────────────────────

class _NoPersonaCard extends StatelessWidget {
  const _NoPersonaCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_awesome_outlined, size: 56, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text('Persona Belum Terbentuk',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.grey[400])),
        const SizedBox(height: 8),
        Text(
          'Catat minimal 1 minggu aktivitas belajarmu, lalu sistem akan '
          'menganalisis pola belajarmu secara otomatis setiap Senin pagi.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[400], height: 1.5),
        ),
      ]),
    );
  }
}

// ── Feature Values Mini Chart ──────────────────────────────────

class _FeatureValues extends StatelessWidget {
  final Map<String, double> values;
  final bool small;
  const _FeatureValues({required this.values, this.small = false});

  static const _labels = {
    'x1': 'Frekuensi',
    'x2': 'Durasi',
    'x3': 'Fokus',
    'x4': 'Konsistensi',
    'x5': 'Progres',
  };

  @override
  Widget build(BuildContext context) {
    final keys = ['x1', 'x2', 'x3', 'x4', 'x5'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Data Aktivitas Minggu Ini:',
          style: TextStyle(
              fontSize: small ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500])),
      const SizedBox(height: 6),
      ...keys.map((k) {
        final v = values[k] ?? 0;
        final maxVal = k == 'x2' ? 120.0 : 100.0;
        final pct = (v / maxVal).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(children: [
            SizedBox(
              width: 80,
              child: Text(_labels[k] ?? k,
                  style: TextStyle(
                      fontSize: small ? 10 : 11, color: Colors.grey[500])),
            ),
            Expanded(
                child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: Colors.grey[200],
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF5C4DFF)),
                minHeight: 5,
              ),
            )),
            const SizedBox(width: 6),
            Text(v.toStringAsFixed(1),
                style: TextStyle(
                    fontSize: small ? 10 : 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF5C4DFF))),
          ]),
        );
      }),
    ]);
  }
}

// ── Shared Sub-widgets ─────────────────────────────────────────

// Pill/badge generik dengan style seragam -- dipakai untuk badge warning
// tier ("Mandiri"/"Responsif") maupun badge tren ("Tren: Meningkat"), agar
// keduanya konsisten secara visual dan bisa disusun rapi berdampingan di
// dalam Wrap tanpa terpotong.
class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );
}

class _BulletText extends StatelessWidget {
  final String text;
  final Color color;
  final double fontSize;
  const _BulletText(
      {required this.text, required this.color, this.fontSize = 13});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 8),
            child: Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
          ),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: fontSize,
                      color: const Color(0xFF374151),
                      height: 1.45))),
        ]),
      );
}

class _TwoColSection extends StatelessWidget {
  final String title;
  final Color titleColor;
  final List<String> items;
  const _TwoColSection(
      {required this.title, required this.titleColor, required this.items});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: titleColor)),
          const SizedBox(height: 6),
          ...items.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('• $t',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600], height: 1.4)),
              )),
        ],
      );
}
