// test/models/recommendation_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_learning_tracker/models/persona_and_recommendation.dart';

Map<String, dynamic> _rawMap({
  String msrDimension = 'planning',
  int? priority,
  bool? isCompleted,
  bool? isDismissed,
}) =>
    {
      'id': 'rec-1',
      'user_id': 'user-1',
      'msr_dimension': msrDimension,
      'title': 'Buat jadwal belajar harian',
      'ai_insight': 'Skor perencanaan Anda masih rendah minggu ini.',
      'strategy': 'Time blocking',
      'action': 'Tulis 3 target belajar setiap pagi.',
      'reflection_question': 'Apa target belajar Anda hari ini?',
      'is_completed': isCompleted,
      'is_dismissed': isDismissed,
      'viewed_at': null,
      'completed_at': null,
      'created_at': '2026-07-04T00:00:00.000Z',
      'priority': priority,
    };

void main() {
  group('Recommendation.fromMap', () {
    test('parses field yang lengkap dengan benar', () {
      final rec = Recommendation.fromMap(_rawMap(priority: 1, isCompleted: true));
      expect(rec.id, 'rec-1');
      expect(rec.msrDimension, 'planning');
      expect(rec.title, 'Buat jadwal belajar harian');
      expect(rec.priority, 1);
      expect(rec.isCompleted, isTrue);
      expect(rec.viewedAt, isNull);
      expect(rec.completedAt, isNull);
    });

    test('default isCompleted/isDismissed ke false dan priority ke 2 saat null', () {
      final rec = Recommendation.fromMap(_rawMap());
      expect(rec.isCompleted, isFalse);
      expect(rec.isDismissed, isFalse);
      expect(rec.priority, 2);
    });

    test('mem-parse viewed_at dan completed_at ketika tersedia', () {
      final map = _rawMap();
      map['viewed_at'] = '2026-07-04T08:00:00.000Z';
      map['completed_at'] = '2026-07-04T09:00:00.000Z';
      final rec = Recommendation.fromMap(map);
      expect(rec.viewedAt, DateTime.parse('2026-07-04T08:00:00.000Z'));
      expect(rec.completedAt, DateTime.parse('2026-07-04T09:00:00.000Z'));
    });
  });

  group('dimensionDisplay', () {
    test('planning -> PERENCANAAN', () {
      expect(Recommendation.fromMap(_rawMap(msrDimension: 'planning')).dimensionDisplay,
          'PERENCANAAN');
    });
    test('monitoring -> PEMANTAUAN', () {
      expect(Recommendation.fromMap(_rawMap(msrDimension: 'monitoring')).dimensionDisplay,
          'PEMANTAUAN');
    });
    test('evaluating -> EVALUASI', () {
      expect(Recommendation.fromMap(_rawMap(msrDimension: 'evaluating')).dimensionDisplay,
          'EVALUASI');
    });
    test('dimensi tak dikenal -> ditampilkan uppercase apa adanya', () {
      expect(Recommendation.fromMap(_rawMap(msrDimension: 'lainnya')).dimensionDisplay,
          'LAINNYA');
    });
  });

  group('priorityDisplay', () {
    test('priority 1 -> PRIORITAS TINGGI', () {
      expect(Recommendation.fromMap(_rawMap(priority: 1)).priorityDisplay,
          'PRIORITAS TINGGI');
    });
    test('priority 2 -> PRIORITAS SEDANG', () {
      expect(Recommendation.fromMap(_rawMap(priority: 2)).priorityDisplay,
          'PRIORITAS SEDANG');
    });
    test('priority 3 (atau lainnya) -> PRIORITAS RENDAH', () {
      expect(Recommendation.fromMap(_rawMap(priority: 3)).priorityDisplay,
          'PRIORITAS RENDAH');
    });
  });

  group('copyWith', () {
    test('hanya memperbarui field yang diberikan, sisanya tetap sama', () {
      final original = Recommendation.fromMap(_rawMap(priority: 1));
      final now = DateTime(2026, 7, 4, 12, 0);

      final updated = original.copyWith(isCompleted: true, completedAt: now);

      expect(updated.isCompleted, isTrue);
      expect(updated.completedAt, now);
      // field lain tidak berubah
      expect(updated.id, original.id);
      expect(updated.title, original.title);
      expect(updated.msrDimension, original.msrDimension);
      expect(updated.priority, original.priority);
      expect(updated.isDismissed, original.isDismissed);
    });

    test('tanpa argumen, copyWith mengembalikan salinan identik', () {
      final original = Recommendation.fromMap(_rawMap());
      final copy = original.copyWith();
      expect(copy.isCompleted, original.isCompleted);
      expect(copy.viewedAt, original.viewedAt);
      expect(copy.completedAt, original.completedAt);
    });
  });
}
