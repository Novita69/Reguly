-- =====================================================================
-- AI Learning Tracker — Migration v3.0: Thesis Alignment
-- =====================================================================
-- Tujuan migrasi ini:
--   A. Mengunci SRL Reassessment (T2) single-cycle: hanya bisa diisi
--      setelah 7 hari dari Baseline (T1), dan hanya sekali seumur akun
--      (validasi di sisi server/DB, bukan cuma UI Flutter).
--   B. Anchor seluruh perhitungan "periode mingguan" ke assessed_at
--      (completed_at milik Baseline Assessment), bukan created_at atau
--      kalender global (DATE_TRUNC('week', ...)).
--   C. period_start/period_end pada learning_goals tidak lagi bebas
--      diisi klien, melainkan digenerate dari assessed_at.
--   D. View v_reassessment_gate: satu sumber kebenaran untuk status
--      "boleh isi T2 atau belum" yang dipakai Dashboard & Progress screen.
--   E. View v_registered_respondents: hanya menghitung akun yang sudah
--      menyelesaikan T1 sebagai "responden" (selaras BAB 3.1.1).
--   F. BUG FIX (ditemukan saat audit, di luar topik revisi skripsi):
--      Edge Function run-kmeans membaca/menulis kolom yang TIDAK ADA
--      di skema v2 (clustering_runs, persona_history, recommendations,
--      recommendation_rules, v_weekly_activity_aggregates). Migrasi ini
--      menambahkan kolom yang hilang supaya pipeline clustering &
--      rekomendasi benar-benar berjalan.
-- Jalankan file ini SETELAH v2_schema.sql, di Supabase SQL Editor.
-- =====================================================================


-- ─────────────────────────────────────────────────────────────────────
-- A. VALIDASI SERVER-SIDE: SRL Reassessment single-cycle, 7 hari
-- ─────────────────────────────────────────────────────────────────────
-- Pesan RAISE EXCEPTION diberi prefix kode (BASELINE_NOT_COMPLETED,
-- REASSESSMENT_LOCKED, REASSESSMENT_ALREADY_DONE) supaya sisi Flutter
-- bisa mendeteksi jenis error dan menampilkan pesan yang sesuai
-- (lihat AssessmentService.submitAssessment).

CREATE OR REPLACE FUNCTION public.validate_reassessment_timing()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_baseline_at TIMESTAMPTZ;
  v_existing_count INT;
BEGIN
  IF NEW.assessment_type = 'reassessment' THEN

    SELECT completed_at INTO v_baseline_at
    FROM public.assessment_results
    WHERE user_id = NEW.user_id AND assessment_type = 'baseline'
    ORDER BY completed_at ASC
    LIMIT 1;

    IF v_baseline_at IS NULL THEN
      RAISE EXCEPTION 'BASELINE_NOT_COMPLETED: Baseline Assessment (T1) belum diselesaikan.';
    END IF;

    IF NOW() < v_baseline_at + INTERVAL '7 days' THEN
      RAISE EXCEPTION 'REASSESSMENT_LOCKED: SRL Reassessment (T2) baru dapat diisi setelah 7 hari sejak Baseline Assessment selesai.';
    END IF;

    SELECT COUNT(*) INTO v_existing_count
    FROM public.assessment_results
    WHERE user_id = NEW.user_id AND assessment_type = 'reassessment';

    IF v_existing_count > 0 THEN
      RAISE EXCEPTION 'REASSESSMENT_ALREADY_DONE: SRL Reassessment (T2) bersifat satu kali (single-cycle) dan sudah pernah diisi.';
    END IF;

  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS before_insert_validate_reassessment ON public.assessment_results;
CREATE TRIGGER before_insert_validate_reassessment
  BEFORE INSERT ON public.assessment_results
  FOR EACH ROW EXECUTE FUNCTION public.validate_reassessment_timing();


-- ─────────────────────────────────────────────────────────────────────
-- B & C. Anchor learning_goals.period_start/period_end ke assessed_at
-- ─────────────────────────────────────────────────────────────────────
-- Nilai period_start/period_end yang dikirim klien (jika ada) akan
-- DITIMPA oleh trigger ini, sehingga tetap konsisten walau UI lama
-- masih mengirim CURRENT_DATE sebagai default.

CREATE OR REPLACE FUNCTION public.set_goal_period_from_baseline()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_baseline_at TIMESTAMPTZ;
BEGIN
  SELECT completed_at INTO v_baseline_at
  FROM public.assessment_results
  WHERE user_id = NEW.user_id AND assessment_type = 'baseline'
  ORDER BY completed_at ASC
  LIMIT 1;

  IF v_baseline_at IS NOT NULL THEN
    NEW.period_start := v_baseline_at::DATE;
    NEW.period_end   := (v_baseline_at + INTERVAL '7 days')::DATE;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS before_insert_goal_period ON public.learning_goals;
CREATE TRIGGER before_insert_goal_period
  BEFORE INSERT ON public.learning_goals
  FOR EACH ROW EXECUTE FUNCTION public.set_goal_period_from_baseline();


-- ─────────────────────────────────────────────────────────────────────
-- D. View: v_reassessment_gate
-- ─────────────────────────────────────────────────────────────────────
-- Satu sumber kebenaran status T2 per pengguna, dipakai oleh:
--   - Dashboard (untuk popup pengingat)
--   - Progress Evaluation screen (untuk state tombol: terkunci/aktif/selesai)
-- RLS pada profiles & assessment_results (id/user_id = uid()) otomatis
-- membatasi view ini hanya menampilkan baris milik pengguna yang login,
-- mengikuti pola yang sama seperti v_assessment_delta.

CREATE OR REPLACE VIEW public.v_reassessment_gate AS
SELECT
  p.id AS user_id,
  b.baseline_at,
  CASE WHEN b.baseline_at IS NOT NULL
       THEN b.baseline_at + INTERVAL '7 days' END AS unlock_at,
  COALESCE(b.baseline_at IS NOT NULL AND NOW() >= b.baseline_at + INTERVAL '7 days', FALSE) AS can_reassess,
  (r.reassessment_at IS NOT NULL) AS has_reassessed,
  r.reassessment_at,
  CASE WHEN b.baseline_at IS NULL THEN NULL
       ELSE GREATEST(0, CEIL(EXTRACT(EPOCH FROM
              ((b.baseline_at + INTERVAL '7 days') - NOW())) / 86400.0))::INT
  END AS days_remaining
FROM public.profiles p
LEFT JOIN (
  SELECT user_id, MIN(completed_at) AS baseline_at
  FROM public.assessment_results
  WHERE assessment_type = 'baseline'
  GROUP BY user_id
) b ON b.user_id = p.id
LEFT JOIN (
  SELECT user_id, MIN(completed_at) AS reassessment_at
  FROM public.assessment_results
  WHERE assessment_type = 'reassessment'
  GROUP BY user_id
) r ON r.user_id = p.id;

GRANT SELECT ON public.v_reassessment_gate TO authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- E. View: v_registered_respondents
-- ─────────────────────────────────────────────────────────────────────
-- "Terdaftar sebagai responden" = sudah menyelesaikan T1 (BAB 3.1.1).
-- Pakai view ini (bukan tabel profiles mentah) untuk semua rekap
-- jumlah responden di BAB 4, supaya akun yang tidak pernah isi T1
-- tidak ikut terhitung.

CREATE OR REPLACE VIEW public.v_registered_respondents AS
SELECT p.*, b.baseline_at
FROM public.profiles p
JOIN (
  SELECT user_id, MIN(completed_at) AS baseline_at
  FROM public.assessment_results
  WHERE assessment_type = 'baseline'
  GROUP BY user_id
) b ON b.user_id = p.id;

GRANT SELECT ON public.v_registered_respondents TO authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- B (lanjutan). Perbaikan v_weekly_activity_aggregates
-- ─────────────────────────────────────────────────────────────────────
-- Perubahan dari versi lama:
--   1. Anchor periode mingguan = assessed_at (baseline completed_at),
--      BUKAN DATE_TRUNC('week', ...) kalender global.
--   2. Nama kolom output disamakan dengan yang dibaca Edge Function
--      run-kmeans: x1_frequency, x2_avg_duration, x3_avg_focus,
--      x4_consistency, x5_progress (sebelumnya tidak cocok sama sekali,
--      x4 & x5 bahkan belum pernah dihitung).
--   3. Menerapkan aturan preprocessing BAB 3.4.3 poin 5: observasi
--      tanpa goal tidak digunakan; minggu dengan goal tapi tanpa sesi
--      tetap masuk dengan x1=x2=x3=0.

CREATE OR REPLACE VIEW public.v_weekly_activity_aggregates AS
WITH baseline AS (
  SELECT user_id, MIN(completed_at) AS baseline_at
  FROM public.assessment_results
  WHERE assessment_type = 'baseline'
  GROUP BY user_id
),
activity_agg AS (
  SELECT
    la.user_id,
    FLOOR(EXTRACT(EPOCH FROM (la.activity_date::TIMESTAMPTZ - b.baseline_at))
          / (7 * 86400))::INT + 1 AS week_number,
    COUNT(*)                  AS session_count,
    AVG(la.duration_minutes)  AS avg_duration,
    AVG(la.focus_score)       AS avg_focus
  FROM public.learning_activities la
  JOIN baseline b ON b.user_id = la.user_id
  WHERE la.activity_date::TIMESTAMPTZ >= b.baseline_at
  GROUP BY la.user_id, week_number
),
goal_agg AS (
  SELECT
    g.user_id,
    FLOOR(EXTRACT(EPOCH FROM (g.period_start::TIMESTAMPTZ - b.baseline_at))
          / (7 * 86400))::INT + 1 AS week_number,
    SUM(g.target_sessions) AS target_sessions,
    SUM(g.actual_sessions) AS actual_sessions,
    AVG(g.actual_progress) AS actual_progress
  FROM public.learning_goals g
  JOIN baseline b ON b.user_id = g.user_id
  GROUP BY g.user_id, week_number
),
weeks AS (
  -- Union agar minggu dengan goal-tapi-tanpa-aktivitas tetap muncul
  SELECT user_id, week_number FROM activity_agg
  UNION
  SELECT user_id, week_number FROM goal_agg
)
SELECT
  w.user_id,
  (b.baseline_at + ((w.week_number - 1) * INTERVAL '7 days'))::DATE AS week_start,
  w.week_number,
  COALESCE(a.session_count, 0)                        AS x1_frequency,
  ROUND(COALESCE(a.avg_duration, 0)::NUMERIC, 2)       AS x2_avg_duration,
  ROUND(COALESCE(a.avg_focus, 0)::NUMERIC, 2)          AS x3_avg_focus,
  ROUND(LEAST(COALESCE(g.actual_sessions, 0)::NUMERIC
        / NULLIF(g.target_sessions, 0) * 100, 100), 2) AS x4_consistency,
  ROUND(COALESCE(g.actual_progress, 0)::NUMERIC, 2)    AS x5_progress
FROM weeks w
JOIN baseline b ON b.user_id = w.user_id
LEFT JOIN activity_agg a ON a.user_id = w.user_id AND a.week_number = w.week_number
LEFT JOIN goal_agg g ON g.user_id = w.user_id AND g.week_number = w.week_number
WHERE g.week_number IS NOT NULL;  -- observasi tanpa goal tidak digunakan (3.4.3 poin 5)


-- ─────────────────────────────────────────────────────────────────────
-- F. BUG FIX: skema clustering_runs / persona_history / recommendations
--    / recommendation_rules belum cocok dengan yang dibaca-tulis oleh
--    Edge Function run-kmeans (dan dengan Tabel 3.6/3.3.4 di skripsi).
--    Tanpa ini, setiap eksekusi run-kmeans akan gagal di step
--    logRun()/updatePersonaHistory()/generateRecommendations().
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.clustering_runs
  ADD COLUMN IF NOT EXISTS selected_k INT,
  ADD COLUMN IF NOT EXISTS sse_values JSONB,
  ADD COLUMN IF NOT EXISTS centroids JSONB,
  ADD COLUMN IF NOT EXISTS normalization JSONB,
  ADD COLUMN IF NOT EXISTS total_observations INT,
  ADD COLUMN IF NOT EXISTS status TEXT,
  ADD COLUMN IF NOT EXISTS random_seed INT;

ALTER TABLE public.persona_history
  ADD COLUMN IF NOT EXISTS cluster_number INT,
  ADD COLUMN IF NOT EXISTS persona_label TEXT,
  ADD COLUMN IF NOT EXISTS feature_values JSONB,
  ADD COLUMN IF NOT EXISTS centroid_values JSONB;

-- Diperlukan agar .upsert(..., onConflict: "user_id,week_start") di
-- Edge Function berfungsi (sebelumnya tidak ada constraint sama sekali).
CREATE UNIQUE INDEX IF NOT EXISTS uq_persona_history_user_week
  ON public.persona_history(user_id, week_start);

ALTER TABLE public.recommendation_rules
  ADD COLUMN IF NOT EXISTS persona_label_id TEXT,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

UPDATE public.recommendation_rules
  SET persona_label_id = persona_id
  WHERE persona_label_id IS NULL;

ALTER TABLE public.recommendations
  ADD COLUMN IF NOT EXISTS persona_history_id UUID
    REFERENCES public.persona_history(id) ON DELETE SET NULL;

-- =====================================================================
-- SELESAI. Setelah menjalankan file ini:
--   1. Deploy ulang Edge Function run-kmeans (tidak perlu diubah kodenya,
--      hanya skema yang tadinya kurang lengkap).
--   2. Uji end-to-end: buat akun test → isi Baseline → mundurkan
--      completed_at baseline test itu 7+ hari via SQL Editor → coba isi
--      Reassessment → pastikan sukses & terarah ke TAM.
-- =====================================================================
