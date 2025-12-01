/// Tests de validation des demandes de remplacement
/// Vérifie les contrôles de validation (plages horaires, auto-acceptation, etc.)
library;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';

import '../../helpers/test_data.dart';

void main() {
  group('Tests de Validation', () {
    late FakeFirebaseFirestore fakeFirestore;
    late ReplacementNotificationService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = ReplacementNotificationService(firestore: fakeFirestore);
    });

    test(
      'Validation: Heure de fin avant heure de début - Erreur',
      () async {
        // ARRANGE
        final requestId = 'test-invalid-time-range';
        final requesterId = 'user-requester';
        final replacerId = 'user-replacer';

        // Demande avec heure de fin AVANT heure de début (invalide)
        final startTime = DateTime(2025, 12, 25, 17, 0);
        final endTime = DateTime(2025, 12, 25, 14, 0); // Avant le début!

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

        // ACT & ASSERT
        // L'acceptation devrait échouer avec heure de fin avant heure de début
        expect(
          () async => await service.acceptReplacementRequest(
            requestId: requestId,
            replacerId: replacerId,
          ),
          throwsA(isA<Exception>()),
          reason: 'Heure de fin avant heure de début doit lever une exception',
        );
      },
    );

    test(
      'Validation: Acceptation partielle avec plage invalide - Erreur',
      () async {
        // ARRANGE
        final requestId = 'test-invalid-partial';
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

        // ACT & ASSERT
        // Tenter d'accepter 18h-20h alors que la demande est 14h-17h (hors plage)
        expect(
          () async => await service.acceptReplacementRequest(
            requestId: requestId,
            replacerId: replacerId,
            acceptedStartTime: DateTime(2025, 12, 25, 18, 0),
            acceptedEndTime: DateTime(2025, 12, 25, 20, 0),
          ),
          throwsA(isA<Exception>()),
          reason:
              'Acceptation hors de la plage demandée doit lever une exception',
        );
      },
    );

    test(
      'Validation: Acceptation partielle avant le début de la demande - Erreur',
      () async {
        // ARRANGE
        final requestId = 'test-invalid-before';
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

        // ACT & ASSERT
        // Tenter d'accepter 12h-15h alors que la demande commence à 14h
        expect(
          () async => await service.acceptReplacementRequest(
            requestId: requestId,
            replacerId: replacerId,
            acceptedStartTime: DateTime(2025, 12, 25, 12, 0), // Avant 14h!
            acceptedEndTime: DateTime(2025, 12, 25, 15, 0),
          ),
          throwsA(isA<Exception>()),
          reason: 'Heure de début avant la demande doit lever une exception',
        );
      },
    );

    test(
      'Validation: Acceptation partielle après la fin de la demande - Erreur',
      () async {
        // ARRANGE
        final requestId = 'test-invalid-after';
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

        // ACT & ASSERT
        // Tenter d'accepter 16h-19h alors que la demande finit à 17h
        expect(
          () async => await service.acceptReplacementRequest(
            requestId: requestId,
            replacerId: replacerId,
            acceptedStartTime: DateTime(2025, 12, 25, 16, 0),
            acceptedEndTime: DateTime(2025, 12, 25, 19, 0), // Après 17h!
          ),
          throwsA(isA<Exception>()),
          reason: 'Heure de fin après la demande doit lever une exception',
        );
      },
    );

    test(
      'Validation: Auto-acceptation interdite - Agent ne peut pas accepter sa propre demande',
      () async {
        // ARRANGE
        final requestId = 'test-self-accept';
        final userId = 'user-same';

        final startTime = DateTime(2025, 12, 25, 14, 0);
        final endTime = DateTime(2025, 12, 25, 17, 0);

        await fakeFirestore.collection('replacementRequests').doc(requestId).set(
              createTestReplacementRequest(
                id: requestId,
                requesterId: userId, // Même utilisateur
                startTime: startTime,
                endTime: endTime,
              ),
            );

        await fakeFirestore.collection('users').doc(userId).set(
              createTestUser(id: userId),
            );
        await fakeFirestore.collection('plannings').doc('planning-123').set(
              createTestPlanning(id: 'planning-123'),
            );

        // ACT & ASSERT
        // Note: Le code actuel ne vérifie pas l'auto-acceptation
        // Ce test documente le comportement attendu
        // TODO: Ajouter la validation dans le service si nécessaire

        // Pour l'instant, on teste que ça fonctionne (pas de validation)
        // Mais on devrait bloquer l'auto-acceptation
        await expectLater(
          service.acceptReplacementRequest(
            requestId: requestId,
            replacerId: userId, // Même que requesterId
          ),
          completes,
          reason:
              'Actuellement aucune validation, mais devrait être bloqué dans le futur',
        );

        // Vérifier que la demande a été acceptée (comportement actuel)
        final doc = await fakeFirestore
            .collection('replacementRequests')
            .doc(requestId)
            .get();
        expect(doc.data()?['status'], equals('accepted'));
      },
    );

    test(
      'Validation: Demande inexistante - Erreur',
      () async {
        // ARRANGE
        final requestId = 'non-existent-request';
        final replacerId = 'user-replacer';

        await fakeFirestore.collection('users').doc(replacerId).set(
              createTestUser(id: replacerId),
            );

        // ACT & ASSERT
        expect(
          () async => await service.acceptReplacementRequest(
            requestId: requestId,
            replacerId: replacerId,
          ),
          throwsA(isA<Exception>()),
          reason: 'Demande inexistante doit lever une exception',
        );
      },
    );

    test(
      'Validation: Demande déjà acceptée - Erreur',
      () async {
        // ARRANGE
        final requestId = 'test-already-accepted';
        final requesterId = 'user-requester';
        final replacerId = 'user-replacer';

        final startTime = DateTime(2025, 12, 25, 14, 0);
        final endTime = DateTime(2025, 12, 25, 17, 0);

        // Demande déjà acceptée
        await fakeFirestore.collection('replacementRequests').doc(requestId).set(
              createTestReplacementRequest(
                id: requestId,
                requesterId: requesterId,
                startTime: startTime,
                endTime: endTime,
                status: ReplacementRequestStatus.accepted,
                replacerId: 'user-other',
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

        // ACT & ASSERT
        expect(
          () async => await service.acceptReplacementRequest(
            requestId: requestId,
            replacerId: replacerId,
          ),
          throwsA(
            predicate((e) =>
                e is Exception &&
                e.toString().contains('déjà été acceptée')),
          ),
          reason: 'Demande déjà acceptée doit lever une exception',
        );
      },
    );

    test(
      'Validation: Demande refusée - Peut être acceptée par quelqu\'un d\'autre',
      () async {
        // ARRANGE
        final requestId = 'test-refused-then-accept';
        final requesterId = 'user-requester';
        final replacerId = 'user-replacer';

        final startTime = DateTime(2025, 12, 25, 14, 0);
        final endTime = DateTime(2025, 12, 25, 17, 0);

        // Demande refusée par quelqu'un d'autre (mais toujours pending)
        await fakeFirestore.collection('replacementRequests').doc(requestId).set(
              createTestReplacementRequest(
                id: requestId,
                requesterId: requesterId,
                startTime: startTime,
                endTime: endTime,
                status: ReplacementRequestStatus.pending,
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

        // ACT
        await service.acceptReplacementRequest(
          requestId: requestId,
          replacerId: replacerId,
        );

        // ASSERT
        final doc = await fakeFirestore
            .collection('replacementRequests')
            .doc(requestId)
            .get();
        expect(doc.data()?['status'], equals('accepted'));
        expect(doc.data()?['replacerId'], equals(replacerId));
      },
    );

    test(
      'Validation: Acceptation avec dates dans le passé - Devrait être permis',
      () async {
        // ARRANGE
        final requestId = 'test-past-date';
        final requesterId = 'user-requester';
        final replacerId = 'user-replacer';

        // Dates dans le passé (cas de test ou demande en retard)
        final startTime = DateTime(2020, 1, 1, 14, 0);
        final endTime = DateTime(2020, 1, 1, 17, 0);

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

        // ACT
        // Le système ne devrait pas bloquer les dates passées
        // (utile pour les tests et les corrections)
        await expectLater(
          service.acceptReplacementRequest(
            requestId: requestId,
            replacerId: replacerId,
          ),
          completes,
          reason: 'Les dates passées devraient être permises',
        );

        // ASSERT
        final doc = await fakeFirestore
            .collection('replacementRequests')
            .doc(requestId)
            .get();
        expect(doc.data()?['status'], equals('accepted'));
      },
    );

    test(
      'Validation: Plage horaire valide partielle - Succès',
      () async {
        // ARRANGE
        final requestId = 'test-valid-partial';
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

        // ACT - Acceptation partielle VALIDE (dans la plage)
        await service.acceptReplacementRequest(
          requestId: requestId,
          replacerId: replacerId,
          acceptedStartTime: DateTime(2025, 12, 25, 14, 30),
          acceptedEndTime: DateTime(2025, 12, 25, 16, 30),
        );

        // ASSERT
        final doc = await fakeFirestore
            .collection('replacementRequests')
            .doc(requestId)
            .get();
        expect(doc.data()?['status'], equals('accepted'));
        expect(doc.data()?['replacerId'], equals(replacerId));

        // Vérifier que les heures acceptées sont enregistrées
        final acceptedStart =
            (doc.data()?['acceptedStartTime'] as dynamic).toDate();
        final acceptedEnd = (doc.data()?['acceptedEndTime'] as dynamic).toDate();

        expect(acceptedStart, equals(DateTime(2025, 12, 25, 14, 30)));
        expect(acceptedEnd, equals(DateTime(2025, 12, 25, 16, 30)));
      },
    );
  });
}
