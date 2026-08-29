// test/models/learning_goal_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_learning_tracker/models/learning_goal.dart';

void main() {
  group('LearningGoal.fromMap', () {
    test('parses a complete map correctly', () {
      final map = {
        'id': 'goal-1',
        'user_id': 'user-1',
        'title': 'Selesaikan Bab 3 Skripsi',
        'category': 'Penelitian',
        'period_start': '2026-07-01',
        'period_end': '2026-07-31',
        'target_sessions': 10,
        'target_duration': 300,
        'target_progress': 100.0,
        'status': 'active',
        'actual_sessions': 4,
        'actual_progress': 40.0,
        'created_at': '2026-07-01T00:00:00.000Z',
      };

      final goal = LearningGoal.fromMap(map);

      expect(goal.id, 'goal-1');
      expect(goal.title, 'Selesaikan Bab 3 Skripsi');
      expect(goal.category, 'Penelitian');
      expect(goal.periodStart, DateTime.parse('2026-07-01'));
      expect(goal.periodEnd, DateTime.parse('2026-07-31'));
      expect(goal.targetSessions, 10);
      expect(goal.targetDurationMinutes, 300);
      expect(goal.targetProgress, 100.0);
      expect(goal.status, 'active');
      expect(goal.actualSessions, 4);
      expect(goal.actualProgress, 40.0);
    });

    test('period_end null menghasilkan periodEnd null (tanpa batas waktu)', () {
      final map = {
        'id': 'goal-2',
        'user_id': 'user-1',
        'title': 'Belajar Flutter',
        'category': 'Lainnya',
        'period_start': '2026-07-01',
        'period_end': null,
        'target_sessions': 5,
        'target_duration': 100,
        'target_progress': 100.0,
        'status': 'active',
        'created_at': '2026-07-01T00:00:00.000Z',
      };

      final goal = LearningGoal.fromMap(map);

      expect(goal.periodEnd, isNull);
      expect(goal.actualSessions, 0);
      expect(goal.actualProgress, 0.0);
    });
  });

  group('LearningGoal.sessionProgressFraction', () {
    test('menghitung fraksi normal', () {
      final goal = _buildGoal(targetSessions: 4, actualSessions: 2);
      expect(goal.sessionProgressFraction, 0.5);
    });

    test('clamp ke maksimal 1.0 walau sesi aktual melebihi target', () {
      final goal = _buildGoal(targetSessions: 4, actualSessions: 10);
      expect(goal.sessionProgressFraction, 1.0);
    });

    test('menghasilkan 0 saat targetSessions 0 (menghindari pembagian nol)', () {
      final goal = _buildGoal(targetSessions: 0, actualSessions: 0);
      expect(goal.sessionProgressFraction, 0.0);
    });
  });

  group('LearningGoal.isCompleted', () {
    test('true ketika status "completed"', () {
      final goal = _buildGoal(status: 'completed', actualProgress: 10);
      expect(goal.isCompleted, isTrue);
    });

    test('true ketika actualProgress mencapai 100 walau status masih active', () {
      final goal = _buildGoal(status: 'active', actualProgress: 100);
      expect(goal.isCompleted, isTrue);
    });

    test('false ketika status active dan progress belum 100', () {
      final goal = _buildGoal(status: 'active', actualProgress: 50);
      expect(goal.isCompleted, isFalse);
    });
  });

  group('LearningGoal.isOverdue', () {
    test('true jika periodEnd sudah lewat dan belum selesai', () {
      final goal = _buildGoal(
        status: 'active',
        actualProgress: 50,
        periodEnd: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(goal.isOverdue, isTrue);
    });

    test('false jika periodEnd null (tanpa batas waktu)', () {
      final goal = _buildGoal(status: 'active', actualProgress: 50, periodEnd: null);
      expect(goal.isOverdue, isFalse);
    });

    test('false jika periodEnd belum lewat', () {
      final goal = _buildGoal(
        status: 'active',
        actualProgress: 50,
        periodEnd: DateTime.now().add(const Duration(days: 3)),
      );
      expect(goal.isOverdue, isFalse);
    });

    test('false jika sudah selesai walau periodEnd sudah lewat', () {
      final goal = _buildGoal(
        status: 'completed',
        actualProgress: 100,
        periodEnd: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(goal.isOverdue, isFalse);
    });
  });

  test('progressLabel memformat "actual/target Sesi (persen%)"', () {
    final goal = _buildGoal(targetSessions: 4, actualSessions: 3);
    expect(goal.progressLabel, '3/4 Sesi (75%)');
  });
}

LearningGoal _buildGoal({
  int targetSessions = 4,
  int actualSessions = 0,
  double actualProgress = 0,
  String status = 'active',
  DateTime? periodEnd,
}) {
  return LearningGoal(
    id: 'g',
    userId: 'u',
    title: 'Target belajar',
    category: 'Umum',
    periodStart: DateTime(2026, 7, 1),
    periodEnd: periodEnd,
    targetSessions: targetSessions,
    targetDurationMinutes: 60,
    targetProgress: 100.0,
    status: status,
    actualSessions: actualSessions,
    actualProgress: actualProgress,
    createdAt: DateTime(2026, 7, 1),
  );
}
