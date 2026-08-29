// lib/models/assessment_result.dart

class AssessmentResult {
  final String id;
  final String userId;
  final String assessmentType; // 'baseline' | 'reassessment'
  final int assessmentSequence;
  final List<int> items; // 12 jawaban Likert 1-5
  final int scorePlanning;
  final int scoreMonitoring;
  final int scoreEvaluating;
  final int scoreTotal;
  final DateTime completedAt;

  const AssessmentResult({
    required this.id,
    required this.userId,
    required this.assessmentType,
    required this.assessmentSequence,
    required this.items,
    required this.scorePlanning,
    required this.scoreMonitoring,
    required this.scoreEvaluating,
    required this.scoreTotal,
    required this.completedAt,
  });

  factory AssessmentResult.fromMap(Map<String, dynamic> map) {
    return AssessmentResult(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      assessmentType: map['assessment_type'] as String,
      assessmentSequence: map['assessment_sequence'] as int? ?? 1,
      items: [
        map['item_01'] as int,
        map['item_02'] as int,
        map['item_03'] as int,
        map['item_04'] as int,
        map['item_05'] as int,
        map['item_06'] as int,
        map['item_07'] as int,
        map['item_08'] as int,
        map['item_09'] as int,
        map['item_10'] as int,
        map['item_11'] as int,
        map['item_12'] as int,
      ],
      scorePlanning: map['score_planning'] as int,
      scoreMonitoring: map['score_monitoring'] as int,
      scoreEvaluating: map['score_evaluating'] as int,
      scoreTotal: map['score_total'] as int,
      completedAt: DateTime.parse(map['completed_at'] as String),
    );
  }

  // ── Kategori keseluruhan (12–60) ──────────────────────────
  String get category {
    if (scoreTotal >= 45) return 'Tinggi';
    if (scoreTotal >= 29) return 'Sedang';
    return 'Rendah';
  }

  // ── Kategori per dimensi (4–20) ───────────────────────────
  String get planningCategory => _dimCategory(scorePlanning);
  String get monitoringCategory => _dimCategory(scoreMonitoring);
  String get evaluatingCategory => _dimCategory(scoreEvaluating);

  String _dimCategory(int score) {
    if (score >= 15) return 'Tinggi';
    if (score >= 10) return 'Sedang';
    return 'Rendah';
  }

  // ── Persentase per dimensi (0.0–1.0) ─────────────────────
  double get planningPercent => scorePlanning / 20.0;
  double get monitoringPercent => scoreMonitoring / 20.0;
  double get evaluatingPercent => scoreEvaluating / 20.0;
  double get totalPercent => scoreTotal / 60.0;

  // ── Dimensi tertinggi & terendah ──────────────────────────
  String get strongestDimension {
    final scores = {
      'Perencanaan': scorePlanning,
      'Pemantauan': scoreMonitoring,
      'Evaluasi': scoreEvaluating,
    };
    return scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  String get weakestDimension {
    final scores = {
      'Perencanaan': scorePlanning,
      'Pemantauan': scoreMonitoring,
      'Evaluasi': scoreEvaluating,
    };
    return scores.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }

  // ── Teks interpretasi berdasarkan kategori ────────────────
  String get interpretationText {
    switch (category) {
      case 'Tinggi':
        return 'Tingkat regulasi diri Anda berada pada kategori Tinggi. '
            'Anda secara konsisten mampu merencanakan, memantau, dan '
            'mengevaluasi proses belajar dengan baik. Pertahankan dan '
            'tingkatkan strategi yang sudah berjalan efektif.';
      case 'Sedang':
        return 'Tingkat regulasi diri Anda berada pada kategori Sedang. '
            'Anda menyadari pentingnya merancang tujuan, namun eksekusi '
            'harian dan kesadaran memantau diri secara mandiri masih '
            'perlu ditingkatkan secara konsisten.';
      default:
        return 'Tingkat regulasi diri Anda berada pada kategori Rendah. '
            'Ini adalah titik awal yang baik untuk membangun kebiasaan '
            'belajar yang lebih terencana. Sistem akan membantu Anda '
            'meningkatkan regulasi diri secara bertahap.';
    }
  }

  // ── Kekuatan utama berdasarkan dimensi tertinggi ──────────
  String get strengthText {
    switch (strongestDimension) {
      case 'Perencanaan':
        return 'Antusiasme tinggi dalam menyusun tujuan belajar dan '
            'merencanakan strategi sebelum memulai aktivitas.';
      case 'Pemantauan':
        return 'Kemampuan memantau kemajuan belajar dan menyesuaikan '
            'strategi secara adaptif saat proses berlangsung.';
      default:
        return 'Kecenderungan reflektif yang baik dalam mengevaluasi '
            'efektivitas strategi dan merencanakan perbaikan.';
    }
  }

  // ── Area pembenahan berdasarkan dimensi terendah ──────────
  String get improvementText {
    switch (weakestDimension) {
      case 'Perencanaan':
        return 'Perencanaan tujuan dan alokasi waktu belajar sebelum '
            'memulai sesi masih perlu dibiasakan secara konsisten.';
      case 'Pemantauan':
        return 'Kurang stabil saat melakukan pengawasan fokus internal '
            'di sela-sela kepadatan aktivitas belajar rutin.';
      default:
        return 'Evaluasi strategi belajar dan perencanaan perbaikan '
            'setelah sesi belajar belum dilakukan secara teratur.';
    }
  }

  // ── Saran tindakan strategis ──────────────────────────────
  String get strategicTip {
    switch (weakestDimension) {
      case 'Perencanaan':
        return 'Gunakan fitur Goal Setting untuk menetapkan target '
            'belajar yang spesifik sebelum memulai setiap sesi.';
      case 'Pemantauan':
        return 'Gunakan Sesi Fokus minimal satu kali sehari untuk '
            'membangun ketekunan dan melatih daya konsentrasi Anda.';
      default:
        return 'Isi Refleksi Mingguan setiap akhir pekan untuk '
            'membiasakan diri mengevaluasi dan merencanakan perbaikan.';
    }
  }
}
