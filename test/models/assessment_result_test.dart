// test/models/assessment_result_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_learning_tracker/models/assessment_result.dart';

Map<String, dynamic> _rawMap({
  int scorePlanning = 15,
  int scoreMonitoring = 15,
  int scoreEvaluating = 15,
  int? scoreTotal,
}) {
  return {
    'id': 'assess-1',
    'user_id': 'user-1',
    'assessment_type': 'baseline',
    'assessment_sequence': 1,
    'item_01': 4, 'item_02': 4, 'item_03': 4, 'item_04': 4,
    'item_05': 4, 'item_06': 4, 'item_07': 4, 'item_08': 4,
    'item_09': 4, 'item_10': 4, 'item_11': 4, 'item_12': 4,
    'score_planning': scorePlanning,
    'score_monitoring': scoreMonitoring,
    'score_evaluating': scoreEvaluating,
    'score_total': scoreTotal ?? (scorePlanning + scoreMonitoring + scoreEvaluating),
    'completed_at': '2026-07-04T10:00:00.000Z',
  };
}

void main() {
  group('AssessmentResult.fromMap', () {
    test('parses 12 item jawaban dengan urutan yang benar', () {
      final map = _rawMap();
      map['item_03'] = 2;
      map['item_11'] = 5;

      final result = AssessmentResult.fromMap(map);

      expect(result.items.length, 12);
      expect(result.items[2], 2); // item_03 -> index 2
      expect(result.items[10], 5); // item_11 -> index 10
    });

    test('assessment_sequence default ke 1 jika null', () {
      final map = _rawMap();
      map['assessment_sequence'] = null;
      final result = AssessmentResult.fromMap(map);
      expect(result.assessmentSequence, 1);
    });
  });

  group('AssessmentResult.category (total 12-60)', () {
    test('Tinggi untuk skor total >= 45', () {
      final result = AssessmentResult.fromMap(_rawMap(
        scorePlanning: 15, scoreMonitoring: 15, scoreEvaluating: 15, scoreTotal: 45));
      expect(result.category, 'Tinggi');
    });

    test('Sedang untuk skor total di rentang 29-44', () {
      final result = AssessmentResult.fromMap(_rawMap(
        scorePlanning: 10, scoreMonitoring: 10, scoreEvaluating: 9, scoreTotal: 29));
      expect(result.category, 'Sedang');
    });

    test('Rendah untuk skor total < 29', () {
      final result = AssessmentResult.fromMap(_rawMap(
        scorePlanning: 8, scoreMonitoring: 8, scoreEvaluating: 8, scoreTotal: 24));
      expect(result.category, 'Rendah');
    });
  });

  group('Kategori per dimensi (4-20)', () {
    test('Tinggi untuk skor dimensi >= 15', () {
      final result = AssessmentResult.fromMap(_rawMap(scorePlanning: 15));
      expect(result.planningCategory, 'Tinggi');
    });

    test('Sedang untuk skor dimensi 10-14', () {
      final result = AssessmentResult.fromMap(_rawMap(scoreMonitoring: 10));
      expect(result.monitoringCategory, 'Sedang');
    });

    test('Rendah untuk skor dimensi < 10', () {
      final result = AssessmentResult.fromMap(_rawMap(scoreEvaluating: 9));
      expect(result.evaluatingCategory, 'Rendah');
    });
  });

  test('persentase per dimensi dan total dihitung benar', () {
    final result = AssessmentResult.fromMap(_rawMap(
      scorePlanning: 10, scoreMonitoring: 20, scoreEvaluating: 15, scoreTotal: 45));
    expect(result.planningPercent, 10 / 20.0);
    expect(result.monitoringPercent, 20 / 20.0);
    expect(result.evaluatingPercent, 15 / 20.0);
    expect(result.totalPercent, 45 / 60.0);
  });

  group('strongestDimension dan weakestDimension', () {
    test('mengenali dimensi dengan skor tertinggi', () {
      final result = AssessmentResult.fromMap(_rawMap(
        scorePlanning: 18, scoreMonitoring: 10, scoreEvaluating: 8, scoreTotal: 36));
      expect(result.strongestDimension, 'Perencanaan');
      expect(result.weakestDimension, 'Evaluasi');
    });

    test('mengenali Pemantauan sebagai dimensi terkuat', () {
      final result = AssessmentResult.fromMap(_rawMap(
        scorePlanning: 8, scoreMonitoring: 18, scoreEvaluating: 10, scoreTotal: 36));
      expect(result.strongestDimension, 'Pemantauan');
    });

    test('saat semua skor sama, tie-break konsisten (Perencanaan menang)', () {
      final result = AssessmentResult.fromMap(_rawMap(
        scorePlanning: 12, scoreMonitoring: 12, scoreEvaluating: 12, scoreTotal: 36));
      expect(result.strongestDimension, 'Perencanaan');
      expect(result.weakestDimension, 'Perencanaan');
    });
  });

  group('Teks interpretasi mengikuti kategori', () {
    test('kategori Tinggi menyebut kata "Tinggi" pada interpretasi', () {
      final result = AssessmentResult.fromMap(_rawMap(
        scorePlanning: 15, scoreMonitoring: 15, scoreEvaluating: 15, scoreTotal: 45));
      expect(result.interpretationText, contains('Tinggi'));
    });

    test('kategori Sedang menyebut kata "Sedang" pada interpretasi', () {
      final result = AssessmentResult.fromMap(_rawMap(
        scorePlanning: 10, scoreMonitoring: 10, scoreEvaluating: 10, scoreTotal: 30));
      expect(result.interpretationText, contains('Sedang'));
    });

    test('kategori Rendah menyebut kata "Rendah" pada interpretasi', () {
      final result = AssessmentResult.fromMap(_rawMap(
        scorePlanning: 6, scoreMonitoring: 6, scoreEvaluating: 6, scoreTotal: 18));
      expect(result.interpretationText, contains('Rendah'));
    });
  });

  group('strengthText, improvementText, dan strategicTip mengikuti dimensi', () {
    test('dimensi Perencanaan sebagai kelemahan mengarahkan ke Goal Setting', () {
      final result = AssessmentResult.fromMap(_rawMap(
        scorePlanning: 6, scoreMonitoring: 15, scoreEvaluating: 15, scoreTotal: 36));
      expect(result.weakestDimension, 'Perencanaan');
      expect(result.strategicTip, contains('Goal Setting'));
      expect(result.improvementText, isNotEmpty);
    });

    test('dimensi Pemantauan sebagai kelemahan mengarahkan ke Sesi Fokus', () {
      final result = AssessmentResult.fromMap(_rawMap(
        scorePlanning: 15, scoreMonitoring: 6, scoreEvaluating: 15, scoreTotal: 36));
      expect(result.weakestDimension, 'Pemantauan');
      expect(result.strategicTip, contains('Sesi Fokus'));
    });

    test('dimensi Evaluasi sebagai kelemahan mengarahkan ke Refleksi Mingguan', () {
      final result = AssessmentResult.fromMap(_rawMap(
        scorePlanning: 15, scoreMonitoring: 15, scoreEvaluating: 6, scoreTotal: 36));
      expect(result.weakestDimension, 'Evaluasi');
      expect(result.strategicTip, contains('Refleksi Mingguan'));
    });

    test('strengthText mengikuti dimensi terkuat (Perencanaan)', () {
      final result = AssessmentResult.fromMap(_rawMap(
        scorePlanning: 18, scoreMonitoring: 10, scoreEvaluating: 10, scoreTotal: 38));
      expect(result.strongestDimension, 'Perencanaan');
      expect(result.strengthText, isNotEmpty);
    });
  });
}
