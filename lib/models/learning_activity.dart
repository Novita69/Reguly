// lib/models/learning_activity.dart

class LearningActivity {
  final String id;
  final String userId;
  final String? goalId;
  final String activityName;
  final String category;
  final DateTime activityDate;
  final String? startTime; // "HH:mm"
  final int durationMinutes;
  final int focusScore; // 1–5
  final double progressPercent;
  final String? notes;
  final String sourceType; // 'manual' | 'focus_session'
  final DateTime createdAt;

  const LearningActivity({
    required this.id,
    required this.userId,
    this.goalId,
    required this.activityName,
    required this.category,
    required this.activityDate,
    this.startTime,
    required this.durationMinutes,
    required this.focusScore,
    required this.progressPercent,
    this.notes,
    required this.sourceType,
    required this.createdAt,
  });

  factory LearningActivity.fromMap(Map<String, dynamic> m) => LearningActivity(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        goalId: m['goal_id'] as String?,
        activityName: m['activity_name'] as String,
        category: m['category'] as String? ?? 'Lainnya', // diubah dari 'Umum' -> 'Lainnya' agar selalu valid di kActivityCategories
        activityDate: DateTime.parse(m['activity_date'] as String),
        startTime: m['start_time'] as String?,
        durationMinutes: m['duration_minutes'] as int,
        focusScore: m['focus_score'] as int,
        progressPercent: (m['progress_percent'] as num? ?? 0).toDouble(),
        notes: m['notes'] as String?,
        sourceType: m['source_type'] as String? ?? 'manual',
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  String get focusEmoji {
    switch (focusScore) {
      case 1: return '😞';
      case 2: return '😐';
      case 3: return '🙂';
      case 4: return '🤩';
      default: return '🚀';
    }
  }

  String get focusLabel {
    switch (focusScore) {
      case 1: return 'Sangat Buruk';
      case 2: return 'Kurang Baik';
      case 3: return 'Cukup';
      case 4: return 'Bagus';
      default: return 'Luar Biasa';
    }
  }

  String get formattedDate {
    final d = activityDate;
    return '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

// Kategori yang tersedia (dipakai di dropdown Activity maupun Goal).
// Ini adalah SATU-SATUNYA sumber daftar kategori di aplikasi -- baik
// goal_list_screen.dart maupun add_activity_screen.dart mengimpor
// kActivityCategories dari sini, supaya kedua layar selalu sinkron.
// Disesuaikan dengan konteks populasi penelitian: mahasiswa skripsi/tugas akhir.
//
// Riwayat perubahan taksonomi (data testing, belum ada responden nyata
// saat perubahan ini dibuat):
// - 'Penelitian' dihapus: terlalu umum, tumpang tindih dengan hampir
//   semua kategori lain (Membaca, Pengumpulan Data, Analisis Data juga
//   "penelitian"), menyebabkan ambiguitas saat memilih.
// - 'Persiapan Sidang/Ujian' & 'Administrasi' ditambahkan: dua aktivitas
//   nyata yang sering dilakukan mahasiswa tapi sebelumnya tidak punya
//   tempat, sehingga selalu numpuk di 'Lainnya' dan kehilangan sinyal.
// - Urutan disusun longgar mengikuti alur umum pengerjaan skripsi
//   (Membaca -> Pengumpulan Data -> Analisis Data -> Menulis ->
//   Bimbingan -> Revisi -> Persiapan Sidang -> Administrasi -> Lainnya),
//   bukan aturan wajib berurutan, murni bantu scanning visual di dropdown.
const kActivityCategories = [
  'Membaca',
  'Pengumpulan Data',
  'Analisis Data',
  'Menulis',
  'Bimbingan/Konsultasi',
  'Revisi',
  'Persiapan Sidang/Ujian',
  'Administrasi',
  'Lainnya',
];

// Batas durasi per sesi aktivitas (berlaku untuk SEMUA jalur pencatatan
// aktivitas: form Tambah Aktivitas manual maupun Sesi Fokus/Pomodoro).
// Sumber tunggal supaya kedua layar selalu sinkron satu sama lain, dan
// dengan lapisan server (ActivityService + CHECK constraint di migration
// 20260727100000_activity_duration_and_single_active_goal.sql). Kalau
// aktivitas belajar berlangsung lebih dari 120 menit, arahkan pengguna
// untuk mencatatnya sebagai beberapa aktivitas/sesi terpisah, supaya satu
// sesi tetap merepresentasikan satu blok fokus yang wajar.
const int kMinActivityDurationMinutes = 1;
const int kMaxActivityDurationMinutes = 120;