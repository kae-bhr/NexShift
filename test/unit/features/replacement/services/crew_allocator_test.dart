/// Tests unitaires du CrewAllocator
/// Vérifie la logique d'allocation d'équipages aux véhicules
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexshift_app/features/replacement/services/crew_allocator.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/trucks_model.dart';
import 'package:nexshift_app/core/data/models/crew_position_model.dart';

void main() {
  group('CrewAllocator', () {
    // Helpers pour créer des données de test
    User createAgent({
      required String id,
      required List<String> skills,
    }) {
      return User(
        id: id,
        firstName: 'Agent',
        lastName: id,
        station: 'Test',
        status: 'active',
        admin: false,
        team: 'A',
        skills: skills,
      );
    }

    CrewPosition createPosition({
      required String id,
      required String label,
      required List<String> requiredSkills,
      List<String> fallbackSkills = const [],
    }) {
      return CrewPosition(
        id: id,
        label: label,
        requiredSkills: requiredSkills,
        fallbackSkills: fallbackSkills,
      );
    }

    test('PositionAssignment: Agent assigné correctement', () {
      // ARRANGE
      final position = createPosition(
        id: 'chef',
        label: 'Chef d\'agrès',
        requiredSkills: ['FDF2'],
      );

      final agent = createAgent(id: 'alice', skills: ['FDF2', 'INC']);

      // ACT
      final assignment = PositionAssignment(
        position: position,
        assignedAgent: agent,
        isFallback: false,
      );

      // ASSERT
      expect(assignment.isFilled, isTrue);
      expect(assignment.assignedAgent, equals(agent));
      expect(assignment.isFallback, isFalse);
    });

    test('PositionAssignment: Poste non rempli', () {
      // ARRANGE
      final position = createPosition(
        id: 'chef',
        label: 'Chef d\'agrès',
        requiredSkills: ['FDF2'],
      );

      // ACT
      final assignment = PositionAssignment(position: position);

      // ASSERT
      expect(assignment.isFilled, isFalse);
      expect(assignment.assignedAgent, isNull);
    });

    test('CrewResult: Statut green pour équipage complet', () {
      // ARRANGE
      final truck = Truck(
        id: 1,
        displayNumber: 1,
        type: 'VSAV',
        station: 'Station Test',
      );

      final agents = [
        createAgent(id: 'alice', skills: ['FDF2']),
        createAgent(id: 'bob', skills: ['FDF1']),
      ];

      final positions = [
        createPosition(id: 'chef', label: 'Chef', requiredSkills: ['FDF2']),
        createPosition(id: 'equi', label: 'Équipier', requiredSkills: ['FDF1']),
      ];

      final assignments = [
        PositionAssignment(position: positions[0], assignedAgent: agents[0]),
        PositionAssignment(position: positions[1], assignedAgent: agents[1]),
      ];

      // ACT
      final result = CrewResult(
        truck: truck,
        crew: agents,
        positions: assignments,
        status: VehicleStatus.green,
        statusLabel: 'Équipage complet',
      );

      // ASSERT
      expect(result.status, equals(VehicleStatus.green));
      expect(result.statusLabel, equals('Équipage complet'));
      expect(result.crew.length, equals(2));
      expect(result.isRestrictedMode, isFalse);
    });

    test('CrewResult: Statut orange pour mode restreint (prompt secours)', () {
      // ARRANGE
      final truck = Truck(
        id: 2,
        displayNumber: 1,
        type: 'FPT',
        station: 'Station Test',
      );

      final agents = [
        createAgent(id: 'alice', skills: ['FDF2', 'COD1']),
        createAgent(id: 'bob', skills: ['FDF2']),
      ];

      final missingPositions = [
        createPosition(id: 'sap', label: 'SAP', requiredSkills: ['SAP1']),
      ];

      // ACT
      final result = CrewResult(
        truck: truck,
        crew: agents,
        positions: [],
        missingForFull: missingPositions,
        status: VehicleStatus.orange,
        statusLabel: 'Prompt secours (4H)',
        isRestrictedMode: true,
      );

      // ASSERT
      expect(result.status, equals(VehicleStatus.orange));
      expect(result.statusLabel, contains('Prompt secours'));
      expect(result.isRestrictedMode, isTrue);
      expect(result.missingForFull.length, equals(1));
    });

    test('CrewResult: Statut red pour équipage incomplet', () {
      // ARRANGE
      final truck = Truck(
        id: 3,
        displayNumber: 1,
        type: 'VSAV',
        station: 'Station Test',
      );

      // ACT
      final result = CrewResult(
        truck: truck,
        crew: [],
        positions: [],
        status: VehicleStatus.red,
        statusLabel: 'Équipage incomplet',
      );

      // ASSERT
      expect(result.status, equals(VehicleStatus.red));
      expect(result.statusLabel, equals('Équipage incomplet'));
      expect(result.crew.isEmpty, isTrue);
    });

    test('CrewResult: Statut grey pour véhicule non géré', () {
      // ARRANGE
      final truck = Truck(
        id: 4,
        displayNumber: 1,
        type: 'UNKNOWN',
        station: 'Station Test',
      );

      // ACT
      final result = CrewResult(
        truck: truck,
        crew: [],
        positions: [],
        status: VehicleStatus.grey,
        statusLabel: 'Type de véhicule non géré',
      );

      // ASSERT
      expect(result.status, equals(VehicleStatus.grey));
      expect(result.statusLabel, contains('non géré'));
    });

    // NOTE: Les tests suivants nécessitent d'accéder aux méthodes privées
    // (_findAndConsumeForPosition) qui ne sont pas accessibles directement.
    // Ces tests seront implémentés via allocateVehicleCrew avec des mocks
    // de VehicleRulesRepository pour tester indirectement cette logique.
    //
    // Tests à implémenter avec mockito :
    // - Optimisation: Agent avec moins de compétences sélectionné en premier
    // - Priorité: Agent avec compétences requises prioritaire sur fallback
    // - Fallback: Agent avec fallback skills accepté si pas de requis
    // - Échec allocation: Aucun agent qualifié disponible
    // - Consommation: Agent retiré de la liste après allocation

    test('Tri véhicules: Respect de l\'ordre de priorité', () {
      // ARRANGE
      final specs = [
        {'type': 'FPT', 'id': 1, 'period': '6H'},
        {'type': 'VSAV', 'id': 2},
        {'type': 'VTU', 'id': 1},
        {'type': 'FPT', 'id': 1, 'period': '4H'},
        {'type': 'VSAV', 'id': 1},
      ];

      // ACT
      final sorted = CrewAllocator.sortVehicleSpecs(specs);

      // ASSERT
      // Ordre attendu : VSAV1, VSAV2, VTU1, FPT1_4H, FPT1_6H
      expect(sorted[0]['type'], equals('VSAV'));
      expect(sorted[0]['id'], equals(1));

      expect(sorted[1]['type'], equals('VSAV'));
      expect(sorted[1]['id'], equals(2));

      expect(sorted[2]['type'], equals('VTU'));
      expect(sorted[2]['id'], equals(1));

      expect(sorted[3]['type'], equals('FPT'));
      expect(sorted[3]['id'], equals(1));
      expect(sorted[3]['period'], equals('4H'));

      expect(sorted[4]['type'], equals('FPT'));
      expect(sorted[4]['id'], equals(1));
      expect(sorted[4]['period'], equals('6H'));
    });

    // NOTE: Les tests suivants nécessitent des mocks pour VehicleRulesRepository
    // car ils dépendent de Firestore. Ils seront marqués comme skippés pour l'instant.

    test(
      'Allocation réelle: Équipage complet VSAV (2 agents)',
      () async {
        // Ce test nécessite VehicleRulesRepository mocké
        // TODO: Implémenter avec mockito quand les règles de véhicules seront mockables
      },
      skip: 'Nécessite mock de VehicleRulesRepository',
    );

    test(
      'Allocation réelle: Mode restreint FPT (prompt secours)',
      () async {
        // Ce test nécessite VehicleRulesRepository mocké
        // TODO: Implémenter avec mockito quand les règles de véhicules seront mockables
      },
      skip: 'Nécessite mock de VehicleRulesRepository',
    );

    test(
      'Allocation multiple: Plusieurs véhicules avec pool partagé',
      () async {
        // Ce test nécessite VehicleRulesRepository mocké
        // TODO: Implémenter avec mockito quand les règles de véhicules seront mockables
      },
      skip: 'Nécessite mock de VehicleRulesRepository',
    );
  });
}
