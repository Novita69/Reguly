// lib/features/goals/goal_list_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/goal_provider.dart';
import '../../models/learning_goal.dart';
import '../../models/learning_activity.dart'; // untuk kActivityCategories (sumber tunggal daftar kategori)

const _purple = Color(0xFF5C4DFF);
const _teal = Color(0xFF4ECDC4);
const _bg = Color(0xFFF5F7FA);

// Dipanggil saat tombol "Tambah Target" ditekan. Selama masih ada Goal
// aktif yang belum selesai (belum completed / progress < 100%), pembuatan
// Goal baru diblokir di sini -- sebelum user sempat mengisi form -- supaya
// tidak ada beberapa Goal berjalan sekaligus dalam periode yang tumpang
// tindih (mencegah data belajar yang bias/tidak bersih). Pagar yang sama
// juga ditegakkan di GoalService.createGoal() (lapisan submit) dan di
// server (migration goal_target_limits / goal_single_active), jadi ini
// murni untuk UX yang lebih cepat & jelas.
void _onTapAddTarget(BuildContext context, WidgetRef ref) {
  final blocking = ref.read(goalProvider).blockingActiveGoal;
  if (blocking == null) {
    context.push('/goals/add');
    return;
  }
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: const Icon(Icons.flag_rounded, color: _purple, size: 36),
      title: const Text('Selesaikan Target Berjalan Dulu',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      content: Text(
        'Kamu masih punya target "${blocking.title}" yang belum selesai '
        '(${blocking.progressLabel}). Selesaikan target ini dulu sebelum '
        'membuat target belajar baru, supaya progres belajarmu tetap '
        'tercatat rapi dan tidak tumpang tindih.',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: _purple,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Mengerti'),
        ),
      ],
    ),
  );
}

// Dipanggil saat opsi "Hapus" dipilih dari menu Goal. Menampilkan dialog
// konfirmasi dengan info EKSPLISIT soal apa yang terjadi pada aktivitas
// yang terhubung -- supaya user tahu persis konsekuensinya SEBELUM klik,
// bukan menebak-nebak. Penghapusan goal TIDAK menghapus aktivitas
// terkait (goal_id di learning_activities memakai ON DELETE SET NULL,
// lihat v2_schema.sql) -- aktivitas tetap tersimpan sebagai riwayat
// belajar, hanya jadi tidak terhubung ke target mana pun lagi.
//
// goal.actualSessions dipakai langsung sebagai jumlah aktivitas
// terhubung, karena kolom itu di-maintain real-time oleh trigger
// update_goal_progress() (COUNT(*) dari learning_activities WHERE
// goal_id = goal ini) -- tidak perlu query tambahan ke server.
void _confirmDeleteGoal(
    BuildContext context, WidgetRef ref, LearningGoal goal) {
  final activityCount = goal.actualSessions;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: const Icon(Icons.delete_outline_rounded,
          color: Color(0xFFEF4444), size: 36),
      title: const Text('Hapus Target Belajar?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      content: Text(
        activityCount > 0
            ? 'Target "${goal.title}" akan dihapus permanen.\n\n'
                '$activityCount aktivitas yang terhubung akan tetap '
                'tersimpan, tapi jadi tidak terhubung ke target mana pun.'
            : 'Target "${goal.title}" akan dihapus permanen. Tindakan '
                'ini tidak bisa dibatalkan.',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('Batal', style: TextStyle(color: Colors.grey[600])),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            ref.read(goalProvider.notifier).deleteGoal(goal.id);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Hapus'),
        ),
      ],
    ),
  );
}

// Dipanggil saat opsi "Selesai" dipilih dari menu Goal. Untuk kasus user
// menuntaskan target lebih cepat dari jadwal (mis. sudah tercapai sebelum
// period_end lewat) -- menandai goal 'completed' secara manual, tanpa perlu
// menunggu progress alami mencapai 100% atau period_end lewat lebih dulu.
//
// Ini terhubung LANGSUNG ke database lewat GoalService.markCompleted (sudah
// ada sebelumnya, dipakai juga di recommendation_screen.dart): meng-update
// learning_goals.status jadi 'completed' dan actual_progress jadi 100.0.
// PENTING secara bisnis: karena trigger validate_single_active_goal
// (migration 20260727100000) mengunci pembuatan target baru selama masih
// ada goal 'active' yang belum selesai, tombol ini adalah SATU-SATUNYA jalan
// user membuka kunci itu manual kalau target sebenarnya sudah tercapai
// sebelum waktunya -- tanpa tombol ini, user akan terjebak menunggu
// period_end lewat dulu sebelum bisa membuat target baru.
void _confirmMarkCompleted(
    BuildContext context, WidgetRef ref, LearningGoal goal) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: const Icon(Icons.check_circle_outline_rounded,
          color: Color(0xFF10B981), size: 36),
      title: const Text('Tandai Target Selesai?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      content: Text(
        'Target "${goal.title}" akan ditandai selesai (100%) sekarang, '
        'walau belum mencapai tanggal target. Kamu bisa langsung membuat '
        'target belajar baru setelah ini.',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('Batal', style: TextStyle(color: Colors.grey[600])),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            ref.read(goalProvider.notifier).markCompleted(goal.id);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Selesai'),
        ),
      ],
    ),
  );
}

class GoalListScreen extends ConsumerWidget {
  const GoalListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(goalProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Daftar Target Belajar',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
        actions: [
          TextButton.icon(
            onPressed: () => _onTapAddTarget(context, ref),
            icon: const Icon(Icons.add_rounded, size: 18, color: _purple),
            label: const Text('Tambah Target',
                style: TextStyle(
                    color: _purple, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator(color: _purple))
          : RefreshIndicator(
              color: _purple,
              onRefresh: () => ref.read(goalProvider.notifier).load(),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _HeaderCard(state: state)),
                  if (state.goals.isEmpty)
                    const SliverFillRemaining(child: _EmptyGoals())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _GoalCard(
                            goal: state.goals[i],
                            onEdit: () => context.push('/goals/edit',
                                extra: state.goals[i]),
                            onDelete: () => _confirmDeleteGoal(
                                context, ref, state.goals[i]),
                            onComplete: () => _confirmMarkCompleted(
                                context, ref, state.goals[i]),
                          ),
                          childCount: state.goals.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final GoalState state;
  const _HeaderCard({required this.state});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [_purple, Color(0xFF3DBDB7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('METODE SMART',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 4),
              const Text('Regulasi Target',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 4),
              Text(
                  'Pilah tujuan belajarmu ke dalam target-target\nkecil yang terencana dengan ketat.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.85),
                      height: 1.4)),
            ]),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.my_location_rounded,
                color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final LearningGoal goal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onComplete;
  const _GoalCard({
    required this.goal,
    required this.onEdit,
    required this.onDelete,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = goal.isCompleted;
    final isOverdue = goal.isOverdue;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDone
              ? const Color(0xFF10B981).withOpacity(0.4)
              : isOverdue
                  ? const Color(0xFFEF4444).withOpacity(0.3)
                  : Colors.transparent,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _CategoryBadge(label: goal.category),
          const Spacer(),
          if (isDone) ...[
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF10B981), size: 22),
            const SizedBox(width: 4),
          ],
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'delete') onDelete();
              if (v == 'complete') onComplete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              // Tombol "Selesai" hanya masuk akal untuk goal yang memang
              // BELUM ditandai selesai -- goal yang isDone sudah tidak
              // memblokir goal baru manapun (lihat catatan di
              // _confirmMarkCompleted), jadi opsi ini tidak perlu (dan bisa
              // membingungkan) untuk ditampilkan lagi di sana.
              if (!isDone)
                const PopupMenuItem(
                    value: 'complete',
                    child: Text('Selesai',
                        style: TextStyle(color: Color(0xFF10B981)))),
              const PopupMenuItem(
                  value: 'delete',
                  child: Text('Hapus', style: TextStyle(color: Colors.red))),
            ],
            child: Icon(Icons.more_horiz_rounded, color: Colors.grey[400]),
          ),
        ]),
        const SizedBox(height: 8),
        Text(goal.title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDone ? Colors.grey[400] : const Color(0xFF1A1A2E),
                decoration: isDone ? TextDecoration.lineThrough : null)),
        const SizedBox(height: 10),
        Row(children: [
          Text('Penyelesaian Sesi:',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const Spacer(),
          Text(goal.progressLabel,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDone ? const Color(0xFF10B981) : _purple)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: goal.sessionProgressFraction,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(
                isDone ? const Color(0xFF10B981) : _purple),
            minHeight: 7,
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.calendar_today_outlined,
              size: 13, color: Colors.grey[400]),
          const SizedBox(width: 4),
          Text(
            'Target: ${_fmt(goal.periodEnd)}',
            style: TextStyle(
                fontSize: 12,
                color: isOverdue ? const Color(0xFFEF4444) : Colors.grey[500]),
          ),
          const Spacer(),
          Text('${goal.targetDurationMinutes} Menit Belajar',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ]),
      ]),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _CategoryBadge extends StatelessWidget {
  final String label;
  const _CategoryBadge({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _purple.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: _purple)),
    );
  }
}

class _EmptyGoals extends StatelessWidget {
  const _EmptyGoals();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.flag_outlined, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text('Belum ada target belajar',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[400])),
        const SizedBox(height: 8),
        Text('Tetapkan targetmu agar belajar\nlebih terarah dan terukur.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[400])),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ADD GOAL SCREEN
// ═══════════════════════════════════════════════════════════════

class AddGoalScreen extends ConsumerStatefulWidget {
  // Jika `goal` diisi, layar ini berjalan dalam mode Edit: semua field
  // di-prefill dari data goal tersebut dan submit akan memanggil
  // updateGoal (bukan addGoal).
  final LearningGoal? goal;
  const AddGoalScreen({super.key, this.goal});
  @override
  ConsumerState<AddGoalScreen> createState() => _AddGoalScreenState();
}

class _AddGoalScreenState extends ConsumerState<AddGoalScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _titleCtrl = TextEditingController(text: widget.goal?.title);
  String? _category; // diubah dari: String _category = 'Pilih Kategori';
  late DateTime _periodStart = widget.goal?.periodStart ?? DateTime.now();
  late DateTime _periodEnd = widget.goal?.periodEnd ??
      DateTime.now().add(const Duration(
          days: 7)); // wajib -- default 7 hari, tetap bisa diubah
  // Batas bisnis: maks. 7 sesi & maks. 120 menit per sesi (lihat juga
  // validasi di GoalService dan constraint DB pada migration
  // 20260724090000_goal_target_limits.sql). Nilai goal LAMA yang mungkin
  // sudah melebihi batas ini (dibuat sebelum aturan berlaku) di-clamp saat
  // masuk mode edit, supaya stepper tidak tampil dalam kondisi tidak valid.
  static const int kMaxTargetSessions = 7;
  static const int kMaxTargetDurationMinutes = 120;
  late int _targetSessions =
      (widget.goal?.targetSessions ?? 5).clamp(1, kMaxTargetSessions);
  late int _targetDuration = (widget.goal?.targetDurationMinutes ?? 30)
      .clamp(5, kMaxTargetDurationMinutes);

  bool get _isEditMode => widget.goal != null;

  @override
  void initState() {
    super.initState();
    _category = widget.goal?.category;
  }

  // Daftar kategori TIDAK lagi didefinisikan lokal di sini -- sekarang
  // memakai kActivityCategories dari lib/models/learning_activity.dart
  // sebagai satu-satunya sumber, supaya selalu sinkron dengan layar
  // Tambah Aktivitas Belajar.

  // Helper: pastikan value yang sedang aktif selalu ada di daftar item,
  // walau itu kategori lama (data goal sebelumnya) yang sudah tidak
  // ditawarkan lagi untuk goal baru. Ini mencegah crash saat mengedit
  // goal lama tanpa perlu mengubah data lama itu sendiri.
  List<String> _dropdownOptions(String? currentValue) {
    if (currentValue != null && !kActivityCategories.contains(currentValue)) {
      return [...kActivityCategories, currentValue];
    }
    return kActivityCategories;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isEnd) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isEnd ? _periodEnd : _periodStart,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx)
            .copyWith(colorScheme: const ColorScheme.light(primary: _purple)),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => isEnd ? _periodEnd = picked : _periodStart = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_periodEnd.isBefore(_periodStart)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Deadline tidak boleh sebelum tanggal mulai')));
      return;
    }
    final notifier = ref.read(goalProvider.notifier);
    final ok = _isEditMode
        ? await notifier.updateGoal(
            goalId: widget.goal!.id,
            title: _titleCtrl.text.trim(),
            category:
                _category!, // aman: form sudah memvalidasi _category tidak null
            periodStart: _periodStart,
            periodEnd: _periodEnd,
            targetSessions: _targetSessions,
            targetDurationMinutes: _targetDuration,
          )
        : await notifier.addGoal(
            title: _titleCtrl.text.trim(),
            category:
                _category!, // aman: form sudah memvalidasi _category tidak null
            periodStart: _periodStart,
            periodEnd: _periodEnd,
            targetSessions: _targetSessions,
            targetDurationMinutes: _targetDuration,
          );
    if (ok && mounted) context.pop();
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(goalProvider).isSaving;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
            _isEditMode ? 'Edit Target Belajar' : 'Tambah Target Belajar',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _card(children: [
              _label('JUDUL TARGET *'),
              TextFormField(
                controller: _titleCtrl,
                decoration: _inputDeco('Misal: Membaca 5 Jurnal Skripsi'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Judul tidak boleh kosong'
                    : null,
              ),
            ]),
            const SizedBox(height: 12),
            _card(children: [
              _label('KATEGORI'),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: _inputDeco('Pilih Kategori'), // hint tampil di sini
                items: _dropdownOptions(_category)
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v),
                validator: (v) => v == null ? 'Kategori wajib dipilih' : null,
              ),
            ]),
            const SizedBox(height: 12),
            _card(children: [
              Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      _label('MULAI PERIODE'),
                      const SizedBox(height: 6),
                      _DateTile(
                          label: _fmtDate(_periodStart),
                          onTap: () => _pickDate(false)),
                    ])),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      _label('DEADLINE *'),
                      const SizedBox(height: 6),
                      _DateTile(
                          label: _fmtDate(_periodEnd),
                          onTap: () => _pickDate(true)),
                    ])),
              ]),
            ]),
            const SizedBox(height: 12),
            _card(children: [
              Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      _label('TARGET SESI (MAKS. $kMaxTargetSessions)'),
                      const SizedBox(height: 8),
                      _NumberStepper(
                          value: _targetSessions,
                          min: 1,
                          max: kMaxTargetSessions,
                          onChanged: (v) =>
                              setState(() => _targetSessions = v)),
                    ])),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      _label(
                          'MENIT PER SESI (MAKS. $kMaxTargetDurationMinutes)'),
                      const SizedBox(height: 8),
                      _NumberStepper(
                          value: _targetDuration,
                          min: 5,
                          max: kMaxTargetDurationMinutes,
                          step: 5,
                          onChanged: (v) =>
                              setState(() => _targetDuration = v)),
                    ])),
              ]),
            ]),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        _isEditMode
                            ? 'Simpan Perubahan'
                            : 'Simpan Target Belajar',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey[500],
                letterSpacing: 0.6)),
      );

  InputDecoration _inputDeco(String? hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF5F7FA),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );
}

class _DateTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DateTile({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined, size: 16, color: _purple),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A2E))),
        ]),
      ),
    );
  }
}

class _NumberStepper extends StatelessWidget {
  final int value, min, max, step;
  final ValueChanged<int> onChanged;
  const _NumberStepper(
      {required this.value,
      required this.min,
      required this.max,
      this.step = 1,
      required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _Btn(
          icon: Icons.remove_rounded,
          onTap: value > min ? () => onChanged(value - step) : null),
      const SizedBox(width: 12),
      Text('$value',
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E))),
      const SizedBox(width: 12),
      _Btn(
          icon: Icons.add_rounded,
          onTap: value < max ? () => onChanged(value + step) : null),
    ]);
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _Btn({required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: onTap != null ? _purple.withOpacity(0.1) : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            size: 18, color: onTap != null ? _purple : Colors.grey[300]),
      ),
    );
  }
}
