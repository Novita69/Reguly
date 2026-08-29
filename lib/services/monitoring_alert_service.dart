// lib/services/monitoring_alert_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/monitoring_alert.dart';

class MonitoringAlertService {
  final _sb = Supabase.instance.client;
  String get _uid => _sb.auth.currentUser!.id;

  // ── Riwayat notifikasi milik user, terbaru dulu ────────────
  //
  // Rule seperti W1_DAILY/W1_STREAK sengaja dikirim ulang setiap hari
  // (lihat check-monitoring-warnings/index.ts) selama kondisinya masih
  // terpenuhi -- itu bagian dari desain reminder harian, BUKAN bug.
  // Tapi kalau ditampilkan apa adanya, riwayat jadi menumpuk banyak kartu
  // dengan judul/isi yang nyaris sama persis dari hari-hari sebelumnya.
  //
  // Supaya layar Riwayat Notifikasi terasa "ter-refresh" per hari (bukan
  // terus terakumulasi), kita ambil lebih banyak baris dari DB lalu di
  // sisi klien hanya menyisakan SATU alert TERBARU untuk tiap kombinasi
  // rule_code+goal_id. Histori lengkapnya tetap utuh di database (berguna
  // untuk analitik/riset), yang disaring cuma tampilannya di app.
  Future<List<MonitoringAlert>> getAlerts({int limit = 50}) async {
    // Ambil lebih banyak baris mentah daripada limit final, karena setelah
    // di-dedup jumlahnya pasti berkurang -- tanpa ini, riwayat bisa terlihat
    // lebih pendek dari yang seharusnya kalau limit mentah == limit final.
    final res = await _sb
        .from('monitoring_alerts')
        .select()
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .limit(limit * 4);

    final all = (res as List).map((e) => MonitoringAlert.fromMap(e)).toList();

    final seen = <String>{};
    final deduped = <MonitoringAlert>[];
    for (final alert in all) {
      final key = '${alert.ruleCode}:${alert.goalId ?? ''}';
      if (seen.add(key)) deduped.add(alert);
      if (deduped.length >= limit) break;
    }
    return deduped;
  }

  Future<int> getUnreadCount() async {
    final res = await _sb
        .from('monitoring_alerts')
        .select('id')
        .eq('user_id', _uid)
        .filter('read_at', 'is', null)
        .count(CountOption.exact);
    return res.count;
  }

  Future<void> markAsRead(String alertId) async {
    await _sb
        .from('monitoring_alerts')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('id', alertId)
        .eq('user_id', _uid);
  }

  Future<void> markAsClicked(String alertId) async {
    await _sb
        .from('monitoring_alerts')
        .update({
          'clicked_at': DateTime.now().toIso8601String(),
          'read_at': DateTime.now().toIso8601String(),
        })
        .eq('id', alertId)
        .eq('user_id', _uid);
  }

  Future<void> markAllAsRead() async {
    await _sb
        .from('monitoring_alerts')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('user_id', _uid)
        .filter('read_at', 'is', null);
  }
}
