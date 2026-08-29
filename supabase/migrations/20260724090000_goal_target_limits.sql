-- v6_goal_target_limits.sql
--
-- Menegakkan batas bisnis Learning Goals di sisi SERVER (Postgres), agar
-- tidak bisa dilewati dengan langsung memanggil Supabase REST API / SQL
-- client secara manual -- terlepas dari validasi apa pun yang ada di
-- Flutter:
--   - target_sessions : 1..7
--   - target_duration : 5..120 (menit per sesi)
--
-- Dua mekanisme independen diterapkan sekaligus (defense-in-depth), sama
-- seperti pola trigger yang sudah dipakai di v2_schema.sql
-- (update_goal_progress) dan v3_thesis_alignment.sql
-- (set_goal_period_from_baseline):
--   1. Trigger BEFORE INSERT/UPDATE -> lapisan "backend": pesan error
--      yang jelas, dapat dibedakan dari error lain oleh Flutter
--      (lihat _friendlyGoalError di goal_provider.dart).
--   2. CHECK constraint -> lapisan "database": jaring pengaman terakhir
--      yang tetap berlaku walau trigger di-disable atau ada akses
--      langsung ke DB (mis. lewat SQL editor / service_role key yang
--      melewati RLS).
--
-- Nilai 7 dan 120 sengaja di-hardcode di trigger (bukan dibaca dari
-- tabel konfigurasi seperti monitoring_rules) karena ini adalah batas
-- desain SMART Goal yang tetap, bukan parameter yang perlu diubah tanpa
-- deploy ulang.

-- ── 1. Backfill data lama yang sudah melebihi batas baru ───────────────
-- Tanpa ini, ALTER TABLE ... ADD CONSTRAINT di langkah 3 akan gagal jika
-- ada baris lama (dibuat sebelum aturan 7/120 berlaku) yang melanggar.
-- Pola sama seperti migration period_end_required.sql sebelumnya.
UPDATE public.learning_goals
SET target_sessions = LEAST(target_sessions, 7)
WHERE target_sessions > 7;

UPDATE public.learning_goals
SET target_duration = LEAST(target_duration, 120)
WHERE target_duration > 120;

-- ── 2. Trigger: validasi dengan pesan error ramah pengguna ─────────────
CREATE OR REPLACE FUNCTION public.validate_goal_target_limits()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.target_sessions IS NULL
     OR NEW.target_sessions < 1
     OR NEW.target_sessions > 7 THEN
    RAISE EXCEPTION
      'target_sessions harus di antara 1 dan 7 (nilai diterima: %)',
      NEW.target_sessions
      USING ERRCODE = '23514'; -- check_violation, konsisten dgn CHECK constraint di bawah
  END IF;

  IF NEW.target_duration IS NULL
     OR NEW.target_duration < 5
     OR NEW.target_duration > 120 THEN
    RAISE EXCEPTION
      'target_duration harus di antara 5 dan 120 menit (nilai diterima: %)',
      NEW.target_duration
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS before_insert_update_goal_limits ON public.learning_goals;
CREATE TRIGGER before_insert_update_goal_limits
  BEFORE INSERT OR UPDATE ON public.learning_goals
  FOR EACH ROW EXECUTE FUNCTION public.validate_goal_target_limits();

-- ── 3. CHECK constraint: jaring pengaman terakhir di level tabel ───────
-- DROP ... IF EXISTS dulu sebelum ADD supaya migration ini aman dijalankan
-- ulang (idempotent) -- Postgres tidak punya "ADD CONSTRAINT IF NOT EXISTS".
ALTER TABLE public.learning_goals
  DROP CONSTRAINT IF EXISTS learning_goals_target_sessions_check;
ALTER TABLE public.learning_goals
  ADD CONSTRAINT learning_goals_target_sessions_check
    CHECK (target_sessions BETWEEN 1 AND 7);

ALTER TABLE public.learning_goals
  DROP CONSTRAINT IF EXISTS learning_goals_target_duration_check;
ALTER TABLE public.learning_goals
  ADD CONSTRAINT learning_goals_target_duration_check
    CHECK (target_duration BETWEEN 5 AND 120);
