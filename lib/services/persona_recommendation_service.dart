// lib/services/persona_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/persona_and_recommendation.dart';

class KMeansTriggerResult {
  final bool success;
  final String message;
  final int? count;
  final int? minimum;
  final bool isInsufficientData;
  final bool isTechnicalError;

  const KMeansTriggerResult({
    required this.success,
    required this.message,
    this.count,
    this.minimum,
    this.isInsufficientData = false,
    this.isTechnicalError = false,
  });
}

// Satu baris breakdown "berapa kali rule_code ini trigger dalam 28 hari
// terakhir" -- dipakai kartu breakdown peringatan di halaman Persona.
// Label/deskripsi manusiawi untuk KEENAM rule_code yang ada di sistem
// (lihat check-monitoring-warnings/index.ts): W1_STREAK, W1_DAILY, W2, W3,
// W4, W5. Kalau ada rule_code baru ditambahkan ke backend di masa depan
// tanpa update di sini, displayLabel/description punya fallback yang aman
// (menampilkan kode mentahnya) alih-alih crash.
class RuleWarningCount {
  final String ruleCode;
  final int count;

  const RuleWarningCount({required this.ruleCode, required this.count});

  String get displayLabel {
    switch (ruleCode) {
      case 'W1_STREAK':
        return 'Jeda belajar terlalu lama';
      case 'W1_DAILY':
        return 'Belum belajar hari ini';
      case 'W2':
        return 'Target mendekati tenggat';
      case 'W3':
        return 'Target lewat tenggat';
      case 'W4':
        return 'Frekuensi belajar menurun';
      case 'W5':
        return 'Rencana jangka panjang tertinggal';
      default:
        return ruleCode;
    }
  }

  String get description {
    switch (ruleCode) {
      case 'W1_STREAK':
        return 'Tidak ada aktivitas tercatat selama beberapa hari berturut-turut.';
      case 'W1_DAILY':
        return 'Belum ada aktivitas belajar yang tercatat hari ini.';
      case 'W2':
        return 'Ada target yang tenggatnya sudah dekat, tapi progresnya masih di bawah rencana.';
      case 'W3':
        return 'Ada target yang tenggatnya sudah lewat namun belum ditandai selesai.';
      case 'W4':
        return 'Jumlah sesi belajarmu minggu ini turun cukup jauh dibanding minggu sebelumnya.';
      case 'W5':
        return 'Progres pada rencana belajar jangka panjang tertinggal dari jadwal yang seharusnya.';
      default:
        return '';
    }
  }
}

class PersonaService {
  final _sb = Supabase.instance.client;
  String get _uid => _sb.auth.currentUser!.id;

  // Persona aktif saat ini
  Future<PersonaInfo?> getCurrentPersona() async {
    final res = await _sb
        .from('persona_history')
        .select()
        .eq('user_id', _uid)
        .eq('is_current', true)
        .maybeSingle();
    if (res == null) return null;
    return PersonaInfo.fromMap(res);
  }

  // Seluruh riwayat persona (urut terbaru dulu)
  Future<List<PersonaInfo>> getPersonaHistory() async {
    final res = await _sb
        .from('persona_history')
        .select()
        .eq('user_id', _uid)
        .order('week_start', ascending: false)
        .limit(12);
    return (res as List).map((e) => PersonaInfo.fromMap(e)).toList();
  }

  // Breakdown jumlah monitoring_alerts per rule_code dalam 28 hari terakhir
  // -- window SAMA PERSIS dengan yang dipakai computeWarningTier() di
  // backend (run-kmeans/generate_recommendations.ts, WARNING_WINDOW_DAYS=28)
  // dan replikanya di dashboard_provider.dart, supaya total breakdown ini
  // selalu konsisten dengan warningCount yang sudah ditampilkan di Beranda.
  // Hasil diurutkan dari yang PALING SERING ke paling jarang.
  Future<List<RuleWarningCount>> getWarningBreakdown() async {
    const warningWindowDays = 28;
    final windowStart = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: warningWindowDays));
    final res = await _sb
        .from('monitoring_alerts')
        .select('rule_code')
        .eq('user_id', _uid)
        .gte('created_at', windowStart.toIso8601String());
    final rows = (res as List).cast<Map<String, dynamic>>();

    final counts = <String, int>{};
    for (final row in rows) {
      final code = row['rule_code'] as String?;
      if (code == null) continue;
      counts[code] = (counts[code] ?? 0) + 1;
    }

    final items = counts.entries
        .map((e) => RuleWarningCount(ruleCode: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return items;
  }

  // Trigger K-Means secara manual (memanggil Edge Function).
  // Respons backend tetap harus dibaca karena kondisi insufficient_data
  // dikirim dengan HTTP 200, tetapi memiliki success: false.
  Future<KMeansTriggerResult> triggerKMeans() async {
    try {
      final response = await _sb.functions.invoke('run-kmeans');
      final raw = response.data;

      if (raw is! Map) {
        return const KMeansTriggerResult(
          success: false,
          message: 'Respons analisis tidak dapat dibaca.',
          isTechnicalError: true,
        );
      }

      final data = Map<String, dynamic>.from(raw);
      final success = data['success'] == true;
      final count = _toInt(data['count'] ?? data['total_observations']);
      final minimum = _toInt(data['minimum']);
      final backendMessage = data['message']?.toString().trim();

      if (!success) {
        final isInsufficientData = data['status'] == 'insufficient_data' ||
            minimum != null ||
            backendMessage?.toLowerCase().contains('insufficient data') == true;

        final message = isInsufficientData
            ? 'Learner persona belum terbentuk karena data aktivitas belajar belum mencukupi. '
                'Silakan lanjutkan aktivitas belajar secara rutin, kemudian jalankan analisis kembali.'
            : (backendMessage?.isNotEmpty == true
                ? backendMessage!
                : 'Analisis learner persona tidak dapat dijalankan saat ini.');

        return KMeansTriggerResult(
          success: false,
          message: message,
          count: count,
          minimum: minimum,
          isInsufficientData: isInsufficientData,
        );
      }

      return KMeansTriggerResult(
        success: true,
        message: backendMessage?.isNotEmpty == true
            ? backendMessage!
            : 'Analisis persona berhasil diperbarui.',
        count: count,
        minimum: minimum,
      );
    } on FunctionException catch (e) {
      final details = e.details;
      String? message;
      if (details is Map && details['message'] != null) {
        message = details['message'].toString();
      }
      return KMeansTriggerResult(
        success: false,
        message: message ?? 'Gagal menjalankan analisis persona.',
        isTechnicalError: true,
      );
    } catch (_) {
      return const KMeansTriggerResult(
        success: false,
        message:
            'Tidak dapat terhubung ke layanan analisis. Periksa koneksi internet.',
        isTechnicalError: true,
      );
    }
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

// ─────────────────────────────────────────────────────────────

// lib/services/recommendation_service.dart

class RecommendationService {
  final _sb = Supabase.instance.client;
  String get _uid => _sb.auth.currentUser!.id;

  Future<List<Recommendation>> getRecommendations() async {
    // Rekomendasi hanya boleh ditampilkan setelah persona aktif terbentuk.
    final personaRow = await _sb
        .from('persona_history')
        .select('persona_label_id, persona_label')
        .eq('user_id', _uid)
        .eq('is_current', true)
        .maybeSingle();

    if (personaRow == null) return [];

    final persona = PersonaInfo.fromMap({
      'id': '',
      'user_id': _uid,
      'persona_label_id': personaRow['persona_label_id'],
      'persona_label': personaRow['persona_label'],
      'week_start': DateTime.now().toIso8601String(),
      'is_current': true,
      'feature_values': <String, dynamic>{},
      'centroid_values': <String, dynamic>{},
      'assigned_at': DateTime.now().toIso8601String(),
    });

    if (!persona.isAnalyzed) return [];

    final res = await _sb
        .from('recommendations')
        .select('''
          id, user_id, msr_dimension, title, ai_insight, strategy,
          action, reflection_question, is_completed, is_dismissed,
          viewed_at, completed_at, created_at,
          recommendation_rules ( priority )
        ''')
        .eq('user_id', _uid)
        .eq('is_dismissed', false)
        .order('created_at', ascending: false);

    return (res as List).map((e) {
      final map = Map<String, dynamic>.from(e);
      // Flatten priority dari nested join
      final rules = map['recommendation_rules'] as Map<String, dynamic>?;
      map['priority'] = rules?['priority'] as int? ?? 2;
      return Recommendation.fromMap(map);
    }).toList();
  }

  Future<void> markCompleted(String id) async {
    await _sb
        .from('recommendations')
        .update({
          'is_completed': true,
          'completed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', _uid);
  }

  Future<void> markViewed(String id) async {
    await _sb
        .from('recommendations')
        .update({
          'viewed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', _uid);
  }

  Future<void> dismiss(String id) async {
    await _sb
        .from('recommendations')
        .update({
          'is_dismissed': true,
        })
        .eq('id', id)
        .eq('user_id', _uid);
  }
}
