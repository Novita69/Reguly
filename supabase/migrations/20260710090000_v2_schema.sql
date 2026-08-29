-- =====================================================================
-- AI Learning Tracker — Database Schema v2.0
-- Supabase (PostgreSQL 15)
-- =====================================================================
-- CATATAN: Jalankan file ini di Supabase SQL Editor secara BERURUTAN.
-- Jika schema sudah ada, gunakan perintah ALTER TABLE / CREATE IF NOT EXISTS.
-- =====================================================================

-- ── Extension ─────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── Tabel: profiles ────────────────────────────────────────────────────
-- Auto-created saat user mendaftar via Supabase Auth trigger
CREATE TABLE IF NOT EXISTS profiles (
  id                     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name              TEXT,
  avatar_url             TEXT,
  institution            TEXT,
  study_program          TEXT,
  -- [v2.0] Kolom baru: routing lebih efisien
  has_completed_baseline BOOLEAN NOT NULL DEFAULT FALSE,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger: auto-insert profile saat user baru mendaftar
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, avatar_url)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'avatar_url'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Trigger: update has_completed_baseline setelah asesmen pertama
CREATE OR REPLACE FUNCTION public.mark_baseline_completed()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.assessment_type = 'baseline' THEN
    UPDATE public.profiles
    SET has_completed_baseline = TRUE, updated_at = NOW()
    WHERE id = NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_baseline_submitted ON public.assessment_results;

-- ── Tabel: assessment_results ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS assessment_results (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id             UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  assessment_type     TEXT NOT NULL CHECK (assessment_type IN ('baseline', 'reassessment')),
  -- [v2.0] Kolom baru: urutan T1→T2→T3
  assessment_sequence INT  NOT NULL DEFAULT 1,
  -- 12 item Likert 1–5
  item_01 SMALLINT NOT NULL CHECK (item_01 BETWEEN 1 AND 5),
  item_02 SMALLINT NOT NULL CHECK (item_02 BETWEEN 1 AND 5),
  item_03 SMALLINT NOT NULL CHECK (item_03 BETWEEN 1 AND 5),
  item_04 SMALLINT NOT NULL CHECK (item_04 BETWEEN 1 AND 5),
  item_05 SMALLINT NOT NULL CHECK (item_05 BETWEEN 1 AND 5),
  item_06 SMALLINT NOT NULL CHECK (item_06 BETWEEN 1 AND 5),
  item_07 SMALLINT NOT NULL CHECK (item_07 BETWEEN 1 AND 5),
  item_08 SMALLINT NOT NULL CHECK (item_08 BETWEEN 1 AND 5),
  item_09 SMALLINT NOT NULL CHECK (item_09 BETWEEN 1 AND 5),
  item_10 SMALLINT NOT NULL CHECK (item_10 BETWEEN 1 AND 5),
  item_11 SMALLINT NOT NULL CHECK (item_11 BETWEEN 1 AND 5),
  item_12 SMALLINT NOT NULL CHECK (item_12 BETWEEN 1 AND 5),
  -- Computed scores (di-set oleh trigger di bawah)
  score_planning    INT GENERATED ALWAYS AS (item_01 + item_02 + item_03 + item_04) STORED,
  score_monitoring  INT GENERATED ALWAYS AS (item_05 + item_06 + item_07 + item_08) STORED,
  score_evaluating  INT GENERATED ALWAYS AS (item_09 + item_10 + item_11 + item_12) STORED,
  score_total       INT GENERATED ALWAYS AS (
    item_01+item_02+item_03+item_04+item_05+item_06+
    item_07+item_08+item_09+item_10+item_11+item_12
  ) STORED,
  completed_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger: isi assessment_sequence secara otomatis
CREATE OR REPLACE FUNCTION public.set_assessment_sequence()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  SELECT COALESCE(MAX(assessment_sequence), 0) + 1
  INTO NEW.assessment_sequence
  FROM public.assessment_results
  WHERE user_id = NEW.user_id AND assessment_type = NEW.assessment_type;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS before_insert_assessment ON public.assessment_results;
CREATE TRIGGER before_insert_assessment
  BEFORE INSERT ON public.assessment_results
  FOR EACH ROW EXECUTE FUNCTION public.set_assessment_sequence();

-- Buat trigger mark_baseline_completed setelah tabel ada
CREATE TRIGGER on_baseline_submitted
  AFTER INSERT ON public.assessment_results
  FOR EACH ROW EXECUTE FUNCTION public.mark_baseline_completed();

-- ── Tabel: learning_goals ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS learning_goals (
  id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id                 UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title                   TEXT NOT NULL,
  category                TEXT NOT NULL DEFAULT 'Umum',
  -- [v2.0] period_start & period_end untuk filter K-Means
  period_start            DATE NOT NULL DEFAULT CURRENT_DATE,
  period_end              DATE,
  target_sessions         INT  NOT NULL DEFAULT 5,
  target_duration         INT  NOT NULL DEFAULT 30,  -- menit per sesi
  target_progress         NUMERIC(5,2) NOT NULL DEFAULT 100.0,
  status                  TEXT NOT NULL DEFAULT 'active'
                              CHECK (status IN ('active','completed','paused')),
  actual_sessions         INT  NOT NULL DEFAULT 0,
  actual_progress         NUMERIC(5,2) NOT NULL DEFAULT 0.0,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Tabel: learning_activities ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS learning_activities (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id          UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  goal_id          UUID REFERENCES learning_goals(id) ON DELETE SET NULL,
  activity_name    TEXT NOT NULL,
  category         TEXT NOT NULL DEFAULT 'Umum',
  activity_date    DATE NOT NULL DEFAULT CURRENT_DATE,
  start_time       TIME,
  duration_minutes INT  NOT NULL CHECK (duration_minutes > 0),
  focus_score      SMALLINT NOT NULL CHECK (focus_score BETWEEN 1 AND 5),
  progress_percent NUMERIC(5,2) NOT NULL DEFAULT 0.0
                       CHECK (progress_percent BETWEEN 0 AND 100),
  notes            TEXT,
  source_type      TEXT NOT NULL DEFAULT 'manual'
                       CHECK (source_type IN ('manual','focus_session')),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger: update actual_sessions di learning_goals saat aktivitas ditambah
CREATE OR REPLACE FUNCTION public.update_goal_progress()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.goal_id IS NOT NULL THEN
    UPDATE public.learning_goals
    SET
      actual_sessions = (
        SELECT COUNT(*) FROM public.learning_activities
        WHERE goal_id = NEW.goal_id
      ),
      actual_progress = LEAST(
        (SELECT COUNT(*) FROM public.learning_activities WHERE goal_id = NEW.goal_id)::NUMERIC
        / NULLIF(target_sessions, 0) * 100,
        100
      ),
      updated_at = NOW()
    WHERE id = NEW.goal_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_activity_insert ON public.learning_activities;
CREATE TRIGGER after_activity_insert
  AFTER INSERT ON public.learning_activities
  FOR EACH ROW EXECUTE FUNCTION public.update_goal_progress();

-- ── Tabel: clustering_runs ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS clustering_runs (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  run_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  k                SMALLINT NOT NULL,
  sse              NUMERIC,
  users_processed  INT NOT NULL DEFAULT 0,
  -- [v2.0] is_latest untuk query cepat
  is_latest        BOOLEAN NOT NULL DEFAULT FALSE,
  metadata         JSONB
);

-- Trigger: reset is_latest saat run baru dibuat
CREATE OR REPLACE FUNCTION public.reset_latest_clustering_run()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.clustering_runs SET is_latest = FALSE WHERE id <> NEW.id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_clustering_run_insert ON public.clustering_runs;
CREATE TRIGGER after_clustering_run_insert
  AFTER INSERT ON public.clustering_runs
  FOR EACH ROW EXECUTE FUNCTION public.reset_latest_clustering_run();

-- ── Tabel: persona_history ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS persona_history (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  clustering_run_id UUID REFERENCES clustering_runs(id) ON DELETE SET NULL,
  persona_label_id TEXT NOT NULL
                       CHECK (persona_label_id IN ('consistent','passive','seasonal','ambitious')),
  week_start      DATE NOT NULL,
  is_current      BOOLEAN NOT NULL DEFAULT TRUE,
  assigned_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Tabel: recommendation_rules ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS recommendation_rules (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  persona_id    TEXT NOT NULL
                    CHECK (persona_id IN ('consistent','passive','seasonal','ambitious')),
  msr_dimension TEXT NOT NULL
                    CHECK (msr_dimension IN ('planning','monitoring','evaluating')),
  priority      INT  NOT NULL DEFAULT 2,
  title         TEXT NOT NULL,
  ai_insight    TEXT NOT NULL,
  strategy      TEXT NOT NULL,
  action        TEXT NOT NULL,
  reflection_question TEXT NOT NULL
);

-- ── Tabel: recommendations ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS recommendations (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  rule_id       UUID REFERENCES recommendation_rules(id) ON DELETE SET NULL,
  msr_dimension TEXT NOT NULL,
  title         TEXT NOT NULL,
  ai_insight    TEXT NOT NULL,
  strategy      TEXT NOT NULL,
  action        TEXT NOT NULL,
  reflection_question TEXT NOT NULL,
  is_completed  BOOLEAN NOT NULL DEFAULT FALSE,
  -- [v2.0] Kolom baru untuk analytics
  is_dismissed  BOOLEAN NOT NULL DEFAULT FALSE,
  viewed_at     TIMESTAMPTZ,
  completed_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Tabel: weekly_reflections ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS weekly_reflections (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  week_year       INT  NOT NULL,
  week_number     INT  NOT NULL,
  answer_1        TEXT,
  answer_2        TEXT,
  answer_3        TEXT,
  answer_4        TEXT,
  answer_5        TEXT,
  overall_rating  SMALLINT CHECK (overall_rating BETWEEN 1 AND 5),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, week_year, week_number)
);

-- ── Tabel: tam_responses ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tam_responses (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  peou_1 SMALLINT CHECK (peou_1 BETWEEN 1 AND 5),
  peou_2 SMALLINT CHECK (peou_2 BETWEEN 1 AND 5),
  peou_3 SMALLINT CHECK (peou_3 BETWEEN 1 AND 5),
  peou_4 SMALLINT CHECK (peou_4 BETWEEN 1 AND 5),
  peou_5 SMALLINT CHECK (peou_5 BETWEEN 1 AND 5),
  pu_1   SMALLINT CHECK (pu_1   BETWEEN 1 AND 5),
  pu_2   SMALLINT CHECK (pu_2   BETWEEN 1 AND 5),
  pu_3   SMALLINT CHECK (pu_3   BETWEEN 1 AND 5),
  pu_4   SMALLINT CHECK (pu_4   BETWEEN 1 AND 5),
  pu_5   SMALLINT CHECK (pu_5   BETWEEN 1 AND 5),
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Tabel: reminder_settings [v2.0 BARU] ─────────────────────────────
CREATE TABLE IF NOT EXISTS reminder_settings (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id              UUID NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  study_reminder       BOOLEAN NOT NULL DEFAULT TRUE,
  study_time           TIME NOT NULL DEFAULT '08:00:00',
  reflection_reminder  BOOLEAN NOT NULL DEFAULT TRUE,
  reassessment_reminder BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Tabel: app_user_settings [v2.0 BARU] ─────────────────────────────
CREATE TABLE IF NOT EXISTS app_user_settings (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  dark_mode  BOOLEAN NOT NULL DEFAULT FALSE,
  language   TEXT NOT NULL DEFAULT 'id',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── View: v_assessment_delta [v2.0 FIXED] ────────────────────────────
-- Fix: handle multiple T2 assessments dengan DISTINCT ON
CREATE OR REPLACE VIEW public.v_assessment_delta AS
WITH t1 AS (
  SELECT DISTINCT ON (user_id)
    user_id,
    score_planning   AS t1_planning,
    score_monitoring AS t1_monitoring,
    score_evaluating AS t1_evaluating,
    score_total      AS t1_total,
    completed_at     AS t1_at
  FROM public.assessment_results
  WHERE assessment_type = 'baseline'
  ORDER BY user_id, completed_at ASC
),
t2 AS (
  SELECT DISTINCT ON (user_id)
    user_id,
    score_planning   AS t2_planning,
    score_monitoring AS t2_monitoring,
    score_evaluating AS t2_evaluating,
    score_total      AS t2_total,
    completed_at     AS t2_at
  FROM public.assessment_results
  WHERE assessment_type = 'reassessment'
  ORDER BY user_id, completed_at DESC
)
SELECT
  t1.user_id,
  t1.t1_planning,  t2.t2_planning,
  (t2.t2_planning  - t1.t1_planning)  AS delta_planning,
  t1.t1_monitoring, t2.t2_monitoring,
  (t2.t2_monitoring - t1.t1_monitoring) AS delta_monitoring,
  t1.t1_evaluating, t2.t2_evaluating,
  (t2.t2_evaluating - t1.t1_evaluating) AS delta_evaluating,
  t1.t1_total,     t2.t2_total,
  (t2.t2_total     - t1.t1_total)     AS delta_total,
  t1.t1_at,        t2.t2_at
FROM t1
JOIN t2 USING (user_id);

-- ── View: v_weekly_activity_aggregates [v2.0 FIXED] ──────────────────
-- Fix: hapus Cartesian product dengan memisahkan aggregasi
CREATE OR REPLACE VIEW public.v_weekly_activity_aggregates AS
SELECT
  la.user_id,
  DATE_TRUNC('week', la.activity_date::TIMESTAMPTZ)::DATE AS week_start,
  COUNT(*)                        AS total_sessions,
  SUM(la.duration_minutes)        AS total_duration_minutes,
  ROUND(AVG(la.focus_score), 2)  AS avg_focus_score,
  COUNT(DISTINCT la.activity_date) AS active_days
FROM public.learning_activities la
GROUP BY la.user_id, DATE_TRUNC('week', la.activity_date::TIMESTAMPTZ);

-- ── RLS Policies ──────────────────────────────────────────────────────
ALTER TABLE profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE assessment_results   ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning_goals       ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning_activities  ENABLE ROW LEVEL SECURITY;
ALTER TABLE clustering_runs      ENABLE ROW LEVEL SECURITY;
ALTER TABLE persona_history      ENABLE ROW LEVEL SECURITY;
ALTER TABLE recommendation_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE recommendations      ENABLE ROW LEVEL SECURITY;
ALTER TABLE weekly_reflections   ENABLE ROW LEVEL SECURITY;
ALTER TABLE tam_responses        ENABLE ROW LEVEL SECURITY;
ALTER TABLE reminder_settings    ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_user_settings    ENABLE ROW LEVEL SECURITY;

-- Helper: current user id
CREATE OR REPLACE FUNCTION public.uid() RETURNS UUID
LANGUAGE sql STABLE AS $$ SELECT auth.uid() $$;

-- profiles: user bisa baca & update miliknya sendiri
CREATE POLICY "user_own_profile_select" ON profiles FOR SELECT USING (id = uid());
CREATE POLICY "user_own_profile_update" ON profiles FOR UPDATE USING (id = uid());

-- assessment_results
CREATE POLICY "user_own_assessment_select" ON assessment_results FOR SELECT USING (user_id = uid());
CREATE POLICY "user_own_assessment_insert" ON assessment_results FOR INSERT WITH CHECK (user_id = uid());

-- learning_goals
CREATE POLICY "user_own_goals_all" ON learning_goals FOR ALL USING (user_id = uid());

-- learning_activities
CREATE POLICY "user_own_activities_all" ON learning_activities FOR ALL USING (user_id = uid());

-- clustering_runs: semua bisa baca (untuk Edge Function)
CREATE POLICY "all_read_clustering_runs" ON clustering_runs FOR SELECT USING (TRUE);

-- persona_history
CREATE POLICY "user_own_persona_select" ON persona_history FOR SELECT USING (user_id = uid());

-- recommendation_rules: semua bisa baca
CREATE POLICY "all_read_recommendation_rules" ON recommendation_rules FOR SELECT USING (TRUE);

-- recommendations
CREATE POLICY "user_own_recommendations_all" ON recommendations FOR ALL USING (user_id = uid());

-- weekly_reflections
CREATE POLICY "user_own_reflections_all" ON weekly_reflections FOR ALL USING (user_id = uid());

-- tam_responses
CREATE POLICY "user_own_tam_all" ON tam_responses FOR ALL USING (user_id = uid());

-- reminder_settings
CREATE POLICY "user_own_reminders_all" ON reminder_settings FOR ALL USING (user_id = uid());

-- app_user_settings
CREATE POLICY "user_own_settings_all" ON app_user_settings FOR ALL USING (user_id = uid());

-- ── Indexes ───────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_activities_user_date ON learning_activities(user_id, activity_date DESC);
CREATE INDEX IF NOT EXISTS idx_activities_goal     ON learning_activities(goal_id);
CREATE INDEX IF NOT EXISTS idx_goals_user_status   ON learning_goals(user_id, status);
CREATE INDEX IF NOT EXISTS idx_assessment_user_type ON assessment_results(user_id, assessment_type, completed_at DESC);
CREATE INDEX IF NOT EXISTS idx_persona_user_current ON persona_history(user_id, is_current) WHERE is_current = TRUE;
CREATE INDEX IF NOT EXISTS idx_recommendations_user ON recommendations(user_id, is_dismissed, created_at DESC);

