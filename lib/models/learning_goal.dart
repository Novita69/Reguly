// lib/models/learning_goal.dart

class LearningGoal {
  final String id;
  final String userId;
  final String title;
  final String category;
  final DateTime periodStart;
  final DateTime periodEnd; // WAJIB -- deadline dibutuhkan untuk W2/W3/W5 di monitoring, dan agar fitur ini benar-benar membantu manajemen waktu.
  final int targetSessions;
  final int targetDurationMinutes;
  final double targetProgress;
  final String status; // 'active' | 'completed' | 'paused'
  final int actualSessions;
  final double actualProgress;
  final DateTime createdAt;

  const LearningGoal({
    required this.id,
    required this.userId,
    required this.title,
    required this.category,
    required this.periodStart,
    required this.periodEnd,
    required this.targetSessions,
    required this.targetDurationMinutes,
    required this.targetProgress,
    required this.status,
    required this.actualSessions,
    required this.actualProgress,
    required this.createdAt,
  });

  factory LearningGoal.fromMap(Map<String, dynamic> m) => LearningGoal(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        title: m['title'] as String,
        category: m['category'] as String? ?? 'Umum',
        periodStart: DateTime.parse(m['period_start'] as String),
        periodEnd: DateTime.parse(m['period_end'] as String),
        targetSessions: m['target_sessions'] as int,
        targetDurationMinutes: m['target_duration'] as int,
        targetProgress: (m['target_progress'] as num).toDouble(),
        status: m['status'] as String,
        actualSessions: m['actual_sessions'] as int? ?? 0,
        actualProgress: (m['actual_progress'] as num? ?? 0).toDouble(),
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  double get sessionProgressFraction =>
      targetSessions == 0 ? 0 : (actualSessions / targetSessions).clamp(0.0, 1.0);

  bool get isCompleted => status == 'completed' || actualProgress >= 100;

  bool get isOverdue =>
      DateTime.now().isAfter(periodEnd) &&
      !isCompleted;

  String get progressLabel =>
      '$actualSessions/$targetSessions Sesi (${(sessionProgressFraction * 100).toStringAsFixed(0)}%)';
}