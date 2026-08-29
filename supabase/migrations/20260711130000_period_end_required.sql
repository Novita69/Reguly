-- v5_period_end_required.sql
--
-- Menjadikan learning_goals.period_end WAJIB (NOT NULL), sesuai keputusan
-- desain: Target Belajar tanpa deadline tidak bisa dipantau oleh warning
-- W2/W3/W5, dan bertentangan dengan tujuan utama aplikasi ini (membantu
-- mahasiswa mengelola WAKTU pengerjaan skripsinya).
--
-- Backfill dulu data lama (testing, belum ada responden nyata) yang
-- period_end-nya masih NULL, supaya ALTER COLUMN ... SET NOT NULL tidak
-- gagal. Nilai backfill: period_start + 7 hari (sekadar default aman,
-- bukan klaim deadline yang "benar" untuk data lama itu).
UPDATE public.learning_goals
SET period_end = period_start + INTERVAL '7 days'
WHERE period_end IS NULL;

ALTER TABLE public.learning_goals
  ALTER COLUMN period_end SET NOT NULL;
