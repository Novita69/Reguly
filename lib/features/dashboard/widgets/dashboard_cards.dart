// lib/features/dashboard/widgets/dashboard_cards.dart
//
// File ini berisi semua kartu dashboard selain WeeklyProgressCard:
//   - SrlScoreCard
//   - PersonaPreviewCard
//   - StreakCard
//   - TodayGoalsCard
//   - QuickStatsRow
//   - WeeklyChartCard
//   - AiInsightsCard

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../providers/dashboard_provider.dart';

const _primaryPurple = Color(0xFF5C4DFF);
const _teal = Color(0xFF4ECDC4);
const _amber = Color(0xFFF59E0B);
const _rose = Color(0xFFEF4444);
const _indigo = Color(0xFF3B82F6);

// ╔══════════════════════════════════════════════════════════════╗
// ║  SrlScoreCard                                               ║
// ╚══════════════════════════════════════════════════════════════╝

class SrlScoreCard extends StatelessWidget {
  final DashboardData data;
  const SrlScoreCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.latestScore == null) {
      return _EmptyCard(
        icon: Icons.psychology_outlined,
        title: 'Skor Regulasi Diri',
        subtitle:
            'Selesaikan Penilaian Awal\nuntuk melihat skor regulasi dirimu.',
        onTap: () => context.push('/baseline'),
        actionLabel: 'Mulai Penilaian',
      );
    }

    final score = data.latestScore!;
    final delta = data.deltaTotal;
    final cat = data.scoreCategory ?? '';

    return _WhiteCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardLabel('ASESMEN TERKINI'),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Skor Regulasi Diri: ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      '$score/60',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _primaryPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (delta != null) _DeltaChip(delta: delta, category: cat),
                const SizedBox(height: 10),
                // Mini dimension bars
                if (data.scorePlanning != null) ...[
                  _MiniBar(
                      color: _primaryPurple, value: data.scorePlanning! / 20),
                  const SizedBox(height: 4),
                  _MiniBar(
                      color: _teal, value: (data.scoreMonitoring ?? 0) / 20),
                  const SizedBox(height: 4),
                  _MiniBar(
                      color: _amber, value: (data.scoreEvaluating ?? 0) / 20),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _primaryPurple.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.psychology_outlined,
                color: _primaryPurple, size: 26),
          ),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final int delta;
  final String category;
  const _DeltaChip({required this.delta, required this.category});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String text;

    if (delta > 0) {
      color = const Color(0xFF10B981);
      icon = Icons.arrow_upward_rounded;
      text = 'Naik $delta poin dari penilaian sebelumnya (Kategori: $category)';
    } else if (delta < 0) {
      color = const Color(0xFFEF4444);
      icon = Icons.arrow_downward_rounded;
      text = 'Turun ${delta.abs()} poin (Kategori: $category)';
    } else {
      color = const Color(0xFF6B7280);
      icon = Icons.remove_rounded;
      text = 'Tidak berubah (Kategori: $category)';
    }

    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MiniBar extends StatelessWidget {
  final Color color;
  final double value;
  const _MiniBar({required this.color, required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        backgroundColor: color.withOpacity(0.12),
        valueColor: AlwaysStoppedAnimation<Color>(color),
        minHeight: 6,
      ),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════╗
// ║  PersonaPreviewCard                                         ║
// ╚══════════════════════════════════════════════════════════════╝

class PersonaPreviewCard extends StatelessWidget {
  final DashboardData data;
  const PersonaPreviewCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final color = data.personaColor;
    return GestureDetector(
      onTap: () => context.push('/persona'),
      child: _WhiteCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.auto_awesome_outlined, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CardLabel('PERSONA PEMBELAJARAN'),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        data.personaDisplayName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      if (data.warningTierDisplayLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: data.warningTierColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            data.warningTierDisplayLabel!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: data.warningTierColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.personaDescription,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600], height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: Colors.grey[400], size: 22),
          ],
        ),
      ),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════╗
// ║  StreakCard                                                  ║
// ╚══════════════════════════════════════════════════════════════╝

class StreakCard extends StatelessWidget {
  final DashboardData data;
  const StreakCard({super.key, required this.data});

  static const _dayLabels = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  static const _dayInitials = ['S', 'S', 'R', 'K', 'J', 'S', 'M'];

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Flexible(
                child: Text(
                  'Rangkaian Belajar (Streak)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (data.streakDays > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '${data.streakDays} Hari ',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFEF6C00),
                  ),
                ),
                const Text('🔥', style: TextStyle(fontSize: 14)),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
                7,
                (i) => _DayCircle(
                      initial: _dayInitials[i],
                      label: _dayLabels[i],
                      isActive: data.weekStreak[i],
                      isToday: i == DateTime.now().weekday - 1,
                    )),
          ),
        ],
      ),
    );
  }
}

class _DayCircle extends StatelessWidget {
  final String initial;
  final String label;
  final bool isActive;
  final bool isToday;
  const _DayCircle({
    required this.initial,
    required this.label,
    required this.isActive,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isActive ? const Color(0xFFEF6C00) : Colors.grey[200]!;
    final fg = isActive ? Colors.white : Colors.grey[400]!;
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: isToday
                ? Border.all(color: const Color(0xFFEF6C00), width: 2)
                : null,
          ),
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
      ],
    );
  }
}

// ╔══════════════════════════════════════════════════════════════╗
// ║  TodayGoalsCard                                             ║
// ╚══════════════════════════════════════════════════════════════╝

class TodayGoalsCard extends StatelessWidget {
  final DashboardData data;
  const TodayGoalsCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.activeGoals.isEmpty) {
      return _EmptyCard(
        icon: Icons.flag_outlined,
        title: 'Target Belajar',
        subtitle:
            'Kamu belum punya target aktif.\nYuk tetapkan target belajarmu!',
        onTap: () => context.push('/goals'),
        actionLabel: 'Tambah Target',
      );
    }

    final total = data.activeGoals.length;
    final done = data.completedGoalsToday;

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Target Belajar Hari Ini',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const Spacer(),
              Text(
                '$done/$total Selesai',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _primaryPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...data.activeGoals.take(3).map((g) => _GoalRow(goal: g)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => context.push('/goals'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Lihat Semua Target',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  final GoalItem goal;
  const _GoalRow({required this.goal});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            // Sebelumnya pakai radio_button_unchecked_rounded — bentuknya
            // persis checkbox kosong padahal item ini cuma indikator status
            // (read-only, tidak bisa di-tap). Diganti ikon jam supaya jelas
            // ini "belum selesai", bukan tombol yang bisa dicentang manual.
            goal.isCompleted
                ? Icons.check_circle_rounded
                : Icons.schedule_rounded,
            color:
                goal.isCompleted ? const Color(0xFF10B981) : Colors.grey[400],
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              goal.title,
              style: TextStyle(
                fontSize: 14,
                color: goal.isCompleted
                    ? Colors.grey[400]
                    : const Color(0xFF1A1A2E),
                decoration:
                    goal.isCompleted ? TextDecoration.lineThrough : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${goal.targetDurationMinutes} M',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════╗
// ║  QuickStatsRow                                              ║
// ╚══════════════════════════════════════════════════════════════╝

class QuickStatsRow extends StatelessWidget {
  final DashboardData data;
  const QuickStatsRow({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Sesi Minggu Ini',
            value: '${data.weeklySessions} Sesi',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Total Durasi',
            value: '${data.weeklyTotalMinutes} Menit',
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════╗
// ║  WeeklyChartCard                                            ║
// ╚══════════════════════════════════════════════════════════════╝

// Menyimpulkan "kamu paling mirip persona apa, dan di variabel mana yang
// paling dekat" dari clusterComparison yang sudah dihitung provider --
// murni fungsi tampilan (tidak query apa pun), makanya hidup di sini
// (widget layer), bukan di provider -- sama seperti pola _generateInsights
// di dashboard_provider.dart yang juga murni mengolah data yang sudah ada
// jadi kalimat, tanpa menyentuh sumber data.
//
// "Paling mirip" dihitung lewat jarak Euclidean (akar dari jumlah kuadrat
// selisih tiap fitur) antara nilai user dan tiap centroid persona -- makin
// kecil jaraknya, makin dekat. Ini metrik yang SAMA dipakai K-Means sendiri
// untuk assignment cluster (lihat fungsi `euclidean` di
// run-kmeans/index.ts), jadi kesimpulan ini konsisten dengan bagaimana
// backend sebenarnya menentukan persona.
String? _computeClusterSummary(List<ClusterComparisonPoint> points) {
  if (points.isEmpty) return null;

  const personas = ['consistent', 'passive', 'seasonal', 'ambitious'];
  const personaDisplayNames = {
    'consistent': 'Consistent',
    'passive': 'Passive',
    'seasonal': 'Seasonal',
    'ambitious': 'Ambitious',
  };

  String? closestPersona;
  double closestDistance = double.infinity;
  for (final persona in personas) {
    var sumSquared = 0.0;
    for (final p in points) {
      final centroidVal = p.centroidByPersona[persona];
      if (centroidVal == null)
        return null; // data tidak lengkap, jangan menyimpulkan
      final diff = p.userNormalized - centroidVal;
      sumSquared += diff * diff;
    }
    final distance = math.sqrt(sumSquared);
    if (distance < closestDistance) {
      closestDistance = distance;
      closestPersona = persona;
    }
  }
  if (closestPersona == null) return null;

  // Variabel dengan selisih PALING KECIL ke centroid terdekat itu -- ini
  // yang disebut spesifik di kalimat, supaya user tahu bukan cuma "mirip
  // persona X" secara umum, tapi tahu persis di aspek mana kemiripannya.
  ClusterComparisonPoint? closestFeature;
  double closestFeatureDiff = double.infinity;
  for (final p in points) {
    final centroidVal = p.centroidByPersona[closestPersona]!;
    final diff = (p.userNormalized - centroidVal).abs();
    if (diff < closestFeatureDiff) {
      closestFeatureDiff = diff;
      closestFeature = p;
    }
  }

  final personaName = personaDisplayNames[closestPersona]!;
  if (closestFeature != null) {
    return 'Polamu paling mirip dengan $personaName — terutama di variabel '
        '${closestFeature.label}.';
  }
  return 'Polamu paling mirip dengan $personaName.';
}

class WeeklyChartCard extends StatelessWidget {
  final DashboardData data;
  const WeeklyChartCard({super.key, required this.data});

  static const _userColor = _primaryPurple;

  // Warna + urutan tetap untuk keempat centroid persona, konsisten dipakai
  // untuk garis DAN legenda. Key harus sama persis dengan
  // ClusterComparisonPoint.centroidByPersona ('consistent' dst).
  static const _personaMeta = [
    _PersonaMeta('consistent', 'Consistent', _teal),
    _PersonaMeta('passive', 'Passive', _amber),
    _PersonaMeta('seasonal', 'Seasonal', _rose),
    _PersonaMeta('ambitious', 'Ambitious', _indigo),
  ];

  @override
  Widget build(BuildContext context) {
    final points = data.clusterComparison;

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kamu vs pusat tiap persona',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Garis mana yang paling dekat dengan "Kamu" menunjukkan '
            'kenapa kamu masuk persona ${data.personaDisplayName}',
            style:
                TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.4),
          ),
          const SizedBox(height: 16),
          if (points.isEmpty)
            // persona_history belum ada, ATAU clustering_run terkait belum
            // punya cluster_labels (run lama sebelum migration ini ada --
            // lihat catatan di load()) -- tampilkan pesan jelas, bukan
            // grafik kosong/salah pemetaan.
            Container(
              height: 140,
              alignment: Alignment.center,
              child: Text(
                'Persona belum terbentuk. Catat aktivitas belajar lebih '
                'banyak untuk melihat perbandingan ini.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[500], height: 1.4),
              ),
            )
          else ...[
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 1.0,
                  lineBarsData: [
                    _buildLine(
                        points, _userColor, 3.5, (p) => p.userNormalized),
                    for (final meta in _personaMeta)
                      _buildLine(points, meta.color, 2,
                          (p) => p.centroidByPersona[meta.key] ?? 0),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= points.length)
                            return const SizedBox();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(points[i].label,
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey[500]),
                                textAlign: TextAlign.center),
                          );
                        },
                        reservedSize: 28,
                      ),
                    ),
                    leftTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 0.25,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: Colors.grey[100]!, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots.map((spot) {
                        final point = points[spot.x.toInt()];
                        final isUser = spot.barIndex == 0;
                        final text = isUser
                            ? 'Kamu: ${_rawValueText(point)}'
                            : _personaMeta[spot.barIndex - 1].displayName;
                        return LineTooltipItem(
                          text,
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _LegendDot(color: _userColor, label: 'Kamu', bold: true),
                for (final meta in _personaMeta)
                  _LegendDot(
                      color: meta.color, label: meta.displayName, bold: false),
              ],
            ),
            const SizedBox(height: 14),
            Builder(builder: (context) {
              final summary = _computeClusterSummary(points);
              if (summary == null) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: _primaryPurple.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  summary,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1A1A2E),
                    height: 1.4,
                  ),
                ),
              );
            }),
          ],
          GestureDetector(
            onTap: () => context.push('/recommendation'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Lihat Wawasan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _buildLine(
    List<ClusterComparisonPoint> points,
    Color color,
    double width,
    double Function(ClusterComparisonPoint) getValue,
  ) {
    return LineChartBarData(
      spots: points.asMap().entries.map((e) {
        return FlSpot(e.key.toDouble(), getValue(e.value));
      }).toList(),
      isCurved: true,
      color: color,
      barWidth: width,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: width > 3 ? 3.5 : 2.5, color: color, strokeWidth: 0),
      ),
      belowBarData: BarAreaData(show: false),
    );
  }

  // Nilai ASLI milik user (bukan yang dinormalisasi) untuk tooltip -- garis
  // "Kamu" di grafik pakai skala 0-1 supaya sebanding dengan centroid, tapi
  // angka yang berarti bagi pengguna tetap satuan aslinya.
  String _rawValueText(ClusterComparisonPoint p) {
    switch (p.label) {
      case 'Frekuensi':
        return '${p.userRaw.toInt()} ${p.rawUnit}';
      case 'Durasi':
        return '${p.userRaw.toInt()} ${p.rawUnit}';
      case 'Fokus':
        return '${p.userRaw.toStringAsFixed(1)}${p.rawUnit}';
      case 'Konsistensi':
        return '${p.userRaw.toInt()}${p.rawUnit}';
      case 'Progres':
        return '${p.userRaw.toInt()}${p.rawUnit}';
      default:
        return '${p.userRaw}';
    }
  }
}

class _PersonaMeta {
  final String key; // 'consistent' dst -- cocok dengan centroidByPersona
  final String displayName; // 'Consistent' dst -- untuk label UI
  final Color color;
  const _PersonaMeta(this.key, this.displayName, this.color);
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool bold;
  const _LegendDot(
      {required this.color, required this.label, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            )),
      ],
    );
  }
}

// Simpler AiInsightsCard without the transform hack
class AiInsightsCardSimple extends StatelessWidget {
  final DashboardData data;
  const AiInsightsCardSimple({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _primaryPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_outlined,
                    color: _primaryPurple, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Wawasan AI Hari Ini',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _primaryPurple,
                      ),
                    ),
                    Text(
                      'Strategi dipersonalisasi berdasarkan perilaku belajarmu minggu ini:',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[500], height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...data.aiInsights.map((insight) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: const BoxDecoration(
                        color: _primaryPurple,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '"$insight"',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          height: 1.55,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════╗
// ║  Shared Helpers                                             ║
// ╚══════════════════════════════════════════════════════════════╝

class _WhiteCard extends StatelessWidget {
  final Widget child;
  const _WhiteCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

class _CardLabel extends StatelessWidget {
  final String text;
  const _CardLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.grey[500],
        letterSpacing: 0.6,
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String actionLabel;

  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.grey[400], size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13, color: Colors.grey[500], height: 1.5),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: _primaryPurple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _primaryPurple.withOpacity(0.3)),
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _primaryPurple,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
