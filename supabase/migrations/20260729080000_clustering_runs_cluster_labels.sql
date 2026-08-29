-- Menambahkan kolom cluster_labels ke clustering_runs: pemetaan label
-- persona per index centroid (sejajar dengan array centroids), supaya
-- klien (Flutter) bisa menampilkan SEMUA centroid dengan label yang benar
-- tanpa perlu menghitung ulang labelAllClusters() di sisi klien.
--
-- KENAPA INI PERLU: sebelum kolom ini ada, satu-satunya cara mengaitkan
-- cluster_number dengan nama persona adalah lewat persona_history, tapi
-- RLS "user_own_persona_select" (lihat v2_schema.sql) membatasi user hanya
-- bisa membaca baris miliknya sendiri -- jadi user TIDAK BISA merekonstruksi
-- pemetaan untuk cluster lain (mis. Consistent, Seasonal) dari data user
-- lain. Menghitung ulang labelAllClusters() di Dart berisiko hasil berbeda
-- dari backend kalau ada kesalahan replikasi logic (personaScore, urutan
-- greedy assignment, dst) -- risiko yang tidak sepadan untuk fitur yang
-- tujuannya justru membantu transparansi ke pengguna.
--
-- clustering_runs sendiri sudah "all_read_clustering_runs FOR SELECT USING
-- (TRUE)" (semua orang boleh baca), jadi menambah kolom ini tidak mengubah
-- eksposur data apa pun -- centroids (angka agregat, bukan data personal
-- user manapun) sudah bisa dibaca semua orang sejak awal.

ALTER TABLE public.clustering_runs
  ADD COLUMN IF NOT EXISTS cluster_labels JSONB;

COMMENT ON COLUMN public.clustering_runs.cluster_labels IS
  'Array label persona sejajar index dengan kolom centroids, mis. '
  '["consistent","passive","seasonal","ambitious"] berarti centroids[0] '
  'adalah centroid persona consistent, dst. Diisi run-kmeans/index.ts '
  'lewat labelAllClusters(), SATU SUMBER KEBENARAN yang sama dipakai untuk '
  'menentukan persona_label_id user -- bukan dihitung ulang di klien.';
