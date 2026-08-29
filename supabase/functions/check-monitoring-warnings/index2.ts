// supabase/functions/check-monitoring-warnings/index.ts
//
// Fitur: Monitoring & Push Notification Warning.
// TIDAK menyentuh algoritma K-Means, x1-x5, persona, atau perhitungan SRL.
// Function ini hanya MEMBACA learning_goals, learning_activities, dan
// v_weekly_activity_aggregates (read-only), lalu menulis ke monitoring_alerts.
//
// Dipanggil berkala oleh pg_cron (lihat migration cron), bukan oleh client.
//
// Alur:
//   1. Ambil konfigurasi rule aktif dari monitoring_rules
//   2. Evaluasi tiap rule (W1_DAILY, W1_STREAK, W2, W3, W4, W5)
//   3. Untuk kandidat yang lolos threshold, cek cooldown ke monitoring_alerts
//   4. Insert alert baru (status pending) -> kirim FCM -> update status sent/failed

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// HARUS SAMA PERSIS dengan _kGoalAlertChannelId di lib/main.dart (Flutter).
// Channel ini didaftarkan di sisi client dengan custom sound
// (android/app/src/main/res/raw/goal_alert.mp3) SEBELUM notifikasi apa pun
// dikirim ke channel ini — kalau string di sini beda dengan yang di
// main.dart, Android akan diam-diam pakai channel default (suara pelan lagi)
// tanpa error apa pun yang terlihat di log Edge Function ini.
const GOAL_ALERT_ANDROID_CHANNEL_ID = "goal_alert_channel";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type RuleConfig = {
  rule_code: string;
  threshold: Record<string, number>;
  cooldown_hours: number;
};

type AlertCandidate = {
  user_id: string;
  goal_id: string | null;
  rule_code: string;
  title: string;
  body: string;
  deep_link: string;
  meta: Record<string, unknown>;
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1. Ambil konfigurasi rule aktif
    const { data: rulesData, error: rulesError } = await supabase
      .from("monitoring_rules")
      .select("rule_code, threshold, cooldown_hours")
      .eq("is_active", true);
    if (rulesError) throw rulesError;

    const rules: Record<string, RuleConfig> = {};
    for (const r of rulesData ?? []) {
      rules[r.rule_code] = {
        rule_code: r.rule_code,
        threshold: (r.threshold ?? {}) as Record<string, number>,
        cooldown_hours: r.cooldown_hours,
      };
    }

    const candidates: AlertCandidate[] = [];

    // 2a. Evaluasi rule global per user: W1_DAILY, W1_STREAK, W4
    candidates.push(...(await evaluateW1(supabase, rules)));
    candidates.push(...(await evaluateW4(supabase, rules)));

    // 2b. Evaluasi rule per goal aktif: W2, W3, W5
    candidates.push(...(await evaluateGoalRules(supabase, rules)));

    // 3-4. Cooldown check + insert + kirim push, satu per satu
    let sentCount = 0;
    let skippedCount = 0;
    let failedCount = 0;

    for (const c of candidates) {
      const cfg = rules[c.rule_code];
      if (!cfg) continue;

      const withinCooldown = await isWithinCooldown(supabase, c.user_id, c.rule_code, c.goal_id, cfg.cooldown_hours);
      if (withinCooldown) {
        skippedCount++;
        continue;
      }

      const { data: inserted, error: insertError } = await supabase
        .from("monitoring_alerts")
        .insert({
          user_id: c.user_id,
          goal_id: c.goal_id,
          rule_code: c.rule_code,
          title: c.title,
          body: c.body,
          deep_link: c.deep_link,
          status: "pending",
          meta: c.meta,
        })
        .select("id")
        .single();

      if (insertError) {
        console.error("Insert alert gagal:", insertError);
        failedCount++;
        continue;
      }

      const pushResult = await sendPushToUser(supabase, c.user_id, c.title, c.body, c.deep_link, c.rule_code);

      await supabase
        .from("monitoring_alerts")
        .update({
          status: pushResult.success ? "sent" : "failed",
          sent_at: pushResult.success ? new Date().toISOString() : null,
        })
        .eq("id", inserted!.id);

      if (pushResult.success) sentCount++;
      else failedCount++;
    }

    return new Response(
      JSON.stringify({
        success: true,
        evaluated: candidates.length,
        sent: sentCount,
        skipped_cooldown: skippedCount,
        failed: failedCount,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    console.error(error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// ============================================================================
// Cooldown check
// ============================================================================
async function isWithinCooldown(
  sb: any,
  userId: string,
  ruleCode: string,
  goalId: string | null,
  cooldownHours: number
): Promise<boolean> {
  const since = new Date(Date.now() - cooldownHours * 60 * 60 * 1000).toISOString();
  let query = sb
    .from("monitoring_alerts")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("rule_code", ruleCode)
    .gte("created_at", since);

  query = goalId ? query.eq("goal_id", goalId) : query.is("goal_id", null);

  const { count, error } = await query;
  if (error) {
    console.error("Cooldown check gagal:", error);
    return true; // aman: kalau gagal cek, anggap masih cooldown supaya tidak double-send
  }
  return (count ?? 0) > 0;
}

// ============================================================================
// W1_DAILY & W1_STREAK — evaluasi global per user
// Berdasarkan tanggal aktivitas terakhir (granularitas hari), untuk user yang
// punya minimal 1 goal aktif.
// ============================================================================
async function evaluateW1(sb: any, rules: Record<string, RuleConfig>): Promise<AlertCandidate[]> {
  const candidates: AlertCandidate[] = [];
  if (!rules["W1_DAILY"] && !rules["W1_STREAK"]) return candidates;

  const { data: activeGoalUsers, error: guError } = await sb
    .from("learning_goals")
    .select("user_id")
    .eq("status", "active");
  if (guError) throw guError;

  const userIds = [...new Set((activeGoalUsers ?? []).map((g: any) => g.user_id))];
  if (userIds.length === 0) return candidates;

  const { data: lastActivities, error: laError } = await sb
    .from("learning_activities")
    .select("user_id, activity_date")
    .in("user_id", userIds)
    .order("activity_date", { ascending: false });
  if (laError) throw laError;

  const lastActivityByUser = new Map<string, string>();
  for (const row of lastActivities ?? []) {
    if (!lastActivityByUser.has(row.user_id)) lastActivityByUser.set(row.user_id, row.activity_date);
  }

  const today = new Date();
  today.setUTCHours(0, 0, 0, 0);

  for (const userId of userIds) {
    const lastDateStr = lastActivityByUser.get(userId);
    const daysSinceLast = lastDateStr
      ? Math.floor((today.getTime() - new Date(lastDateStr + "T00:00:00Z").getTime()) / 86400000)
      : Infinity; // belum pernah mencatat aktivitas sama sekali

    if (rules["W1_STREAK"] && daysSinceLast >= (rules["W1_STREAK"].threshold.inactive_days ?? 3)) {
      candidates.push({
        user_id: userId,
        goal_id: null,
        rule_code: "W1_STREAK",
        title: "Sudah beberapa hari tanpa progres skripsi",
        body: `Kamu sudah ${daysSinceLast} hari belum mencatat progres skripsi. Semakin lama ditunda, semakin besar risiko keteteran mengejar deadline. Lanjutkan lagi sekarang, sesi singkat juga tetap dihitung.`,
        deep_link: "/monitoring",
        meta: { days_since_last: daysSinceLast },
      });
    } else if (rules["W1_DAILY"] && daysSinceLast >= 1) {
      candidates.push({
        user_id: userId,
        goal_id: null,
        rule_code: "W1_DAILY",
        title: "Progres hari ini belum tercatat",
        body: "Setiap hari yang terlewat bisa menggeser jadwal penyelesaian skripsimu. Catat progres hari ini, sekecil apapun, biar tetap sesuai rencana deadline.",
        deep_link: "/activity/new",
        meta: { days_since_last: daysSinceLast },
      });
    }
  }

  return candidates;
}

// ============================================================================
// W4 — frekuensi belajar menurun, berbasis v_weekly_activity_aggregates
// (week_number anchor assessed_at, BUKAN kalender — konsisten dgn x1-x5)
// ============================================================================
async function evaluateW4(sb: any, rules: Record<string, RuleConfig>): Promise<AlertCandidate[]> {
  const candidates: AlertCandidate[] = [];
  const cfg = rules["W4"];
  if (!cfg) return candidates;

  const dropPercent = cfg.threshold.drop_percent ?? 30;
  const minPrevSessions = cfg.threshold.min_sessions_previous_week ?? 2;

  const { data, error } = await sb
    .from("v_weekly_activity_aggregates")
    .select("user_id, week_number, x1_frequency")
    .order("week_number", { ascending: false });
  if (error) throw error;

  const byUser = new Map<string, { week_number: number; x1_frequency: number }[]>();
  for (const row of data ?? []) {
    const arr = byUser.get(row.user_id) ?? [];
    arr.push({ week_number: row.week_number, x1_frequency: row.x1_frequency });
    byUser.set(row.user_id, arr);
  }

  for (const [userId, weeks] of byUser.entries()) {
    if (weeks.length < 2) continue; // butuh minimal 2 minggu data untuk dibandingkan
    const [current, previous] = weeks; // sudah diurutkan DESC oleh query

    if (previous.x1_frequency < minPrevSessions) continue; // data minggu lalu terlalu sedikit, hindari false positive

    const dropActual = ((previous.x1_frequency - current.x1_frequency) / previous.x1_frequency) * 100;
    if (dropActual >= dropPercent) {
      candidates.push({
        user_id: userId,
        goal_id: null,
        rule_code: "W4",
        title: "Ritme pengerjaan skripsi melambat",
        body: "Progresmu minggu ini lebih lambat dibanding minggu lalu. Kalau dibiarkan, ini bisa membuatmu ketinggalan target penyelesaian. Coba sesi fokus 20 menit untuk mengembalikan ritmenya.",
        deep_link: "/monitoring/trend",
        meta: {
          current_week_sessions: current.x1_frequency,
          previous_week_sessions: previous.x1_frequency,
          drop_percent: Math.round(dropActual),
        },
      });
    }
  }

  return candidates;
}

// ============================================================================
// W2, W3, W5 — evaluasi per goal aktif
// ============================================================================
async function evaluateGoalRules(sb: any, rules: Record<string, RuleConfig>): Promise<AlertCandidate[]> {
  const candidates: AlertCandidate[] = [];
  if (!rules["W2"] && !rules["W3"] && !rules["W5"]) return candidates;

  const { data: goals, error } = await sb
    .from("learning_goals")
    .select("id, user_id, title, period_start, period_end, target_sessions, actual_sessions, actual_progress, status")
    .eq("status", "active");
  if (error) throw error;

  const today = new Date();
  today.setUTCHours(0, 0, 0, 0);

  for (const goal of goals ?? []) {
    const periodStart = new Date(goal.period_start + "T00:00:00Z");
    const periodEnd = new Date(goal.period_end + "T00:00:00Z");
    const totalDays = Math.max(1, Math.round((periodEnd.getTime() - periodStart.getTime()) / 86400000));
    const elapsedDays = Math.round((today.getTime() - periodStart.getTime()) / 86400000);
    const daysLeft = Math.round((periodEnd.getTime() - today.getTime()) / 86400000);
    const paceRatio = Math.min(1, Math.max(0, elapsedDays / totalDays));

    // ---- W3: lewat deadline, belum selesai ----
    if (rules["W3"] && daysLeft < 0) {
      candidates.push({
        user_id: goal.user_id,
        goal_id: goal.id,
        rule_code: "W3",
        title: "Deadline target sudah terlewat",
        body: `Target "${goal.title}" sudah melewati deadline yang direncanakan. Segera tinjau ulang jadwalmu dan tetapkan deadline baru yang realistis, supaya skripsi tetap bisa selesai tepat waktu secara keseluruhan.`,
        deep_link: `/goals`,
        meta: { days_overdue: Math.abs(daysLeft), actual_progress: goal.actual_progress },
      });
    }

    // ---- W2: deadline dekat, progres di bawah pace linear ----
    if (rules["W2"] && daysLeft >= 0 && daysLeft <= (rules["W2"].threshold.days_left_threshold ?? 3)) {
      const expectedProgress = paceRatio * 100;
      const tolerance = rules["W2"].threshold.pace_tolerance_percent ?? 10;
      const actualProgress = goal.actual_progress ?? 0;
      if (actualProgress < expectedProgress - tolerance) {
        candidates.push({
          user_id: goal.user_id,
          goal_id: goal.id,
          rule_code: "W2",
          title: "Deadline mendekat, progres masih tertinggal",
          body: `Target "${goal.title}" tinggal ${daysLeft} hari, tetapi progresmu masih ${Math.round(actualProgress)}%. Prioritaskan target ini sekarang supaya penyelesaiannya tetap sesuai jadwal.`,
          deep_link: `/goals`,
          meta: { days_left: daysLeft, actual_progress: actualProgress, expected_progress: Math.round(expectedProgress) },
        });
      }
    }

    // ---- W5: sering melewatkan pace target (sudah >=2 minggu berjalan & tetap ketinggalan) ----
    if (rules["W5"] && goal.target_sessions > 0) {
      const consecutiveWeeks = rules["W5"].threshold.consecutive_weeks ?? 2;
      const minElapsedDays = consecutiveWeeks * 7;
      if (elapsedDays >= minElapsedDays && daysLeft >= 0) {
        const expectedSessions = paceRatio * goal.target_sessions;
        const tolerance = rules["W5"].threshold.pace_tolerance_percent ?? 10;
        const actualSessions = goal.actual_sessions ?? 0;
        if (actualSessions < expectedSessions - (tolerance / 100) * goal.target_sessions) {
          candidates.push({
            user_id: goal.user_id,
            goal_id: goal.id,
            rule_code: "W5",
            title: "Progres konsisten tertinggal dari rencana",
            body: `Sesi pengerjaan untuk target "${goal.title}" berulang kali di bawah rencana mingguan. Kalau pola ini berlanjut, deadline berisiko tidak tercapai — sesuaikan lagi rencana sesi mingguanmu sekarang.`,
            deep_link: `/goals`,
            meta: { actual_sessions: actualSessions, expected_sessions: Math.round(expectedSessions), target_sessions: goal.target_sessions },
          });
        }
      }
    }
  }

  return candidates;
}

// ============================================================================
// FCM push sender (HTTP v1 API) — pakai service account dari Supabase secrets
// ============================================================================
async function sendPushToUser(
  sb: any,
  userId: string,
  title: string,
  body: string,
  deepLink: string,
  ruleCode: string
): Promise<{ success: boolean }> {
  const { data: tokens, error } = await sb
    .from("push_tokens")
    .select("fcm_token")
    .eq("user_id", userId)
    .eq("is_active", true);

  if (error || !tokens || tokens.length === 0) {
    return { success: false };
  }

  const accessToken = await getFcmAccessToken();
  const projectId = Deno.env.get("FCM_PROJECT_ID")!;

  let anySuccess = false;
  for (const t of tokens) {
    try {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: t.fcm_token,
              notification: { title, body },
              data: { deep_link: deepLink, rule_code: ruleCode },
              android: {
                priority: "HIGH",
                notification: {
                  // Mengarahkan notifikasi ini ke channel custom-sound yang
                  // didaftarkan di main.dart. Tanpa field ini, Android akan
                  // fallback ke channel default plugin firebase_messaging
                  // (suara sistem standar, itulah sebabnya sebelumnya kecil).
                  channel_id: GOAL_ALERT_ANDROID_CHANNEL_ID,
                  // Eksplisit di payload juga (bukan cuma andalkan channel
                  // sisi client). Nama TANPA ekstensi, harus sama dengan
                  // android/app/src/main/res/raw/goal_alert.mp3.
                  // Catatan: field ini tidak bisa "mengoverride" channel yang
                  // sudah pernah dibuat di suatu device dengan sound berbeda —
                  // lihat catatan di main.dart soal channel yang terkunci OS.
                  sound: "goal_alert",
                },
              },
            },
          }),
        }
      );
      if (res.ok) {
        anySuccess = true;
      } else {
        const errBody = await res.text();
        console.error(`FCM gagal untuk token ${t.fcm_token.slice(0, 12)}...:`, errBody);
        // Token tidak valid/kadaluarsa (uninstall dsb) -> nonaktifkan
        if (res.status === 404 || res.status === 400) {
          await sb.from("push_tokens").update({ is_active: false }).eq("fcm_token", t.fcm_token);
        }
      }
    } catch (e) {
      console.error("FCM fetch error:", e);
    }
  }

  return { success: anySuccess };
}

// ----------------------------------------------------------------------------
// OAuth2 access token dari service account (JWT bearer flow), untuk FCM HTTP v1
// ----------------------------------------------------------------------------
let cachedToken: { token: string; expiresAt: number } | null = null;

async function getFcmAccessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) {
    return cachedToken.token;
  }

  const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL")!;
  const privateKeyPem = Deno.env.get("FCM_PRIVATE_KEY")!;

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const encoder = new TextEncoder();
  const base64url = (bytes: Uint8Array) =>
    btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

  const headerB64 = base64url(encoder.encode(JSON.stringify(header)));
  const claimsB64 = base64url(encoder.encode(JSON.stringify(claims)));
  const unsigned = `${headerB64}.${claimsB64}`;

  const key = await importPrivateKey(privateKeyPem);
  const signature = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    key,
    encoder.encode(unsigned)
  );
  const signatureB64 = base64url(new Uint8Array(signature));
  const jwt = `${unsigned}.${signatureB64}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!tokenRes.ok) {
    const errText = await tokenRes.text();
    throw new Error(`Gagal ambil access token FCM: ${errText}`);
  }

  const tokenJson = await tokenRes.json();
  cachedToken = { token: tokenJson.access_token, expiresAt: Date.now() + tokenJson.expires_in * 1000 };
  return cachedToken.token;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const pemBody = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\\n/g, "")
    .replace(/\n/g, "")
    .trim();
  const binary = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    binary,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
}