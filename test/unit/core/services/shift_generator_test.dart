/// Tests unitaires du ShiftGenerator
/// Vérifie la logique de génération de plannings d'astreintes
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexshift_app/core/services/shift_generator.dart';
import 'package:nexshift_app/core/data/models/shift_rule_model.dart';
import 'package:nexshift_app/core/data/models/shift_exception_model.dart';
import 'package:nexshift_app/core/data/models/generated_shift_model.dart';

void main() {
  group('ShiftGenerator', () {
    late ShiftGenerator generator;

    setUp(() {
      generator = ShiftGenerator();
    });

    // Helpers pour créer des données de test
    ShiftRule createRule({
      required String id,
      required String name,
      required TimeOfDay startTime,
      required TimeOfDay endTime,
      bool spansNextDay = false,
      required ShiftRotationType rotationType,
      required List<String> teamIds,
      int rotationIntervalDays = 1,
      DaysOfWeek applicableDays = DaysOfWeek.all,
      required DateTime startDate,
      DateTime? endDate,
      int priority = 0,
      bool isActive = true,
    }) {
      return ShiftRule(
        id: id,
        name: name,
        startTime: startTime,
        endTime: endTime,
        spansNextDay: spansNextDay,
        rotationType: rotationType,
        teamIds: teamIds,
        rotationIntervalDays: rotationIntervalDays,
        applicableDays: applicableDays,
        isActive: isActive,
        startDate: startDate,
        endDate: endDate,
        priority: priority,
      );
    }

    ShiftException createException({
      required DateTime startDateTime,
      required DateTime endDateTime,
      String? teamId,
      String reason = 'Test exception',
    }) {
      return ShiftException(
        id: 'exc-${DateTime.now().millisecondsSinceEpoch}',
        startDateTime: startDateTime,
        endDateTime: endDateTime,
        teamId: teamId,
        reason: reason,
      );
    }

    test('Génération simple: Rotation quotidienne 2 équipes sur 3 jours', () {
      // ARRANGE
      final rule = createRule(
        id: 'rule-1',
        name: 'Garde 24h',
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 8, minute: 0),
        spansNextDay: true,
        rotationType: ShiftRotationType.daily,
        teamIds: ['A', 'B'],
        startDate: DateTime(2025, 1, 1),
        applicableDays: DaysOfWeek.all,
      );

      final startDate = DateTime(2025, 1, 1);
      final endDate = DateTime(2025, 1, 3);

      // ACT
      final shifts = generator.generateShifts(
        rules: [rule],
        exceptions: [],
        startDate: startDate,
        endDate: endDate,
      );

      // ASSERT
      expect(shifts.length, equals(3)); // 3 jours = 3 astreintes
      expect(shifts[0].teamId, equals('A')); // Jour 1 = Équipe A
      expect(shifts[1].teamId, equals('B')); // Jour 2 = Équipe B
      expect(shifts[2].teamId, equals('A')); // Jour 3 = Équipe A (rotation)

      // Vérifier les horaires
      expect(shifts[0].startDateTime, equals(DateTime(2025, 1, 1, 8, 0)));
      expect(shifts[0].endDateTime, equals(DateTime(2025, 1, 2, 8, 0)));
    });

    test('Rotation hebdomadaire: 3 équipes sur 4 semaines', () {
      // ARRANGE
      final rule = createRule(
        id: 'rule-2',
        name: 'Garde hebdo',
        startTime: const TimeOfDay(hour: 0, minute: 0),
        endTime: const TimeOfDay(hour: 23, minute: 59),
        rotationType: ShiftRotationType.weekly,
        teamIds: ['A', 'B', 'C'],
        startDate: DateTime(2025, 1, 6), // Lundi
        applicableDays: DaysOfWeek.weekdays, // Lun-Ven
      );

      final startDate = DateTime(2025, 1, 6);
      final endDate = DateTime(2025, 2, 2); // 4 semaines

      // ACT
      final shifts = generator.generateShifts(
        rules: [rule],
        exceptions: [],
        startDate: startDate,
        endDate: endDate,
      );

      // ASSERT
      // 4 semaines * 5 jours = 20 astreintes
      expect(shifts.length, equals(20));

      // Semaine 1 (6-10 jan) = Équipe A
      expect(shifts[0].teamId, equals('A'));
      expect(shifts[4].teamId, equals('A'));

      // Semaine 2 (13-17 jan) = Équipe B
      expect(shifts[5].teamId, equals('B'));
      expect(shifts[9].teamId, equals('B'));

      // Semaine 3 (20-24 jan) = Équipe C
      expect(shifts[10].teamId, equals('C'));

      // Semaine 4 (27-31 jan) = Équipe A (rotation)
      expect(shifts[15].teamId, equals('A'));
    });

    test('Jours applicables: Seulement weekend', () {
      // ARRANGE
      final rule = createRule(
        id: 'rule-3',
        name: 'Garde weekend',
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 20, minute: 0),
        rotationType: ShiftRotationType.daily,
        teamIds: ['A', 'B'],
        startDate: DateTime(2025, 1, 1), // Mercredi
        applicableDays: DaysOfWeek.weekend, // Sam-Dim seulement
      );

      final startDate = DateTime(2025, 1, 1);
      final endDate = DateTime(2025, 1, 14); // 2 semaines

      // ACT
      final shifts = generator.generateShifts(
        rules: [rule],
        exceptions: [],
        startDate: startDate,
        endDate: endDate,
      );

      // ASSERT
      // 2 semaines * 2 jours weekend = 4 astreintes
      expect(shifts.length, equals(4));

      // Vérifier que tous les shifts sont le weekend
      for (final shift in shifts) {
        final weekday = shift.startDateTime.weekday;
        expect(
          weekday == DateTime.saturday || weekday == DateTime.sunday,
          isTrue,
          reason: 'Shift devrait être un weekend',
        );
      }
    });

    test('Fusion: Astreintes consécutives de la même équipe fusionnées', () {
      // ARRANGE
      // Deux règles adjacentes pour la même équipe
      final rule1 = createRule(
        id: 'rule-1',
        name: 'Nuit',
        startTime: const TimeOfDay(hour: 20, minute: 0),
        endTime: const TimeOfDay(hour: 8, minute: 0),
        spansNextDay: true,
        rotationType: ShiftRotationType.daily,
        teamIds: ['A'],
        startDate: DateTime(2025, 1, 1),
        applicableDays: DaysOfWeek.all,
      );

      final rule2 = createRule(
        id: 'rule-2',
        name: 'Jour',
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 20, minute: 0),
        rotationType: ShiftRotationType.daily,
        teamIds: ['A'],
        startDate: DateTime(2025, 1, 1),
        applicableDays: DaysOfWeek.all,
      );

      final startDate = DateTime(2025, 1, 1);
      final endDate = DateTime(2025, 1, 2);

      // ACT
      final shifts = generator.generateShifts(
        rules: [rule1, rule2],
        exceptions: [],
        startDate: startDate,
        endDate: endDate,
      );

      // ASSERT
      // 2 jours * 2 règles = 4 shifts bruts, triés chronologiquement
      // Fusion: jour 1 (8h-20h + 20h-8h) + jour 2 (8h-20h + 20h-8h) = 1 seul shift fusionné
      // car même équipe et consécutif
      expect(shifts.length, equals(1));

      // L'astreinte fusionnée doit couvrir du 8h du jour 1 au 8h du jour 3 (48h)
      expect(shifts[0].startDateTime, equals(DateTime(2025, 1, 1, 8, 0)));
      expect(shifts[0].endDateTime, equals(DateTime(2025, 1, 3, 8, 0)));

      // Le nom doit combiner les deux règles
      expect(shifts[0].ruleName, contains('+'));
    });

    test('Priorité: Règle avec priorité plus haute écrase règle priorité basse', () {
      // ARRANGE
      final ruleLowPriority = createRule(
        id: 'low',
        name: 'Règle basse priorité',
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 20, minute: 0),
        rotationType: ShiftRotationType.daily,
        teamIds: ['A'],
        startDate: DateTime(2025, 1, 1),
        priority: 10, // Priorité basse
      );

      final ruleHighPriority = createRule(
        id: 'high',
        name: 'Règle haute priorité',
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 20, minute: 0),
        rotationType: ShiftRotationType.daily,
        teamIds: ['B'],
        startDate: DateTime(2025, 1, 1),
        priority: 0, // Priorité haute
      );

      final startDate = DateTime(2025, 1, 1);
      final endDate = DateTime(2025, 1, 1);

      // ACT
      final shifts = generator.generateShifts(
        rules: [ruleLowPriority, ruleHighPriority],
        exceptions: [],
        startDate: startDate,
        endDate: endDate,
      );

      // ASSERT
      // La règle haute priorité est appliquée en premier
      expect(shifts[0].ruleId, equals('high'));
      expect(shifts[0].teamId, equals('B'));
    });

    test('Exception: Remplacement d\'équipe sur période spécifique', () {
      // ARRANGE
      final rule = createRule(
        id: 'rule-1',
        name: 'Garde normale',
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 8, minute: 0),
        spansNextDay: true,
        rotationType: ShiftRotationType.daily,
        teamIds: ['A'],
        startDate: DateTime(2025, 1, 1),
      );

      final exception = createException(
        startDateTime: DateTime(2025, 1, 2, 8, 0),
        endDateTime: DateTime(2025, 1, 3, 8, 0),
        teamId: 'B', // Équipe B remplace A
        reason: 'Congés équipe A',
      );

      final startDate = DateTime(2025, 1, 1);
      final endDate = DateTime(2025, 1, 3);

      // ACT
      final shifts = generator.generateShifts(
        rules: [rule],
        exceptions: [exception],
        startDate: startDate,
        endDate: endDate,
      );

      // ASSERT
      expect(shifts.length, equals(3));

      // Jour 1: Équipe A (normal)
      expect(shifts[0].teamId, equals('A'));
      expect(shifts[0].isException, isFalse);

      // Jour 2: Équipe B (exception)
      expect(shifts[1].teamId, equals('B'));
      expect(shifts[1].isException, isTrue);
      expect(shifts[1].exceptionReason, equals('Congés équipe A'));

      // Jour 3: Équipe A (normal)
      expect(shifts[2].teamId, equals('A'));
      expect(shifts[2].isException, isFalse);
    });

    test('Exception: Annulation d\'astreinte (teamId null)', () {
      // ARRANGE
      final rule = createRule(
        id: 'rule-1',
        name: 'Garde',
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 20, minute: 0),
        rotationType: ShiftRotationType.daily,
        teamIds: ['A'],
        startDate: DateTime(2025, 1, 1),
      );

      final exception = createException(
        startDateTime: DateTime(2025, 1, 2, 8, 0),
        endDateTime: DateTime(2025, 1, 2, 20, 0),
        teamId: null, // Annulation
        reason: 'Jour férié',
      );

      final startDate = DateTime(2025, 1, 1);
      final endDate = DateTime(2025, 1, 3);

      // ACT
      final shifts = generator.generateShifts(
        rules: [rule],
        exceptions: [exception],
        startDate: startDate,
        endDate: endDate,
      );

      // ASSERT
      // Seulement 2 shifts (jour 1 et 3), jour 2 annulé
      expect(shifts.length, equals(2));
      expect(shifts[0].startDateTime, equals(DateTime(2025, 1, 1, 8, 0)));
      expect(shifts[1].startDateTime, equals(DateTime(2025, 1, 3, 8, 0)));
    });

    test('Exception partielle: Découpage d\'astreinte', () {
      // ARRANGE
      final rule = createRule(
        id: 'rule-1',
        name: 'Garde 24h',
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 8, minute: 0),
        spansNextDay: true,
        rotationType: ShiftRotationType.daily,
        teamIds: ['A'],
        startDate: DateTime(2025, 1, 1),
      );

      // Exception au milieu de l'astreinte (14h-18h)
      final exception = createException(
        startDateTime: DateTime(2025, 1, 1, 14, 0),
        endDateTime: DateTime(2025, 1, 1, 18, 0),
        teamId: 'B',
        reason: 'Renfort équipe B',
      );

      final startDate = DateTime(2025, 1, 1);
      final endDate = DateTime(2025, 1, 1);

      // ACT
      final shifts = generator.generateShifts(
        rules: [rule],
        exceptions: [exception],
        startDate: startDate,
        endDate: endDate,
      );

      // ASSERT
      // 3 segments: avant exception (A), exception (B), après exception (A)
      expect(shifts.length, equals(3));

      // Segment 1: 8h-14h (Équipe A)
      expect(shifts[0].startDateTime, equals(DateTime(2025, 1, 1, 8, 0)));
      expect(shifts[0].endDateTime, equals(DateTime(2025, 1, 1, 14, 0)));
      expect(shifts[0].teamId, equals('A'));
      expect(shifts[0].isException, isFalse);

      // Segment 2: 14h-18h (Équipe B - exception)
      expect(shifts[1].startDateTime, equals(DateTime(2025, 1, 1, 14, 0)));
      expect(shifts[1].endDateTime, equals(DateTime(2025, 1, 1, 18, 0)));
      expect(shifts[1].teamId, equals('B'));
      expect(shifts[1].isException, isTrue);

      // Segment 3: 18h-8h (Équipe A)
      expect(shifts[2].startDateTime, equals(DateTime(2025, 1, 1, 18, 0)));
      expect(shifts[2].endDateTime, equals(DateTime(2025, 1, 2, 8, 0)));
      expect(shifts[2].teamId, equals('A'));
      expect(shifts[2].isException, isFalse);
    });

    test('Règle inactive: Non prise en compte dans génération', () {
      // ARRANGE
      final activeRule = createRule(
        id: 'active',
        name: 'Règle active',
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 20, minute: 0),
        rotationType: ShiftRotationType.daily,
        teamIds: ['A'],
        startDate: DateTime(2025, 1, 1),
        isActive: true,
      );

      final inactiveRule = createRule(
        id: 'inactive',
        name: 'Règle inactive',
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 20, minute: 0),
        rotationType: ShiftRotationType.daily,
        teamIds: ['B'],
        startDate: DateTime(2025, 1, 1),
        isActive: false, // Inactive
      );

      final startDate = DateTime(2025, 1, 1);
      final endDate = DateTime(2025, 1, 1);

      // ACT
      final shifts = generator.generateShifts(
        rules: [activeRule, inactiveRule],
        exceptions: [],
        startDate: startDate,
        endDate: endDate,
      );

      // ASSERT
      expect(shifts.length, equals(1));
      expect(shifts[0].ruleId, equals('active'));
      expect(shifts[0].teamId, equals('A'));
    });

    test('getShiftsForDate: Récupère astreintes pour une date spécifique', () {
      // ARRANGE
      final allShifts = [
        GeneratedShift(
          id: '1',
          startDateTime: DateTime(2025, 1, 1, 8, 0),
          endDateTime: DateTime(2025, 1, 1, 20, 0),
          teamId: 'A',
          ruleId: 'rule-1',
          ruleName: 'Jour',
          isException: false,
        ),
        GeneratedShift(
          id: '2',
          startDateTime: DateTime(2025, 1, 1, 20, 0),
          endDateTime: DateTime(2025, 1, 2, 8, 0),
          teamId: 'B',
          ruleId: 'rule-2',
          ruleName: 'Nuit',
          isException: false,
        ),
        GeneratedShift(
          id: '3',
          startDateTime: DateTime(2025, 1, 2, 8, 0),
          endDateTime: DateTime(2025, 1, 2, 20, 0),
          teamId: 'A',
          ruleId: 'rule-1',
          ruleName: 'Jour',
          isException: false,
        ),
      ];

      // ACT
      final shiftsForJan1 = generator.getShiftsForDate(
        allShifts,
        DateTime(2025, 1, 1),
      );
      final shiftsForJan2 = generator.getShiftsForDate(
        allShifts,
        DateTime(2025, 1, 2),
      );

      // ASSERT
      // 1er janvier: 2 astreintes (jour + nuit qui commence)
      expect(shiftsForJan1.length, equals(2));
      expect(shiftsForJan1[0].id, equals('1'));
      expect(shiftsForJan1[1].id, equals('2'));

      // 2 janvier: 2 astreintes (nuit qui se termine + jour)
      expect(shiftsForJan2.length, equals(2));
      expect(shiftsForJan2[0].id, equals('2')); // Nuit (se termine le 2)
      expect(shiftsForJan2[1].id, equals('3')); // Jour
    });

    test('getShiftsForTeam: Récupère astreintes pour une équipe', () {
      // ARRANGE
      final allShifts = [
        GeneratedShift(
          id: '1',
          startDateTime: DateTime(2025, 1, 1, 8, 0),
          endDateTime: DateTime(2025, 1, 2, 8, 0),
          teamId: 'A',
          ruleId: 'rule-1',
          ruleName: 'Garde',
          isException: false,
        ),
        GeneratedShift(
          id: '2',
          startDateTime: DateTime(2025, 1, 2, 8, 0),
          endDateTime: DateTime(2025, 1, 3, 8, 0),
          teamId: 'B',
          ruleId: 'rule-1',
          ruleName: 'Garde',
          isException: false,
        ),
        GeneratedShift(
          id: '3',
          startDateTime: DateTime(2025, 1, 3, 8, 0),
          endDateTime: DateTime(2025, 1, 4, 8, 0),
          teamId: 'A',
          ruleId: 'rule-1',
          ruleName: 'Garde',
          isException: false,
        ),
      ];

      // ACT
      final shiftsForTeamA = generator.getShiftsForTeam(allShifts, 'A');
      final shiftsForTeamB = generator.getShiftsForTeam(allShifts, 'B');

      // ASSERT
      expect(shiftsForTeamA.length, equals(2));
      expect(shiftsForTeamA[0].id, equals('1'));
      expect(shiftsForTeamA[1].id, equals('3'));

      expect(shiftsForTeamB.length, equals(1));
      expect(shiftsForTeamB[0].id, equals('2'));
    });

    test('Rotation mensuelle: 3 équipes sur 4 mois', () {
      // ARRANGE
      final rule = createRule(
        id: 'rule-monthly',
        name: 'Garde mensuelle',
        startTime: const TimeOfDay(hour: 0, minute: 0),
        endTime: const TimeOfDay(hour: 23, minute: 59),
        rotationType: ShiftRotationType.monthly,
        teamIds: ['A', 'B', 'C'],
        startDate: DateTime(2025, 1, 1),
        applicableDays: const DaysOfWeek(monday: true), // Seulement lundis
      );

      final startDate = DateTime(2025, 1, 1);
      final endDate = DateTime(2025, 4, 30);

      // ACT
      final shifts = generator.generateShifts(
        rules: [rule],
        exceptions: [],
        startDate: startDate,
        endDate: endDate,
      );

      // ASSERT
      // Vérifier qu'il y a des shifts et qu'ils tournent par équipe
      expect(shifts.isNotEmpty, isTrue);

      // Compter les lundis de janvier (équipe A), février (équipe B), mars (équipe C)
      final janShifts = shifts.where((s) => s.startDateTime.month == 1).toList();
      final febShifts = shifts.where((s) => s.startDateTime.month == 2).toList();
      final marShifts = shifts.where((s) => s.startDateTime.month == 3).toList();

      // Tous les lundis de janvier doivent être équipe A
      expect(janShifts.every((s) => s.teamId == 'A'), isTrue);
      // Tous les lundis de février doivent être équipe B
      expect(febShifts.every((s) => s.teamId == 'B'), isTrue);
      // Tous les lundis de mars doivent être équipe C
      expect(marShifts.every((s) => s.teamId == 'C'), isTrue);
    });
  });
}
