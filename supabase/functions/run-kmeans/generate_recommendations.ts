/**
 * ============================================================================
 * SUBSTITUSI PLACEHOLDER x1-x5 PADA METACOGNITIVE RECOMMENDATION
 * ============================================================================
 *
 * Ditempatkan pada Edge Function yang sama dengan K-Means Clustering
 * (KF-08/KF-09), dijalankan SETELAH persona ditetapkan untuk user pada
 * periode tersebut, SEBELUM snapshot disimpan ke tabel `recommendations`.
 *
 * Alur: persona ditetapkan -> ambil rule aktif utk persona itu -> substitusi
 * placeholder [x1]-[x5] dengan nilai asli user -> simpan ke `recommendations`
 * ============================================================================
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// Nilai x1-x5 mentah, hasil agregasi mingguan (Tabel 3.10)
interface WeeklyMetrics {
  x1: number; // frekuensi belajar (sesi/minggu)
  x2: number; // durasi belajar (menit/sesi, rata-rata)
  x3: number; // tingkat fokus (skor 1-5, rata-rata)
  x4: number; // konsistensi belajar (%)
  x5: number; // progres pencapaian target (%)
}

// Format tiap nilai sesuai cara penulisannya di template ai_insight.
// Contoh template: "...mencapai [x4]% dari target..." -> [x4] diganti "82"
// (bukan "82%", karena tanda % sudah tertulis di template itu sendiri).
function formatMetrics(raw: WeeklyMetrics): Record<string, string> {
  return {
    x1: String(Math.round(raw.x1)),
    x2: String(Math.round(raw.x2)),
    x3: raw.x3.toFixed(1),
    x4: String(Math.round(raw.x4)),
    x5: String(Math.round(raw.x5)),
  };
}

// Ganti semua kemunculan [x1]..[x5] pada sebuah teks template dengan nilai asli.
function substitutePlaceholders(template: string, values: Record<string, string>): string {
  let result = template;
  for (const [key, value] of Object.entries(values)) {
    const pattern = new RegExp(`\\[${key}\\]`, "g");
    result = result.replace(pattern, value);
  }
  return result;
}

// Jaring pengaman: pastikan tidak ada placeholder yang lolos tanpa tersubstitusi
// (misalnya karena data x1-x6 belum tersedia, atau ada typo di rule template).
function hasUnresolvedPlaceholder(text: string): boolean {
  return /\[x[1-6]\]/.test(text);
}

const WARNING_WINDOW_DAYS = 28;
const WARNING_THRESHOLD = 3;

// Label warning_tier di recommendation_rules kini SERAGAM untuk KEEMPAT
// persona (revisi per arahan dosen pembimbing): 'mandiri' / 'responsif'.
// Sebelum revisi ini, kosakata dibedakan per persona ('consistent' ->
// mandiri/responsif, persona lain -> jarang_warning/sering_warning) --
// perbedaan itu dihapus supaya definisi tag konsisten untuk semua
// mahasiswa terlepas dari persona hasil clustering-nya. Mekanisme hitung
// (jumlah monitoring_alerts dalam WARNING_WINDOW_DAYS) tidak berubah.
//
// Definisi (lihat 3.4.8a pada skripsi):
// - Mandiri   (isFrequent = false, < WARNING_THRESHOLD peringatan/28 hari):
//   pengguna mencapai/menjalankan target belajarnya tanpa banyak bergantung
//   pada dorongan notifikasi sistem -- regulasi diri berjalan relatif mandiri.
// - Responsif (isFrequent = true, >= WARNING_THRESHOLD peringatan/28 hari):
//   pengguna baru banyak beraktivitas setelah didahului notifikasi berulang --
//   menandakan ketergantungan yang lebih besar pada dorongan eksternal sistem.
function mapWarningTierLabel(personaLabelId: string, isFrequent: boolean): string {
  return isFrequent ? "responsif" : "mandiri";
}

// Hitung jumlah monitoring_alerts yang diterima user dalam WARNING_WINDOW_DAYS
// hari sebelum periodStart, lalu petakan ke label tier 'mandiri'/'responsif'.
// Berlaku SERAGAM untuk KEEMPAT persona -- setiap persona kini punya 2 varian
// rule per dimensi di recommendation_rules, dibedakan lewat warning_tier ini.
//
// personaLabelId dipertahankan pada signature (walau tidak lagi memengaruhi
// nama tier sejak revisi keseragaman label) supaya pemanggil di index.ts
// tidak perlu diubah, dan supaya perhitungan tier tetap mudah dibedakan lagi
// per persona di masa depan bila diperlukan.
export async function computeWarningTier(
  supabase: SupabaseClient,
  userId: string,
  periodStart: string,
  personaLabelId: string
): Promise<{ tier: string; count: number }> {
  // windowEnd pakai akhir hari (23:59:59), bukan awal hari (00:00:00) --
  // supaya warning yang tercatat PADA hari periodStart itu sendiri tetap
  // ikut terhitung, bukan cuma warning dari hari-hari sebelumnya.
  const windowEnd = new Date(`${periodStart}T23:59:59.999Z`);
  const windowStart = new Date(windowEnd);
  windowStart.setUTCDate(windowStart.getUTCDate() - WARNING_WINDOW_DAYS);

  const { count, error } = await supabase
    .from("monitoring_alerts")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", windowStart.toISOString())
    .lte("created_at", windowEnd.toISOString());

  if (error) {
    throw new Error(`Gagal menghitung warning_count untuk user ${userId}: ${error.message}`);
  }

  const warningCount = count ?? 0;
  const isFrequent = warningCount >= WARNING_THRESHOLD;
  return { tier: mapWarningTierLabel(personaLabelId, isFrequent), count: warningCount };
}

/**
 * Membuat snapshot rekomendasi (3 baris: planning/monitoring/evaluating)
 * untuk satu user pada satu periode, dengan placeholder sudah tersubstitusi.
 */
export async function generateRecommendationsForUser(
  supabase: SupabaseClient,
  params: {
    userId: string;
    personaLabelId: string; // 'consistent' | 'passive' | 'seasonal' | 'ambitious'
    periodStart: string; // format YYYY-MM-DD
    personaHistoryId: string;
  }
) {
  const { userId, personaLabelId, periodStart, personaHistoryId } = params;

  // 1. Ambil nilai x1-x5 ASLI milik user untuk periode ini
  const { data: metricsRow, error: metricsError } = await supabase
    .from("v_weekly_activity_aggregates")
    .select("x1:x1_frequency, x2:x2_avg_duration, x3:x3_avg_focus, x4:x4_consistency, x5:x5_progress")
    .eq("user_id", userId)
    .eq("week_start", periodStart)
    .single();

  if (metricsError || !metricsRow) {
    throw new Error(
      `Metrics x1-x5 tidak ditemukan untuk user ${userId} pada periode ${periodStart}. ` +
      `Pastikan goal dan aktivitas periode ini sudah lengkap sebelum generate rekomendasi.`
    );
  }

  const values = formatMetrics(metricsRow as WeeklyMetrics);

  // 2. Ambil rule aktif untuk persona user ini (harus tepat 3 baris:
  //    planning, monitoring, evaluating -- sesuai Tabel 3.12)
  //
  // Keempat persona sekarang punya 2 varian rule per dimensi, dibedakan
  // lewat warning_tier -- kosakata SERAGAM 'mandiri'/'responsif' untuk
  // keempat persona (lihat mapWarningTierLabel), mekanisme hitungnya
  // sama untuk semua.
  const warningResult = await computeWarningTier(supabase, userId, periodStart, personaLabelId);
  const tierFilter = warningResult.tier;

  // [x6] dipakai di template ai_insight varian "sering"/"responsif" --
  // selalu diisi supaya placeholder tidak lolos tanpa tersubstitusi.
  values.x6 = String(warningResult.count);

  const { data: rules, error: rulesError } = await supabase
    .from("recommendation_rules")
    .select("id, msr_dimension, title, ai_insight, strategy, action, reflection_question, priority")
    .eq("persona_label_id", personaLabelId)
    .eq("is_active", true)
    .or(`warning_tier.is.null,warning_tier.eq.${tierFilter}`);

  if (rulesError || !rules || rules.length === 0) {
    throw new Error(`Tidak ada rule aktif untuk persona '${personaLabelId}'.`);
  }
  if (rules.length !== 3) {
    console.warn(
      `Peringatan: persona '${personaLabelId}' punya ${rules.length} rule aktif, ` +
      `seharusnya 3 (planning, monitoring, evaluating). Cek kemungkinan versi ganda aktif.`
    );
  }

  // 3. Substitusi placeholder pada tiap rule, lalu susun payload snapshot
  const snapshots = rules.map((rule) => {
    const insightFilled = substitutePlaceholders(rule.ai_insight, values);
    const actionFilled = substitutePlaceholders(rule.action, values);

    // Jaring pengaman: jangan simpan teks yang masih ada [xN] tersisa.
    // Fallback ke pesan generik + catat di log untuk ditinjau manual.
    const safeInsight = hasUnresolvedPlaceholder(insightFilled)
      ? logAndFallback(insightFilled, userId, rule.id, "ai_insight")
      : insightFilled;
    const safeAction = hasUnresolvedPlaceholder(actionFilled)
      ? logAndFallback(actionFilled, userId, rule.id, "action")
      : actionFilled;

    return {
      user_id: userId,
      persona_history_id: personaHistoryId,
      rule_id: rule.id,
      msr_dimension: rule.msr_dimension,
      title: rule.title,
      ai_insight: safeInsight,
      strategy: rule.strategy,
      action: safeAction,
      reflection_question: rule.reflection_question,
      // Catatan: kolom 'priority' dan 'generated_at' TIDAK dikirim di sini --
      // keduanya tidak ada di tabel `recommendations` (beda dari tabel
      // `recommendation_rules` yang punya kolom 'priority'). created_at
      // di tabel ini nullable, kemungkinan besar sudah punya DEFAULT now()
      // di sisi database, jadi tidak perlu diisi manual dari sini.
    };
  });

  // 4. Simpan snapshot ke tabel recommendations
  const { error: insertError } = await supabase
    .from("recommendations")
    .insert(snapshots);

  if (insertError) {
    throw new Error(`Gagal menyimpan snapshot rekomendasi: ${insertError.message}`);
  }

  return snapshots;
}

function logAndFallback(text: string, userId: string, ruleId: string, field: string): string {
  console.error(
    `Placeholder tidak terselesaikan pada user=${userId} rule=${ruleId} field=${field}: "${text}"`
  );
  return "Rekomendasi sedang diperbarui. Silakan cek kembali beberapa saat lagi.";
}

/**
 * ============================================================================
 * CONTOH PEMANGGILAN (dari alur utama Edge Function, setelah persona
 * ditetapkan untuk user pada KF-08):
 * ============================================================================
 *
 * await generateRecommendationsForUser(supabase, {
 *   userId: user.id,
 *   personaLabelId: personaResult.label, // hasil interpretasi centroid, Tabel 3.11
 *   periodStart: currentPeriod.start_date,
 *   personaHistoryId: personaResult.persona_history_id,
 * });
 * ============================================================================
 */
