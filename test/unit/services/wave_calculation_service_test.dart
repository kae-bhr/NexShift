/// Tests unitaires du service de calcul de vagues
/// Vérifie la logique de priorisation des notifications de remplacement
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexshift_app/core/services/wave_calculation_service.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';

void main() {
  group('WaveCalculationService', () {
    late WaveCalculationService service;

    setUp(() {
      service = WaveCalculationService();
    });

    // Helpers pour créer des utilisateurs de test
    User createTestUser({
      required String id,
      required String team,
      required List<String> skills,
    }) {
      return User(
        id: id,
        firstName: 'Test',
        lastName: 'User',
        station: 'Test Station',
        status: 'active',
        admin: false,
        team: team,
        skills: skills,
      );
    }

    test('Vague 0 : Agents en astreinte ne sont jamais notifiés', () {
      // ARRANGE
      final requester = createTestUser(
        id: 'requester',
        team: 'A',
        skills: ['FDF1', 'FDF2'],
      );

      final candidateInPlanning = createTestUser(
        id: 'candidate-planning',
        team: 'A',
        skills: ['FDF1', 'FDF2'],
      );

      // ACT
      final wave = service.calculateWave(
        requester: requester,
        candidate: candidateInPlanning,
        planningTeam: 'A',
        agentsInPlanning: ['candidate-planning'], // Agent dans le planning
        skillRarityWeights: {},
      );

      // ASSERT
      expect(wave, equals(0),
          reason: 'Les agents en astreinte doivent être en vague 0 (jamais notifiés)');
    });

    test('Vague 1 : Agents de la même équipe (hors astreinte)', () {
      // ARRANGE
      final requester = createTestUser(
        id: 'requester',
        team: 'A',
        skills: ['FDF1', 'FDF2'],
      );

      final candidateSameTeam = createTestUser(
        id: 'candidate-team',
        team: 'A', // Même équipe
        skills: ['FDF3', 'FDF4'], // Compétences différentes
      );

      // ACT
      final wave = service.calculateWave(
        requester: requester,
        candidate: candidateSameTeam,
        planningTeam: 'A',
        agentsInPlanning: [], // Pas dans le planning
        skillRarityWeights: {},
      );

      // ASSERT
      expect(wave, equals(1),
          reason: 'Les agents de la même équipe doivent être en vague 1');
    });

    test('Vague 2 : Compétences exactement identiques', () {
      // ARRANGE
      final requester = createTestUser(
        id: 'requester',
        team: 'A',
        skills: ['FDF1', 'FDF2', 'INC'],
      );

      final candidateSameSkills = createTestUser(
        id: 'candidate-same',
        team: 'B', // Équipe différente
        skills: ['FDF1', 'FDF2', 'INC'], // Compétences identiques
      );

      // ACT
      final wave = service.calculateWave(
        requester: requester,
        candidate: candidateSameSkills,
        planningTeam: 'A',
        agentsInPlanning: [],
        skillRarityWeights: {},
      );

      // ASSERT
      expect(wave, equals(2),
          reason: 'Les agents avec compétences identiques doivent être en vague 2');
    });

    test('Vague 2 : Ordre des compétences ne compte pas', () {
      // ARRANGE
      final requester = createTestUser(
        id: 'requester',
        team: 'A',
        skills: ['FDF1', 'FDF2', 'INC'],
      );

      final candidateDifferentOrder = createTestUser(
        id: 'candidate-order',
        team: 'B',
        skills: ['INC', 'FDF1', 'FDF2'], // Ordre différent, même contenu
      );

      // ACT
      final wave = service.calculateWave(
        requester: requester,
        candidate: candidateDifferentOrder,
        planningTeam: 'A',
        agentsInPlanning: [],
        skillRarityWeights: {},
      );

      // ASSERT
      expect(wave, equals(2),
          reason: 'L\'ordre des compétences ne doit pas affecter la vague');
    });

    test('Vague 3 : Compétences très proches (≥80% similarité)', () {
      // ARRANGE
      final requester = createTestUser(
        id: 'requester',
        team: 'A',
        skills: ['FDF1', 'FDF2', 'INC', 'SAP1', 'SAP2'], // 5 compétences
      );

      final candidateClose = createTestUser(
        id: 'candidate-close',
        team: 'B',
        skills: ['FDF1', 'FDF2', 'INC', 'SAP1'], // 4/5 = 80%
      );

      // ACT
      final wave = service.calculateWave(
        requester: requester,
        candidate: candidateClose,
        planningTeam: 'A',
        agentsInPlanning: [],
        skillRarityWeights: {},
      );

      // ASSERT
      expect(wave, equals(3),
          reason: 'Similarité ≥80% doit donner vague 3');
    });

    test('Vague 4 : Compétences relativement proches (≥60% similarité)', () {
      // ARRANGE
      final requester = createTestUser(
        id: 'requester',
        team: 'A',
        skills: ['FDF1', 'FDF2', 'INC', 'SAP1', 'SAP2'], // 5 compétences
      );

      final candidateSomewhatClose = createTestUser(
        id: 'candidate-somewhat',
        team: 'B',
        skills: ['FDF1', 'FDF2', 'INC'], // 3/5 = 60%
      );

      // ACT
      final wave = service.calculateWave(
        requester: requester,
        candidate: candidateSomewhatClose,
        planningTeam: 'A',
        agentsInPlanning: [],
        skillRarityWeights: {},
      );

      // ASSERT
      expect(wave, equals(4),
          reason: 'Similarité ≥60% doit donner vague 4');
    });

    test('Vague 5 : Compétences peu similaires (<60% similarité)', () {
      // ARRANGE
      final requester = createTestUser(
        id: 'requester',
        team: 'A',
        skills: ['FDF1', 'FDF2', 'INC', 'SAP1', 'SAP2'], // 5 compétences
      );

      final candidateDifferent = createTestUser(
        id: 'candidate-different',
        team: 'B',
        skills: ['FDF1', 'DIV'], // 1/5 = 20%
      );

      // ACT
      final wave = service.calculateWave(
        requester: requester,
        candidate: candidateDifferent,
        planningTeam: 'A',
        agentsInPlanning: [],
        skillRarityWeights: {},
      );

      // ASSERT
      expect(wave, equals(5),
          reason: 'Similarité <60% doit donner vague 5');
    });

    test('Vague 5 : Aucune compétence en commun', () {
      // ARRANGE
      final requester = createTestUser(
        id: 'requester',
        team: 'A',
        skills: ['FDF1', 'FDF2', 'INC'],
      );

      final candidateNoCommon = createTestUser(
        id: 'candidate-none',
        team: 'B',
        skills: ['SAP1', 'SAP2', 'DIV'], // Aucune en commun
      );

      // ACT
      final wave = service.calculateWave(
        requester: requester,
        candidate: candidateNoCommon,
        planningTeam: 'A',
        agentsInPlanning: [],
        skillRarityWeights: {},
      );

      // ASSERT
      expect(wave, equals(5),
          reason: 'Aucune compétence en commun doit donner vague 5');
    });

    test('Cas limite : Demandeur sans compétences', () {
      // ARRANGE
      final requesterNoSkills = createTestUser(
        id: 'requester',
        team: 'A',
        skills: [], // Aucune compétence
      );

      final candidate = createTestUser(
        id: 'candidate',
        team: 'B',
        skills: ['FDF1', 'FDF2'],
      );

      // ACT
      final wave = service.calculateWave(
        requester: requesterNoSkills,
        candidate: candidate,
        planningTeam: 'A',
        agentsInPlanning: [],
        skillRarityWeights: {},
      );

      // ASSERT
      // Sans compétences, devrait tomber en vague 5 (aucune similarité)
      expect(wave, equals(5),
          reason: 'Demandeur sans compétences doit donner vague 5');
    });

    test('Cas limite : Candidat sans compétences', () {
      // ARRANGE
      final requester = createTestUser(
        id: 'requester',
        team: 'A',
        skills: ['FDF1', 'FDF2'],
      );

      final candidateNoSkills = createTestUser(
        id: 'candidate',
        team: 'B',
        skills: [], // Aucune compétence
      );

      // ACT
      final wave = service.calculateWave(
        requester: requester,
        candidate: candidateNoSkills,
        planningTeam: 'A',
        agentsInPlanning: [],
        skillRarityWeights: {},
      );

      // ASSERT
      expect(wave, equals(5),
          reason: 'Candidat sans compétences doit donner vague 5');
    });

    test('Vague 1 prioritaire sur vague 2 (même équipe > mêmes compétences)', () {
      // ARRANGE
      final requester = createTestUser(
        id: 'requester',
        team: 'A',
        skills: ['FDF1', 'FDF2'],
      );

      final candidateSameTeamAndSkills = createTestUser(
        id: 'candidate',
        team: 'A', // Même équipe
        skills: ['FDF1', 'FDF2'], // Mêmes compétences
      );

      // ACT
      final wave = service.calculateWave(
        requester: requester,
        candidate: candidateSameTeamAndSkills,
        planningTeam: 'A',
        agentsInPlanning: [],
        skillRarityWeights: {},
      );

      // ASSERT
      expect(wave, equals(1),
          reason: 'Même équipe doit avoir priorité sur compétences identiques');
    });

    // SKIP: Pondération par rareté non encore implémentée dans WaveCalculationService
    // Activer ce test quand la fonctionnalité sera ajoutée
    test(
      'Pondération par rareté des compétences (compétences rares prioritaires)',
      () {
        // ARRANGE
        final requester = createTestUser(
          id: 'requester',
          team: 'A',
          skills: ['FDF1', 'RARE1', 'RARE2'],
        );

        final candidateWithRare = createTestUser(
          id: 'candidate-rare',
          team: 'B',
          skills: ['FDF1', 'RARE1'],
        );

        final candidateWithoutRare = createTestUser(
          id: 'candidate-common',
          team: 'B',
          skills: ['FDF1', 'FDF2'],
        );

        final skillRarityWeights = {
          'FDF1': 1,
          'FDF2': 1,
          'RARE1': 10,
          'RARE2': 10,
        };

        // ACT
        final waveWithRare = service.calculateWave(
          requester: requester,
          candidate: candidateWithRare,
          planningTeam: 'A',
          agentsInPlanning: [],
          skillRarityWeights: skillRarityWeights,
        );

        final waveWithoutRare = service.calculateWave(
          requester: requester,
          candidate: candidateWithoutRare,
          planningTeam: 'A',
          agentsInPlanning: [],
          skillRarityWeights: skillRarityWeights,
        );

        // ASSERT
        expect(waveWithRare, lessThan(waveWithoutRare),
            reason: 'Compétences rares doivent être prioritaires');
      },
      skip: 'Fonctionnalité de pondération non implémentée',
    );
  });
}
