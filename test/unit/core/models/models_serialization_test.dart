/// Tests de sérialisation des modèles
/// Vérifie que les modèles se convertissent correctement en JSON et inversement
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/trucks_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';

void main() {
  group('Planning Model Serialization', () {
    test('toJson: Convertit Planning en JSON avec Timestamp', () {
      // ARRANGE
      final planning = Planning(
        id: 'planning-1',
        startTime: DateTime(2025, 1, 1, 8, 0),
        endTime: DateTime(2025, 1, 1, 20, 0),
        station: 'Station Test',
        team: 'A',
        agentsId: ['agent-1', 'agent-2', 'agent-3'],
        maxAgents: 6,
      );

      // ACT
      final json = planning.toJson();

      // ASSERT
      expect(json['id'], equals('planning-1'));
      expect(json['station'], equals('Station Test'));
      expect(json['team'], equals('A'));
      expect(json['maxAgents'], equals(6));
      expect(json['agentsId'], isA<List>());
      expect((json['agentsId'] as List).length, equals(3));
      expect(json['startTime'], isA<Timestamp>());
      expect(json['endTime'], isA<Timestamp>());
    });

    test('fromJson: Parse Planning depuis JSON avec Timestamp', () {
      // ARRANGE
      final json = {
        'id': 'planning-2',
        'startTime': Timestamp.fromDate(DateTime(2025, 2, 1, 8, 0)),
        'endTime': Timestamp.fromDate(DateTime(2025, 2, 1, 20, 0)),
        'station': 'Station Alpha',
        'team': 'B',
        'agentsId': ['alice', 'bob'],
        'maxAgents': 5,
      };

      // ACT
      final planning = Planning.fromJson(json);

      // ASSERT
      expect(planning.id, equals('planning-2'));
      expect(planning.startTime, equals(DateTime(2025, 2, 1, 8, 0)));
      expect(planning.endTime, equals(DateTime(2025, 2, 1, 20, 0)));
      expect(planning.station, equals('Station Alpha'));
      expect(planning.team, equals('B'));
      expect(planning.agentsId.length, equals(2));
      expect(planning.maxAgents, equals(5));
    });

    test('fromJson: Parse Planning depuis JSON avec String ISO8601', () {
      // ARRANGE
      final json = {
        'id': 'planning-3',
        'startTime': '2025-03-01T08:00:00.000',
        'endTime': '2025-03-01T20:00:00.000',
        'station': 'Station Beta',
        'team': 'C',
        'agentsId': ['charlie'],
        'maxAgents': 6,
      };

      // ACT
      final planning = Planning.fromJson(json);

      // ASSERT
      expect(planning.id, equals('planning-3'));
      expect(planning.startTime, equals(DateTime(2025, 3, 1, 8, 0)));
      expect(planning.endTime, equals(DateTime(2025, 3, 1, 20, 0)));
      expect(planning.station, equals('Station Beta'));
      expect(planning.team, equals('C'));
    });

    test('copyWith: Crée une copie modifiée du Planning', () {
      // ARRANGE
      final original = Planning(
        id: 'planning-1',
        startTime: DateTime(2025, 1, 1, 8, 0),
        endTime: DateTime(2025, 1, 1, 20, 0),
        station: 'Station A',
        team: 'A',
        agentsId: ['agent-1'],
        maxAgents: 6,
      );

      // ACT
      final modified = original.copyWith(
        team: 'B',
        agentsId: ['agent-1', 'agent-2'],
      );

      // ASSERT
      expect(modified.id, equals('planning-1')); // Non modifié
      expect(modified.station, equals('Station A')); // Non modifié
      expect(modified.team, equals('B')); // Modifié
      expect(modified.agentsId.length, equals(2)); // Modifié
      expect(modified.maxAgents, equals(6)); // Non modifié
    });

    test('empty: Crée un Planning vide', () {
      // ACT
      final empty = Planning.empty();

      // ASSERT
      expect(empty.id, equals(''));
      expect(empty.station, equals(''));
      expect(empty.team, equals(''));
      expect(empty.agentsId.isEmpty, isTrue);
      expect(empty.maxAgents, equals(6));
    });
  });

  group('Truck Model Serialization', () {
    test('toJson: Convertit Truck en JSON', () {
      // ARRANGE
      final truck = Truck(
        id: 1,
        displayNumber: 2,
        type: 'VSAV',
        station: 'Station Test',
        available: true,
        modeId: '4h',
      );

      // ACT
      final json = truck.toJson();

      // ASSERT
      expect(json['id'], equals(1));
      expect(json['displayNumber'], equals(2));
      expect(json['type'], equals('VSAV'));
      expect(json['station'], equals('Station Test'));
      expect(json['available'], equals(true));
      expect(json['modeId'], equals('4h'));
    });

    test('fromJson: Parse Truck depuis JSON avec id int', () {
      // ARRANGE
      final json = {
        'id': 5,
        'displayNumber': 3,
        'type': 'FPT',
        'station': 'Station Alpha',
        'available': false,
        'modeId': '6h',
      };

      // ACT
      final truck = Truck.fromJson(json);

      // ASSERT
      expect(truck.id, equals(5));
      expect(truck.displayNumber, equals(3));
      expect(truck.type, equals('FPT'));
      expect(truck.station, equals('Station Alpha'));
      expect(truck.available, equals(false));
      expect(truck.modeId, equals('6h'));
    });

    test('fromJson: Parse Truck depuis JSON avec id String (Firestore)', () {
      // ARRANGE - Firestore retourne parfois l'id en String
      final json = {
        'id': '7',
        'displayNumber': '2',
        'type': 'VTU',
        'station': 'Station Beta',
        'available': true,
      };

      // ACT
      final truck = Truck.fromJson(json);

      // ASSERT
      expect(truck.id, equals(7));
      expect(truck.displayNumber, equals(2));
      expect(truck.type, equals('VTU'));
      expect(truck.modeId, isNull);
    });

    test('fromJson: Utilise id comme displayNumber si displayNumber absent', () {
      // ARRANGE - Compatibilité avec anciennes données
      final json = {
        'id': 10,
        'type': 'VSAV',
        'station': 'Station Gamma',
        'available': true,
      };

      // ACT
      final truck = Truck.fromJson(json);

      // ASSERT
      expect(truck.displayNumber, equals(10)); // Fallback vers id
    });

    test('copyWith: Crée une copie modifiée du Truck', () {
      // ARRANGE
      final original = Truck(
        id: 1,
        displayNumber: 1,
        type: 'VSAV',
        station: 'Station A',
        available: true,
      );

      // ACT
      final modified = original.copyWith(
        available: false,
        modeId: '4h',
      );

      // ASSERT
      expect(modified.id, equals(1)); // Non modifié
      expect(modified.type, equals('VSAV')); // Non modifié
      expect(modified.available, equals(false)); // Modifié
      expect(modified.modeId, equals('4h')); // Modifié
    });

    test('displayName: Génère le nom d\'affichage correct', () {
      // ARRANGE
      final truck = Truck(
        id: 1,
        displayNumber: 3,
        type: 'FPT',
        station: 'Station Test',
      );

      // ACT
      final displayName = truck.displayName;

      // ASSERT
      expect(displayName, equals('FPT3'));
    });
  });

  group('User Model Serialization', () {
    test('toJson: Convertit User en JSON', () {
      // ARRANGE
      final user = User(
        id: 'user-1',
        firstName: 'Alice',
        lastName: 'Dupont',
        station: 'Station Test',
        status: 'active',
        admin: true,
        team: 'A',
        skills: ['FDF2', 'INC', 'SAP1'],
      );

      // ACT
      final json = user.toJson();

      // ASSERT
      expect(json['id'], equals('user-1'));
      expect(json['firstName'], equals('Alice'));
      expect(json['lastName'], equals('Dupont'));
      expect(json['station'], equals('Station Test'));
      expect(json['status'], equals('active'));
      expect(json['admin'], equals(true));
      expect(json['team'], equals('A'));
      expect(json['skills'], isA<List>());
      expect((json['skills'] as List).length, equals(3));
    });

    test('fromJson: Parse User depuis JSON', () {
      // ARRANGE
      final json = {
        'id': 'user-2',
        'firstName': 'Bob',
        'lastName': 'Martin',
        'station': 'Station Alpha',
        'status': 'inactive',
        'admin': false,
        'team': 'B',
        'skills': ['FDF1', 'DIV'],
      };

      // ACT
      final user = User.fromJson(json);

      // ASSERT
      expect(user.id, equals('user-2'));
      expect(user.firstName, equals('Bob'));
      expect(user.lastName, equals('Martin'));
      expect(user.station, equals('Station Alpha'));
      expect(user.status, equals('inactive'));
      expect(user.admin, equals(false));
      expect(user.team, equals('B'));
      expect(user.skills.length, equals(2));
    });

    test('empty: Crée un User vide', () {
      // ACT
      final empty = User.empty();

      // ASSERT
      expect(empty.id, equals(''));
      expect(empty.firstName, equals('Inconnu'));
      expect(empty.lastName, equals(''));
      expect(empty.station, equals(''));
      expect(empty.status, equals(''));
      expect(empty.admin, equals(false));
      expect(empty.team, equals(''));
      expect(empty.skills.isEmpty, isTrue);
    });
  });

  group('Serialization Round-trip Tests', () {
    test('Planning: toJson → fromJson conserve les données', () {
      // ARRANGE
      final original = Planning(
        id: 'planning-rt',
        startTime: DateTime(2025, 5, 15, 10, 30),
        endTime: DateTime(2025, 5, 15, 22, 30),
        station: 'Station Round-trip',
        team: 'RT',
        agentsId: ['a1', 'a2', 'a3'],
        maxAgents: 8,
      );

      // ACT
      final json = original.toJson();
      final reconstructed = Planning.fromJson(json);

      // ASSERT
      expect(reconstructed.id, equals(original.id));
      expect(reconstructed.startTime, equals(original.startTime));
      expect(reconstructed.endTime, equals(original.endTime));
      expect(reconstructed.station, equals(original.station));
      expect(reconstructed.team, equals(original.team));
      expect(reconstructed.agentsId, equals(original.agentsId));
      expect(reconstructed.maxAgents, equals(original.maxAgents));
    });

    test('Truck: toJson → fromJson conserve les données', () {
      // ARRANGE
      final original = Truck(
        id: 99,
        displayNumber: 5,
        type: 'EPA',
        station: 'Station Round-trip',
        available: false,
        modeId: 'complet',
      );

      // ACT
      final json = original.toJson();
      final reconstructed = Truck.fromJson(json);

      // ASSERT
      expect(reconstructed.id, equals(original.id));
      expect(reconstructed.displayNumber, equals(original.displayNumber));
      expect(reconstructed.type, equals(original.type));
      expect(reconstructed.station, equals(original.station));
      expect(reconstructed.available, equals(original.available));
      expect(reconstructed.modeId, equals(original.modeId));
    });

    test('User: toJson → fromJson conserve les données', () {
      // ARRANGE
      final original = User(
        id: 'user-rt',
        firstName: 'Emma',
        lastName: 'Rousseau',
        station: 'Station Round-trip',
        status: 'active',
        admin: true,
        team: 'RT',
        skills: ['FDF2', 'INC', 'SAP1', 'COD1'],
      );

      // ACT
      final json = original.toJson();
      final reconstructed = User.fromJson(json);

      // ASSERT
      expect(reconstructed.id, equals(original.id));
      expect(reconstructed.firstName, equals(original.firstName));
      expect(reconstructed.lastName, equals(original.lastName));
      expect(reconstructed.station, equals(original.station));
      expect(reconstructed.status, equals(original.status));
      expect(reconstructed.admin, equals(original.admin));
      expect(reconstructed.team, equals(original.team));
      expect(reconstructed.skills, equals(original.skills));
    });
  });
}
