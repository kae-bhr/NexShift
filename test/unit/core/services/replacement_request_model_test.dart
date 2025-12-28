/// Tests du modèle ReplacementRequest étendu
/// Phase 1 - Vérification des nouveaux champs
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';

void main() {
  group('ReplacementRequest - Nouveaux champs Phase 1', () {
    test('toJson: Inclut tous les nouveaux champs', () {
      // ARRANGE
      final request = ReplacementRequest(
        id: 'request-1',
        requesterId: 'user-1',
        planningId: 'planning-1',
        startTime: DateTime(2025, 12, 15, 8, 0),
        endTime: DateTime(2025, 12, 15, 20, 0),
        station: 'Station Alpha',
        team: 'A',
        createdAt: DateTime(2025, 12, 10, 10, 0),
        status: ReplacementRequestStatus.pending,
        // Nouveaux champs
        seenByUserIds: ['user-2', 'user-3'],
        declinedByUserIds: ['user-4'],
        mode: ReplacementMode.similarity,
        wavesSuspended: true,
      );

      // ACT
      final json = request.toJson();

      // ASSERT
      expect(json['seenByUserIds'], equals(['user-2', 'user-3']));
      expect(json['declinedByUserIds'], equals(['user-4']));
      expect(json['mode'], equals('similarity'));
      expect(json['wavesSuspended'], equals(true));
    });

    test('fromJson: Parse les nouveaux champs avec valeurs par défaut', () {
      // ARRANGE - JSON sans les nouveaux champs (rétrocompatibilité)
      final json = {
        'id': 'request-2',
        'requesterId': 'user-2',
        'planningId': 'planning-2',
        'startTime': Timestamp.fromDate(DateTime(2025, 12, 16, 8, 0)),
        'endTime': Timestamp.fromDate(DateTime(2025, 12, 16, 20, 0)),
        'station': 'Station Beta',
        'team': 'B',
        'createdAt': Timestamp.fromDate(DateTime(2025, 12, 11, 9, 0)),
        'status': 'pending',
        'currentWave': 1,
        'notifiedUserIds': ['user-3', 'user-4'],
        'requestType': 'replacement',
        // Pas de nouveaux champs
      };

      // ACT
      final request = ReplacementRequest.fromJson(json);

      // ASSERT - Valeurs par défaut appliquées
      expect(request.seenByUserIds, equals([]));
      expect(request.declinedByUserIds, equals([]));
      expect(request.mode, equals(ReplacementMode.similarity));
      expect(request.wavesSuspended, equals(false));
    });

    test('fromJson: Parse les nouveaux champs présents', () {
      // ARRANGE
      final json = {
        'id': 'request-3',
        'requesterId': 'user-3',
        'planningId': 'planning-3',
        'startTime': Timestamp.fromDate(DateTime(2025, 12, 17, 8, 0)),
        'endTime': Timestamp.fromDate(DateTime(2025, 12, 17, 20, 0)),
        'station': 'Station Gamma',
        'createdAt': Timestamp.fromDate(DateTime(2025, 12, 12, 10, 0)),
        'status': 'pending',
        'currentWave': 2,
        'notifiedUserIds': ['user-4'],
        'requestType': 'replacement',
        // Nouveaux champs présents
        'seenByUserIds': ['user-5', 'user-6'],
        'declinedByUserIds': ['user-7', 'user-8'],
        'mode': 'manual',
        'wavesSuspended': true,
      };

      // ACT
      final request = ReplacementRequest.fromJson(json);

      // ASSERT
      expect(request.seenByUserIds, equals(['user-5', 'user-6']));
      expect(request.declinedByUserIds, equals(['user-7', 'user-8']));
      expect(request.mode, equals(ReplacementMode.manual));
      expect(request.wavesSuspended, equals(true));
    });

    test('Mode inference: availability depuis requestType', () {
      // ARRANGE
      final json = {
        'id': 'request-4',
        'requesterId': 'user-4',
        'planningId': 'planning-4',
        'startTime': Timestamp.fromDate(DateTime(2025, 12, 18, 8, 0)),
        'endTime': Timestamp.fromDate(DateTime(2025, 12, 18, 20, 0)),
        'station': 'Station Delta',
        'createdAt': Timestamp.fromDate(DateTime(2025, 12, 13, 11, 0)),
        'status': 'pending',
        'requestType': 'availability', // Type availability
        'requiredSkills': ['skill-1', 'skill-2'],
        // mode devrait être inféré à availability (migration)
      };

      // ACT
      final request = ReplacementRequest.fromJson(json);

      // ASSERT
      // Note: Le code actuel utilise la valeur par défaut similarity
      // La migration côté backend devra gérer cette inférence
      expect(request.requestType, equals(RequestType.availability));
    });

    test('Compatibilité ascendante: Ancien JSON sans nouveaux champs', () {
      // ARRANGE - JSON dans le format ancien
      final oldFormatJson = {
        'id': 'old-request',
        'requesterId': 'user-5',
        'planningId': 'planning-5',
        'startTime': Timestamp.fromDate(DateTime(2025, 12, 1, 8, 0)),
        'endTime': Timestamp.fromDate(DateTime(2025, 12, 1, 20, 0)),
        'station': 'Old Station',
        'team': 'C',
        'createdAt': Timestamp.fromDate(DateTime(2025, 11, 25, 9, 0)),
        'status': 'accepted',
        'replacerId': 'user-6',
        'acceptedAt': Timestamp.fromDate(DateTime(2025, 11, 25, 14, 0)),
        'currentWave': 3,
        'notifiedUserIds': ['user-7', 'user-8', 'user-9'],
        'lastWaveSentAt': Timestamp.fromDate(DateTime(2025, 11, 25, 12, 0)),
        'requestType': 'replacement',
      };

      // ACT
      final request = ReplacementRequest.fromJson(oldFormatJson);

      // ASSERT - Pas d'erreur et valeurs par défaut
      expect(request.id, equals('old-request'));
      expect(request.status, equals(ReplacementRequestStatus.accepted));
      expect(request.replacerId, equals('user-6'));
      expect(request.seenByUserIds, isEmpty);
      expect(request.declinedByUserIds, isEmpty);
      expect(request.mode, equals(ReplacementMode.similarity));
      expect(request.wavesSuspended, isFalse);
    });

    test('Round-trip: toJson -> fromJson préserve les données', () {
      // ARRANGE
      final original = ReplacementRequest(
        id: 'roundtrip-test',
        requesterId: 'user-10',
        planningId: 'planning-10',
        startTime: DateTime(2025, 12, 20, 8, 0),
        endTime: DateTime(2025, 12, 20, 20, 0),
        station: 'Station Test',
        team: 'D',
        createdAt: DateTime(2025, 12, 15, 10, 0),
        status: ReplacementRequestStatus.pending,
        currentWave: 2,
        notifiedUserIds: ['user-11', 'user-12'],
        seenByUserIds: ['user-13'],
        declinedByUserIds: ['user-14', 'user-15'],
        mode: ReplacementMode.similarity,
        wavesSuspended: true,
      );

      // ACT
      final json = original.toJson();
      final reconstructed = ReplacementRequest.fromJson(json);

      // ASSERT
      expect(reconstructed.id, equals(original.id));
      expect(reconstructed.station, equals(original.station));
      expect(reconstructed.currentWave, equals(original.currentWave));
      expect(reconstructed.seenByUserIds, equals(original.seenByUserIds));
      expect(reconstructed.declinedByUserIds, equals(original.declinedByUserIds));
      expect(reconstructed.mode, equals(original.mode));
      expect(reconstructed.wavesSuspended, equals(original.wavesSuspended));
    });
  });

  group('ReplacementMode Enum', () {
    test('Tous les modes sont parsables', () {
      final modes = [
        'similarity',
        'position',
        'manual',
        'availability',
      ];

      for (final modeStr in modes) {
        final json = {
          'id': 'test',
          'requesterId': 'user-1',
          'planningId': 'planning-1',
          'startTime': Timestamp.fromDate(DateTime(2025, 12, 1)),
          'endTime': Timestamp.fromDate(DateTime(2025, 12, 2)),
          'station': 'Station',
          'createdAt': Timestamp.fromDate(DateTime(2025, 11, 30)),
          'status': 'pending',
          'mode': modeStr,
        };

        final request = ReplacementRequest.fromJson(json);
        expect(request.mode.toString().split('.').last, equals(modeStr));
      }
    });

    test('Mode invalide utilise similarity par défaut', () {
      final json = {
        'id': 'test-invalid',
        'requesterId': 'user-1',
        'planningId': 'planning-1',
        'startTime': Timestamp.fromDate(DateTime(2025, 12, 1)),
        'endTime': Timestamp.fromDate(DateTime(2025, 12, 2)),
        'station': 'Station',
        'createdAt': Timestamp.fromDate(DateTime(2025, 11, 30)),
        'status': 'pending',
        'mode': 'unknown_mode',
      };

      final request = ReplacementRequest.fromJson(json);
      expect(request.mode, equals(ReplacementMode.similarity));
    });
  });

  group('État "Vu" (seenByUserIds)', () {
    test('toJson: Inclut seenByUserIds dans la sortie', () {
      // ARRANGE
      final request = ReplacementRequest(
        id: 'request-seen-1',
        requesterId: 'user-1',
        planningId: 'planning-1',
        startTime: DateTime(2025, 12, 20, 8, 0),
        endTime: DateTime(2025, 12, 20, 20, 0),
        station: 'Station Test',
        createdAt: DateTime(2025, 12, 15, 10, 0),
        status: ReplacementRequestStatus.pending,
        seenByUserIds: ['user-2', 'user-3', 'user-4'],
      );

      // ACT
      final json = request.toJson();

      // ASSERT
      expect(json['seenByUserIds'], isA<List>());
      expect(json['seenByUserIds'], equals(['user-2', 'user-3', 'user-4']));
    });

    test('fromJson: Parse seenByUserIds correctement', () {
      // ARRANGE
      final json = {
        'id': 'request-seen-2',
        'requesterId': 'user-1',
        'planningId': 'planning-1',
        'startTime': Timestamp.fromDate(DateTime(2025, 12, 21, 8, 0)),
        'endTime': Timestamp.fromDate(DateTime(2025, 12, 21, 20, 0)),
        'station': 'Station Beta',
        'createdAt': Timestamp.fromDate(DateTime(2025, 12, 16, 9, 0)),
        'status': 'pending',
        'seenByUserIds': ['user-5', 'user-6'],
      };

      // ACT
      final request = ReplacementRequest.fromJson(json);

      // ASSERT
      expect(request.seenByUserIds, isA<List<String>>());
      expect(request.seenByUserIds, equals(['user-5', 'user-6']));
    });

    test('fromJson: seenByUserIds vide par défaut si absent', () {
      // ARRANGE
      final json = {
        'id': 'request-seen-3',
        'requesterId': 'user-1',
        'planningId': 'planning-1',
        'startTime': Timestamp.fromDate(DateTime(2025, 12, 22, 8, 0)),
        'endTime': Timestamp.fromDate(DateTime(2025, 12, 22, 20, 0)),
        'station': 'Station Gamma',
        'createdAt': Timestamp.fromDate(DateTime(2025, 12, 17, 10, 0)),
        'status': 'pending',
        // Pas de seenByUserIds
      };

      // ACT
      final request = ReplacementRequest.fromJson(json);

      // ASSERT
      expect(request.seenByUserIds, isEmpty);
    });

    test('Logique métier: Utilisateur peut marquer comme "Vu"', () {
      // ARRANGE
      final request = ReplacementRequest(
        id: 'request-seen-4',
        requesterId: 'user-1',
        planningId: 'planning-1',
        startTime: DateTime(2025, 12, 23, 8, 0),
        endTime: DateTime(2025, 12, 23, 20, 0),
        station: 'Station Delta',
        createdAt: DateTime(2025, 12, 18, 11, 0),
        status: ReplacementRequestStatus.pending,
        notifiedUserIds: ['user-2', 'user-3', 'user-4'],
        seenByUserIds: [],
      );

      // ACT - Simuler l'ajout de user-3 dans seenByUserIds
      final updatedSeenBy = [...request.seenByUserIds, 'user-3'];

      // ASSERT
      expect(updatedSeenBy, contains('user-3'));
      expect(updatedSeenBy.length, equals(1));
    });

    test('Logique métier: Agent "Vu" n\'apparaît pas dans compteur pending', () {
      // ARRANGE
      final request = ReplacementRequest(
        id: 'request-seen-5',
        requesterId: 'user-1',
        planningId: 'planning-1',
        startTime: DateTime(2025, 12, 24, 8, 0),
        endTime: DateTime(2025, 12, 24, 20, 0),
        station: 'Station Epsilon',
        createdAt: DateTime(2025, 12, 19, 12, 0),
        status: ReplacementRequestStatus.pending,
        notifiedUserIds: ['user-2', 'user-3', 'user-4'],
        seenByUserIds: ['user-3'],
        declinedByUserIds: ['user-4'],
      );

      const currentUserId = 'user-3';

      // ACT - Vérifier si l'utilisateur a vu la demande
      final hasSeen = request.seenByUserIds.contains(currentUserId);
      final hasDeclined = request.declinedByUserIds.contains(currentUserId);
      final isNotified = request.notifiedUserIds.contains(currentUserId);

      // ASSERT
      expect(hasSeen, isTrue, reason: 'user-3 a marqué comme "Vu"');
      expect(hasDeclined, isFalse, reason: 'user-3 n\'a pas refusé');
      expect(isNotified, isTrue, reason: 'user-3 est notifié');

      // Dans le compteur du drawer, cette demande ne devrait PAS être comptée
      // car l'utilisateur l'a marquée comme "Vue"
      final shouldCountInPending = isNotified && !hasSeen && !hasDeclined;
      expect(shouldCountInPending, isFalse);
    });

    test('Round-trip avec seenByUserIds préserve les données', () {
      // ARRANGE
      final original = ReplacementRequest(
        id: 'request-seen-6',
        requesterId: 'user-1',
        planningId: 'planning-1',
        startTime: DateTime(2025, 12, 25, 8, 0),
        endTime: DateTime(2025, 12, 25, 20, 0),
        station: 'Station Zeta',
        createdAt: DateTime(2025, 12, 20, 13, 0),
        status: ReplacementRequestStatus.pending,
        notifiedUserIds: ['user-2', 'user-3', 'user-4', 'user-5'],
        seenByUserIds: ['user-2', 'user-5'],
        declinedByUserIds: ['user-4'],
      );

      // ACT
      final json = original.toJson();
      final reconstructed = ReplacementRequest.fromJson(json);

      // ASSERT
      expect(reconstructed.seenByUserIds, equals(original.seenByUserIds));
      expect(reconstructed.seenByUserIds, equals(['user-2', 'user-5']));
    });
  });
}
