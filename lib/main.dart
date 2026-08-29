// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/supabase_constants.dart';
import 'core/router/app_router.dart';
import 'services/push_notification_service.dart';
import 'shared/themes/app_theme.dart';

// ID & nama channel notifikasi goal terbengkalai (>24 jam tidak diisi).
// String ini HARUS SAMA PERSIS dengan yang dikirim Edge Function
// (check-monitoring-warnings/index.ts) lewat field android.notification.channel_id,
// dan file suaranya harus ada di android/app/src/main/res/raw/goal_alert.mp3
// (nama file TANPA ekstensi ".mp3" saat dirujuk di kode Kotlin/Dart Android).
const String _kGoalAlertChannelId = 'goal_alert_channel';
const String _kGoalAlertChannelName = 'Peringatan Goal Terbengkalai';
const String _kGoalAlertChannelDesc =
    'Notifikasi saat goal belajar tidak terisi selama 24 jam';

// Mendaftarkan Android notification channel dengan custom sound.
// WAJIB dipanggil SEBELUM notifikasi pertama masuk — karena begitu sebuah
// channel ID pernah dipakai sekali di device (walau dengan setting lama),
// Android MENGUNCI importance & sound-nya secara permanen; pemanggilan
// ulang dengan parameter berbeda tidak akan mengubah apa pun pada channel
// yang sudah ada, hanya efektif untuk device yang belum pernah menerimanya.
Future<void> _registerGoalAlertChannel() async {
  const androidChannel = AndroidNotificationChannel(
    _kGoalAlertChannelId,
    _kGoalAlertChannelName,
    description: _kGoalAlertChannelDesc,
    importance: Importance.max, // wajib max supaya heads-up + suara konsisten muncul
    playSound: true,
    // Nama file TANPA ekstensi — merujuk ke
    // android/app/src/main/res/raw/goal_alert.mp3
    sound: const RawResourceAndroidNotificationSound('goal_alert'),
  );

  final plugin = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await plugin?.createNotificationChannel(androidChannel);
}

// Harus top-level function (di luar class), dan diberi anotasi ini —
// dipanggil di isolate terpisah saat app di background/terminated.
// Kalau server sewaktu-waktu kirim data-only message (tanpa field
// "notification"), tanpa handler ini FCM tidak akan memproses apa pun
// di kondisi background/terminated.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Cukup no-op untuk sekarang: kalau payload sudah menyertakan field
  // "notification", Android/iOS akan auto-tampilkan tanpa perlu kode ini.
  // Riwayatnya sudah tercatat di monitoring_alerts oleh Edge Function.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConstants.supabaseUrl,
    anonKey: SupabaseConstants.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
  // Tanpa FirebaseOptions eksplisit: di Android, Firebase.initializeApp()
  // otomatis membaca konfigurasi dari android/app/google-services.json
  // lewat Google Services Gradle plugin. Cukup untuk target Android saja.
  await Firebase.initializeApp();
  // WAJIB didaftarkan SEBELUM runApp(), supaya FCM tahu isolate mana
  // yang harus dipanggil saat message masuk ketika app background/terminated.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  // WAJIB sebelum runApp(): mendaftarkan channel dengan custom sound
  // SEBELUM ada kemungkinan notifikasi pertama masuk ke channel ini.
  await _registerGoalAlertChannel();
  runApp(const ProviderScope(child: AILearningTrackerApp()));
}

class AILearningTrackerApp extends ConsumerStatefulWidget {
  const AILearningTrackerApp({super.key});

  @override
  ConsumerState<AILearningTrackerApp> createState() => _AILearningTrackerAppState();
}

class _AILearningTrackerAppState extends ConsumerState<AILearningTrackerApp> {
  final _pushService = PushNotificationService();
  bool _pushInitialized = false;

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    // Registrasi FCM token & pasang listener tap-notifikasi sekali saja,
    // setelah router siap (supaya deep_link bisa langsung di-push).
    if (!_pushInitialized) {
      _pushInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pushService.initialize(
          onDeepLink: (deepLink) {
            // FCM callback dapat berjalan tepat saat aplikasi sedang resume.
            // Jadwalkan navigasi setelah frame aktif agar Navigator/GoRouter
            // tidak dibangun dan dimutasi pada saat yang sama.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;

              final target = switch (deepLink) {
                '/activity/new' => '/activity/add',
                '/monitoring/trend' => '/monitoring',
                _ => deepLink,
              };

              // Deep link notifikasi adalah tujuan tunggal. Gunakan go(),
              // bukan push(), supaya tidak menumpuk navigator lama ketika
              // aplikasi dibangunkan dari background/terminated.
              router.go(target);
            });
          },
        );
      });
    }

    // Mode Gelap dinonaktifkan sementara: banyak layar masih hardcode
    // warna mode terang (AppBar, background), sehingga toggle dark mode
    // menyebabkan elemen seperti ikon kembali menjadi tak terlihat
    // (putih di atas putih). Dikunci ke tema terang saja supaya stabil
    // untuk pengujian dengan responden.
    return MaterialApp.router(
      title: 'Reguly',
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}