// lib/features/baseline/baseline_result_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/assessment_result.dart';
import 'providers/baseline_provider.dart';
import '../../services/push_notification_service.dart';

const _primaryPurple = Color(0xFF5C4DFF);
const _teal = Color(0xFF4ECDC4);
const _amber = Color(0xFFF59E0B);
const _bgColor = Color(0xFFF5F7FA);

class BaselineResultScreen extends ConsumerWidget {
  const BaselineResultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(baselineProvider);
    final result = state.result;

    // Guard: seharusnya tidak terjadi, tapi jika result null redirect ke baseline
    if (result == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/baseline');
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildHeader(result),
                    const SizedBox(height: 20),
                    _buildScoreCircle(result),
                    const SizedBox(height: 20),
                    _buildDimensionCard(result),
                    const SizedBox(height: 16),
                    _buildInterpretationCard(result),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
            _buildContinueButton(context, ref),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────

  Widget _buildHeader(AssessmentResult result) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _primaryPurple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.emoji_events_outlined,
              color: _primaryPurple, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hasil Penilaian Awal',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              Text(
                'Analisis Kemampuan Regulasi Diri Belajar',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Circular Score ──────────────────────────────────────────

  Widget _buildScoreCircle(AssessmentResult result) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 160,
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: CustomPaint(
                    painter: _ArcPainter(progress: result.totalPercent),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${result.scoreTotal}',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      'dari 60 skor',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _CategoryBadge(category: result.category),
        ],
      ),
    );
  }

  // ── Dimension Bars ──────────────────────────────────────────

  Widget _buildDimensionCard(AssessmentResult result) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Skor Berdasarkan Dimensi Regulasi Diri:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 16),
          _DimensionBar(
            label: 'Perencanaan (Planning)',
            score: result.scorePlanning,
            percent: result.planningPercent,
            color: _primaryPurple,
          ),
          const SizedBox(height: 14),
          _DimensionBar(
            label: 'Pemantauan (Monitoring)',
            score: result.scoreMonitoring,
            percent: result.monitoringPercent,
            color: _teal,
          ),
          const SizedBox(height: 14),
          _DimensionBar(
            label: 'Evaluasi (Evaluating)',
            score: result.scoreEvaluating,
            percent: result.evaluatingPercent,
            color: _amber,
          ),
        ],
      ),
    );
  }

  // ── Interpretation Card ─────────────────────────────────────

  Widget _buildInterpretationCard(AssessmentResult result) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Interpretasi
          Row(
            children: [
              Icon(Icons.psychology_outlined,
                  color: _primaryPurple.withOpacity(0.7), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Interpretasi Metakognitif',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _primaryPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            result.interpretationText,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Colors.grey[700],
            ),
          ),

          const Divider(height: 28),

          // Kekuatan
          _InsightRow(
            icon: Icons.check_circle_outline_rounded,
            iconColor: const Color(0xFF10B981),
            title: 'Kekuatan Utama',
            text: result.strengthText,
          ),

          const Divider(height: 28),

          // Area pembenahan
          _InsightRow(
            icon: Icons.cancel_outlined,
            iconColor: const Color(0xFFEF4444),
            title: 'Area Pembenahan',
            text: result.improvementText,
          ),

          const Divider(height: 28),

          // Saran strategis
          _InsightRow(
            icon: Icons.lightbulb_outline_rounded,
            iconColor: _amber,
            title: 'Saran Tindakan Strategis',
            text: result.strategicTip,
          ),
        ],
      ),
    );
  }

  // ── Continue Button ─────────────────────────────────────────

  Widget _buildContinueButton(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      color: Colors.white,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: () async {
            ref.read(baselineProvider.notifier).reset();
            // Sign out dulu → lalu ke Login
            // User harus login ulang untuk akses Dashboard
            try {
              await PushNotificationService().deactivateCurrentToken();
              await Supabase.instance.client.auth.signOut();
            } catch (_) {}
            if (context.mounted) context.go('/login');
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryPurple,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Selesai & Masuk ke Aplikasi',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.login_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Subwidget: Category Badge ──────────────────────────────────

class _CategoryBadge extends StatelessWidget {
  final String category;
  const _CategoryBadge({required this.category});

  Color get _bgColor {
    switch (category) {
      case 'Tinggi':
        return const Color(0xFFD1FAE5);
      case 'Sedang':
        return const Color(0xFFFEF3C7);
      default:
        return const Color(0xFFFEE2E2);
    }
  }

  Color get _textColor {
    switch (category) {
      case 'Tinggi':
        return const Color(0xFF065F46);
      case 'Sedang':
        return const Color(0xFF92400E);
      default:
        return const Color(0xFF991B1B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Regulasi Diri: $category',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: _textColor,
        ),
      ),
    );
  }
}

// ── Subwidget: Dimension Progress Bar ─────────────────────────

class _DimensionBar extends StatelessWidget {
  final String label;
  final int score;
  final double percent;
  final Color color;

  const _DimensionBar({
    required this.label,
    required this.score,
    required this.percent,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (percent * 100).toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ),
            Text(
              '$score/20 ($pct%)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

// ── Subwidget: Insight Row ──────────────────────────────────────

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String text;

  const _InsightRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: iconColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }
}

// ── Custom Painter: Arc (Circular Score) ───────────────────────

class _ArcPainter extends CustomPainter {
  final double progress;
  const _ArcPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 14.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    const startAngle = -2.356194; // -135°
    const fullSweep = 4.712389;   // 270°

    // Track (background)
    final trackPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      fullSweep,
      false,
      trackPaint,
    );

    if (progress <= 0) return;

    // Purple arc (0 – 50%)
    final purplePaint = Paint()
      ..color = const Color(0xFF5C4DFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Teal arc (50% – 100%)
    final tealPaint = Paint()
      ..color = const Color(0xFF4ECDC4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final half = fullSweep / 2;
    if (progress <= 0.5) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        fullSweep * progress,
        false,
        purplePaint,
      );
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        half,
        false,
        purplePaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + half,
        fullSweep * (progress - 0.5),
        false,
        tealPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.progress != progress;
}
