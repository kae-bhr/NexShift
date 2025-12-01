/// Tests unitaires du TruckRepository
/// Vérifie les opérations CRUD sur les véhicules avec fake_cloud_firestore
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexshift_app/core/data/models/trucks_model.dart';
import 'package:nexshift_app/core/repositories/truck_repository.dart';

void main() {
  group('TruckRepository', () {
    late FakeFirebaseFirestore fakeFirestore;
    late TruckRepository repository;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      repository = TruckRepository.forTest(fakeFirestore);
    });

    // Helper pour créer un truck de test
    Truck createTestTruck({
      required int id,
      required int displayNumber,
      required String type,
      required String station,
      bool available = true,
      String? modeId,
    }) {
      return Truck(
        id: id,
        displayNumber: displayNumber,
        type: type,
        station: station,
        available: available,
        modeId: modeId,
      );
    }

    test('save: Sauvegarde un véhicule dans Firestore', () async {
      // ARRANGE
      final truck = createTestTruck(
        id: 1,
        displayNumber: 1,
        type: 'VSAV',
        station: 'Station Test',
      );

      // ACT
      await repository.save(truck);

      // ASSERT
      final doc = await fakeFirestore.collection('trucks').doc('1').get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['type'], equals('VSAV'));
      expect(doc.data()?['station'], equals('Station Test'));
      expect(doc.data()?['displayNumber'], equals(1));
      expect(doc.data()?['available'], equals(true));
    });

    test('getById: Récupère un véhicule par ID', () async {
      // ARRANGE
      final truck = createTestTruck(
        id: 2,
        displayNumber: 2,
        type: 'FPT',
        station: 'Station Alpha',
      );
      await repository.save(truck);

      // ACT
      final result = await repository.getById(2);

      // ASSERT
      expect(result, isNotNull);
      expect(result!.id, equals(2));
      expect(result.displayNumber, equals(2));
      expect(result.type, equals('FPT'));
      expect(result.station, equals('Station Alpha'));
    });

    test('getById: Retourne null si véhicule inexistant', () async {
      // ACT
      final result = await repository.getById(999);

      // ASSERT
      expect(result, isNull);
    });

    test('getAll: Récupère tous les véhicules', () async {
      // ARRANGE
      final truck1 = createTestTruck(
        id: 1,
        displayNumber: 1,
        type: 'VSAV',
        station: 'Station A',
      );
      final truck2 = createTestTruck(
        id: 2,
        displayNumber: 2,
        type: 'VSAV',
        station: 'Station A',
      );
      final truck3 = createTestTruck(
        id: 3,
        displayNumber: 1,
        type: 'FPT',
        station: 'Station B',
      );

      await repository.save(truck1);
      await repository.save(truck2);
      await repository.save(truck3);

      // ACT
      final results = await repository.getAll();

      // ASSERT
      expect(results.length, equals(3));
      expect(results.map((t) => t.id), containsAll([1, 2, 3]));
    });

    test('getByStation: Filtre les véhicules par station', () async {
      // ARRANGE
      final truck1 = createTestTruck(
        id: 1,
        displayNumber: 1,
        type: 'VSAV',
        station: 'Station Alpha',
      );
      final truck2 = createTestTruck(
        id: 2,
        displayNumber: 2,
        type: 'VSAV',
        station: 'Station Beta',
      );
      final truck3 = createTestTruck(
        id: 3,
        displayNumber: 1,
        type: 'FPT',
        station: 'Station Alpha',
      );

      await repository.save(truck1);
      await repository.save(truck2);
      await repository.save(truck3);

      // ACT
      final alphaVehicles = await repository.getByStation('Station Alpha');
      final betaVehicles = await repository.getByStation('Station Beta');

      // ASSERT
      expect(alphaVehicles.length, equals(2));
      expect(alphaVehicles.map((t) => t.id), containsAll([1, 3]));

      expect(betaVehicles.length, equals(1));
      expect(betaVehicles.first.id, equals(2));
    });

    test('delete: Supprime un véhicule', () async {
      // ARRANGE
      final truck = createTestTruck(
        id: 10,
        displayNumber: 1,
        type: 'VTU',
        station: 'Station Test',
      );
      await repository.save(truck);

      // Vérifier qu'il existe
      var result = await repository.getById(10);
      expect(result, isNotNull);

      // ACT
      await repository.delete(10);

      // ASSERT
      result = await repository.getById(10);
      expect(result, isNull);
    });

    test('clear: Supprime tous les véhicules', () async {
      // ARRANGE
      final truck1 = createTestTruck(
        id: 1,
        displayNumber: 1,
        type: 'VSAV',
        station: 'Station A',
      );
      final truck2 = createTestTruck(
        id: 2,
        displayNumber: 2,
        type: 'VSAV',
        station: 'Station A',
      );

      await repository.save(truck1);
      await repository.save(truck2);

      // Vérifier qu'ils existent
      var all = await repository.getAll();
      expect(all.length, equals(2));

      // ACT
      await repository.clear();

      // ASSERT
      all = await repository.getAll();
      expect(all.isEmpty, isTrue);
    });

    test('getNextId: Calcule le prochain ID disponible', () async {
      // ARRANGE - DB vide
      var nextId = await repository.getNextId();
      expect(nextId, equals(1));

      // Ajouter quelques véhicules
      await repository.save(createTestTruck(
        id: 1,
        displayNumber: 1,
        type: 'VSAV',
        station: 'Station A',
      ));
      await repository.save(createTestTruck(
        id: 5,
        displayNumber: 2,
        type: 'VSAV',
        station: 'Station A',
      ));
      await repository.save(createTestTruck(
        id: 3,
        displayNumber: 3,
        type: 'VSAV',
        station: 'Station A',
      ));

      // ACT
      nextId = await repository.getNextId();

      // ASSERT
      // Le prochain ID devrait être le max (5) + 1 = 6
      expect(nextId, equals(6));
    });

    test('getNextDisplayNumber: Calcule le prochain numéro d\'affichage par type',
        () async {
      // ARRANGE
      final station = 'Station Test';

      // Ajouter VSAV1, VSAV2
      await repository.save(createTestTruck(
        id: 1,
        displayNumber: 1,
        type: 'VSAV',
        station: station,
      ));
      await repository.save(createTestTruck(
        id: 2,
        displayNumber: 2,
        type: 'VSAV',
        station: station,
      ));

      // Ajouter FPT1
      await repository.save(createTestTruck(
        id: 3,
        displayNumber: 1,
        type: 'FPT',
        station: station,
      ));

      // ACT
      final nextVSAV = await repository.getNextDisplayNumber('VSAV', station);
      final nextFPT = await repository.getNextDisplayNumber('FPT', station);
      final nextVTU = await repository.getNextDisplayNumber('VTU', station);

      // ASSERT
      expect(nextVSAV, equals(3)); // VSAV3
      expect(nextFPT, equals(2)); // FPT2
      expect(nextVTU, equals(1)); // VTU1 (premier)
    });

    test('getNextDisplayNumber: Isolé par station', () async {
      // ARRANGE
      // Station A: VSAV1, VSAV2
      await repository.save(createTestTruck(
        id: 1,
        displayNumber: 1,
        type: 'VSAV',
        station: 'Station A',
      ));
      await repository.save(createTestTruck(
        id: 2,
        displayNumber: 2,
        type: 'VSAV',
        station: 'Station A',
      ));

      // Station B: VSAV1
      await repository.save(createTestTruck(
        id: 3,
        displayNumber: 1,
        type: 'VSAV',
        station: 'Station B',
      ));

      // ACT
      final nextStationA = await repository.getNextDisplayNumber('VSAV', 'Station A');
      final nextStationB = await repository.getNextDisplayNumber('VSAV', 'Station B');

      // ASSERT
      expect(nextStationA, equals(3)); // VSAV3 pour Station A
      expect(nextStationB, equals(2)); // VSAV2 pour Station B
    });

    test('Propriété available: True par défaut', () async {
      // ARRANGE
      final truck = createTestTruck(
        id: 1,
        displayNumber: 1,
        type: 'VSAV',
        station: 'Station Test',
      );

      // ACT
      await repository.save(truck);
      final result = await repository.getById(1);

      // ASSERT
      expect(result!.available, isTrue);
    });

    test('Propriété modeId: Peut être null ou défini', () async {
      // ARRANGE
      final truckWithoutMode = createTestTruck(
        id: 1,
        displayNumber: 1,
        type: 'VSAV',
        station: 'Station Test',
        modeId: null,
      );

      final truckWithMode = createTestTruck(
        id: 2,
        displayNumber: 2,
        type: 'FPT',
        station: 'Station Test',
        modeId: '4h',
      );

      // ACT
      await repository.save(truckWithoutMode);
      await repository.save(truckWithMode);

      final result1 = await repository.getById(1);
      final result2 = await repository.getById(2);

      // ASSERT
      expect(result1!.modeId, isNull);
      expect(result2!.modeId, equals('4h'));
    });

    test('displayName: Génère le nom d\'affichage correct', () async {
      // ARRANGE
      final truck = createTestTruck(
        id: 1,
        displayNumber: 2,
        type: 'VSAV',
        station: 'Station Test',
      );

      // ACT
      await repository.save(truck);
      final result = await repository.getById(1);

      // ASSERT
      expect(result!.displayName, equals('VSAV2'));
    });
  });
}
