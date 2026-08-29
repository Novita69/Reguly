// lib/features/activity/focus_session_screen.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:audioplayers/audioplayers.dart';
import 'providers/activity_provider.dart';
import '../goals/providers/goal_provider.dart';
import '../../models/learning_activity.dart';

const _purple = Color(0xFF5C4DFF);
const _teal = Color(0xFF4ECDC4);
const _bg = Color(0xFFF5F7FA);

// ═══════════════════════════════════════════════════════════════
// FOCUS SESSION SETUP SCREEN
// ═══════════════════════════════════════════════════════════════

class FocusSessionScreen extends ConsumerStatefulWidget {
  const FocusSessionScreen({super.key});
  @override
  ConsumerState<FocusSessionScreen> createState() => _FocusSessionScreenState();
}

class _FocusSessionScreenState extends ConsumerState<FocusSessionScreen> {
  final _topicCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _customDurCtrl = TextEditingController();
  String? _selectedGoalId;
  int _selectedDuration = 25; // menit
  bool _useCustom = false;

  static const _presets = [
    _DurationPreset(label: '25 Menit', sub: 'POMODORO', minutes: 25),
    _DurationPreset(label: '50 Menit', sub: 'FOKUS PENUH', minutes: 50),
    _DurationPreset(label: '90 Menit', sub: 'SPESIALIS', minutes: 90),
  ];

  @override
  void dispose() {
    _topicCtrl.dispose(); _notesCtrl.dispose(); _customDurCtrl.dispose();
    super.dispose();
  }

  void _applyCustom() {
    final v = int.tryParse(_customDurCtrl.text.trim()) ?? 0;
    if (v < kMinActivityDurationMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          'Durasi minimal $kMinActivityDurationMinutes menit')));
      return;
    }
    if (v > kMaxActivityDurationMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          'Maks $kMaxActivityDurationMinutes menit. Mulai sesi baru '
          'setelah ini selesai.')));
      return;
    }
    setState(() { _selectedDuration = v; _useCustom = false; });
    FocusScope.of(context).unfocus();
  }

  void _start() {
    if (_topicCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi topik/mata kuliah terlebih dahulu')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FocusSessionTimerScreen(
        topic: _topicCtrl.text.trim(),
        goalId: _selectedGoalId,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        durationMinutes: _selectedDuration,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final activeGoals = ref.watch(activeGoalsProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('Sesi Fokus Metakognitif',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: Colors.grey)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _purple.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _purple.withOpacity(0.2)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.timer_outlined, color: _purple, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Aturan Self-Monitoring',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: _purple)),
                const SizedBox(height: 4),
                Text(
                  'Sesi Fokus membantu Anda memantau daya tumpu belajar secara aktif. '
                  'Sekali dimulai, pertahankan fokus penuh Anda!',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4),
                ),
              ])),
            ]),
          ),
          const SizedBox(height: 16),

          // Topik
          _card(children: [
            _label('TOPIK SESI FOKUS *'),
            TextField(
              controller: _topicCtrl,
              decoration: _inputDeco('Misal: Menyusun Bab 1, Analisis UML'),
            ),
          ]),
          const SizedBox(height: 12),

          // Goal + Notes
          _card(children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('HUBUNGKAN KE TARGET'),
                DropdownButton<String?>(
                  value: _selectedGoalId,
                  isExpanded: true,
                  underline: const SizedBox(),
                  style: const TextStyle(fontSize: 13,
                      color: Color(0xFF1A1A2E)),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('-- Tidak Hubungkan --',
                            style: TextStyle(color: Colors.grey, fontSize: 13))),
                    ...activeGoals.map((g) => DropdownMenuItem<String?>(
                        value: g.id,
                        child: Text(g.title, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)))),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _selectedGoalId = v;
                      // Auto-isi Topik dari judul Goal yang dipilih, HANYA
                      // kalau kolom Topik masih kosong -- konsisten dengan
                      // add_activity_screen.dart, supaya tidak menimpa apa
                      // pun yang sudah diketik user.
                      if (v != null && _topicCtrl.text.trim().isEmpty) {
                        final linkedGoal = activeGoals.firstWhere((g) => g.id == v);
                        _topicCtrl.text = linkedGoal.title;
                      }
                    });
                  },
                ),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('CATATAN SESI (OPSIONAL)'),
                TextField(
                  controller: _notesCtrl,
                  decoration: _inputDeco('Misal: Fokus membaca...'),
                ),
              ])),
            ]),
          ]),
          const SizedBox(height: 16),

          // Duration presets
          _label('PILIH DURASI FOKUS'),
          const SizedBox(height: 8),
          Row(children: _presets.map((p) {
            final isSelected = !_useCustom && _selectedDuration == p.minutes;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedDuration = p.minutes;
                    _useCustom = false;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? _purple : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: isSelected ? _purple : Colors.grey[300]!),
                    ),
                    child: Column(children: [
                      Text(p.label,
                          style: TextStyle(fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? Colors.white : const Color(0xFF1A1A2E))),
                      const SizedBox(height: 2),
                      Text(p.sub,
                          style: TextStyle(fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white70 : Colors.grey[400])),
                    ]),
                  ),
                ),
              ),
            );
          }).toList()),
          const SizedBox(height: 12),

          // Custom duration
          _card(children: [
            _label('ATUR DURASI SENDIRI (MENIT)'),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _customDurCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDeco('Misal: 15, 45, 60...'),
                  onChanged: (_) => setState(() => _useCustom = true),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _applyCustom,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0, minimumSize: const Size(90, 52),
                ),
                child: const Text('Terapkan',
                    style: TextStyle(fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ]),
            if (_useCustom)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Durasi kustom: ${_customDurCtrl.text} menit (tekan Terapkan)',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ),
          ]),
          const SizedBox(height: 24),

          // Start button
          SizedBox(
            width: double.infinity, height: 56,
            child: ElevatedButton(
              onPressed: _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text(
                'Mulai Sesi $_selectedDuration Menit Sekarang',
                style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
        color: Colors.grey[500], letterSpacing: 0.6)),
  );

  InputDecoration _inputDeco(String? hint) => InputDecoration(
    hintText: hint, hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
    filled: true, fillColor: const Color(0xFFF5F7FA),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

class _DurationPreset {
  final String label, sub;
  final int minutes;
  const _DurationPreset({required this.label, required this.sub, required this.minutes});
}

// ═══════════════════════════════════════════════════════════════
// FOCUS SESSION TIMER SCREEN
// ═══════════════════════════════════════════════════════════════

class FocusSessionTimerScreen extends ConsumerStatefulWidget {
  final String topic;
  final String? goalId;
  final String? notes;
  final int durationMinutes;

  const FocusSessionTimerScreen({
    super.key,
    required this.topic,
    this.goalId,
    this.notes,
    required this.durationMinutes,
  });

  @override
  ConsumerState<FocusSessionTimerScreen> createState() =>
      _FocusSessionTimerScreenState();
}

class _FocusSessionTimerScreenState
    extends ConsumerState<FocusSessionTimerScreen>
    with SingleTickerProviderStateMixin {
  late int _remaining; // detik tersisa
  late int _total;
  Timer? _timer;
  bool _paused = false;
  bool _finished = false;
  int _focusScore = 4;
  final _completionPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _total = widget.durationMinutes * 60;
    _remaining = _total;
    _startTimer();
    // Lock orientation to portrait
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _completionPlayer.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused) return;
      if (_remaining <= 0) {
        _timer?.cancel();
        // Chime khusus aplikasi ini, ganti suara klik sistem generik
        // sebelumnya. File ada di assets/sounds/session_complete.wav —
        // pastikan sudah didaftarkan di pubspec.yaml.
        _completionPlayer.play(AssetSource('sounds/session_complete.wav'));
        HapticFeedback.mediumImpact();
        setState(() => _finished = true);
        _onFinish();
        return;
      }
      setState(() => _remaining--);
    });
  }

  void _togglePause() => setState(() => _paused = !_paused);

  Future<void> _onFinish() async {
    final elapsed = _total - _remaining;
    final elapsedMin = (elapsed / 60).ceil().clamp(1, widget.durationMinutes);

    // Kategori ikut Goal yang dihubungkan (konsisten dengan
    // AddActivityScreen), fallback ke 'Lainnya' kalau sesi ini tidak
    // dihubungkan ke goal apa pun. Sebelumnya hardcode 'Belajar Materi',
    // yang tidak ada di kActivityCategories manapun (bug kosmetik --
    // tidak mempengaruhi x1-x5, tapi bikin data kategori "nyasar").
    String category = 'Lainnya';
    if (widget.goalId != null) {
      final activeGoals = ref.read(activeGoalsProvider);
      for (final g in activeGoals) {
        if (g.id == widget.goalId && kActivityCategories.contains(g.category)) {
          category = g.category;
          break;
        }
      }
    }

    await ref.read(addActivityProvider.notifier).save(
      goalId: widget.goalId,
      activityName: widget.topic,
      category: category,
      activityDate: DateTime.now(),
      startTime: null,
      durationMinutes: elapsedMin,
      focusScore: _focusScore,
      progressPercent: _finished ? 100.0 : (elapsed / _total * 100),
      notes: widget.notes,
      sourceType: 'focus_session',
    );
    ref.read(activityHistoryProvider.notifier).load();
  }

  Future<void> _endEarly() async {
    _timer?.cancel();
    setState(() => _paused = true);
    await _onFinish();
    // Sama seperti tombol "Kembali ke Dashboard" — pakai context.go supaya
    // tidak nyangkut di layar Setup yang masih ada di bawahnya.
    if (mounted) context.go('/dashboard');
  }

  String get _timeStr {
    final m = _remaining ~/ 60;
    final s = _remaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _progress => (_total - _remaining) / _total;

  @override
  Widget build(BuildContext context) {
    if (_finished) return _FinishedView(topic: widget.topic, onBack: () {
      // Sebelumnya cuma Navigator.pop() satu kali — itu cuma menutup layar
      // Timer ini dan membuka kembali layar Setup di baliknya (karena Timer
      // dibuka lewat Navigator.push biasa, bukan go_router). context.go
      // mengganti seluruh stack navigasi langsung ke Dashboard.
      context.go('/dashboard');
    });

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              // Header
              Row(children: [
                GestureDetector(
                  onTap: _endEarly,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(widget.topic,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16,
                          fontWeight: FontWeight.w600, color: Colors.white)),
                ),
                if (_paused)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('DIJEDA',
                        style: TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF59E0B))),
                  ),
              ]),
              const SizedBox(height: 48),

              // Circle timer
              SizedBox(
                width: 240, height: 240,
                child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(
                    size: const Size(240, 240),
                    painter: _TimerPainter(progress: _progress, paused: _paused),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_timeStr,
                        style: const TextStyle(fontSize: 52,
                            fontWeight: FontWeight.w800, color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()])),
                    Text(
                      '${widget.durationMinutes} menit total',
                      style: TextStyle(fontSize: 13,
                          color: Colors.white.withOpacity(0.5)),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 48),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(_teal),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).round()}% selesai',
                style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
              ),
              const Spacer(),

              // Focus score (bisa ubah selama sesi)
              Column(children: [
                Text('Tingkat fokus saat ini',
                    style: TextStyle(fontSize: 13,
                        color: Colors.white.withOpacity(0.6))),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) => GestureDetector(
                      onTap: () => setState(() => _focusScore = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          i < _focusScore ? Icons.circle : Icons.circle_outlined,
                          size: 16,
                          color: i < _focusScore
                              ? const Color(0xFFF59E0B)
                              : Colors.white.withOpacity(0.3),
                        ),
                      ),
                    ))),
              ]),
              const SizedBox(height: 28),

              // Controls
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                // End early
                GestureDetector(
                  onTap: _endEarly,
                  child: Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.stop_rounded,
                        color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 24),
                // Pause/Resume
                GestureDetector(
                  onTap: _togglePause,
                  child: Container(
                    width: 72, height: 72,
                    decoration: const BoxDecoration(
                      color: _purple, shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      color: Colors.white, size: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                const SizedBox(width: 56, height: 56),
              ]),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Timer Custom Painter ───────────────────────────────────────

class _TimerPainter extends CustomPainter {
  final double progress;
  final bool paused;
  const _TimerPainter({required this.progress, required this.paused});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 10;
    const sw = 12.0;

    canvas.drawCircle(c, r, Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw);

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = paused ? const Color(0xFFF59E0B) : _teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TimerPainter old) =>
      old.progress != progress || old.paused != paused;
}

// ── Finished View ──────────────────────────────────────────────

class _FinishedView extends StatelessWidget {
  final String topic;
  final VoidCallback onBack;
  const _FinishedView({required this.topic, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🎉', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 20),
              const Text('Sesi Selesai!',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 10),
              Text(topic,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15,
                      color: Colors.white.withOpacity(0.7))),
              const SizedBox(height: 8),
              Text('Aktivitas telah otomatis tersimpan.',
                  style: TextStyle(fontSize: 13,
                      color: Colors.white.withOpacity(0.5))),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: onBack,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text('Kembali ke Dashboard',
                      style: TextStyle(fontSize: 15,
                          fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}