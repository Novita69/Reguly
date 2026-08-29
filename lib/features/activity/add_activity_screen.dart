// lib/features/activity/add_activity_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/activity_provider.dart';
import '../goals/providers/goal_provider.dart';
import '../../models/learning_activity.dart';
import '../../models/learning_goal.dart';

const _purple = Color(0xFF5C4DFF);
const _bg = Color(0xFFF5F7FA);

class AddActivityScreen extends ConsumerStatefulWidget {
  const AddActivityScreen({super.key});
  @override
  ConsumerState<AddActivityScreen> createState() => _AddActivityScreenState();
}

class _AddActivityScreenState extends ConsumerState<AddActivityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _durationCtrl = TextEditingController(text: '30');
  final _notesCtrl = TextEditingController();

  String _category = kActivityCategories.first;
  DateTime _date = DateTime.now();
  int _focusScore = 3;
  String? _selectedGoalId;

  // Melacak judul goal yang terakhir kali dipakai untuk auto-fill nama
  // aktivitas, supaya kalau user ganti Target Belajar TAPI belum sempat
  // mengetik detail sendiri, sarannya ikut ter-update. Tapi kalau user
  // sudah mengetik detail yang beda dari saran, itu tidak ditimpa lagi.
  String _lastAutoFilledTitle = '';
  // Dropdown Kategori disembunyikan secara default (sudah otomatis ikut
  // Target Belajar yang dipilih) -- baru dimunculkan kalau user memang
  // ingin override manual, supaya form tidak terasa menanyakan
  // "apa aktivitas ini" tiga kali sekaligus (Target Belajar, Detail
  // Aktivitas, dan Kategori).
  bool _showCategoryOverride = false;

  @override
  void dispose() {
    _nameCtrl.dispose(); _durationCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  static const _focusEmoji = ['', '😞', '😐', '🙂', '🤩', '🚀'];
  static const _focusLabel = ['', 'Sangat Buruk', 'Kurang Baik', 'Cukup', 'Bagus', 'Luar Biasa'];

  // Pastikan value kategori yang sedang aktif selalu ada di items, walau
  // itu kategori lama/usang dari data lama (mis. goal lama atau field
  // category null di database yang sudah di-fallback). Mencegah crash
  // DropdownButtonFormField ("there should be exactly one item with value").
  List<String> _categoryOptions(String current) {
    if (!kActivityCategories.contains(current)) {
      return [...kActivityCategories, current];
    }
    return kActivityCategories;
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _date, firstDate: DateTime(2024), lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: _purple)),
        child: child!,
      ),
    );
    if (p != null) setState(() => _date = p);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedGoalId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pilih Target Belajar terlebih dahulu')));
      return;
    }
    final duration = int.tryParse(_durationCtrl.text.trim()) ?? 0;
    if (duration < kMinActivityDurationMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          'Durasi minimal $kMinActivityDurationMinutes menit')));
      return;
    }
    if (duration > kMaxActivityDurationMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          'Maks $kMaxActivityDurationMinutes menit. Buat aktivitas baru '
          'untuk sisa waktunya.')));
      return;
    }

    // Cek dulu SEBELUM disimpan: apakah aktivitas ini akan menjadi sesi
    // terakhir yang melengkapi target (actual_sessions + 1 == target_sessions),
    // supaya bisa munculkan popup yang lebih jelas ketimbang notifikasi biasa.
    LearningGoal? linkedGoal;
    for (final g in ref.read(activeGoalsProvider)) {
      if (g.id == _selectedGoalId) { linkedGoal = g; break; }
    }
    final willCompleteGoal = linkedGoal != null &&
        (linkedGoal.actualSessions + 1) >= linkedGoal.targetSessions;

    final act = await ref.read(addActivityProvider.notifier).save(
      goalId: _selectedGoalId,
      activityName: _nameCtrl.text.trim(),
      category: _category,
      activityDate: _date,
      startTime: '${TimeOfDay.now().hour.toString().padLeft(2,'0')}:${TimeOfDay.now().minute.toString().padLeft(2,'0')}',
      durationMinutes: duration,
      focusScore: _focusScore,
      progressPercent: 0,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    if (act == null) {
      final err = ref.read(addActivityProvider).error ??
          'Gagal menyimpan aktivitas. Coba lagi.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err), backgroundColor: const Color(0xFFEF4444)));
      return;
    }

    ref.read(activityHistoryProvider.notifier).addToList(act);

    if (willCompleteGoal) {
      // Popup khusus: sesi terakhir dari target ini baru saja tercatat.
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          icon: const Icon(Icons.emoji_events_rounded,
              color: Color(0xFF10B981), size: 40),
          title: const Text('Target Sudah Selesai!',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          content: Text(
            'Kerja bagus! Target "${linkedGoal!.title}" sudah selesai di sesi ini.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Oke'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktivitas berhasil disimpan!'),
            backgroundColor: Color(0xFF10B981)));
    }

    if (mounted) context.pop();
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(addActivityProvider).isSaving;
    final activeGoals = ref.watch(activeGoalsProvider);

    // Tidak ada Target Belajar aktif sama sekali → blokir pencatatan
    // aktivitas dan arahkan untuk membuat Goal dulu. Ini penting supaya
    // setiap aktivitas selalu terhubung ke satu Goal: view agregasi
    // mingguan (v_weekly_activity_aggregates) mengabaikan minggu yang
    // tidak punya Goal sama sekali (lihat BAB 3.4.3 poin 5), jadi
    // aktivitas tanpa Goal berisiko tidak pernah terhitung di clustering.
    if (activeGoals.isEmpty) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white, elevation: 0,
          title: const Text('Tambah Aktivitas Belajar',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E))),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.flag_outlined, size: 56, color: Colors.grey[300]),
              const SizedBox(height: 16),
              const Text('Belum Ada Target Belajar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E))),
              const SizedBox(height: 8),
              Text(
                'Buat Target Belajar terlebih dahulu sebelum mencatat '
                'aktivitas, supaya progres belajarmu tetap tercatat dan '
                'dapat dipantau dengan baik.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[500], height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/goals/add'),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Buat Target Belajar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    // Default pilih Goal pertama begitu tersedia, supaya pengguna tidak
    // bisa submit form tanpa Goal terpilih (lihat validator di _save()).
    _selectedGoalId ??= activeGoals.first.id;

    // Saran awal nama aktivitas = judul Goal yang terpilih, supaya user
    // tidak mulai dari kolom kosong (lihat penjelasan di deklarasi
    // _lastAutoFilledTitle di atas). Hanya dilakukan sekali di awal.
    if (_nameCtrl.text.isEmpty && _lastAutoFilledTitle.isEmpty) {
      final initialGoal =
          activeGoals.firstWhere((g) => g.id == _selectedGoalId, orElse: () => activeGoals.first);
      _nameCtrl.text = initialGoal.title;
      _lastAutoFilledTitle = initialGoal.title;
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('Tambah Aktivitas Belajar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
        actions: [
          TextButton(onPressed: () => context.push('/focus-session'),
            child: const Text('Sesi Fokus',
                style: TextStyle(color: _purple, fontWeight: FontWeight.w600))),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            // Link ke Goal — WAJIB dipilih (lihat catatan di atas).
            _card(children: [
              _label('HUBUNGKAN DENGAN TARGET BELAJAR *'),
              DropdownButtonFormField<String>(
                value: _selectedGoalId,
                decoration: _inputDeco(null),
                isDense: true,
                isExpanded: true,
                items: activeGoals.map((g) => DropdownMenuItem<String>(
                    value: g.id,
                    child: Text(g.title, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)))).toList(),
                validator: (v) => v == null ? 'Pilih Target Belajar' : null,
                onChanged: (v) {
                  setState(() {
                    _selectedGoalId = v;
                    // Auto-fill kategori dari Goal yang dihubungkan, tapi
                    // tetap bisa diubah manual lewat dropdown Kategori di
                    // bawah. Guard `contains` mencegah crash kalau Goal
                    // yang dipilih punya kategori lama/usang yang sudah
                    // tidak ada di kActivityCategories.
                    if (v != null) {
                      final linkedGoal =
                          activeGoals.firstWhere((g) => g.id == v);
                      if (kActivityCategories.contains(linkedGoal.category)) {
                        _category = linkedGoal.category;
                      }
                      // Ikut update saran nama aktivitas HANYA kalau user
                      // belum mengubahnya sendiri dari saran sebelumnya --
                      // supaya detail yang sudah diketik user tidak
                      // tertimpa tanpa disadari saat ganti Target Belajar.
                      if (_nameCtrl.text.trim().isEmpty ||
                          _nameCtrl.text == _lastAutoFilledTitle) {
                        _nameCtrl.text = linkedGoal.title;
                        _lastAutoFilledTitle = linkedGoal.title;
                      }
                    }
                  });
                },
              ),
            ]),
            const SizedBox(height: 12),
            _card(children: [
              _label('DETAIL AKTIVITAS *'),
              TextFormField(
                controller: _nameCtrl,
                decoration: _inputDeco('Misal: Revisi bagian metodologi, Baca 3 jurnal terkait analisis data'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Detail aktivitas tidak boleh kosong' : null,
              ),
            ]),
            const SizedBox(height: 12),

            // Durasi (selalu tampil) + Kategori (disembunyikan default,
            // karena sudah otomatis ikut Target Belajar -- lihat komentar
            // di deklarasi _showCategoryOverride).
            _card(children: [
              _label('DURASI (MENIT) *'),
              TextFormField(
                controller: _durationCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _inputDeco(
                    'Masukkan menit, min $kMinActivityDurationMinutes - '
                    'maks $kMaxActivityDurationMinutes menit'),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < kMinActivityDurationMinutes) {
                    return 'Durasi minimal $kMinActivityDurationMinutes menit';
                  }
                  if (n > kMaxActivityDurationMinutes) {
                    return 'Maks $kMaxActivityDurationMinutes menit. Buat '
                        'aktivitas baru untuk sisa waktunya.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              if (!_showCategoryOverride)
                GestureDetector(
                  onTap: () => setState(() => _showCategoryOverride = true),
                  child: Row(children: [
                    Icon(Icons.local_offer_outlined, size: 14, color: Colors.grey[400]),
                    const SizedBox(width: 6),
                    Text('Kategori: $_category',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(width: 6),
                    const Text('· Ubah',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _purple)),
                  ]),
                )
              else
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('KATEGORI'),
                  DropdownButtonFormField<String>(
                    value: _category,
                    decoration: _inputDeco(null),
                    isDense: true,
                    isExpanded: true,
                    items: _categoryOptions(_category).map((c) =>
                        DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() => _category = v!),
                  ),
                ]),
            ]),
            const SizedBox(height: 12),

            // Tanggal
            _card(children: [
              _label('TANGGAL'),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined, size: 16, color: _purple),
                    const SizedBox(width: 10),
                    Text(_fmtDate(_date),
                        style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E))),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 12),

            // Focus slider
            _card(children: [
              Row(children: [
                Expanded(child: _label('TINGKAT FOKUS (SKALA 1 – 5)')),
                Text('SKOR: $_focusScore/5',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: _purple)),
              ]),
              const SizedBox(height: 4),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _purple,
                  thumbColor: _purple,
                  inactiveTrackColor: Colors.grey[200],
                  overlayColor: _purple.withOpacity(0.15),
                  trackHeight: 5,
                ),
                child: Slider(
                  value: _focusScore.toDouble(),
                  min: 1, max: 5, divisions: 4,
                  onChanged: (v) => setState(() => _focusScore = v.round()),
                ),
              ),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: _purple.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_focusEmoji[_focusScore]} ${_focusLabel[_focusScore]}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                        color: _purple),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),

            // Notes
            _card(children: [
              _label('CATATAN REFLEKSI RINGKAS'),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration: _inputDeco(
                    'Tuliskan apa saja yang kamu pelajari, kendala teknis singkat, '
                    'atau pencapaian kecil yang kamu sukai.'),
              ),
            ]),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: saving
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Simpan Aktivitas Belajar',
                        style: TextStyle(fontSize: 15,
                            fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
        color: Colors.grey[500], letterSpacing: 0.6)),
  );

  InputDecoration _inputDeco(String? hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
    filled: true, fillColor: const Color(0xFFF5F7FA),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    errorMaxLines: 3,
  );
}

// ═══════════════════════════════════════════════════════════════
// ACTIVITY HISTORY SCREEN
// ═══════════════════════════════════════════════════════════════

class ActivityHistoryScreen extends ConsumerWidget {
  const ActivityHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activityHistoryProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('Riwayat Aktivitas',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
        actions: [
          TextButton(
            onPressed: () => context.push('/activity/add'),
            child: const Text('Catat Baru',
                style: TextStyle(color: _purple, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Column(children: [
        // Summary stat row
        _SummaryRow(totalMinutes: state.totalMinutes, avgFocus: state.avgFocus),
        // Search bar
        _SearchBar(onChanged: (q) =>
            ref.read(activityHistoryProvider.notifier).setSearch(q)),
        // Filter chips
        _FilterChips(
          selected: state.filter.period,
          onSelect: (f) => ref.read(activityHistoryProvider.notifier).setPeriodFilter(f),
        ),
        // List
        Expanded(
          child: state.isLoading
              ? const Center(child: CircularProgressIndicator(color: _purple))
              : state.activities.isEmpty
                  ? const _EmptyActivities()
                  : RefreshIndicator(
                      color: _purple,
                      onRefresh: () => ref.read(activityHistoryProvider.notifier).load(),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: state.activities.length,
                        itemBuilder: (ctx, i) => _ActivityCard(
                          activity: state.activities[i],
                          onDelete: () => ref
                              .read(activityHistoryProvider.notifier)
                              .deleteActivity(state.activities[i].id),
                        ),
                      ),
                    ),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/activity/add'),
        backgroundColor: _purple,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final int totalMinutes;
  final double avgFocus;
  const _SummaryRow({required this.totalMinutes, required this.avgFocus});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(children: [
        Expanded(child: _MiniStatCard(
          icon: Icons.calendar_month_outlined,
          label: 'Berdurasi total',
          value: '$totalMinutes Menit',
          color: _purple,
        )),
        const SizedBox(width: 12),
        Expanded(child: _MiniStatCard(
          icon: Icons.sentiment_satisfied_outlined,
          label: 'Rata-rata fokus',
          value: '${avgFocus.toStringAsFixed(1)}/5.0',
          color: const Color(0xFF4ECDC4),
        )),
      ]),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final IconData icon; final String label, value; final Color color;
  const _MiniStatCard({required this.icon, required this.label,
    required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
            color: color)),
      ]),
    ]),
  );
}

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Cari detail aktivitas atau catatan...',
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
        prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[400], size: 20),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[200]!)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[200]!)),
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
      ),
    ),
  );
}

class _FilterChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _FilterChips({required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    const filters = [
      ('all', 'Semua'), ('today', 'Hari Ini'),
      ('week', 'Minggu Ini'), ('month', 'Bulan Ini'),
    ];
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        children: filters.map((f) {
          final isActive = selected == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(f.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? _purple : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive ? _purple : Colors.grey[300]!),
                ),
                child: Text(f.$2,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: isActive ? Colors.white : Colors.grey[600])),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final LearningActivity activity;
  final VoidCallback onDelete;
  const _ActivityCard({required this.activity, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _purple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(activity.category,
                  style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w600, color: _purple)),
            ),
            const Spacer(),
            Text('${activity.durationMinutes} Min',
                style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w700, color: _purple)),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              onSelected: (v) { if (v == 'delete') onDelete(); },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'delete',
                    child: Text('Hapus',
                        style: TextStyle(color: Colors.red))),
              ],
              child: Icon(Icons.more_vert_rounded, size: 18, color: Colors.grey[400]),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            '${activity.startTime != null ? "${activity.startTime} • " : ""}${activity.formattedDate}',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
          const SizedBox(height: 6),
          Text(activity.activityName,
              style: const TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
          if (activity.notes != null && activity.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.description_outlined, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('"${activity.notes}"',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600],
                          fontStyle: FontStyle.italic)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            const Text('Tingkat Konsentrasi: ',
                style: TextStyle(fontSize: 12, color: Color(0xFF1A1A2E))),
            const Spacer(),
            Row(children: List.generate(5, (i) => Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Icon(
                i < activity.focusScore ? Icons.circle : Icons.circle_outlined,
                size: 10,
                color: i < activity.focusScore
                    ? const Color(0xFFF59E0B) : Colors.grey[300],
              ),
            ))),
          ]),
        ]),
      ),
    );
  }
}

class _EmptyActivities extends StatelessWidget {
  const _EmptyActivities();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.history_outlined, size: 64, color: Colors.grey[300]),
      const SizedBox(height: 16),
      Text('Belum ada aktivitas',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
              color: Colors.grey[400])),
      const SizedBox(height: 8),
      Text('Mulai catat sesi belajarmu!',
          style: TextStyle(fontSize: 13, color: Colors.grey[400])),
    ]),
  );
}