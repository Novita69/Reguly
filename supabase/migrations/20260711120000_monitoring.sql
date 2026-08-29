-- ============================================================================
-- v4_monitoring.sql
-- Fitur: Monitoring & Push Notification Warning
--
-- TIDAK mengubah: algoritma K-Means, variabel x1-x5, pembentukan learner
-- persona, atau perhitungan SRL. Tabel di file ini murni untuk memantau
-- aktivitas belajar SETELAH target dibuat, dan tidak menjadi variabel baru
-- dalam clustering/persona.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. push_tokens
--    Menyimpan FCM token per device. Satu user bisa punya banyak device aktif.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS push_tokens (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  fcm_token        TEXT NOT NULL UNIQUE,
  device_platform  TEXT NOT NULL DEFAULT 'android' CHECK (device_platform IN ('android', 'ios')),
  is_active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 2. monitoring_rules
--    Konfigurasi threshold & cooldown per rule (W1_DAILY, W1_STREAK, W2..W5).
--    Disimpan sebagai data, bukan hardcode, supaya bisa disesuaikan saat
--    Tahap 3 (Evaluasi dan perbaikan prototype) tanpa deploy ulang kode.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS monitoring_rules (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_code      TEXT NOT NULL UNIQUE,
  name           TEXT NOT NULL,
  description    TEXT,
  threshold      JSONB NOT NULL DEFAULT '{}'::JSONB,
  cooldown_hours INTEGER NOT NULL DEFAULT 24,
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 3. monitoring_alerts
--    Riwayat setiap notifikasi yang diputuskan/dikirim sistem. Juga menjadi
--    sumber kebenaran untuk anti-duplikasi (cooldown check).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS monitoring_alerts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  goal_id     UUID REFERENCES learning_goals(id) ON DELETE CASCADE,  -- NULL untuk warning global (W1, W4)
  rule_code   TEXT NOT NULL REFERENCES monitoring_rules(rule_code),
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  deep_link   TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed')),
  meta        JSONB NOT NULL DEFAULT '{}'::JSONB,  -- snapshot data pemicu, misal progress_percent/days_left, untuk audit
  sent_at     TIMESTAMPTZ,
  clicked_at  TIMESTAMPTZ,
  read_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- Index
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_push_tokens_user       ON push_tokens(user_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_alerts_user_created    ON monitoring_alerts(user_id, created_at DESC);
-- Index utama untuk cooldown check: "apakah rule ini sudah dikirim untuk kombinasi user+goal ini baru-baru ini?"
CREATE INDEX IF NOT EXISTS idx_alerts_cooldown_lookup  ON monitoring_alerts(user_id, rule_code, goal_id, created_at DESC);

-- ----------------------------------------------------------------------------
-- Seed data: 6 rule (W1 dua tier + W2..W5)
-- ----------------------------------------------------------------------------
INSERT INTO monitoring_rules (rule_code, name, description, threshold, cooldown_hours) VALUES
  ('W1_DAILY',  'Pengingat harian',
   'Tidak ada aktivitas belajar dalam 24 jam terakhir. Nada netral, bukan warning.',
   '{"inactive_hours": 24}', 24),

  ('W1_STREAK', 'Tidak aktif 3 hari berturut-turut',
   'Tidak ada aktivitas belajar sama sekali selama 3 hari berturut-turut. Warning bermakna untuk riset.',
   '{"inactive_days": 3}', 24),

  ('W2', 'Deadline dekat, progres di bawah pace',
   'Sisa hari ke deadline goal <= days_left_threshold, dan actual_progress di bawah pace linear target dikurangi tolerance.',
   '{"days_left_threshold": 3, "pace_tolerance_percent": 10}', 24),

  ('W3', 'Lewat deadline, belum selesai',
   'period_end goal sudah lewat dan status masih active (belum completed).',
   '{}', 72),

  ('W4', 'Frekuensi belajar menurun',
   'Jumlah sesi minggu ini turun >= drop_percent dibanding minggu lalu (dari v_weekly_activity_aggregates), dengan syarat data minggu lalu cukup.',
   '{"drop_percent": 30, "min_sessions_previous_week": 2}', 168),

  ('W5', 'Sering melewatkan pace target',
   'actual_sessions goal di bawah pace linear target_sessions selama >= 2 minggu berturut-turut.',
   '{"consecutive_weeks": 2, "pace_tolerance_percent": 10}', 168)
ON CONFLICT (rule_code) DO NOTHING;

-- ----------------------------------------------------------------------------
-- Row Level Security
-- ----------------------------------------------------------------------------
ALTER TABLE push_tokens       ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitoring_rules  ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitoring_alerts ENABLE ROW LEVEL SECURITY;

-- push_tokens: user hanya boleh kelola device miliknya sendiri
DROP POLICY IF EXISTS "user_own_push_tokens_all" ON push_tokens;
CREATE POLICY "user_own_push_tokens_all" ON push_tokens FOR ALL USING (user_id = auth.uid());

-- monitoring_rules: konfigurasi dibaca semua user yang login, ditulis hanya lewat service role (Edge Function)
DROP POLICY IF EXISTS "all_read_monitoring_rules" ON monitoring_rules;
CREATE POLICY "all_read_monitoring_rules" ON monitoring_rules FOR SELECT USING (TRUE);

-- monitoring_alerts: user hanya boleh lihat & update (mis. tandai read/klik) miliknya sendiri.
-- INSERT baris baru hanya dilakukan Edge Function lewat service role (bypass RLS), bukan dari client.
DROP POLICY IF EXISTS "user_own_alerts_select" ON monitoring_alerts;
CREATE POLICY "user_own_alerts_select" ON monitoring_alerts FOR SELECT USING (user_id = auth.uid());
DROP POLICY IF EXISTS "user_own_alerts_update" ON monitoring_alerts;
CREATE POLICY "user_own_alerts_update" ON monitoring_alerts FOR UPDATE USING (user_id = auth.uid());
