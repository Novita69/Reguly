// lib/features/dashboard/providers/dashboard_provider.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/learning_goal.dart';
import '../../../services/goal_service.dart';
import '../../../services/assessment_service.dart';

String? _normalizePersonaLabel(dynamic value) {
  final normalized = value
      ?.toString()
      .trim()
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  switch (normalized) {
    case 'consistent':
    case 'consistent learner':
      return 'consistent';
    case 'passive':
    case 'passive learner':
      return 'passive';
    case 'seasonal':
    case 'seasonal learner':
      return 'seasonal';
    case 'ambitious':
    case 'ambitious behind':
    case 'ambitious behind learner':
    case 'ambitious but behind':
    case 'ambitious but behind learner':
      return 'ambitious';
    default:
      return null;
  }
}

// ── Data Models ────────────────────────────────────────────────

class GoalItem {
  final String id;
  final String title;
  final int targetDurationMinutes;
  final bool isCompleted;
  final double progressPercent;

  const GoalItem({
    required this.id,
    required this.title,
    required this.targetDurationMinutes,
    required this.isCompleted,
    required this.progressPercent,
  });
}

// Perbandingan "posisi kamu" vs SEMUA centroid persona (Consistent,
// Passive, Seasonal, Ambitious) untuk kelima fitur K-Means
// (x1_frequency..x5_progress). Dipakai untuk grafik yang menjawab "kenapa
// aku masuk persona ini, dan seberapa dekat aku ke persona lain" --
// menampilkan 5 garis sekaligus (Kamu + 4 centroid) supaya user bisa
// membandingkan sendiri, bukan cuma diberitahu satu label.
//
// PENTING soal skala: persona_history.feature_values (nilai user) disimpan
// MENTAH (lihat run-kmeans/index.ts baris ~66, `features` diisi langsung
// dari x1_frequency dst SEBELUM normalisasi), sedangkan centroid yang
// tersimpan di clustering_runs.centroids SUDAH TERNORMALISASI 0-1 (hasil
// minMaxNormalize() yang dijalankan sebelum K-Means). Membandingkan
// keduanya mentah-mentah akan MENYESATKAN (skala beda total).
//
// Perbaikannya: normalisasi nilai user pakai normParams (min/max) yang
// SAMA PERSIS dipakai backend saat run clustering itu -- disimpan di
// clustering_runs.normalization. Ini bukan menghitung ulang dengan
// asumsi/cap sendiri, tapi memakai angka aktual dari perhitungan backend.
//
// Pemetaan index-centroid ke nama persona dibaca dari
// clustering_runs.cluster_labels (lihat migration
// 20260729080000_clustering_runs_cluster_labels.sql) -- SATU SUMBER
// KEBENARAN yang sama dipakai backend untuk menentukan persona_label_id
// user, BUKAN dihitung ulang di Flutter (yang berisiko hasil beda kalau
// ada kesalahan replikasi logic labelAllClusters/personaScore).
class ClusterComparisonPoint {
  final String
      label; // 'Frekuensi' | 'Durasi' | 'Fokus' | 'Konsistensi' | 'Progres'
  final double userRaw;
  final double userNormalized; // 0.0-1.0, dihitung pakai normParams run itu
  final String rawUnit; // untuk tooltip, mis. "sesi", "menit", "/5.0", "%"
  // Nilai centroid (0.0-1.0) untuk KEEMPAT persona pada fitur ini --
  // key: 'consistent'|'passive'|'seasonal'|'ambitious'.
  final Map<String, double> centroidByPersona;

  const ClusterComparisonPoint({
    required this.label,
    required this.userRaw,
    required this.userNormalized,
    required this.centroidByPersona,
    required this.rawUnit,
  });
}

class DashboardData {
  final String userName;
  final String? avatarUrl;
  // Header badge: durasi belajar hari ini
  final int todayDurationMinutes;
  // Weekly progress card
  final double weeklyConsistency; // x4 — 0–100
  final int weeklySessions; // x1 — jumlah sesi
  final int weeklyTotalMinutes; // total menit minggu ini
  final double weeklyAvgFocus; // x3 — 1.0–5.0
  // SRL Score card
  final int? latestScore; // null = belum ada asesmen
  final String? scoreCategory;
  final int? deltaTotal; // null = belum ada T2
  final int? scorePlanning;
  final int? scoreMonitoring;
  final int? scoreEvaluating;
  // Persona card
  final String? personaLabelId; // 'consistent'|'passive'|'seasonal'|'ambitious'
  // Warning tier — dihitung dari COUNT(monitoring_alerts) 28 hari terakhir,
  // REPLIKA PERSIS logika computeWarningTier() di
  // supabase/functions/run-kmeans/generate_recommendations.ts (WARNING_WINDOW_DAYS=28,
  // WARNING_THRESHOLD=3). Sengaja dihitung ulang di Flutter (bukan dibaca dari
  // kolom tersimpan), karena warning_tier TIDAK disimpan sebagai kolom mandiri
  // di persona_history — dia cuma tersirat dalam teks recommendations.ai_insight.
  // null = belum ada persona (belum cukup data untuk clustering).
  final String?
      warningTier; // 'mandiri'|'responsif'|'jarang_warning'|'sering_warning'
  final int warningCount; // jumlah monitoring_alerts 28 hari terakhir
  // Streak — 7 hari (Senin s.d. Minggu): true = ada aktivitas
  final List<bool> weekStreak;
  final int streakDays;
  // Today's goals
  final List<GoalItem> activeGoals;
  final int completedGoalsToday;
  // Weekly chart — menit per hari (indeks 0=Senin, 6=Minggu)
  final List<int> weeklyDailyMinutes;
  final int weeklyMaxMinutes;
  // AI insights (generated dari data)
  final List<String> aiInsights;
  // Jam belajar paling aktif, dihitung dari histori 28 hari terakhir
  // (bukan cuma minggu ini, supaya polanya cukup stabil untuk disimpulkan).
  // null = belum cukup data (kurang dari _kMinSessionsForPeakHour sesi
  // dengan start_time tercatat dalam 28 hari terakhir).
  final String? peakHourLabel; // mis. "malam hari (19:00–21:00)"
  // Perbandingan 5 fitur K-Means milik user vs centroid cluster tempat dia
  // dikelompokkan -- menjawab "kenapa aku masuk persona ini". Dibaca dari
  // persona_history (feature_values + centroid_values pada baris
  // is_current=true) dan clustering_runs.normalization (untuk menormalisasi
  // feature_values user ke skala yang sebanding dengan centroid_values yang
  // tersimpan). Kosong kalau belum ada persona_history sama sekali.
  final List<ClusterComparisonPoint> clusterComparison;
  // Status gerbang SRL Reassessment (T2) — untuk popup pengingat 7 hari
  final ReassessmentGate? reassessmentGate;

  const DashboardData({
    required this.userName,
    this.avatarUrl,
    required this.todayDurationMinutes,
    required this.weeklyConsistency,
    required this.weeklySessions,
    required this.weeklyTotalMinutes,
    required this.weeklyAvgFocus,
    this.latestScore,
    this.scoreCategory,
    this.deltaTotal,
    this.scorePlanning,
    this.scoreMonitoring,
    this.scoreEvaluating,
    this.personaLabelId,
    this.warningTier,
    this.warningCount = 0,
    required this.weekStreak,
    required this.streakDays,
    required this.activeGoals,
    required this.completedGoalsToday,
    required this.weeklyDailyMinutes,
    required this.weeklyMaxMinutes,
    required this.aiInsights,
    this.peakHourLabel,
    this.clusterComparison = const [],
    this.reassessmentGate,
  });

  // Persentase progres minggu ini untuk progress circle (0.0–1.0)
  double get weeklyProgressFraction =>
      (weeklyConsistency / 100).clamp(0.0, 1.0);

  // Persona display name
  String get personaDisplayName {
    switch (personaLabelId) {
      case 'consistent':
        return 'Consistent Learner';
      case 'passive':
        return 'Passive Learner';
      case 'seasonal':
        return 'Seasonal Learner';
      case 'ambitious':
        return 'Ambitious but Behind Learner';
      default:
        return 'Menunggu Analisis';
    }
  }

  // Persona description singkat
  String get personaDescription {
    switch (personaLabelId) {
      case 'consistent':
        return 'Anda belajar secara teratur, disiplin, dan terbiasa merawat kebiasaan belajar secara stabil setiap harinya.';
      case 'passive':
        return 'Anda belajar ketika ada instruksi luar atau tenggat wajib. Perlu dorongan lebih untuk memulai secara mandiri.';
      case 'seasonal':
        return 'Pola belajar Anda berfluktuasi: sangat aktif di beberapa periode, namun cenderung pasif di waktu lain.';
      case 'ambitious':
        return 'Anda menetapkan target tinggi namun progres aktual masih perlu diselaraskan dengan konsistensi harian.';
      default:
        return 'Terus catat aktivitas belajarmu. Persona akan terbentuk setelah data mingguanmu cukup untuk dianalisis.';
    }
  }

  // Warna persona
  Color get personaColor {
    switch (personaLabelId) {
      case 'consistent':
        return const Color(0xFF5C4DFF);
      case 'passive':
        return const Color(0xFFF59E0B);
      case 'seasonal':
        return const Color(0xFF4ECDC4);
      case 'ambitious':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  // Label badge warning_tier — teks pendek untuk ditampilkan sebagai pill
  // di samping/bawah nama persona. null kalau persona belum terbentuk
  // (warningTier null), supaya UI tahu kapan badge ini harus disembunyikan
  // sepenuhnya alih-alih menampilkan pill kosong/menyesatkan.
  String? get warningTierDisplayLabel {
    switch (warningTier) {
      case 'mandiri':
        return 'Mandiri';
      case 'responsif':
        return 'Responsif';
      case 'jarang_warning':
        return 'Mandiri';
      case 'sering_warning':
        return 'Responsif';
      default:
        return null;
    }
  }

  // Warna badge warning_tier — hijau untuk tier yang "baik" (mandiri/jarang),
  // oranye untuk tier yang butuh perhatian lebih (responsif/sering). Sengaja
  // TIDAK memakai personaColor supaya badge ini punya makna independen
  // (baik/butuh-perhatian) yang konsisten lintas persona, bukan ikut warna
  // persona yang tidak berkorelasi dengan level warning.
  Color get warningTierColor {
    switch (warningTier) {
      case 'mandiri':
      case 'jarang_warning':
        return const Color(0xFF10B981); // hijau — jarang butuh notifikasi
      case 'responsif':
      case 'sering_warning':
        return const Color(0xFFF59E0B); // oranye — sering butuh notifikasi
      default:
        return const Color(0xFF9CA3AF);
    }
  }
}

// ── Helper: AI Insights Generator ─────────────────────────────

List<String> _generateInsights(DashboardData d) {
  final insights = <String>[];

  if (d.weeklySessions == 0) {
    insights.add(
        'Mulai sesi belajar pertamamu minggu ini untuk mendapatkan wawasan personal.');
    return insights;
  }

  // Frekuensi sesi minggu ini
  insights.add('Frekuensi belajarmu minggu ini ${d.weeklySessions} sesi — '
      '${d.weeklySessions >= 5 ? 'konsisten dan hebat!' : 'tambah 1–2 sesi lagi untuk target mingguan.'}');

  // Durasi
  if (d.weeklyTotalMinutes > 0) {
    final avg = (d.weeklyTotalMinutes / d.weeklySessions).round();
    insights.add('Rata-rata durasi per sesi $avg menit. '
        '${avg >= 45 ? 'Durasi ideal untuk belajar mendalam.' : 'Coba perpanjang menjadi 30–45 menit per sesi.'}');
  }

  // Fokus
  if (d.weeklyAvgFocus > 0) {
    final focusStr = d.weeklyAvgFocus.toStringAsFixed(1);
    insights.add('Skor fokus rata-ratamu $focusStr/5.0. '
        '${d.weeklyAvgFocus >= 4.0 ? 'Kualitas sesi belajarmu sangat baik!' : 'Gunakan Sesi Fokus untuk melatih konsentrasi.'}');
  }

  // Jam belajar paling aktif (histori 28 hari, lihat peakHourLabel di
  // load()) -- framing kalimatnya beda tergantung warningTier:
  //  - tier "sering" (responsif/sering_warning): framing REFLEKTIF, secara
  //    eksplisit mengaitkan pola jam dengan status warning_tier user itu
  //    sendiri, supaya user SADAR ini bukan cuma info netral tapi masukan
  //    yang relevan dengan kondisinya (permintaan awal: "kasih tau dia
  //    kalau berdasarkan data, dia baiknya belajar di jam segini").
  //  - tier lain (mandiri/jarang_warning) atau warningTier null (persona
  //    belum terbentuk): framing NETRAL, murni informasi pola tanpa
  //    menyinggung status warning (tidak relevan/tidak perlu untuk mereka).
  if (d.peakHourLabel != null) {
    final isFrequentTier =
        d.warningTier == 'responsif' || d.warningTier == 'sering_warning';
    if (isFrequentTier) {
      insights.add(
          'Dalam 28 hari terakhir, kamu paling sering belajar di ${d.peakHourLabel}. '
          'Karena kamu tercatat cukup sering mendapat pengingat monitoring, coba '
          'jadwalkan target belajarmu di jam itu secara rutin — waktu yang sudah '
          'terbukti paling cocok denganmu.');
    } else {
      insights.add(
          'Dalam 28 hari terakhir, kamu paling sering belajar di ${d.peakHourLabel}. '
          'Manfaatkan jam ini secara konsisten untuk hasil belajar yang optimal.');
    }
  }

  // Batas ditambah dari 3 ke 4 supaya insight jam belajar (ditambahkan di
  // atas) selalu ikut tampil bersama 3 insight lain, bukan bersaing
  // rebutan slot -- widget PersonaAiInsightCard (dashboard_cards.dart)
  // sudah pakai `...data.aiInsights.map(...)` tanpa batas tinggi tetap,
  // jadi menambah 1 baris di sini aman, kartu akan otomatis memanjang.
  return insights.take(4).toList();
}

// Mengelompokkan start_time (format "HH:MM:SS" dari kolom
// learning_activities.start_time) ke 4 kategori waktu, lalu mengembalikan
// label kategori dengan frekuensi tertinggi. Dipakai untuk insight
// "jam belajar paling aktif" -- dikelompokkan ke rentang lebar (bukan jam
// presisi) supaya polanya tidak goyah oleh variasi kecil menit ke menit,
// dan supaya kalimat insight terasa alami dibaca ("malam hari"), bukan
// teknis ("pukul 19-21").
//
// _kMinSessionsForPeakHour: ambang minimal jumlah sesi ber-start_time dalam
// 28 hari sebelum pola dianggap cukup bermakna untuk ditampilkan -- di
// bawah ini, null dikembalikan (insight ini disembunyikan sepenuhnya,
// lebih baik tidak menyimpulkan apa-apa daripada menyimpulkan dari sample
// terlalu kecil, mis. cuma 1 sesi kebetulan jam 2 pagi).
const int _kMinSessionsForPeakHour = 3;

String? _computePeakHourLabel(List<Map<String, dynamic>> activities) {
  const buckets = <String, List<int>>{
    'pagi hari (05:00–10:59)': [5, 10],
    'siang hari (11:00–14:59)': [11, 14],
    'sore hari (15:00–17:59)': [15, 17],
    'malam hari (18:00–23:59)': [18, 23],
  };
  // Dini hari (00:00–04:59) sengaja tidak dibuatkan bucket display khusus --
  // kasus yang sangat jarang untuk konteks mahasiswa, dan kalau memang ada,
  // dihitung masuk ke 'malam hari' terdekat lewat fallback di bawah supaya
  // tidak hilang dari perhitungan (bukan diabaikan begitu saja).

  final counts = <String, int>{for (final k in buckets.keys) k: 0};
  var validSessionCount = 0;

  for (final row in activities) {
    final startTimeRaw = row['start_time'] as String?;
    if (startTimeRaw == null || startTimeRaw.isEmpty) continue;
    final hour = int.tryParse(startTimeRaw.split(':').first);
    if (hour == null) continue;

    validSessionCount++;
    String? matchedBucket;
    for (final entry in buckets.entries) {
      if (hour >= entry.value[0] && hour <= entry.value[1]) {
        matchedBucket = entry.key;
        break;
      }
    }
    // Dini hari (00-04) -> masuk ke 'malam hari' terdekat (fallback di atas).
    matchedBucket ??= 'malam hari (18:00–23:59)';
    counts[matchedBucket] = (counts[matchedBucket] ?? 0) + 1;
  }

  if (validSessionCount < _kMinSessionsForPeakHour) return null;

  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  // Kalau semua bucket 0 (tidak seharusnya terjadi karena validSessionCount
  // sudah dicek di atas, tapi dijaga eksplisit) -> jangan menyimpulkan apa pun.
  if (sorted.first.value == 0) return null;
  return sorted.first.key;
}

// ── Notifier ───────────────────────────────────────────────────

class DashboardNotifier extends StateNotifier<AsyncValue<DashboardData>> {
  DashboardNotifier() : super(const AsyncValue.loading()) {
    load();
  }

  final _sb = Supabase.instance.client;
  final _goalService = GoalService();
  final _assessmentService = AssessmentService();
  String get _uid => _sb.auth.currentUser!.id;

  Future<void> refresh() => load();

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final mondayStr = _dateStr(monday);
      final todayStr = _dateStr(now);

      // Setiap query punya fallback sendiri — 1 gagal tidak merusak semua
      final profile = await _sb
              .from('profiles')
              .select('full_name, avatar_url')
              .eq('id', _uid)
              .maybeSingle()
              .catchError((_) => null) ??
          <String, dynamic>{};

      final acts = await _sb
          .from('learning_activities')
          .select('duration_minutes, focus_score, activity_date')
          .eq('user_id', _uid)
          .gte('activity_date', mondayStr)
          .lte('activity_date', todayStr)
          .catchError((_) => <dynamic>[])
          .then((v) => (v as List).cast<Map<String, dynamic>>());

      final assessList = await _sb
          .from('assessment_results')
          .select(
              'score_planning,score_monitoring,score_evaluating,score_total')
          .eq('user_id', _uid)
          .order('completed_at', ascending: false)
          .limit(1)
          .catchError((_) => <dynamic>[])
          .then((v) => (v as List).cast<Map<String, dynamic>>());

      final delta = await _sb
          .from('v_assessment_delta')
          .select()
          .eq('user_id', _uid)
          .maybeSingle()
          .catchError((_) => null);

      final personaRow = await _sb
          .from('persona_history')
          .select('persona_label_id')
          .eq('user_id', _uid)
          .eq('is_current', true)
          .maybeSingle()
          .catchError((_) => null);

      // Warning tier: replika persis computeWarningTier() di
      // supabase/functions/run-kmeans/generate_recommendations.ts --
      // COUNT(monitoring_alerts) dalam 28 hari terakhir (window berakhir
      // HARI INI, bukan periodStart clustering, karena ini untuk tampilan
      // real-time di Dashboard, bukan snapshot rekomendasi), dibandingkan
      // ke ambang 3. null kalau persona belum terbentuk (personaRow null) --
      // warning_tier tidak bermakna tanpa persona.
      //
      // Label tier SERAGAM 'mandiri'/'responsif' untuk KEEMPAT persona
      // (revisi per arahan dosen pembimbing) -- sebelumnya dibedakan per
      // persona ('consistent' -> mandiri/responsif, lainnya ->
      // jarang_warning/sering_warning), kini disamakan di sini agar
      // konsisten dengan mapWarningTierLabel() di generate_recommendations.ts.
      final normalizedPersonaId =
          _normalizePersonaLabel(personaRow?['persona_label_id']);
      String? warningTierValue;
      int warningCountValue = 0;
      if (normalizedPersonaId != null) {
        const warningWindowDays = 28;
        const warningThreshold = 3;
        final windowStart = DateTime.now()
            .toUtc()
            .subtract(const Duration(days: warningWindowDays));
        final alertCountResponse = await _sb
            .from('monitoring_alerts')
            .select('id')
            .eq('user_id', _uid)
            .gte('created_at', windowStart.toIso8601String())
            .catchError((_) => <dynamic>[]);
        warningCountValue = (alertCountResponse as List).length;
        final isFrequent = warningCountValue >= warningThreshold;
        warningTierValue = isFrequent ? 'responsif' : 'mandiri';
      }

      // Jam belajar paling aktif -- histori 28 hari (bukan cuma minggu ini,
      // variabel `acts` di bawah, supaya pola jam yang disimpulkan tidak
      // goyah oleh kebetulan 1-2 sesi dalam seminggu). Query terpisah dari
      // `acts` (yang scope-nya sengaja tetap "minggu ini" untuk kartu
      // Perkembangan Mingguan) supaya tidak mengubah perilaku fitur lain.
      final recentStartTimes = await _sb
          .from('learning_activities')
          .select('start_time')
          .eq('user_id', _uid)
          .gte(
              'activity_date', _dateStr(now.subtract(const Duration(days: 28))))
          .not('start_time', 'is', null)
          .catchError((_) => <dynamic>[])
          .then((v) => (v as List).cast<Map<String, dynamic>>());
      final peakHourLabelValue = _computePeakHourLabel(recentStartTimes);

      // Perbandingan "kamu vs SEMUA centroid persona" -- dibaca dari baris
      // persona_history TERKINI (is_current=true) untuk feature_values
      // (nilai user, MENTAH) dan clustering_run_id, lalu clustering_runs
      // untuk centroids (array SEMUA centroid, ternormalisasi 0-1),
      // cluster_labels (pemetaan index->persona, SATU SUMBER KEBENARAN dari
      // backend -- lihat migration
      // 20260729080000_clustering_runs_cluster_labels.sql), dan
      // normalization (min/max untuk menormalisasi feature_values user ke
      // skala yang sebanding). Lihat komentar panjang di
      // ClusterComparisonPoint untuk detail kenapa langkah normalisasi ini
      // diperlukan.
      final currentPersonaRow = await _sb
          .from('persona_history')
          .select('feature_values, clustering_run_id')
          .eq('user_id', _uid)
          .eq('is_current', true)
          .maybeSingle()
          .catchError((_) => null);

      List<ClusterComparisonPoint> clusterComparisonValue = [];
      if (currentPersonaRow != null &&
          currentPersonaRow['feature_values'] != null) {
        final featureValues =
            currentPersonaRow['feature_values'] as Map<String, dynamic>;
        final clusteringRunId =
            currentPersonaRow['clustering_run_id'] as String?;

        if (clusteringRunId != null) {
          final runRow = await _sb
              .from('clustering_runs')
              .select('centroids, cluster_labels, normalization')
              .eq('id', clusteringRunId)
              .maybeSingle()
              .catchError((_) => null);

          final centroids = runRow?['centroids'] as List<dynamic>?;
          final clusterLabels = runRow?['cluster_labels'] as List<dynamic>?;
          final normParams = runRow?['normalization'] as Map<String, dynamic>?;

          // cluster_labels bisa null untuk run LAMA (sebelum migration ini
          // ada) -- kalau begitu, kita tidak bisa memetakan index ke nama
          // persona dengan aman, jadi grafik ini dikosongkan (bukan
          // menampilkan pemetaan yang mungkin salah). Cukup jalankan
          // run-kmeans sekali lagi untuk mengisi run baru dengan label ini.
          if (centroids != null &&
              clusterLabels != null &&
              centroids.length == clusterLabels.length) {
            // Peta persona -> index centroid, dari cluster_labels yang
            // sejajar dengan array centroids.
            final personaToIndex = <String, int>{};
            for (var i = 0; i < clusterLabels.length; i++) {
              personaToIndex[clusterLabels[i] as String] = i;
            }

            // (v - min) / (max - min), fallback 0 kalau max==min -- REPLIKA
            // PERSIS formula minMaxNormalize() di run-kmeans/index.ts,
            // supaya posisi garis "Kamu" konsisten dengan bagaimana K-Means
            // sesungguhnya melihat data ini saat clustering berjalan.
            double normalize(String key, double raw) {
              if (normParams == null) return 0;
              final min = (normParams['${key}_min'] as num?)?.toDouble();
              final max = (normParams['${key}_max'] as num?)?.toDouble();
              if (min == null || max == null || max == min) return 0;
              return ((raw - min) / (max - min)).clamp(0.0, 1.0);
            }

            double rawOf(Map<String, dynamic> m, String key) =>
                (m[key] as num?)?.toDouble() ?? 0;

            const featureKeys = ['x1', 'x2', 'x3', 'x4', 'x5'];
            const specs = [
              ['x1', 'Frekuensi', 'sesi'],
              ['x2', 'Durasi', 'menit'],
              ['x3', 'Fokus', '/5.0'],
              ['x4', 'Konsistensi', '%'],
              ['x5', 'Progres', '%'],
            ];
            final featureIndexOf = {
              for (var i = 0; i < featureKeys.length; i++) featureKeys[i]: i
            };

            clusterComparisonValue = specs.map((spec) {
              final key = spec[0];
              final userRaw = rawOf(featureValues, key);
              final featureIdx = featureIndexOf[key]!;
              final centroidByPersona = <String, double>{};
              for (final entry in personaToIndex.entries) {
                final centroidRow = centroids[entry.value] as List<dynamic>;
                final v = (centroidRow.length > featureIdx)
                    ? (centroidRow[featureIdx] as num?)?.toDouble() ?? 0
                    : 0.0;
                centroidByPersona[entry.key] = v.clamp(0.0, 1.0);
              }
              return ClusterComparisonPoint(
                label: spec[1],
                userRaw: userRaw,
                userNormalized: normalize(key, userRaw),
                centroidByPersona: centroidByPersona,
                rawUnit: spec[2],
              );
            }).toList();
          }
        }
      }

      // Pakai GoalService yang sama persis dengan layar Daftar Target, supaya
      // status selesai/belum di Dashboard tidak pernah berbeda dari sana.
      // Sebelumnya di sini ada query mentah terpisah yang menghitung "selesai"
      // sendiri dari kolom actual_progress saja — beda definisi dengan
      // LearningGoal.isCompleted (yang juga mempertimbangkan kolom status),
      // makanya hasilnya bisa tidak sinkron antar layar.
      final allGoals =
          await _goalService.getAllGoals().catchError((_) => <LearningGoal>[]);

      final reassessmentGate = await _assessmentService.getReassessmentGate();

      // Aktivitas minggu ini
      final todayActs =
          acts.where((a) => a['activity_date'] == todayStr).toList();
      final todayMinutes =
          todayActs.fold<int>(0, (s, a) => s + (a['duration_minutes'] as int));
      final totalWeekMinutes =
          acts.fold<int>(0, (s, a) => s + (a['duration_minutes'] as int));
      final avgFocus = acts.isEmpty
          ? 0.0
          : acts.fold<double>(0, (s, a) => s + (a['focus_score'] as int)) /
              acts.length;

      final weekStreak = List.generate(7, (i) {
        final dayStr = _dateStr(monday.add(Duration(days: i)));
        return acts.any((a) => a['activity_date'] == dayStr);
      });
      int streak = 0;
      for (int i = now.weekday - 1; i >= 0; i--) {
        if (weekStreak[i])
          streak++;
        else
          break;
      }

      final dailyMinutes = List.generate(7, (i) {
        final dayStr = _dateStr(monday.add(Duration(days: i)));
        return acts
            .where((a) => a['activity_date'] == dayStr)
            .fold<int>(0, (s, a) => s + (a['duration_minutes'] as int));
      });
      final maxMin = dailyMinutes.isEmpty
          ? 60
          : dailyMinutes.reduce((a, b) => a > b ? a : b);

      final assess = assessList.isNotEmpty ? assessList.first : null;

      final goalItems = allGoals
          .take(5)
          .map((g) => GoalItem(
                id: g.id,
                title: g.title,
                targetDurationMinutes: g.targetDurationMinutes,
                isCompleted:
                    g.isCompleted, // sama persis dgn LearningGoal.isCompleted
                progressPercent: g.actualProgress,
              ))
          .toList();

      final daysPassed = now.weekday.toDouble();
      final expectedSessions =
          allGoals.isNotEmpty ? allGoals.first.targetSessions.toDouble() : 5.0;
      final consistency = acts.isEmpty
          ? 0.0
          : ((acts.length / ((expectedSessions / 7) * daysPassed)) * 100)
              .clamp(0.0, 100.0);

      String? cat;
      if (assess != null) {
        final s = assess['score_total'] as int;
        cat = s >= 45
            ? 'Tinggi'
            : s >= 29
                ? 'Sedang'
                : 'Rendah';
      }

      final data = DashboardData(
        userName: (profile['full_name'] as String?) ?? 'Pengguna',
        avatarUrl: profile['avatar_url'] as String?,
        todayDurationMinutes: todayMinutes,
        weeklyConsistency: consistency,
        weeklySessions: acts.length,
        weeklyTotalMinutes: totalWeekMinutes,
        weeklyAvgFocus: avgFocus,
        latestScore: assess != null ? assess['score_total'] as int : null,
        scoreCategory: cat,
        deltaTotal: delta != null ? delta['delta_total'] as int? : null,
        scorePlanning: assess != null ? assess['score_planning'] as int? : null,
        scoreMonitoring:
            assess != null ? assess['score_monitoring'] as int? : null,
        scoreEvaluating:
            assess != null ? assess['score_evaluating'] as int? : null,
        personaLabelId: normalizedPersonaId,
        warningTier: warningTierValue,
        warningCount: warningCountValue,
        weekStreak: weekStreak,
        streakDays: streak,
        activeGoals: goalItems,
        completedGoalsToday: goalItems.where((g) => g.isCompleted).length,
        weeklyDailyMinutes: dailyMinutes,
        weeklyMaxMinutes: maxMin == 0 ? 60 : maxMin,
        aiInsights: [],
        peakHourLabel: peakHourLabelValue,
        clusterComparison: clusterComparisonValue,
        reassessmentGate: reassessmentGate,
      );

      // Guard: kalau widget yang nge-watch provider ini sudah pindah halaman
      // sebelum semua query di atas selesai, provider ini sudah "dibuang"
      // (autoDispose). Jangan coba nulis state lagi kalau begitu — itu yang
      // sebelumnya menyebabkan error "Tried to use X after dispose".
      if (!mounted) return;

      state = AsyncValue.data(DashboardData(
        userName: data.userName,
        avatarUrl: data.avatarUrl,
        todayDurationMinutes: data.todayDurationMinutes,
        weeklyConsistency: data.weeklyConsistency,
        weeklySessions: data.weeklySessions,
        weeklyTotalMinutes: data.weeklyTotalMinutes,
        weeklyAvgFocus: data.weeklyAvgFocus,
        latestScore: data.latestScore,
        scoreCategory: data.scoreCategory,
        deltaTotal: data.deltaTotal,
        scorePlanning: data.scorePlanning,
        scoreMonitoring: data.scoreMonitoring,
        scoreEvaluating: data.scoreEvaluating,
        personaLabelId: data.personaLabelId,
        warningTier: data.warningTier,
        warningCount: data.warningCount,
        weekStreak: data.weekStreak,
        streakDays: data.streakDays,
        activeGoals: data.activeGoals,
        completedGoalsToday: data.completedGoalsToday,
        weeklyDailyMinutes: data.weeklyDailyMinutes,
        weeklyMaxMinutes: data.weeklyMaxMinutes,
        aiInsights: _generateInsights(data),
        peakHourLabel: data.peakHourLabel,
        clusterComparison: data.clusterComparison,
        reassessmentGate: data.reassessmentGate,
      ));
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(e, st);
    }
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ── Provider ───────────────────────────────────────────────────

final dashboardProvider = StateNotifierProvider.autoDispose<DashboardNotifier,
    AsyncValue<DashboardData>>(
  (ref) => DashboardNotifier(),
);
