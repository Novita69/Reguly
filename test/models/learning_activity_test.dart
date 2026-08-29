// test/models/learning_activity_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_learning_tracker/models/learning_activity.dart';

void main() {
  group('LearningActivity.fromMap', () {
    test('parses a complete map correctly', () {
      final map = {
        'id': 'act-1',
        'user_id': 'user-1',
        'goal_id': 'goal-1',
        'activity_name': 'Membaca Paper',
        'category': 'Penelitian',
        'activity_date': '2026-07-04',
        'start_time': '09:30',
        'duration_minutes': 45,
        'focus_score': 4,
        'progress_percent': 50.0,
        'notes': 'Catatan singkat',
        'source_type': 'manual',
        'created_at': '2026-07-04T09:30:00.000Z',
      };

      final activity = LearningActivity.fromMap(map);

      expect(activity.id, 'act-1');
      expect(activity.userId, 'user-1');
      expect(activity.goalId, 'goal-1');
      expect(activity.activityName, 'Membaca Paper');
      expect(activity.category, 'Penelitian');
      expect(activity.activityDate, DateTime.parse('2026-07-04'));
      expect(activity.startTime, '09:30');
      expect(activity.durationMinutes, 45);
      expect(activity.focusScore, 4);
      expect(activity.progressPercent, 50.0);
      expect(activity.notes, 'Catatan singkat');
      expect(activity.sourceType, 'manual');
    });

    test('applies default category "Umum" when null', () {
      final map = {
        'id': 'act-2',
        'user_id': 'user-1',
        'goal_id': null,
        'activity_name': 'Tanpa kategori',
        'category': null,
        'activity_date': '2026-07-01',
        'start_time': null,
        'duration_minutes': 20,
        'focus_score': 3,
        'progress_percent': null,
        'notes': null,
        'source_type': null,
        'created_at': '2026-07-01T00:00:00.000Z',
      };

      final activity = LearningActivity.fromMap(map);

      expect(activity.category, 'Umum');
      expect(activity.sourceType, 'manual');
      expect(activity.progressPercent, 0.0);
      expect(activity.goalId, isNull);
      expect(activity.notes, isNull);
    });

    test('converts integer progress_percent to double', () {
      final map = {
        'id': 'act-3',
        'user_id': 'user-1',
        'activity_name': 'Diskusi',
        'category': 'Diskusi',
        'activity_date': '2026-07-02',
        'duration_minutes': 30,
        'focus_score': 5,
        'progress_percent': 75, // int, bukan double
        'source_type': 'focus_session',
        'created_at': '2026-07-02T00:00:00.000Z',
      };

      final activity = LearningActivity.fromMap(map);

      expect(activity.progressPercent, 75.0);
      expect(activity.progressPercent, isA<double>());
    });
  });

  group('LearningActivity.focusEmoji dan focusLabel', () {
    final cases = {
      1: ('😞', 'Sangat Buruk'),
      2: ('😐', 'Kurang Baik'),
      3: ('🙂', 'Cukup'),
      4: ('🤩', 'Bagus'),
      5: ('🚀', 'Luar Biasa'),
    };

    for (final entry in cases.entries) {
      test('skor ${entry.key} menghasilkan emoji dan label yang benar', () {
        final activity = _buildActivity(focusScore: entry.key);
        expect(activity.focusEmoji, entry.value.$1);
        expect(activity.focusLabel, entry.value.$2);
      });
    }

    test('skor di luar 1-5 jatuh ke kasus default (Luar Biasa/🚀)', () {
      final activity = _buildActivity(focusScore: 99);
      expect(activity.focusEmoji, '🚀');
      expect(activity.focusLabel, 'Luar Biasa');
    });
  });

  group('LearningActivity.formattedDate', () {
    test('memformat tanggal dengan padding dua digit', () {
      final activity = _buildActivity(date: DateTime(2026, 1, 5));
      expect(activity.formattedDate, '2026-01-05');
    });

    test('tidak menambah padding berlebih untuk tanggal dua digit', () {
      final activity = _buildActivity(date: DateTime(2026, 12, 25));
      expect(activity.formattedDate, '2026-12-25');
    });
  });

  test('kActivityCategories berisi daftar kategori yang diharapkan', () {
    expect(kActivityCategories, contains('Penelitian'));
    expect(kActivityCategories, contains('Lainnya'));
    expect(kActivityCategories.length, 7);
  });
}

LearningActivity _buildActivity({
  int focusScore = 3,
  DateTime? date,
}) {
  return LearningActivity(
    id: 'x',
    userId: 'u',
    activityName: 'Aktivitas',
    category: 'Umum',
    activityDate: date ?? DateTime(2026, 7, 4),
    durationMinutes: 30,
    focusScore: focusScore,
    progressPercent: 0,
    sourceType: 'manual',
    createdAt: DateTime(2026, 7, 4),
  );
}
