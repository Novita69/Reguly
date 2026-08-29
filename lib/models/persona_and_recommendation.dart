// lib/models/persona_info.dart

import 'package:flutter/material.dart';

class PersonaInfo {
  final String id;
  final String userId;
  final String labelId; // 'consistent'|'passive'|'seasonal'|'ambitious'
  final DateTime weekStart;
  final bool isCurrent;
  final Map<String, double> featureValues; // x1–x5
  final Map<String, double> centroidValues;
  final DateTime assignedAt;
  // Warning tier badge ('mandiri'|'responsif'|'jarang_warning'|'sering_warning')
  // -- REPLIKA logika yang sama dengan warningTier di DashboardData
  // (lib/features/dashboard/providers/dashboard_provider.dart): dihitung
  // dari COUNT(monitoring_alerts) 28 hari terakhir vs ambang 3, TIDAK
  // disimpan sebagai kolom di persona_history, jadi field ini diisi dari
  // luar (oleh provider pemanggil) setelah PersonaInfo dibuat dari data
  // Supabase mentah -- bukan bagian dari fromMap() karena sumbernya beda
  // tabel (monitoring_alerts, bukan persona_history). null = belum dihitung
  // atau tidak relevan (mis. persona belum terbentuk).
  final String? warningTier;

  const PersonaInfo({
    required this.id,
    required this.userId,
    required this.labelId,
    required this.weekStart,
    required this.isCurrent,
    required this.featureValues,
    required this.centroidValues,
    required this.assignedAt,
    this.warningTier,
  });

  // Salinan PersonaInfo dengan warningTier terisi -- dipakai provider
  // setelah menghitung tier dari query monitoring_alerts terpisah.
  PersonaInfo copyWithWarningTier(String? tier) => PersonaInfo(
        id: id,
        userId: userId,
        labelId: labelId,
        weekStart: weekStart,
        isCurrent: isCurrent,
        featureValues: featureValues,
        centroidValues: centroidValues,
        assignedAt: assignedAt,
        warningTier: tier,
      );

  // Label badge warning_tier untuk ditampilkan sebagai pill di samping nama
  // persona -- sama persis dengan DashboardData.warningTierDisplayLabel,
  // supaya label "Mandiri"/"Responsif" konsisten di semua layar (Dashboard,
  // Persona Pembelajaran, Profil).
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

  // Warna badge warning_tier -- sama persis dengan DashboardData.warningTierColor.
  Color get warningTierColor {
    switch (warningTier) {
      case 'mandiri':
      case 'jarang_warning':
        return const Color(0xFF10B981); // hijau
      case 'responsif':
      case 'sering_warning':
        return const Color(0xFFF59E0B); // oranye
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  factory PersonaInfo.fromMap(Map<String, dynamic> m) => PersonaInfo(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        labelId: _normalizePersonaLabel(
          (m['persona_label_id'] ?? m['persona_label'])?.toString(),
        ),
        weekStart: DateTime.parse(m['week_start'] as String),
        isCurrent: m['is_current'] as bool? ?? false,
        featureValues: Map<String, double>.from(
          (m['feature_values'] as Map<String, dynamic>? ?? {})
              .map((k, v) => MapEntry(k, (v as num).toDouble())),
        ),
        centroidValues: Map<String, double>.from(
          (m['centroid_values'] as Map<String, dynamic>? ?? {})
              .map((k, v) => MapEntry(k, (v as num).toDouble())),
        ),
        assignedAt: DateTime.parse(m['assigned_at'] as String),
      );

  static String _normalizePersonaLabel(String? value) {
    final normalized = value
        ?.trim()
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
        return '';
    }
  }

  bool get isAnalyzed {
    return const {
      'consistent',
      'passive',
      'seasonal',
      'ambitious',
    }.contains(labelId);
  }

  // ── Display data ───────────────────────────────────────────

  String get displayName {
    switch (labelId) {
      case 'consistent':
        return 'Consistent Learner';
      case 'passive':
        return 'Passive Learner';
      case 'seasonal':
        return 'Seasonal Learner';
      case 'ambitious':
        return 'Ambitious but Behind Learner';
      default:
        return 'Belum Dianalisis';
    }
  }

  String get shortDescription {
    switch (labelId) {
      case 'consistent':
        return 'Anda belajar secara teratur, disiplin, dan terbiasa merawat kebiasaan belajar secara stabil setiap harinya.';
      case 'passive':
        return 'Anda belajar ketika ada instruksi luar atau tenggat wajib. Perlu dorongan lebih untuk memulai secara mandiri.';
      case 'seasonal':
        return 'Pola belajar Anda berfluktuasi: sangat aktif di beberapa periode, namun cenderung pasif di waktu lain.';
      case 'ambitious':
        return 'Anda menetapkan target belajar sangat tinggi namun kesulitan menyelesaikannya secara konsisten.';
      default:
        return 'Terus catat aktivitas belajarmu agar persona dapat terbentuk.';
    }
  }

  List<String> get characteristics {
    switch (labelId) {
      case 'consistent':
        return [
          'Memiliki jadwal belajar harian yang terstruktur.',
          'Tingkat fokus yang tinggi (rata-rata skor 4–5).',
          'Persentase penyelesaian target mingguan melebihi 75%.',
          'Melakukan refleksi mingguan secara rutin dan objektif.',
        ];
      case 'passive':
        return [
          'Frekuensi belajar sangat rendah atau tidak teratur.',
          'Sesi belajar terjadi hanya karena dorongan eksternal.',
          'Prokrastinasi tinggi dan sulit memulai aktivitas mandiri.',
          'Durasi belajar per sesi pendek atau tidak konsisten.',
        ];
      case 'seasonal':
        return [
          'Pola belajar fluktuatif berdasarkan urgensi tugas.',
          'Aktif belajar saat mendekati tenggat, pasif di waktu lain.',
          'Konsistensi mingguan rendah meskipun frekuensi sesekali tinggi.',
          'Sulit mempertahankan kebiasaan di luar tekanan tenggat.',
        ];
      case 'ambitious':
        return [
          'Daftar target harian sangat panjang hingga tidak realistis.',
          'Pencapaian target aktual rendah (di bawah 40%).',
          'Prokrastinasi akibat rasa cemas kewalahan.',
          'Memiliki niat belajar yang menggebu-gebu di awal.',
        ];
      default:
        return [];
    }
  }

  List<String> get strengths {
    switch (labelId) {
      case 'consistent':
        return [
          'Manajemen waktu belajar yang sangat rapi.',
          'Motivasi belajar internal (intrinsik) yang kokoh.',
          'Kemampuan mitigasi prokrastinasi yang tinggi.',
        ];
      case 'passive':
        return [
          'Mampu belajar intensif dalam waktu singkat.',
          'Peka terhadap umpan balik eksternal.',
        ];
      case 'seasonal':
        return [
          'Mampu belajar dalam tekanan dengan efisiensi tinggi.',
          'Motivasi tinggi saat ada target spesifik yang jelas.',
        ];
      case 'ambitious':
        return [
          'Determinasi belajar yang luar biasa tinggi.',
          'Tertarik mengeksplorasi banyak disiplin ilmu sekaligus.',
        ];
      default:
        return [];
    }
  }

  List<String> get aiTips {
    switch (labelId) {
      case 'consistent':
        return [
          'Luangkan waktu istirahat minimal 5–10 menit di sela-sela Sesi Fokus.',
          'Gunakan teknik visualisasi target agar beban kognitif berkurang.',
          'Latih apresiasi mandiri terhadap progres kecil yang sudah dicapai.',
        ];
      case 'passive':
        return [
          'Mulai dengan satu sesi 15 menit per hari menggunakan Sesi Fokus.',
          'Gunakan Goal Setting untuk menetapkan target harian yang realistis.',
          'Aktifkan pengingat belajar harian dari fitur Reminder.',
        ];
      case 'seasonal':
        return [
          'Tetapkan jadwal minimum 2 sesi per minggu di hari tetap.',
          'Gunakan refleksi mingguan untuk mengidentifikasi pemicu fluktuasi.',
          'Buat target jangka pendek (1–2 minggu) agar ada urgensi reguler.',
        ];
      case 'ambitious':
        return [
          'Terapkan batasan: Maksimal 3 target belajar utama dalam sehari.',
          'Gunakan Pomodoro (25 menit belajar, 5 menit istirahat) untuk mengurangi cemas.',
          'Jangan menambah target baru sebelum target hari ini berhasil dievaluasi.',
        ];
      default:
        return [];
    }
  }

  Color get color {
    switch (labelId) {
      case 'consistent':
        return const Color(0xFF5C4DFF);
      case 'passive':
        return const Color(0xFFF59E0B);
      case 'seasonal':
        return const Color(0xFF4ECDC4);
      case 'ambitious':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF9CA3AF);
    }
  }
}

// ─────────────────────────────────────────────────────────────

// lib/models/recommendation.dart

class Recommendation {
  final String id;
  final String userId;
  final String msrDimension; // 'planning'|'monitoring'|'evaluating'
  final String title;
  final String? aiInsight;
  final String strategy;
  final String action;
  final String? reflectionQuestion;
  final bool isCompleted;
  final bool isDismissed;
  final DateTime? viewedAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  // dari join ke recommendation_rules
  final int priority; // 1=tinggi, 2=sedang, 3=rendah

  const Recommendation({
    required this.id,
    required this.userId,
    required this.msrDimension,
    required this.title,
    this.aiInsight,
    required this.strategy,
    required this.action,
    this.reflectionQuestion,
    required this.isCompleted,
    required this.isDismissed,
    this.viewedAt,
    this.completedAt,
    required this.createdAt,
    required this.priority,
  });

  factory Recommendation.fromMap(Map<String, dynamic> m) => Recommendation(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        msrDimension: m['msr_dimension'] as String,
        title: m['title'] as String,
        aiInsight: m['ai_insight'] as String?,
        strategy: m['strategy'] as String,
        action: m['action'] as String,
        reflectionQuestion: m['reflection_question'] as String?,
        isCompleted: m['is_completed'] as bool? ?? false,
        isDismissed: m['is_dismissed'] as bool? ?? false,
        viewedAt: m['viewed_at'] != null
            ? DateTime.parse(m['viewed_at'] as String)
            : null,
        completedAt: m['completed_at'] != null
            ? DateTime.parse(m['completed_at'] as String)
            : null,
        createdAt: DateTime.parse(m['created_at'] as String),
        priority: m['priority'] as int? ?? 2,
      );

  String get dimensionDisplay {
    switch (msrDimension) {
      case 'planning':
        return 'PERENCANAAN';
      case 'monitoring':
        return 'PEMANTAUAN';
      case 'evaluating':
        return 'EVALUASI';
      default:
        return msrDimension.toUpperCase();
    }
  }

  String get priorityDisplay {
    switch (priority) {
      case 1:
        return 'PRIORITAS TINGGI';
      case 2:
        return 'PRIORITAS SEDANG';
      default:
        return 'PRIORITAS RENDAH';
    }
  }

  Recommendation copyWith({
    bool? isCompleted,
    bool? isDismissed,
    DateTime? completedAt,
    DateTime? viewedAt,
  }) =>
      Recommendation(
        id: id,
        userId: userId,
        msrDimension: msrDimension,
        title: title,
        aiInsight: aiInsight,
        strategy: strategy,
        action: action,
        reflectionQuestion: reflectionQuestion,
        isCompleted: isCompleted ?? this.isCompleted,
        isDismissed: isDismissed ?? this.isDismissed,
        viewedAt: viewedAt ?? this.viewedAt,
        completedAt: completedAt ?? this.completedAt,
        createdAt: createdAt,
        priority: priority,
      );
}

// ─────────────────────────────────────────────────────────────

// lib/models/warning_breakdown_item.dart

/// Ringkasan jumlah kemunculan tiap jenis peringatan monitoring
/// (`rule_code` pada [MonitoringAlert]) dalam suatu rentang waktu.
/// Dipakai untuk kartu "Jenis Peringatan (28 Hari Terakhir)" di
/// halaman Persona — hasil agregasi, bukan baris mentah dari Supabase,
/// sehingga tidak memerlukan factory `fromMap`.
class WarningBreakdownItem {
  final String ruleCode; // W1_DAILY | W1_STREAK | W2 | W3 | W4 | W5
  final int count;

  const WarningBreakdownItem({
    required this.ruleCode,
    required this.count,
  });

  /// Label singkat, selaras dengan `MonitoringAlert.ruleLabel`.
  String get displayLabel {
    switch (ruleCode) {
      case 'W1_DAILY':
        return 'Pengingat Harian';
      case 'W1_STREAK':
        return 'Tidak Aktif 3 Hari';
      case 'W2':
        return 'Deadline Dekat';
      case 'W3':
        return 'Lewat Deadline';
      case 'W4':
        return 'Frekuensi Menurun';
      case 'W5':
        return 'Ketinggalan Pace';
      default:
        return ruleCode;
    }
  }

  /// Penjelasan singkat, ditampilkan di bawah progress bar pada UI.
  String get description {
    switch (ruleCode) {
      case 'W1_DAILY':
        return 'Pengingat rutin agar Anda tetap mencatat aktivitas belajar harian.';
      case 'W1_STREAK':
        return 'Muncul saat Anda tidak tercatat aktif belajar selama 3 hari berturut-turut.';
      case 'W2':
        return 'Muncul saat tenggat target belajar sudah mendekat.';
      case 'W3':
        return 'Muncul saat target belajar telah melewati tenggat waktu.';
      case 'W4':
        return 'Muncul saat frekuensi belajar mingguan menurun dibanding biasanya.';
      case 'W5':
        return 'Muncul saat progres tertinggal dari kecepatan (pace) yang dibutuhkan.';
      default:
        return 'Jenis peringatan monitoring.';
    }
  }
}
