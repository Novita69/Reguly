// test/models/persona_info_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ai_learning_tracker/models/persona_and_recommendation.dart';

Map<String, dynamic> _rawMap({String labelId = 'consistent'}) => {
      'id': 'persona-1',
      'user_id': 'user-1',
      'persona_label_id': labelId,
      'week_start': '2026-06-29',
      'is_current': true,
      'feature_values': {'x1': 0.8, 'x2': 0.6},
      'centroid_values': {'x1': 0.75, 'x2': 0.55},
      'assigned_at': '2026-06-29T00:00:00.000Z',
    };

void main() {
  group('PersonaInfo.fromMap', () {
    test('parses feature_values dan centroid_values sebagai Map<String,double>', () {
      final persona = PersonaInfo.fromMap(_rawMap());
      expect(persona.featureValues['x1'], 0.8);
      expect(persona.featureValues['x2'], 0.6);
      expect(persona.centroidValues['x1'], 0.75);
      expect(persona.isCurrent, isTrue);
    });

    test('default is_current ke false dan map kosong saat field null', () {
      final map = _rawMap();
      map['is_current'] = null;
      map['feature_values'] = null;
      map['centroid_values'] = null;

      final persona = PersonaInfo.fromMap(map);

      expect(persona.isCurrent, isFalse);
      expect(persona.featureValues, isEmpty);
      expect(persona.centroidValues, isEmpty);
    });
  });

  group('Konten tampilan berdasarkan labelId', () {
    test('consistent -> Pembelajaran Konsisten', () {
      final persona = PersonaInfo.fromMap(_rawMap(labelId: 'consistent'));
      expect(persona.displayName, 'Pembelajaran Konsisten');
      expect(persona.shortDescription, isNotEmpty);
      expect(persona.characteristics, isNotEmpty);
      expect(persona.strengths, isNotEmpty);
      expect(persona.aiTips, isNotEmpty);
      expect(persona.color, const Color(0xFF5C4DFF));
    });

    test('passive -> Pembelajaran Pasif', () {
      final persona = PersonaInfo.fromMap(_rawMap(labelId: 'passive'));
      expect(persona.displayName, 'Pembelajaran Pasif');
      expect(persona.characteristics, isNotEmpty);
      expect(persona.color, const Color(0xFFF59E0B));
    });

    test('seasonal -> Pembelajaran Musiman', () {
      final persona = PersonaInfo.fromMap(_rawMap(labelId: 'seasonal'));
      expect(persona.displayName, 'Pembelajaran Musiman');
      expect(persona.color, const Color(0xFF4ECDC4));
    });

    test('ambitious -> Pembelajaran Ambisius-Tertinggal', () {
      final persona = PersonaInfo.fromMap(_rawMap(labelId: 'ambitious'));
      expect(persona.displayName, 'Pembelajaran Ambisius-Tertinggal');
      expect(persona.color, const Color(0xFFEF4444));
    });

    test('labelId tidak dikenali -> fallback "Belum Dianalisis" dengan list kosong', () {
      final persona = PersonaInfo.fromMap(_rawMap(labelId: 'unknown_label'));
      expect(persona.displayName, 'Belum Dianalisis');
      expect(persona.characteristics, isEmpty);
      expect(persona.strengths, isEmpty);
      expect(persona.aiTips, isEmpty);
      expect(persona.color, const Color(0xFF9CA3AF));
    });
  });
}
