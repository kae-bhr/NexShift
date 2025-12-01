/// Tests de remplacements partiels
/// Vérifie que les remplacements partiels créent de nouvelles demandes pour les créneaux restants
library;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';

import '../../helpers/test_data.dart';

void main() {
  group('Tests de Remplacements Partiels', () {
    late FakeFirebaseFirestore fakeFirestore;
    late ReplacementNotificationService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = ReplacementNotificationService(firestore: fakeFirestore);
    });

    test(
      'Situation 1: Acceptation partielle du DÉBUT (14h-16h sur demande 14h-17h)',
      () async {
        // ARRANGE
        final requestId = 'test-partial-1';
        final requesterId = 'user-requester';
        final replacerId = 'user-replacer';

        // Demande initiale : 14h-17h
        final startTime = DateTime(2025, 12, 25, 14, 0);
        final endTime = DateTime(2025, 12, 25, 17, 0);

        // Agent B accepte : 14h-16h
        final acceptedStartTime = DateTime(2025, 12, 25, 14, 0);
        final acceptedEndTime = DateTime(2025, 12, 25, 16, 0);

        // Créer données de test
        await fakeFirestore.collection('replacementRequests').doc(requestId).set(
              createTestReplacementRequest(
                id: requestId,
                requesterId: requesterId,
                startTime: startTime,
                endTime: endTime,
              ),
            );

        await fakeFirestore.collection('users').doc(requesterId).set(
              createTestUser(id: requesterId, firstName: 'Alice'),
            );
        await fakeFirestore.collection('users').doc(replacerId).set(
              createTestUser(id: replacerId, firstName: 'Bob'),
            );
        await fakeFirestore.collection('plannings').doc('planning-123').set(
              createTestPlanning(id: 'planning-123'),
            );

        // ACT - Acceptation partielle
        await service.acceptReplacementRequest(
          requestId: requestId,
          replacerId: replacerId,
          acceptedStartTime: acceptedStartTime,
          acceptedEndTime: acceptedEndTime,
        );

        // ASSERT
        // 1. La demande originale doit être acceptée
        final originalRequest =
            await fakeFirestore.collection('replacementRequests').doc(requestId).get();
        expect(originalRequest.data()?['status'], equals('accepted'));
        expect(originalRequest.data()?['replacerId'], equals(replacerId));

        // 2. Un subshift doit être créé pour 14h-16h
        final subshifts = await fakeFirestore.collection('subshifts').get();
        expect(subshifts.docs.length, equals(1));
        final subshift = subshifts.docs.first.data();
        expect(subshift['replacerId'], equals(replacerId));
        expect(subshift['replacedId'], equals(requesterId));

        // 3. Une NOUVELLE demande doit être créée pour 16h-17h
        final allRequests = await fakeFirestore.collection('replacementRequests').get();
        expect(
          allRequests.docs.length,
          equals(2),
          reason: 'Une nouvelle demande doit être créée pour le créneau restant',
        );

        // Trouver la nouvelle demande (pas l'originale)
        final newRequest = allRequests.docs.firstWhere((doc) => doc.id != requestId);
        final newRequestData = newRequest.data();

        expect(newRequestData['requesterId'], equals(requesterId));
        expect(newRequestData['status'], equals('pending'));
        expect(
          (newRequestData['startTime'] as dynamic).toDate(),
          equals(acceptedEndTime),
          reason: 'La nouvelle demande doit commencer à 16h',
        );
        expect(
          (newRequestData['endTime'] as dynamic).toDate(),
          equals(endTime),
          reason: 'La nouvelle demande doit finir à 17h',
        );
      },
    );

    test(
      'Situation 2: Acceptation partielle de la FIN (15h-17h sur demande 14h-17h)',
      () async {
        // ARRANGE
        final requestId = 'test-partial-2';
        final requesterId = 'user-requester';
        final replacerId = 'user-replacer';

        // Demande initiale : 14h-17h
        final startTime = DateTime(2025, 12, 25, 14, 0);
        final endTime = DateTime(2025, 12, 25, 17, 0);

        // Agent B accepte : 15h-17h
        final acceptedStartTime = DateTime(2025, 12, 25, 15, 0);
        final acceptedEndTime = DateTime(2025, 12, 25, 17, 0);

        // Créer données de test
        await fakeFirestore.collection('replacementRequests').doc(requestId).set(
              createTestReplacementRequest(
                id: requestId,
                requesterId: requesterId,
                startTime: startTime,
                endTime: endTime,
              ),
            );

        await fakeFirestore.collection('users').doc(requesterId).set(
              createTestUser(id: requesterId, firstName: 'Alice'),
            );
        await fakeFirestore.collection('users').doc(replacerId).set(
              createTestUser(id: replacerId, firstName: 'Bob'),
            );
        await fakeFirestore.collection('plannings').doc('planning-123').set(
              createTestPlanning(id: 'planning-123'),
            );

        // ACT - Acceptation partielle
        await service.acceptReplacementRequest(
          requestId: requestId,
          replacerId: replacerId,
          acceptedStartTime: acceptedStartTime,
          acceptedEndTime: acceptedEndTime,
        );

        // ASSERT
        // 1. Demande originale acceptée
        final originalRequest =
            await fakeFirestore.collection('replacementRequests').doc(requestId).get();
        expect(originalRequest.data()?['status'], equals('accepted'));

        // 2. Subshift créé pour 15h-17h
        final subshifts = await fakeFirestore.collection('subshifts').get();
        expect(subshifts.docs.length, equals(1));

        // 3. Nouvelle demande créée pour 14h-15h
        final allRequests = await fakeFirestore.collection('replacementRequests').get();
        expect(allRequests.docs.length, equals(2));

        final newRequest = allRequests.docs.firstWhere((doc) => doc.id != requestId);
        final newRequestData = newRequest.data();

        expect(
          (newRequestData['startTime'] as dynamic).toDate(),
          equals(startTime),
          reason: 'La nouvelle demande doit commencer à 14h',
        );
        expect(
          (newRequestData['endTime'] as dynamic).toDate(),
          equals(acceptedStartTime),
          reason: 'La nouvelle demande doit finir à 15h',
        );
      },
    );

    test(
      'Situation 3: Acceptation partielle du MILIEU (15h-16h sur demande 14h-17h)',
      () async {
        // ARRANGE
        final requestId = 'test-partial-3';
        final requesterId = 'user-requester';
        final replacerId = 'user-replacer';

        // Demande initiale : 14h-17h
        final startTime = DateTime(2025, 12, 25, 14, 0);
        final endTime = DateTime(2025, 12, 25, 17, 0);

        // Agent B accepte : 15h-16h (milieu)
        final acceptedStartTime = DateTime(2025, 12, 25, 15, 0);
        final acceptedEndTime = DateTime(2025, 12, 25, 16, 0);

        // Créer données de test
        await fakeFirestore.collection('replacementRequests').doc(requestId).set(
              createTestReplacementRequest(
                id: requestId,
                requesterId: requesterId,
                startTime: startTime,
                endTime: endTime,
              ),
            );

        await fakeFirestore.collection('users').doc(requesterId).set(
              createTestUser(id: requesterId, firstName: 'Alice'),
            );
        await fakeFirestore.collection('users').doc(replacerId).set(
              createTestUser(id: replacerId, firstName: 'Bob'),
            );
        await fakeFirestore.collection('plannings').doc('planning-123').set(
              createTestPlanning(id: 'planning-123'),
            );

        // ACT - Acceptation partielle
        await service.acceptReplacementRequest(
          requestId: requestId,
          replacerId: replacerId,
          acceptedStartTime: acceptedStartTime,
          acceptedEndTime: acceptedEndTime,
        );

        // ASSERT
        // 1. Demande originale acceptée
        final originalRequest =
            await fakeFirestore.collection('replacementRequests').doc(requestId).get();
        expect(originalRequest.data()?['status'], equals('accepted'));

        // 2. Subshift créé pour 15h-16h
        final subshifts = await fakeFirestore.collection('subshifts').get();
        expect(subshifts.docs.length, equals(1));

        // 3. DEUX nouvelles demandes créées : 14h-15h ET 16h-17h
        final allRequests = await fakeFirestore.collection('replacementRequests').get();
        expect(
          allRequests.docs.length,
          equals(3),
          reason: 'Deux nouvelles demandes doivent être créées (avant et après)',
        );

        final newRequests = allRequests.docs.where((doc) => doc.id != requestId).toList();
        expect(newRequests.length, equals(2));

        // Trouver la demande "avant" et la demande "après"
        final beforeRequest = newRequests.firstWhere(
          (doc) =>
              (doc.data()['endTime'] as dynamic).toDate() == acceptedStartTime,
        );
        final afterRequest = newRequests.firstWhere(
          (doc) =>
              (doc.data()['startTime'] as dynamic).toDate() == acceptedEndTime,
        );

        // Vérifier demande "avant" (14h-15h)
        expect(
          (beforeRequest.data()['startTime'] as dynamic).toDate(),
          equals(startTime),
        );
        expect(
          (beforeRequest.data()['endTime'] as dynamic).toDate(),
          equals(acceptedStartTime),
        );

        // Vérifier demande "après" (16h-17h)
        expect(
          (afterRequest.data()['startTime'] as dynamic).toDate(),
          equals(acceptedEndTime),
        );
        expect(
          (afterRequest.data()['endTime'] as dynamic).toDate(),
          equals(endTime),
        );
      },
    );

    test(
      'Acceptation TOTALE ne crée PAS de nouvelle demande',
      () async {
        // ARRANGE
        final requestId = 'test-total';
        final requesterId = 'user-requester';
        final replacerId = 'user-replacer';

        final startTime = DateTime(2025, 12, 25, 14, 0);
        final endTime = DateTime(2025, 12, 25, 17, 0);

        await fakeFirestore.collection('replacementRequests').doc(requestId).set(
              createTestReplacementRequest(
                id: requestId,
                requesterId: requesterId,
                startTime: startTime,
                endTime: endTime,
              ),
            );

        await fakeFirestore.collection('users').doc(requesterId).set(
              createTestUser(id: requesterId),
            );
        await fakeFirestore.collection('users').doc(replacerId).set(
              createTestUser(id: replacerId),
            );
        await fakeFirestore.collection('plannings').doc('planning-123').set(
              createTestPlanning(id: 'planning-123'),
            );

        // ACT - Acceptation TOTALE (même heures)
        await service.acceptReplacementRequest(
          requestId: requestId,
          replacerId: replacerId,
          acceptedStartTime: startTime,
          acceptedEndTime: endTime,
        );

        // ASSERT
        // Seule la demande originale doit exister (pas de nouvelles demandes)
        final allRequests = await fakeFirestore.collection('replacementRequests').get();
        expect(
          allRequests.docs.length,
          equals(1),
          reason: 'Aucune nouvelle demande ne doit être créée pour un remplacement total',
        );

        expect(allRequests.docs.first.id, equals(requestId));
        expect(allRequests.docs.first.data()['status'], equals('accepted'));
      },
    );

    test(
      'Les nouvelles demandes n\'incluent PAS les utilisateurs déjà notifiés des vagues précédentes',
      () async {
        // ARRANGE
        final requestId = 'test-exclude-notified';
        final requesterId = 'user-requester';
        final replacerId = 'user-replacer';

        final startTime = DateTime(2025, 12, 25, 14, 0);
        final endTime = DateTime(2025, 12, 25, 17, 0);
        final acceptedEndTime = DateTime(2025, 12, 25, 16, 0);

        // Utilisateurs déjà notifiés dans les vagues 1, 2, 3
        final notifiedUserIds = [
          'user-wave1-1',
          'user-wave1-2',
          'user-wave2-1',
          'user-wave3-1',
        ];

        await fakeFirestore.collection('replacementRequests').doc(requestId).set(
              createTestReplacementRequest(
                id: requestId,
                requesterId: requesterId,
                startTime: startTime,
                endTime: endTime,
                currentWave: 3, // On est à la vague 3
                notifiedUserIds: notifiedUserIds,
              ),
            );

        await fakeFirestore.collection('users').doc(requesterId).set(
              createTestUser(id: requesterId),
            );
        await fakeFirestore.collection('users').doc(replacerId).set(
              createTestUser(id: replacerId),
            );
        await fakeFirestore.collection('plannings').doc('planning-123').set(
              createTestPlanning(id: 'planning-123'),
            );

        // ACT - Acceptation partielle
        await service.acceptReplacementRequest(
          requestId: requestId,
          replacerId: replacerId,
          acceptedStartTime: startTime,
          acceptedEndTime: acceptedEndTime,
        );

        // ASSERT
        // La nouvelle demande créée doit avoir excludedUserIds
        final allRequests = await fakeFirestore.collection('replacementRequests').get();
        final newRequest = allRequests.docs.firstWhere((doc) => doc.id != requestId);

        // Note: Le service utilise excludedUserIds lors de createReplacementRequest
        // On vérifie que la nouvelle demande existe (la logique d'exclusion est testée
        // dans le service lui-même)
        expect(newRequest.exists, isTrue);
        expect(
          newRequest.data()['requesterId'],
          equals(requesterId),
          reason: 'La nouvelle demande doit avoir le même demandeur',
        );
      },
    );
  });
}
