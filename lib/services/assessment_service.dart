// lib/services/assessment_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/assessment_result.dart';

// ── Status gerbang SRL Reassessment (T2) ──────────────────────
//
// Satu sumber kebenaran (dibaca dari view v_reassessment_gate) untuk
// menentukan apakah tombol "Penilaian Ulang" boleh aktif, terkunci
// dengan hitung mundur, atau sudah tidak relevan lagi karena T2 sudah
// pernah diisi (single-cycle — lihat BAB 3.4.1 hasil revisi).
class ReassessmentGate {
  final DateTime? baselineAt;
  final DateTime? unlockAt;
  final bool canReassess;
  final bool hasReassessed;
  final int? daysRemaining;

  const ReassessmentGate({
    this.baselineAt,
    this.unlockAt,
    required this.canReassess,
    required this.hasReassessed,
    this.daysRemaining,
  });

  factory ReassessmentGate.fromMap(Map<String, dynamic> map) {
    return ReassessmentGate(
      baselineAt: map['baseline_at'] != null
          ? DateTime.parse(map['baseline_at'] as String)
          : null,
      unlockAt: map['unlock_at'] != null
          ? DateTime.parse(map['unlock_at'] as String)
          : null,
      canReassess: map['can_reassess'] as bool? ?? false,
      hasReassessed: map['has_reassessed'] as bool? ?? false,
      daysRemaining: map['days_remaining'] as int?,
    );
  }

  // Fallback aman selama baseline belum ada / query gagal.
  factory ReassessmentGate.empty() => const ReassessmentGate(
        canReassess: false,
        hasReassessed: false,
        daysRemaining: 28,
      );

  // Tombol seharusnya aktif: sudah lewat 28 hari DAN belum pernah diisi.
  bool get isAvailable => canReassess && !hasReassessed;
}

class AssessmentService {
  final _supabase = Supabase.instance.client;

  String get _uid => _supabase.auth.currentUser!.id;

  // ── Submit asesmen (T1 atau T2) ───────────────────────────
  // assessment_sequence dan score_* dihitung otomatis oleh DB.
  // Validasi 28-hari & single-cycle untuk T2 juga divalidasi ulang
  // di server (trigger validate_reassessment_timing, migrasi v3),
  // sehingga tidak bisa dilewati hanya dengan mengubah jam perangkat.
  Future<AssessmentResult> submitAssessment({
    required List<int> answers,
    required String type, // 'baseline' | 'reassessment'
  }) async {
    assert(answers.length == 12, 'Harus ada tepat 12 jawaban');
    assert(answers.every((a) => a >= 1 && a <= 5), 'Skor harus 1–5');
    assert(type == 'baseline' || type == 'reassessment', 'Tipe tidak valid');

    try {
      // Jaring pengaman terhadap race condition: trigger handle_new_user
      // (yang membuat baris di public.profiles) berjalan ASYNKRON di
      // Postgres segera setelah akun dibuat di auth.users -- pada
      // praktiknya nyaris instan, TAPI ada jeda waktu yang bisa membuat
      // Flutter sudah mencoba insert ke assessment_results SEBELUM baris
      // profiles benar-benar tersimpan, memicu error foreign key
      // "assessment_results_user_id_fkey". Ini terutama berisiko untuk
      // pengguna yang baru saja mendaftar lalu langsung diarahkan ke
      // Penilaian Awal tanpa jeda. _waitForProfile menunggu (dengan retry
      // singkat) sampai baris profiles benar-benar terkonfirmasi ada.
      await _waitForProfile();

      final response = await _supabase
          .from('assessment_results')
          .insert({
            'user_id': _uid,
            'assessment_type': type,
            'item_01': answers[0],
            'item_02': answers[1],
            'item_03': answers[2],
            'item_04': answers[3],
            'item_05': answers[4],
            'item_06': answers[5],
            'item_07': answers[6],
            'item_08': answers[7],
            'item_09': answers[8],
            'item_10': answers[9],
            'item_11': answers[10],
            'item_12': answers[11],
          })
          .select()
          .single();

      // Update has_completed_baseline setelah baseline berhasil disimpan
      if (type == 'baseline') {
        await _supabase
            .from('profiles')
            .update({'has_completed_baseline': true})
            .eq('id', _uid);
      }

      return AssessmentResult.fromMap(response);
    } on PostgrestException catch (e) {
      // Terjemahkan pesan trigger DB (lihat migrasi v3) jadi pesan
      // yang ramah untuk ditampilkan di layar.
      if (e.message.contains('REASSESSMENT_LOCKED')) {
        throw Exception(
            'SRL Reassessment baru dapat diisi setelah 28 hari sejak Baseline Assessment selesai.');
      } else if (e.message.contains('REASSESSMENT_ALREADY_DONE')) {
        throw Exception(
            'SRL Reassessment sudah pernah diisi sebelumnya dan tidak dapat diulang.');
      } else if (e.message.contains('BASELINE_NOT_COMPLETED')) {
        throw Exception('Baseline Assessment (T1) belum diselesaikan.');
      } else if (e.code == '23503' &&
          e.message.contains('assessment_results_user_id_fkey')) {
        // Fallback kalau _waitForProfile di atas tetap kehabisan waktu
        // (mis. koneksi sangat lambat) -- pesan ramah, arahkan retry,
        // BUKAN menampilkan PostgrestException mentah ke pengguna.
        throw Exception(
            'Akunmu masih sedang disiapkan sistem, tunggu beberapa detik lalu coba simpan lagi.');
      }
      rethrow;
    }
  }

  // ── Tunggu sampai baris profiles untuk user ini terkonfirmasi ada ─
  // Mengatasi race condition trigger handle_new_user (lihat komentar di
  // submitAssessment). Retry dengan jeda singkat, total maksimum ~2 detik
  // sebelum menyerah dan membiarkan insert asli gagal secara wajar
  // (ditangkap fallback error 23503 di atas).
  Future<void> _waitForProfile() async {
    const maxAttempts = 5;
    const delayBetweenAttempts = Duration(milliseconds: 400);
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final row = await _supabase
          .from('profiles')
          .select('id')
          .eq('id', _uid)
          .maybeSingle();
      if (row != null) return; // profiles sudah ada, aman lanjut insert
      if (attempt < maxAttempts - 1) {
        await Future.delayed(delayBetweenAttempts);
      }
    }
    // Kehabisan percobaan -- biarkan insert asli yang menentukan hasil
    // akhirnya (kemungkinan besar akan gagal dgn error 23503 yang sudah
    // ditangani fallback-nya di atas, tapi tidak mustahil trigger baru
    // saja selesai tepat setelah percobaan terakhir ini).
  }

  // ── Ambil status gerbang SRL Reassessment (T2) ────────────
  Future<ReassessmentGate> getReassessmentGate() async {
    try {
      final response = await _supabase
          .from('v_reassessment_gate')
          .select()
          .eq('user_id', _uid)
          .maybeSingle();

      if (response == null) return ReassessmentGate.empty();
      return ReassessmentGate.fromMap(response);
    } catch (_) {
      return ReassessmentGate.empty();
    }
  }

  // ── Ambil baseline (T1) pertama milik user ────────────────
  Future<AssessmentResult?> getBaseline() async {
    final response = await _supabase
        .from('assessment_results')
        .select()
        .eq('user_id', _uid)
        .eq('assessment_type', 'baseline')
        .order('completed_at', ascending: true)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return AssessmentResult.fromMap(response);
  }

  // ── Ambil reassessment terbaru milik user ─────────────────
  Future<AssessmentResult?> getLatestReassessment() async {
    final response = await _supabase
        .from('assessment_results')
        .select()
        .eq('user_id', _uid)
        .eq('assessment_type', 'reassessment')
        .order('completed_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return AssessmentResult.fromMap(response);
  }

  // ── Ambil seluruh riwayat asesmen user ────────────────────
  Future<List<AssessmentResult>> getAllAssessments() async {
    final response = await _supabase
        .from('assessment_results')
        .select()
        .eq('user_id', _uid)
        .order('completed_at', ascending: true);

    return (response as List)
        .map((e) => AssessmentResult.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // ── Ambil delta T2 – T1 dari view ─────────────────────────
  Future<Map<String, dynamic>?> getDelta() async {
    final response = await _supabase
        .from('v_assessment_delta')
        .select()
        .eq('user_id', _uid)
        .maybeSingle();

    return response as Map<String, dynamic>?;
  }

  // ── Cek apakah user sudah selesaikan baseline ──────────────
  Future<bool> hasCompletedBaseline() async {
    final profile = await _supabase
        .from('profiles')
        .select('has_completed_baseline')
        .eq('id', _uid)
        .single();

    return (profile['has_completed_baseline'] as bool?) ?? false;
  }
}