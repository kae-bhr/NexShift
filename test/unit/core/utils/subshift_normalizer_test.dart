import 'package:flutter_test/flutter_test.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/utils/subshift_normalizer.dart';

void main() {
  group('resolveReplacementCascades', () {
    test('should resolve and split cascade: C remplace B, B remplace A', () {
      // Arrange
      final now = DateTime.now();
      final planningId = 'planning-1';

      final subshifts = [
        Subshift(
          id: 'sub-1',
          replacedId: 'A',
          replacerId: 'B',
          start: now,
          end: now.add(const Duration(hours: 2)),
          planningId: planningId,
        ),
        Subshift(
          id: 'sub-2',
          replacedId: 'B',
          replacerId: 'C',
          start: now.add(const Duration(hours: 1)),
          end: now.add(const Duration(hours: 2)),
          planningId: planningId,
        ),
      ];

      // Act
      final result = resolveReplacementCascades(subshifts);

      // Assert - devrait être découpé en 2 segments
      expect(result.length, 2);

      // B remplace A de 20h à 21h (découpé)
      expect(result[0].replacedId, 'A');
      expect(result[0].replacerId, 'B');
      expect(result[0].start, now);
      expect(result[0].end, now.add(const Duration(hours: 1)));

      // C remplace A de 21h à 22h
      expect(result[1].replacedId, 'A');
      expect(result[1].replacerId, 'C');
      expect(result[1].start, now.add(const Duration(hours: 1)));
      expect(result[1].end, now.add(const Duration(hours: 2)));
    });

    test('should resolve triple cascade with proper time splitting', () {
      // Arrange
      final now = DateTime.now();
      final planningId = 'planning-1';

      // B remplace A de 20h à 23h
      // C remplace B de 21h à 22h
      // Résultat attendu :
      // - B remplace A de 20h à 21h
      // - C remplace A de 21h à 22h
      // - B remplace A de 22h à 23h
      final subshifts = [
        Subshift(
          id: 'sub-1',
          replacedId: 'A',
          replacerId: 'B',
          start: now,
          end: now.add(const Duration(hours: 3)),
          planningId: planningId,
        ),
        Subshift(
          id: 'sub-2',
          replacedId: 'B',
          replacerId: 'C',
          start: now.add(const Duration(hours: 1)),
          end: now.add(const Duration(hours: 2)),
          planningId: planningId,
        ),
      ];

      // Act
      final result = resolveReplacementCascades(subshifts);

      // Assert - devrait être découpé en 3 segments
      expect(result.length, 3);

      // B remplace A de 20h à 21h
      expect(result[0].replacedId, 'A');
      expect(result[0].replacerId, 'B');
      expect(result[0].start, now);
      expect(result[0].end, now.add(const Duration(hours: 1)));

      // C remplace A de 21h à 22h
      expect(result[1].replacedId, 'A');
      expect(result[1].replacerId, 'C');
      expect(result[1].start, now.add(const Duration(hours: 1)));
      expect(result[1].end, now.add(const Duration(hours: 2)));

      // B remplace A de 22h à 23h
      expect(result[2].replacedId, 'A');
      expect(result[2].replacerId, 'B');
      expect(result[2].start, now.add(const Duration(hours: 2)));
      expect(result[2].end, now.add(const Duration(hours: 3)));
    });

    test('should handle independent replacements (no cascade)', () {
      // Arrange
      final now = DateTime.now();
      final planningId = 'planning-1';

      final subshifts = [
        Subshift(
          id: 'sub-1',
          replacedId: 'A',
          replacerId: 'B',
          start: now,
          end: now.add(const Duration(hours: 2)),
          planningId: planningId,
        ),
        Subshift(
          id: 'sub-2',
          replacedId: 'C',
          replacerId: 'D',
          start: now,
          end: now.add(const Duration(hours: 2)),
          planningId: planningId,
        ),
      ];

      // Act
      final result = resolveReplacementCascades(subshifts);

      // Assert
      expect(result.length, 2);

      // Les deux devraient rester inchangés
      expect(result[0].replacedId, 'A');
      expect(result[0].replacerId, 'B');

      expect(result[1].replacedId, 'C');
      expect(result[1].replacerId, 'D');
    });

    test('should handle overlapping replacements correctly', () {
      // Arrange
      final now = DateTime.now();
      final planningId = 'planning-1';

      // A remplacé par B de 10h à 14h
      // B remplacé par C de 11h à 13h
      // Résultat attendu :
      // - B remplace A de 10h à 11h
      // - C remplace A de 11h à 13h
      // - B remplace A de 13h à 14h
      final subshifts = [
        Subshift(
          id: 'sub-1',
          replacedId: 'A',
          replacerId: 'B',
          start: now,
          end: now.add(const Duration(hours: 4)),
          planningId: planningId,
        ),
        Subshift(
          id: 'sub-2',
          replacedId: 'B',
          replacerId: 'C',
          start: now.add(const Duration(hours: 1)),
          end: now.add(const Duration(hours: 3)),
          planningId: planningId,
        ),
      ];

      // Act
      final result = resolveReplacementCascades(subshifts);

      // Assert
      expect(result.length, 3);
      expect(result[0].replacerId, 'B');
      expect(result[0].start, now);
      expect(result[0].end, now.add(const Duration(hours: 1)));

      expect(result[1].replacerId, 'C');
      expect(result[1].start, now.add(const Duration(hours: 1)));
      expect(result[1].end, now.add(const Duration(hours: 3)));

      expect(result[2].replacerId, 'B');
      expect(result[2].start, now.add(const Duration(hours: 3)));
      expect(result[2].end, now.add(const Duration(hours: 4)));
    });

    test('should return empty list for empty input', () {
      // Act
      final result = resolveReplacementCascades([]);

      // Assert
      expect(result, isEmpty);
    });
  });
}
