import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { computeWarningTier } from "./generate_recommendations.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    // Body opsional -- kalau ada `target_user_id`, langkah generateRecommendations
    // dibatasi ke satu user itu saja (berguna untuk verifikasi bertahap tanpa
    // memproses ulang rekomendasi seluruh pengguna sekaligus). Invoke tanpa body
    // (atau body kosong/tidak valid) tetap berjalan normal untuk semua pengguna,
    // persis seperti sebelumnya -- langkah clustering K-Means di atasnya tidak
    // terpengaruh oleh parameter ini sama sekali.
    let targetUserId: string | undefined;
    try {
      const body = await req.json();
      targetUserId = typeof body?.target_user_id === "string" ? body.target_user_id : undefined;
    } catch {
      targetUserId = undefined;
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ------------------------------------------------------------------
    // SESUAI BAB III Sub-bab 3.4.3 langkah 6: "Agregasi: membentuk SATU
    // OBSERVASI PENGGUNA-MINGGU dan menghitung x1-x5." Unit analisis
    // K-Means adalah kombinasi (pengguna, minggu) -- BUKAN satu baris
    // per pengguna. Setiap baris hasil view adalah satu observasi.
    // Untuk 40 responden x 4 minggu, ini menghasilkan hingga 160
    // observasi (tergantung kelengkapan data per minggu).
    // ------------------------------------------------------------------
    const { data: allWeeklyRows, error } = await supabase
      .from("v_weekly_activity_aggregates")
      .select("*")
      .order("week_start", { ascending: true });

    if (error) throw error;

    const rawData = (allWeeklyRows ?? []).filter((r: any) => r.user_id && r.week_start);

    if (!rawData || rawData.length < 8) {
      await logRun(supabase, { status: "insufficient_data", total_observations: rawData?.length ?? 0, selected_k: 0, sse_values: {}, centroids: [], normalization: {} });
      return new Response(
        JSON.stringify({
          success: false,
          status: "insufficient_data",
          message: "Data belum cukup untuk K-Means.",
          count: rawData?.length ?? 0,
          minimum: 8,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const features = rawData.map((r: any) => [r.x1_frequency ?? 0, r.x2_avg_duration ?? 0, r.x3_avg_focus ?? 0, r.x4_consistency ?? 0, r.x5_progress ?? 0]);
    const userWeeks = rawData.map((r: any) => ({ user_id: r.user_id, week_start: r.week_start }));
    const { normalizedFeatures, normParams } = minMaxNormalize(features);
    // ------------------------------------------------------------------
    // Metode Elbow tetap dihitung sebagai ANALISIS PENDUKUNG.
    // SSE dihitung untuk k = 2 sampai k = 6 agar penurunan SSE dapat
    // dianalisis, tetapi hasil Elbow TIDAK digunakan untuk menggantikan
    // keputusan konseptual penelitian bahwa jumlah cluster final adalah k = 4.
    // ------------------------------------------------------------------
    const maxK = Math.min(6, rawData.length - 1);
    const sseValues: Record<string, number> = {};

    for (let k = 2; k <= maxK; k++) {
      sseValues[`k${k}`] = runKMeans(
        normalizedFeatures,
        k,
        100,
        42,
      ).sse;
    }

    // Hasil rekomendasi matematis dari Metode Elbow hanya dicatat sebagai
    // informasi pendukung dan tidak dipakai sebagai jumlah cluster final.
    const elbowSuggestedK = findElbowK(sseValues);

    // Jumlah cluster final ditetapkan secara konseptual berdasarkan empat
    // learner persona: Consistent, Passive, Seasonal, dan Ambitious-Behind.
    const selectedK = 4;

    console.log(
      `Elbow suggested k=${elbowSuggestedK}; final conceptual k=${selectedK}`,
    );

    // Proses clustering final selalu menggunakan k = 4.
    const finalResult = runKMeans(
      normalizedFeatures,
      selectedK,
      300,
      42,
    );

    // Label per index centroid (sejajar dengan finalResult.centroids),
    // dihitung SEKALI di sini dan disimpan ke clustering_runs.cluster_labels
    // supaya klien (Flutter) bisa menampilkan pemetaan cluster->persona
    // yang benar untuk SEMUA cluster tanpa perlu menghitung ulang logic ini
    // sendiri (lihat migration 20260729080000_clustering_runs_cluster_labels.sql
    // untuk alasan lengkapnya). updatePersonaHistory() di bawah TETAP
    // menghitung labelAllClusters() sendiri secara independen (pola yang
    // sudah ada sebelumnya, query ulang dari DB) -- baris ini TIDAK
    // menggantikan itu, cuma menambah satu sumber baca untuk klien.
    const clusterLabelsForRun = labelAllClusters(finalResult.centroids);

    const runId = await logRun(supabase, {
      status: "success",
      total_observations: rawData.length,
      selected_k: selectedK,
      sse_values: sseValues,
      centroids: finalResult.centroids,
      normalization: normParams,
      cluster_labels: clusterLabelsForRun.map((lbl) => toPersistablePersonaId(lbl)),
    });
    if (!runId) throw new Error("Gagal menyimpan clustering run (logRun mengembalikan null).");

    // clusterLabels[i] = label mentah tiap OBSERVASI MINGGU (bukan label
    // final per pengguna). Ini persis output "cluster bernomor tanpa
    // label semantik" yang disebut BAB III Sub-bab 3.4.5.
    await updatePersonaHistory(supabase, userWeeks, finalResult, runId, features);

    // ------------------------------------------------------------------
    // SESUAI BAB III Sub-bab 3.4.2 & 3.4.5: pelabelan FINAL (khususnya
    // "Pembelajar Musiman"/Seasonal) memerlukan bukti riwayat antar-
    // periode, bukan hanya posisi centroid satu observasi. Tahap ini
    // menelusuri riwayat cluster tiap pengguna lintas minggu: jika
    // pola cluster-nya berubah-ubah antara kelompok "aktif" dan
    // "tidak aktif", label finalnya ditetapkan Seasonal Learner,
    // menggantikan label mentah dari cluster minggu terakhir saja.
    // ------------------------------------------------------------------
    await finalizeSeasonalLabels(supabase, userWeeks);

    await generateRecommendations(supabase, runId, targetUserId);
    return new Response(
      JSON.stringify({
        success: true,

        // Tambahan untuk memastikan Edge Function yang terbaru sudah ter-deploy
        code_version: "persona-fixed-v2",
        seasonal_override_enabled: true,

        selected_k: selectedK,
        elbow_suggested_k: elbowSuggestedK,
        sse_values: sseValues,
        total_observations: rawData.length,
      }),
      {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      },
    );
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});

function minMaxNormalize(data: number[][]): { normalizedFeatures: number[][]; normParams: Record<string, number> } {
  const m = data[0].length;
  const mins = Array(m).fill(Infinity), maxs = Array(m).fill(-Infinity);
  for (const row of data) for (let j = 0; j < m; j++) { mins[j] = Math.min(mins[j], row[j]); maxs[j] = Math.max(maxs[j], row[j]); }
  const normalizedFeatures = data.map(row => row.map((v, j) => maxs[j] - mins[j] === 0 ? 0 : (v - mins[j]) / (maxs[j] - mins[j])));
  const normParams: Record<string, number> = {};
  ["x1", "x2", "x3", "x4", "x5"].forEach((n, j) => { normParams[`${n}_min`] = mins[j]; normParams[`${n}_max`] = maxs[j]; });
  return { normalizedFeatures, normParams };
}
function euclidean(a: number[], b: number[]): number { return Math.sqrt(a.reduce((s, v, i) => s + (v - b[i]) ** 2, 0)); }
function runKMeans(data: number[][], k: number, maxIter: number, seed: number) {
  const n = data.length, m = data[0].length;
  const centroids = initKMeans(data, k, seed);
  let assignments = new Array(n).fill(0), prev = new Array(n).fill(-1);
  for (let iter = 0; iter < maxIter; iter++) {
    for (let i = 0; i < n; i++) { let md = Infinity, mc = 0; for (let j = 0; j < k; j++) { const d = euclidean(data[i], centroids[j]); if (d < md) { md = d; mc = j; } } assignments[i] = mc; }
    if (assignments.every((a, i) => a === prev[i])) break;
    prev = [...assignments];
    for (let j = 0; j < k; j++) { const ms = data.filter((_, i) => assignments[i] === j); if (ms.length === 0) continue; centroids[j] = Array(m).fill(0).map((_, fi) => ms.reduce((s, r) => s + r[fi], 0) / ms.length); }
  }
  return { centroids, assignments, sse: data.reduce((s, p, i) => s + euclidean(p, centroids[assignments[i]]) ** 2, 0) };
}
function initKMeans(data: number[][], k: number, seed: number): number[][] {
  const n = data.length, cs = [data[seed % n]];
  for (let i = 1; i < k; i++) {
    const ds = data.map(p => Math.min(...cs.map(c => euclidean(p, c))));
    const tot = ds.reduce((a, b) => a + b, 0);
    let cum = 0, thr = (seed * i * 0.7654321) % tot, cho = data[(seed * i) % n];
    for (let j = 0; j < n; j++) { cum += ds[j]; if (cum >= thr) { cho = data[j]; break; } }
    cs.push(cho);
  }
  return cs;
}
function findElbowK(sse: Record<string, number>): number {
  const ks = Object.keys(sse).sort();
  if (ks.length < 3) return parseInt(ks[0].replace("k", "")) || 2;
  const ss = ks.map(k => sse[k]);
  let mx = 0, idx = 1;
  for (let i = 1; i < ss.length - 1; i++) { const d = ss[i - 1] - 2 * ss[i] + ss[i + 1]; if (d > mx) { mx = d; idx = i; } }
  return parseInt(ks[idx].replace("k", ""));
}

// ============================================================================
// Pelabelan cluster mentah (per OBSERVASI MINGGU), sesuai BAB III 3.4.5:
// "K-Means menghasilkan cluster bernomor tanpa label semantik." Skor
// kecocokan dihitung terhadap SEMUA definisi persona, lalu greedy
// assignment memastikan setiap persona konseptual dipakai maksimal
// satu kali selama k <= 4.
// ============================================================================

type PersonaKey = "consistent" | "passive" | "seasonal" | "ambitious";

type PersonaLabel = "Consistent" | "Passive" | "Seasonal" | "Ambitious-Behind";

const PERSONA_KEYS: PersonaKey[] = ["consistent", "passive", "seasonal", "ambitious"];

const PERSONA_DISPLAY_LABELS: Record<PersonaKey, PersonaLabel> = {
  consistent: "Consistent",
  passive: "Passive",
  seasonal: "Seasonal",
  ambitious: "Ambitious-Behind",
};

function toPersonaDisplayLabel(persona: PersonaKey): PersonaLabel {
  return PERSONA_DISPLAY_LABELS[persona];
}

function toRecommendationRulePersonaId(label: string): PersonaKey {
  switch (label) {
    case "Consistent":
      return "consistent";
    case "Passive":
      return "passive";
    case "Seasonal":
      return "seasonal";
    case "Ambitious-Behind":
      return "ambitious";
    default:
      throw new Error(`Label persona tidak dikenali: ${label}`);
  }
}

// Sama seperti toRecommendationRulePersonaId, tapi TIDAK melempar error untuk
// label yang tidak dikenal (misal fallback "persona-baru-N" dari
// labelAllClusters saat k > 4 -- lihat baris ~271). Dipakai khusus di titik
// PENULISAN persona_history, supaya satu user dengan persona tak dikenal
// tidak menggagalkan penulisan untuk seluruh user lain dalam batch yang sama.
function toPersistablePersonaId(label: string): string {
  try {
    return toRecommendationRulePersonaId(label);
  } catch {
    return label; // fallback (mis. "persona-baru-1") sudah berformat lowercase/slug
  }
}

// Sisi BACA persona_label_id perlu menerima dua kemungkinan: baris lama
// (ditulis sebelum perbaikan toPersistablePersonaId, masih berformat
// kapital seperti "Passive") ATAU baris baru (sudah lowercase, hasil
// clustering setelah perbaikan). Fungsi ini menormalkan keduanya.
function normalizePersonaLabelId(rawLabelId: string): PersonaKey {
  if ((PERSONA_KEYS as string[]).includes(rawLabelId)) {
    return rawLabelId as PersonaKey;
  }
  return toRecommendationRulePersonaId(rawLabelId);
}

function personaScore(persona: PersonaKey, c: number[], avg: number[]): number {
  const [x1, x2, x3, x4, x5] = c;
  const [a1, a2, a3, a4, a5] = avg;
  const z = (v: number, a: number) => (a === 0 ? 0 : (v - a) / a);

  switch (persona) {
    case "consistent":
      return z(x1, a1) + z(x2, a2) + z(x3, a3) + z(x4, a4) + z(x5, a5);
    case "passive":
      return -(z(x1, a1) + z(x2, a2) + z(x3, a3) + z(x4, a4) + z(x5, a5));
    case "seasonal":
      return -z(x4, a4) + Math.min(z(x1, a1), 0) * -1 + Math.min(z(x2, a2), 0) * -1;
    case "ambitious":
      return z(x2, a2) - z(x5, a5) - z(x4, a4);
  }
}

function labelAllClusters(centroids: number[][]): string[] {
  const k = centroids.length;
  const m = centroids[0].length;
  const avg = Array(m).fill(0).map((_, i) => centroids.reduce((s, c) => s + c[i], 0) / k);

  const candidates: { ci: number; persona: PersonaKey; score: number }[] = [];
  for (let ci = 0; ci < k; ci++) {
    for (const persona of PERSONA_KEYS) {
      candidates.push({ ci, persona, score: personaScore(persona, centroids[ci], avg) });
    }
  }
  candidates.sort((a, b) => b.score - a.score);

  const labels: string[] = new Array(k).fill("");
  const usedPersona = new Set<string>();
  const usedCluster = new Set<number>();

  for (const cand of candidates) {
    if (usedCluster.has(cand.ci) || usedPersona.has(cand.persona)) continue;
    labels[cand.ci] = toPersonaDisplayLabel(cand.persona);
    usedCluster.add(cand.ci);
    usedPersona.add(cand.persona);
    if (usedCluster.size === Math.min(k, PERSONA_KEYS.length)) break;
  }

  let extraCount = 1;
  for (let ci = 0; ci < k; ci++) {
    if (!labels[ci]) {
      labels[ci] = `persona-baru-${extraCount}`;
      extraCount++;
    }
  }

  return labels;
}

async function logRun(sb: any, d: any): Promise<string | null> {
  const { data: r, error } = await sb.from("clustering_runs").insert({ selected_k: d.selected_k, sse_values: d.sse_values, centroids: d.centroids, normalization: d.normalization, total_observations: d.total_observations, status: d.status, cluster_labels: d.cluster_labels ?? null, random_seed: 42 }).select("id").single();
  if (error) console.error(error);
  return r?.id ?? null;
}

async function updatePersonaHistory(sb: any, uws: any[], res: any, runId: string | null, features: number[][]) {
  const uids = [...new Set(uws.map((u: any) => u.user_id))];
  await sb.from("persona_history").update({ is_current: false }).in("user_id", uids);
  const { data: run } = await sb.from("clustering_runs").select("centroids").eq("id", runId).single();
  const cs = run?.centroids ?? [];

  // Label mentah per observasi minggu (bukan label final per pengguna).
  const clusterLabels = labelAllClusters(cs);

  for (let i = 0; i < uws.length; i++) {
    const cn = res.assignments[i];
    const c = cs[cn] ?? [];
    const lbl = clusterLabels[cn];
    const isLatestForUser = uws[i].week_start === maxWeekForUser(uws, uws[i].user_id);
    await sb.from("persona_history").upsert({ user_id: uws[i].user_id, week_start: uws[i].week_start, clustering_run_id: runId, cluster_number: cn, persona_label: lbl, persona_label_id: toPersistablePersonaId(lbl), feature_values: { x1: features[i][0], x2: features[i][1], x3: features[i][2], x4: features[i][3], x5: features[i][4] }, centroid_values: { x1: c[0] ?? 0, x2: c[1] ?? 0, x3: c[2] ?? 0, x4: c[3] ?? 0, x5: c[4] ?? 0 }, is_current: isLatestForUser }, { onConflict: "user_id,week_start" });
  }
}

function maxWeekForUser(uws: any[], userId: string): string {
  return uws.filter((u) => u.user_id === userId).map((u) => u.week_start).sort().slice(-1)[0];
}

// ============================================================================
// SESUAI BAB III Tabel 3.11 (Pembelajar Musiman): "x1 dapat tinggi di satu
// periode [dan rendah di periode lain]" -- riwayat berfluktuasi. Deteksi
// dilakukan langsung dari VARIASI NILAI x1 (frekuensi) antar minggu milik
// tiap pengguna, bukan dari kecocokan nama label cluster (yang bisa gagal
// menangkap kasus di mana minggu aktif/tidak aktif jatuh ke cluster
// perantara yang belum punya nama baku).
// ============================================================================
function mean(arr: number[]): number {
  return arr.length ? arr.reduce((s, v) => s + v, 0) / arr.length : 0;
}
function stdev(arr: number[]): number {
  const m = mean(arr);
  return arr.length ? Math.sqrt(mean(arr.map((v) => (v - m) ** 2))) : 0;
}

async function finalizeSeasonalLabels(sb: any, uws: any[]) {
  const uids = [...new Set(uws.map((u: any) => u.user_id))];
  // Ambang CV (coefficient of variation) x1 antarminggu. Di atas ambang ini,
  // riwayat dianggap "berfluktuasi tinggi antarperiode" sesuai definisi
  // Pembelajar Musiman pada Tabel 3.11.
  const CV_THRESHOLD = 0.4;

  for (const uid of uids) {
    const { data: history } = await sb
      .from("persona_history")
      .select("id, week_start, persona_label, is_current, feature_values")
      .eq("user_id", uid)
      .order("week_start", { ascending: true });
    if (!history || history.length < 3) continue; // minimal 3 minggu data untuk menilai fluktuasi

    const x1Series = history.map((h: any) => h.feature_values?.x1 ?? 0);

    const m = mean(x1Series);
    const cv = m > 0 ? stdev(x1Series) / m : 0;

    const hasAboveAverage = x1Series.some(v => v > m);
    const hasBelowAverage = x1Series.some(v => v < m);

    const range = Math.max(...x1Series) - Math.min(...x1Series);

    // PERBAIKAN (audit designed_persona vs aktual, 80 responden sintetis):
    // range>=2 SEBELUMNYA membuat persona Passive (rentang sesi mingguan
    // seeder 1-3, sehingga range maksimum yang mungkin muncul murni dari
    // variasi acak adalah 2) ikut lolos ambang -- 8 dari 40 akun Passive
    // salah tertandai Seasonal. Dinaikkan ke range>=3: aman untuk Passive
    // (range maks 2), Consistent (rentang 5-7, range maks 2), dan
    // Ambitious-Behind (rentang 3-4, range maks 1) -- ketiganya TIDAK
    // PERNAH bisa mencapai range=3 hanya dari variasi acak intra-persona,
    // sehingga hanya pola yang benar-benar berselang-seling (seperti
    // Seasonal, rentang 5-6 vs 2-3 antarminggu) yang bisa lolos.
    //
    // CATATAN AKADEMIK (BAB III 3.4.5): CV_THRESHOLD dan range di atas
    // adalah konstanta operasional hasil pertimbangan peneliti pada tahap
    // pengembangan, BUKAN hasil kalibrasi empiris terhadap data mahasiswa
    // riil -- konsisten dengan perlakuan ambang lain pada sistem ini
    // (mis. Tabel 3.13.1). Penggunaan coefficient of variation untuk
    // mengukur konsistensi keterlibatan belajar antarperiode merujuk pada
    // pendekatan Goh (2025, Journal of Computers in Education), yang
    // menunjukkan CV lebih andal dibanding rerata/simpangan baku semata
    // untuk merepresentasikan homogenitas sebaran keterlibatan siswa.
    const isSeasonal =
      cv >= CV_THRESHOLD &&
      hasAboveAverage &&
      hasBelowAverage &&
      range >= 3;

    if (isSeasonal) {
      const current = history.find((h: any) => h.is_current);

      if (current) {
        await sb
          .from("persona_history")
          .update({
            persona_label: "Seasonal",
            persona_label_id: "seasonal",
          })
          .eq("id", current.id);
      }
    }
  }
}

async function generateRecommendations(
  sb: any,
  runId: string | null,
  targetUserId?: string,
) {
  let personasQuery = sb
    .from("persona_history")
    .select("id, user_id, persona_label_id, feature_values")
    .eq("is_current", true);
  if (targetUserId) {
    personasQuery = personasQuery.eq("user_id", targetUserId);
  }
  const { data: personas, error: personaError } = await personasQuery;

  if (personaError) {
    console.error(
      "Gagal mengambil persona terkini:",
      personaError,
    );
    return;
  }

  if (!personas || personas.length === 0) {
    console.warn("Tidak ada persona terkini untuk dibuatkan rekomendasi.");
    return;
  }

  for (const persona of personas) {
    try {
      /*
       * ============================================================
       * 1. Tentukan persona untuk recommendation_rules
       * ============================================================
       */
      const recommendationRulePersonaId =
        normalizePersonaLabelId(
          persona.persona_label_id,
        );

      /*
       * ============================================================
       * 1b. Hitung warning_tier berdasarkan jumlah monitoring_alerts
       * dalam 28 hari terakhir (per definisi dosen: "mahasiswa yang
       * SERING mendapat peringatan"). Kosakata tier berbeda per
       * persona -- lihat mapWarningTierLabel di generate_recommendations.ts.
       * Dipakai "hari ini" sebagai acuan periode karena fungsi ini
       * memproses persona is_current=true, bukan satu minggu historis
       * tertentu.
       * ============================================================
       */
      const todayStr = new Date().toISOString().slice(0, 10);
      const warningResult = await computeWarningTier(
        sb,
        persona.user_id,
        todayStr,
        recommendationRulePersonaId,
      );

      /*
       * ============================================================
       * 2. Ambil rule seperti mekanisme lama
       *
       * Setiap persona kini punya 2 varian rule per dimensi (warning_tier).
       * Filter .or() di bawah mengambil hanya varian yang sesuai tier user
       * ini -- TANPA filter ini, query akan mengembalikan 6 baris (bukan 3)
       * dan membuat rekomendasi dobel untuk setiap user.
       * ============================================================
       */
      const { data: rules, error: rulesError } = await sb
        .from("recommendation_rules")
        .select("*")
        .eq(
          "persona_label_id",
          recommendationRulePersonaId,
        )
        .eq("is_active", true)
        .or(`warning_tier.is.null,warning_tier.eq.${warningResult.tier}`);

      if (rulesError) {
        console.error(
          `Gagal mengambil rule untuk user ${persona.user_id}:`,
          rulesError,
        );
        continue;
      }

      if (!rules || rules.length === 0) {
        console.warn(
          `Tidak ada rule aktif untuk persona ${recommendationRulePersonaId}`,
        );
        continue;
      }

      if (rules.length !== 3) {
        console.warn(
          `Peringatan: persona '${recommendationRulePersonaId}' (tier '${warningResult.tier}') ` +
          `punya ${rules.length} rule aktif untuk user ${persona.user_id}, seharusnya 3. ` +
          `Cek kemungkinan versi ganda aktif di recommendation_rules.`,
        );
      }

      /*
       * ============================================================
       * 3. Ambil histori mingguan pengguna
       *
       * Histori hanya digunakan untuk memperkaya rekomendasi.
       * Histori tidak mengubah persona hasil K-Means.
       * ============================================================
       */
      const { data: history, error: historyError } = await sb
        .from("persona_history")
        .select("week_start, feature_values")
        .eq("user_id", persona.user_id)
        .order("week_start", { ascending: true });

      if (historyError) {
        console.error(
          `Gagal mengambil histori user ${persona.user_id}:`,
          historyError,
        );
      }

      const validHistory = history ?? [];

      /*
       * ============================================================
       * 4. Hitung CV frekuensi belajar x1
       * ============================================================
       */
      const x1Series = validHistory
        .map((row: any) =>
          Number(row.feature_values?.x1 ?? 0)
        )
        .filter((value: number) =>
          Number.isFinite(value)
        );

      const historyWeeks = x1Series.length;
      const averageX1 = mean(x1Series);

      const cv =
        averageX1 > 0
          ? stdev(x1Series) / averageX1
          : 0;

      const x1Range =
        x1Series.length > 0
          ? Math.max(...x1Series) -
          Math.min(...x1Series)
          : 0;

      /*
       * ============================================================
       * 5. Ambil kondisi x4 dan x5 terbaru
       * ============================================================
       */
      const currentFeatures =
        persona.feature_values ?? {};

      const consistency = Number(
        currentFeatures.x4 ?? 0,
      );

      const progress = Number(
        currentFeatures.x5 ?? 0,
      );

      /*
       * ============================================================
       * 6. Tentukan kondisi personalisasi
       *
       * Threshold dapat dijelaskan dalam penelitian sebagai:
       * - CV >= 0.4          : pola frekuensi berfluktuasi
       * - x4 < 50            : konsistensi relatif rendah
       * - x5 < 50            : progres relatif rendah
       *
       * Minimal 3 minggu diperlukan untuk menilai fluktuasi.
       * ============================================================
       */
      const isFluctuating =
        historyWeeks >= 3 &&
        cv >= 0.4 &&
        x1Range >= 2;

      const hasLowConsistency =
        consistency < 50;

      const hasLowProgress =
        progress < 50;

      /*
       * ============================================================
       * 7. Buat tambahan insight yang personal
       * ============================================================
       */
      const additionalInsights: string[] = [];
      const additionalActions: string[] = [];

      if (isFluctuating) {
        additionalInsights.push(
          `Frekuensi belajarmu terlihat naik turun antarminggu. ` +
          `Nilai CV sebesar ${cv.toFixed(2)} dengan rentang ` +
          `${x1Range} sesi menunjukkan pola belajar yang belum stabil.`,
        );

        additionalActions.push(
          "Tetapkan dua atau tiga hari belajar yang sama setiap minggu agar pola belajarmu lebih teratur.",
        );
      }

      if (hasLowConsistency) {
        additionalInsights.push(
          `Nilai konsistensi belajarmu saat ini sebesar ` +
          `${Math.round(consistency)}%, sehingga sebagian aktivitas ` +
          `yang direncanakan belum terlaksana secara teratur.`,
        );

        additionalActions.push(
          "Gunakan target mingguan yang lebih realistis dan catat setiap sesi yang berhasil diselesaikan.",
        );
      }

      if (hasLowProgress) {
        additionalInsights.push(
          `Progres target belajarmu saat ini sebesar ` +
          `${Math.round(progress)}%, sehingga strategi atau target ` +
          `belajar perlu dievaluasi kembali.`,
        );

        additionalActions.push(
          "Identifikasi satu hambatan utama dan tentukan satu tindakan kecil yang dapat dilakukan minggu ini.",
        );
      }

      /*
       * Ketika kondisi cukup baik, tetap beri penguatan positif.
       */
      if (
        !isFluctuating &&
        !hasLowConsistency &&
        !hasLowProgress
      ) {
        additionalInsights.push(
          "Pola belajar, konsistensi, dan progresmu saat ini menunjukkan kondisi yang cukup baik.",
        );

        additionalActions.push(
          "Pertahankan strategi yang sudah efektif dan lakukan evaluasi singkat pada akhir minggu.",
        );
      }

      /*
       * ============================================================
       * 8. Isi placeholder rule lama
       * ============================================================
       */
      const values = formatMetrics(
        currentFeatures,
      );
      // [x6] dipakai template ai_insight varian "sering"/"responsif".
      values.x6 = String(warningResult.count);

      /*
       * ============================================================
       * 9. Gabungkan rule persona dengan kondisi aktual pengguna
       * ============================================================
       */
      const rows = rules.map((rule: any) => {
        const originalInsight =
          substitutePlaceholders(
            rule.ai_insight ?? "",
            values,
          );

        const originalAction =
          substitutePlaceholders(
            rule.action ?? "",
            values,
          );

        const personalizedInsight = [
          originalInsight,
          ...additionalInsights,
        ]
          .filter(Boolean)
          .join(" ");

        const personalizedAction = [
          originalAction,
          ...additionalActions,
        ]
          .filter(Boolean)
          .join(" ");

        return {
          user_id: persona.user_id,
          persona_history_id: persona.id,
          rule_id: rule.id,
          msr_dimension: rule.msr_dimension,
          title: rule.title,

          ai_insight: hasUnresolvedPlaceholder(
            personalizedInsight,
          )
            ? logAndFallback(
              personalizedInsight,
              persona.user_id,
              rule.id,
              "ai_insight",
            )
            : personalizedInsight,

          strategy: rule.strategy,

          action: hasUnresolvedPlaceholder(
            personalizedAction,
          )
            ? logAndFallback(
              personalizedAction,
              persona.user_id,
              rule.id,
              "action",
            )
            : personalizedAction,

          reflection_question:
            rule.reflection_question,
        };
      });

      /*
       * ============================================================
       * 10. Hapus rekomendasi lama dan simpan hasil terbaru
       * ============================================================
       */
      const { error: deleteError } = await sb
        .from("recommendations")
        .delete()
        .eq("user_id", persona.user_id);

      if (deleteError) {
        console.error(
          `Gagal menghapus rekomendasi lama user ${persona.user_id}:`,
          deleteError,
        );
        continue;
      }

      const { error: insertError } = await sb
        .from("recommendations")
        .insert(rows);

      if (insertError) {
        console.error(
          `Gagal menyimpan rekomendasi user ${persona.user_id}:`,
          insertError,
        );
        continue;
      }

      /*
       * Log untuk pembuktian saat pengujian.
       */
      console.log({
        user_id: persona.user_id,
        persona: persona.persona_label_id,
        recommendation_rule_persona_id: recommendationRulePersonaId,
        warning_tier: warningResult.tier,
        warning_count: warningResult.count,
        history_weeks: historyWeeks,
        cv: Number(cv.toFixed(3)),
        x1_range: x1Range,
        consistency,
        progress,
        is_fluctuating: isFluctuating,
        low_consistency: hasLowConsistency,
        low_progress: hasLowProgress,
        recommendations_created: rows.length,
      });
    } catch (error) {
      console.error(
        `Kesalahan saat membuat rekomendasi untuk user ${persona.user_id}:`,
        error,
      );
    }
  }
}

function formatMetrics(fv: Record<string, number>): Record<string, string> {
  return {
    x1: String(Math.round(fv.x1 ?? 0)),
    x2: String(Math.round(fv.x2 ?? 0)),
    x3: (fv.x3 ?? 0).toFixed(1),
    x4: String(Math.round(fv.x4 ?? 0)),
    x5: String(Math.round(fv.x5 ?? 0)),
  };
}
function substitutePlaceholders(template: string, values: Record<string, string>): string {
  let result = template;
  for (const [key, value] of Object.entries(values)) {
    result = result.replace(new RegExp(`\\[${key}\\]`, "g"), value);
  }
  return result;
}
function hasUnresolvedPlaceholder(text: string): boolean {
  return /\[x[1-6]\]/.test(text);
}
function logAndFallback(text: string, userId: string, ruleId: string, field: string): string {
  console.error(`Placeholder tidak terselesaikan user=${userId} rule=${ruleId} field=${field}: "${text}"`);
  return "Rekomendasi sedang diperbarui. Silakan cek kembali beberapa saat lagi.";
}