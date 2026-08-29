-- v7_activity_duration_and_single_active_goal.sql
--
-- Dua perbaikan bisnis, ditegakkan di sisi SERVER (Postgres) sebagai
-- lapisan pertahanan kedua di luar validasi Flutter (defense-in-depth,
-- pola yang sama dengan 20260724090000_goal_target_limits.sql):
--
--   1. learning_activities.duration_minutes dibatasi maks. 120 menit per
--      sesi (sebelumnya cuma CHECK (duration_minutes > 0) di
--      v2_schema.sql, tidak ada batas atas).
--   2. Satu user hanya boleh punya SATU Learning Goal berstatus 'active'
--      DAN belum selesai (actual_progress < 100) pada satu waktu. Goal
--      baru hanya boleh dibuat setelah goal aktif sebelumnya ditandai
--      'completed' atau progress-nya mencapai 100%. Ini mencegah data
--      progres antar-goal tumpang tindih/bias saat dianalisis
--      (clustering, agregat mingguan, dsb).

-- ── 1. Durasi aktivitas: maks. 120 menit per sesi ──────────────────────

-- Backfill data lama yang sudah melebihi batas baru, supaya ALTER TABLE
-- ADD CONSTRAINT di bawah tidak gagal (pola sama seperti migration
-- goal_target_limits.sql).
UPDATE public.learning_activities
SET duration_minutes = 120
WHERE duration_minutes > 120;

ALTER TABLE public.learning_activities
  DROP CONSTRAINT IF EXISTS learning_activities_duration_minutes_check;
ALTER TABLE public.learning_activities
  ADD CONSTRAINT learning_activities_duration_minutes_check
    CHECK (duration_minutes BETWEEN 1 AND 120);

-- ── 2. Satu Goal aktif & belum selesai per user ────────────────────────

CREATE OR REPLACE FUNCTION public.validate_single_active_goal()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  existing_id UUID;
BEGIN
  -- Hanya relevan untuk goal yang (akan) berstatus active & belum selesai.
  -- Goal yang langsung dibuat/diubah sebagai 'completed' atau progress
  -- 100% tidak perlu dicek (tidak menambah jumlah goal aktif berjalan).
  --
  -- Catatan penting soal interaksi dengan trigger update_goal_progress()
  -- (v2_schema.sql, AFTER INSERT ON learning_activities): setiap kali
  -- aktivitas baru disimpan, trigger itu meng-UPDATE learning_goals
  -- (actual_sessions/actual_progress), yang otomatis memicu trigger ini
  -- juga (BEFORE UPDATE). Ini aman karena:
  --   a. Saat sesi TERAKHIR tercatat (progress jadi 100), kondisi
  --      "actual_progress < 100" di bawah menjadi FALSE -> tidak
  --      diperiksa -> update tidak diblokir.
  --   b. Saat sesi biasa (progress masih < 100), pengecualian
  --      "id <> NEW.id" membuat goal ini tidak membandingkan dengan
  --      dirinya sendiri -> tidak ada goal lain yang cocok -> update
  --      tidak diblokir.
  -- Jadi trigger ini HANYA memblokir pembuatan/pengaktifan goal BARU
  -- selama goal lain (id berbeda) masih aktif & belum selesai.
  IF NEW.status = 'active' AND COALESCE(NEW.actual_progress, 0) < 100 THEN
    SELECT id INTO existing_id
    FROM public.learning_goals
    WHERE user_id = NEW.user_id
      AND status = 'active'
      AND COALESCE(actual_progress, 0) < 100
      AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::UUID)
    LIMIT 1;

    IF existing_id IS NOT NULL THEN
      RAISE EXCEPTION
        'Masih ada target belajar aktif yang belum selesai. Selesaikan '
        'target tersebut terlebih dahulu sebelum membuat target baru.'
        USING ERRCODE = '23514'; -- check_violation, konsisten dgn pola goal_target_limits.sql
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS before_insert_update_single_active_goal ON public.learning_goals;
CREATE TRIGGER before_insert_update_single_active_goal
  BEFORE INSERT OR UPDATE ON public.learning_goals
  FOR EACH ROW EXECUTE FUNCTION public.validate_single_active_goal();
