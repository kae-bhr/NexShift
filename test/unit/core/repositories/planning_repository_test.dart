/// Tests unitaires du PlanningRepository
/// Vérifie les opérations CRUD sur les plannings avec fake_cloud_firestore
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';

void main() {
  group('PlanningRepository', () {
    late FakeFirebaseFirestore fakeFirestore;
    late PlanningRepository repository;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      repository = PlanningRepository.forTest(fakeFirestore);
    });

    // Helper pour créer un planning de test
    Planning createTestPlanning({
      required String id,
      required DateTime startTime,
      required DateTime endTime,
      String station = 'Station Test',
      String team = 'A',
      List<String> agentsId = const [],
      int maxAgents = 6,
    }) {
      return Planning(
        id: id,
        startTime: startTime,
        endTime: endTime,
        station: station,
        team: team,
        agentsId: agentsId,
        maxAgents: maxAgents,
      );
    }

    test('save: Sauvegarde un planning dans Firestore', () async {
      // ARRANGE
      final planning = createTestPlanning(
        id: 'planning-1',
        startTime: DateTime(2025, 1, 1, 8, 0),
        endTime: DateTime(2025, 1, 1, 20, 0),
        agentsId: ['agent-1', 'agent-2'],
      );

      // ACT
      await repository.save(planning);

      // ASSERT
      final doc = await fakeFirestore.collection('plannings').doc('planning-1').get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['team'], equals('A'));
      expect(doc.data()?['station'], equals('Station Test'));

      // Vérifier la liste des agents
      final agentsId = (doc.data()?['agentsId'] as List).cast<String>();
      expect(agentsId.length, equals(2));
      expect(agentsId, contains('agent-1'));
      expect(agentsId, contains('agent-2'));
    });

    test('getById: Récupère un planning par ID', () async {
      // ARRANGE
      final planning = createTestPlanning(
        id: 'planning-2',
        startTime: DateTime(2025, 1, 2, 8, 0),
        endTime: DateTime(2025, 1, 2, 20, 0),
        team: 'B',
      );
      await repository.save(planning);

      // ACT
      final result = await repository.getById('planning-2');

      // ASSERT
      expect(result, isNotNull);
      expect(result!.id, equals('planning-2'));
      expect(result.team, equals('B'));
      expect(result.startTime, equals(DateTime(2025, 1, 2, 8, 0)));
      expect(result.endTime, equals(DateTime(2025, 1, 2, 20, 0)));
    });

    test('getById: Retourne null si planning inexistant', () async {
      // ACT
      final result = await repository.getById('inexistant');

      // ASSERT
      expect(result, isNull);
    });

    test('getAll: Récupère tous les plannings', () async {
      // ARRANGE
      final planning1 = createTestPlanning(
        id: 'p1',
        startTime: DateTime(2025, 1, 1, 8, 0),
        endTime: DateTime(2025, 1, 1, 20, 0),
      );
      final planning2 = createTestPlanning(
        id: 'p2',
        startTime: DateTime(2025, 1, 2, 8, 0),
        endTime: DateTime(2025, 1, 2, 20, 0),
      );
      final planning3 = createTestPlanning(
        id: 'p3',
        startTime: DateTime(2025, 1, 3, 8, 0),
        endTime: DateTime(2025, 1, 3, 20, 0),
      );

      await repository.save(planning1);
      await repository.save(planning2);
      await repository.save(planning3);

      // ACT
      final results = await repository.getAll();

      // ASSERT
      expect(results.length, equals(3));
      expect(results.map((p) => p.id), containsAll(['p1', 'p2', 'p3']));
    });

    test('delete: Supprime un planning', () async {
      // ARRANGE
      final planning = createTestPlanning(
        id: 'planning-to-delete',
        startTime: DateTime(2025, 1, 1, 8, 0),
        endTime: DateTime(2025, 1, 1, 20, 0),
      );
      await repository.save(planning);

      // Vérifier qu'il existe
      var result = await repository.getById('planning-to-delete');
      expect(result, isNotNull);

      // ACT
      await repository.delete('planning-to-delete');

      // ASSERT
      result = await repository.getById('planning-to-delete');
      expect(result, isNull);
    });

    test('getForUser: Filtre les plannings par utilisateur', () async {
      // ARRANGE
      final p1 = createTestPlanning(
        id: 'p1',
        startTime: DateTime(2025, 1, 1, 8, 0),
        endTime: DateTime(2025, 1, 1, 20, 0),
        agentsId: ['alice', 'bob'],
      );
      final p2 = createTestPlanning(
        id: 'p2',
        startTime: DateTime(2025, 1, 2, 8, 0),
        endTime: DateTime(2025, 1, 2, 20, 0),
        agentsId: ['charlie', 'david'],
      );
      final p3 = createTestPlanning(
        id: 'p3',
        startTime: DateTime(2025, 1, 3, 8, 0),
        endTime: DateTime(2025, 1, 3, 20, 0),
        agentsId: ['alice', 'charlie'],
      );

      await repository.save(p1);
      await repository.save(p2);
      await repository.save(p3);

      // ACT
      final alicePlannings = await repository.getForUser('alice');
      final bobPlannings = await repository.getForUser('bob');
      final charliePlannings = await repository.getForUser('charlie');

      // ASSERT
      expect(alicePlannings.length, equals(2)); // p1, p3
      expect(alicePlannings.map((p) => p.id), containsAll(['p1', 'p3']));

      expect(bobPlannings.length, equals(1)); // p1
      expect(bobPlannings.first.id, equals('p1'));

      expect(charliePlannings.length, equals(2)); // p2, p3
      expect(charliePlannings.map((p) => p.id), containsAll(['p2', 'p3']));
    });

    test('getForTeam: Filtre les plannings par équipe', () async {
      // ARRANGE
      final p1 = createTestPlanning(
        id: 'p1',
        startTime: DateTime(2025, 1, 1, 8, 0),
        endTime: DateTime(2025, 1, 1, 20, 0),
        team: 'A',
      );
      final p2 = createTestPlanning(
        id: 'p2',
        startTime: DateTime(2025, 1, 2, 8, 0),
        endTime: DateTime(2025, 1, 2, 20, 0),
        team: 'B',
      );
      final p3 = createTestPlanning(
        id: 'p3',
        startTime: DateTime(2025, 1, 3, 8, 0),
        endTime: DateTime(2025, 1, 3, 20, 0),
        team: 'A',
      );

      await repository.save(p1);
      await repository.save(p2);
      await repository.save(p3);

      // ACT
      final teamAPlannings = await repository.getForTeam('A');
      final teamBPlannings = await repository.getForTeam('B');

      // ASSERT
      expect(teamAPlannings.length, equals(2)); // p1, p3
      expect(teamAPlannings.map((p) => p.id), containsAll(['p1', 'p3']));

      expect(teamBPlannings.length, equals(1)); // p2
      expect(teamBPlannings.first.id, equals('p2'));
    });

    test('clear: Supprime tous les plannings', () async {
      // ARRANGE
      final p1 = createTestPlanning(
        id: 'p1',
        startTime: DateTime(2025, 1, 1, 8, 0),
        endTime: DateTime(2025, 1, 1, 20, 0),
      );
      final p2 = createTestPlanning(
        id: 'p2',
        startTime: DateTime(2025, 1, 2, 8, 0),
        endTime: DateTime(2025, 1, 2, 20, 0),
      );

      await repository.save(p1);
      await repository.save(p2);

      // Vérifier qu'ils existent
      var all = await repository.getAll();
      expect(all.length, equals(2));

      // ACT
      await repository.clear();

      // ASSERT
      all = await repository.getAll();
      expect(all.isEmpty, isTrue);
    });

    test('deleteFuturePlannings: Supprime plannings à partir d\'une date', () async {
      // ARRANGE
      final p1 = createTestPlanning(
        id: 'p1',
        startTime: DateTime(2025, 1, 1, 8, 0),
        endTime: DateTime(2025, 1, 1, 20, 0),
      );
      final p2 = createTestPlanning(
        id: 'p2',
        startTime: DateTime(2025, 1, 10, 8, 0),
        endTime: DateTime(2025, 1, 10, 20, 0),
      );
      final p3 = createTestPlanning(
        id: 'p3',
        startTime: DateTime(2025, 1, 20, 8, 0),
        endTime: DateTime(2025, 1, 20, 20, 0),
      );

      await repository.save(p1);
      await repository.save(p2);
      await repository.save(p3);

      // ACT
      await repository.deleteFuturePlannings(DateTime(2025, 1, 10));

      // ASSERT
      final remaining = await repository.getAll();
      expect(remaining.length, equals(1));
      expect(remaining.first.id, equals('p1'));
    });

    test('deletePlanningsInRange: Supprime plannings dans une plage', () async {
      // ARRANGE
      final p1 = createTestPlanning(
        id: 'p1',
        startTime: DateTime(2025, 1, 1, 8, 0),
        endTime: DateTime(2025, 1, 1, 20, 0),
      );
      final p2 = createTestPlanning(
        id: 'p2',
        startTime: DateTime(2025, 1, 10, 8, 0),
        endTime: DateTime(2025, 1, 10, 20, 0),
      );
      final p3 = createTestPlanning(
        id: 'p3',
        startTime: DateTime(2025, 1, 15, 8, 0),
        endTime: DateTime(2025, 1, 15, 20, 0),
      );
      final p4 = createTestPlanning(
        id: 'p4',
        startTime: DateTime(2025, 1, 25, 8, 0),
        endTime: DateTime(2025, 1, 25, 20, 0),
      );

      await repository.save(p1);
      await repository.save(p2);
      await repository.save(p3);
      await repository.save(p4);

      // ACT - Supprimer plannings entre le 10 et le 20 janvier
      await repository.deletePlanningsInRange(
        DateTime(2025, 1, 10),
        DateTime(2025, 1, 20),
      );

      // ASSERT
      final remaining = await repository.getAll();
      expect(remaining.length, equals(2));
      expect(remaining.map((p) => p.id), containsAll(['p1', 'p4']));
    });
  });
}
