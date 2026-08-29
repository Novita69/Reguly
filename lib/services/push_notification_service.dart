// lib/services/push_notification_service.dart
//
// Tanggung jawab:
//   1. Minta izin notifikasi (Android 13+ wajib runtime permission)
//   2. Ambil FCM token device, simpan/upsert ke tabel push_tokens
//   3. Refresh token otomatis kalau FCM merotasi token
//   4. Sediakan callback saat notifikasi di-tap (foreground/background/terminated)
//      supaya main.dart bisa arahkan ke deep_link yang sesuai

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationService {
  bool _initialized = false;
  String? _lastHandledMessageId;
  final _sb = Supabase.instance.client;
  final _fcm = FirebaseMessaging.instance;

  /// Dipanggil sekali saat app start (setelah user login), dari main.dart.
  /// [onDeepLink] dipanggil setiap kali notifikasi di-tap, dengan path deep_link-nya.
  Future<void> initialize({required void Function(String deepLink) onDeepLink}) async {
    // Mencegah listener FCM terpasang lebih dari sekali jika widget aplikasi
    // sempat dibangun ulang. Listener ganda dapat memicu dua navigasi untuk
    // satu tap notifikasi.
    if (_initialized) return;
    _initialized = true;

    await _requestPermission();
    unawaited(_registerToken()); // dijalankan di background, TIDAK di-await —
    // supaya kalau upsert ke DB gagal (misal RLS, koneksi), listener-listener
    // di bawah tetap terpasang dan tidak ikut gagal terhenti.

    // Token bisa berubah (reinstall, clear data, dsb) — pastikan selalu tersinkron.
    _fcm.onTokenRefresh.listen((_) => _registerToken());

    // Kalau initialize() ini berjalan sebelum user login (misal masih di
    // halaman Login/Register saat app start), _registerToken() di atas
    // belum bisa menyimpan apa-apa. Daftarkan ulang begitu ada sesi baru.
    // Catatan: menonaktifkan token saat logout SENGAJA tidak ditangani lewat
    // listener AuthChangeEvent.signedOut di sini — pada saat event itu
    // diterima, sesi sudah terhapus, sehingga update ke push_tokens akan
    // diblokir RLS (auth.uid() sudah null) dan gagal diam-diam. Karena itu
    // deactivateCurrentToken() dipanggil manual SEBELUM signOut() di setiap
    // lokasi logout (lihat profile_screen.dart, dsb), bukan di sini.
    _sb.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn) _registerToken();
    });

    // App di foreground, notifikasi masuk tapi user belum tap — cukup diabaikan di sini,
    // riwayatnya sudah tercatat di tabel monitoring_alerts oleh Edge Function.
    FirebaseMessaging.onMessage.listen((_) {});

    // App di background lalu user tap notifikasi.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationTap(message, onDeepLink);
    });

    // App benar-benar tertutup (terminated) lalu dibuka via tap notifikasi.
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage, onDeepLink);
    }
  }

  void _handleNotificationTap(
    RemoteMessage message,
    void Function(String deepLink) onDeepLink,
  ) {
    // Proteksi tambahan agar message yang sama tidak menavigasi dua kali.
    final messageId = message.messageId;
    if (messageId != null && messageId == _lastHandledMessageId) return;
    _lastHandledMessageId = messageId;

    final rawLink = message.data['deep_link'];
    if (rawLink is! String || rawLink.trim().isEmpty) return;
    onDeepLink(rawLink.trim());
  }

  Future<void> _requestPermission() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);
  }

  Future<void> _registerToken() async {
    final user = _sb.auth.currentUser;
    if (user == null) return; // belum login, simpan nanti setelah login

    final token = await _fcm.getToken();
    if (token == null) return;
    debugPrint('=== FCM TOKEN (buat testing Firebase Console) ===');
    debugPrint(token);
    debugPrint('==================================================');

    await _sb.from('push_tokens').upsert({
      'user_id': user.id,
      'fcm_token': token,
      'device_platform': Platform.isIOS ? 'ios' : 'android',
      'is_active': true,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'fcm_token').catchError((e) {
      // Paling sering terjadi saat testing: token ini sebelumnya sudah
      // terdaftar milik user lain (mis. login-logout dengan akun berbeda
      // di device yang sama), sehingga RLS menolak "pengambilalihan" baris
      // tersebut oleh user yang sedang login sekarang. Tidak fatal untuk
      // fitur lain di app, jadi cukup dicatat di log saja.
      debugPrint('[PushNotificationService] Gagal registrasi token: $e');
    });
  }

  /// Panggil saat logout, supaya device ini tidak lagi menerima push
  /// untuk akun yang sudah keluar.
  Future<void> deactivateCurrentToken() async {
    final token = await _fcm.getToken();
    if (token == null) return;
    await _sb.from('push_tokens').update({'is_active': false}).eq('fcm_token', token);
  }
}