-- v9_warning_tier_column_and_label_unification.sql
--
-- Latar belakang (temuan audit skema, di luar topik revisi skripsi utama):
-- Edge Function run-kmeans (generate_recommendations.ts / index.ts) sudah
-- MEMBACA dan MEM-FILTER kolom recommendation_rules.warning_tier sejak
-- migrasi v3 (20260710100000_v3_thesis_alignment.sql), namun kolom
-- tersebut TIDAK PERNAH dibuat lewat migration manapun -- kemungkinan
-- ditambahkan langsung lewat SQL Editor Supabase di luar alur migration
-- terstruktur. Migrasi ini menutup celah dokumentasi tersebut supaya
-- skema basis data yang dilaporkan pada BAB III Sub-bab 3.3.4 benar-benar
-- dapat ditelusuri ulang (auditable) dari file migration, konsisten
-- dengan tujuan yang sama seperti BUG FIX pada v3_thesis_alignment.sql.
--
-- Revisi kedua pada file ini (per arahan dosen pembimbing): label
-- warning_tier DISERAGAMKAN menjadi hanya dua nilai -- 'mandiri' dan
-- 'responsif' -- untuk KEEMPAT persona. Sebelum revisi ini, kosakata
-- tier dibedakan per persona ('consistent' -> mandiri/responsif,
-- persona lain -> jarang_warning/sering_warning) walau mekanisme
-- hitungnya (ambang 3 peringatan/28 hari) selalu sama. Perbedaan
-- kosakata tersebut dihapus supaya definisi tag konsisten untuk semua
-- mahasiswa terlepas dari persona hasil clustering-nya:
--   - Mandiri   : jumlah peringatan (monitoring_alerts) dalam 28 hari
--                 terakhir < 3 -- pengguna relatif tidak bergantung pada
--                 notifikasi sistem untuk menjalankan aktivitas belajarnya.
--   - Responsif : jumlah peringatan tersebut >= 3 -- pengguna banyak
--                 terbantu/didahului notifikasi berulang sebelum
--                 beraktivitas, menandakan ketergantungan yang lebih
--                 besar pada dorongan eksternal sistem.
--
-- Jalankan file ini SETELAH 20260729080000_clustering_runs_cluster_labels.sql.

-- ── 1. Tambahkan kolom warning_tier yang selama ini hilang dari migration ──
ALTER TABLE public.recommendation_rules
  ADD COLUMN IF NOT EXISTS warning_tier TEXT;

-- ── 2. Migrasi data lama: seragamkan kosakata tier pada baris existing ────
-- PENTING: langkah ini harus dijalankan SEBELUM CHECK constraint di langkah 3
-- dipasang -- kalau constraint dipasang lebih dulu, baris lama yang masih
-- berisi kosakata lama ('jarang_warning'/'sering_warning') akan membuat
-- constraint gagal terpasang (ALTER TABLE ... ADD CONSTRAINT memvalidasi
-- SELURUH baris existing terhadap kondisinya).
--
-- Baris recommendation_rules yang sempat ditulis dengan kosakata lama
-- ('jarang_warning'/'sering_warning', untuk persona selain 'consistent')
-- dipetakan ke kosakata baru agar konsisten dengan kode aplikasi yang
-- sudah direvisi (Edge Function & Flutter).
UPDATE public.recommendation_rules
  SET warning_tier = 'mandiri'
  WHERE warning_tier = 'jarang_warning';

UPDATE public.recommendation_rules
  SET warning_tier = 'responsif'
  WHERE warning_tier = 'sering_warning';

-- Jaring pengaman tambahan: nilai APA PUN selain 'mandiri'/'responsif'/NULL
-- (mis. typo lama, kosakata lain yang sempat dicoba secara manual di SQL
-- Editor sebelum migrasi ini ada) di-null-kan alih-alih dibiarkan
-- menggagalkan constraint di langkah 3. NULL berlaku untuk semua tier
-- (lihat filter Edge Function di komentar langkah 3), jadi ini aman
-- sebagai fallback -- baris tersebut sebaiknya ditinjau manual setelah
-- migrasi ini selesai untuk dipastikan tier yang benar.
UPDATE public.recommendation_rules
  SET warning_tier = NULL
  WHERE warning_tier IS NOT NULL
    AND warning_tier NOT IN ('mandiri', 'responsif');

-- Riwayat hasil rekomendasi (persona_history / recommendations) TIDAK
-- menyimpan warning_tier sebagai kolom tersendiri (dihitung on-the-fly
-- dari monitoring_alerts, lihat computeWarningTier()), sehingga tidak
-- ada data historis lain yang perlu di-backfill oleh migrasi ini.

-- ── 3. CHECK constraint dibatasi ke dua nilai baku SETELAH backfill ────────
-- NULL tetap diperbolehkan: baris rule lama yang belum dibedakan per tier
-- (warning_tier IS NULL) berlaku untuk semua tier, sesuai filter
-- `.or('warning_tier.is.null,warning_tier.eq.<tier>')` di Edge Function.
ALTER TABLE public.recommendation_rules
  DROP CONSTRAINT IF EXISTS recommendation_rules_warning_tier_check;
ALTER TABLE public.recommendation_rules
  ADD CONSTRAINT recommendation_rules_warning_tier_check
    CHECK (warning_tier IS NULL OR warning_tier IN ('mandiri', 'responsif'));

-- ── 4. Indeks pendukung filter warning_tier per persona ────────────────────
-- Edge Function melakukan .eq('persona_label_id', ...).eq('is_active', true)
-- .or('warning_tier.is.null,warning_tier.eq.<tier>') pada SETIAP baris
-- persona_history.is_current=true yang diproses batch -- indeks berikut
-- mempercepat pola akses tersebut tanpa mengubah semantik query.
CREATE INDEX IF NOT EXISTS idx_recommendation_rules_persona_tier
  ON public.recommendation_rules(persona_label_id, warning_tier)
  WHERE is_active;
