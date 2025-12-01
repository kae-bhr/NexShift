/// Tests de race conditions sur les demandes de remplacement
/// Vérifie que les transactions atomiques empêchent les doubles acceptations
library;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';

import '../../helpers/test_data.dart';

void main() {
  group('Race Condition Tests - Double acceptation', () {
    late FakeFirebaseFirestore fakeFirestore;
    late ReplacementNotificationService service;

    setUp(() {
      // Créer une instance Firestore fake (en mémoire)
      fakeFirestore = FakeFirebaseFirestore();

      // Créer le service avec Firestore fake
      // Le service va automatiquement créer des repositories en mode test
      service = ReplacementNotificationService(firestore: fakeFirestore);
    });

    test(
      'Deux utilisateurs ne peuvent pas accepter la même demande simultanément',
      () async {
        // ARRANGE - Préparer les données de test
        final requestId = 'test-request-race-1';
        final replacer1Id = 'user-replacer-1';
        final replacer2Id = 'user-replacer-2';

        // Créer la demande de remplacement
        final requestData = createTestReplacementRequest(
          id: requestId,
          requesterId: 'user-requester',
          startTime: DateTime(2025, 12, 25, 6, 30),
          endTime: DateTime(2025, 12, 25, 22, 0),
        );

        await fakeFirestore
            .collection('replacementRequests')
            .doc(requestId)
            .set(requestData);

        // Créer les utilisateurs
        await fakeFirestore.collection('users').doc('user-requester').set(
              createTestUser(
                id: 'user-requester',
                firstName: 'Alice',
                lastName: 'Demandeur',
              ),
            );

        await fakeFirestore.collection('users').doc(replacer1Id).set(
              createTestUser(
                id: replacer1Id,
                firstName: 'Bob',
                lastName: 'Replacer1',
              ),
            );

        await fakeFirestore.collection('users').doc(replacer2Id).set(
              createTestUser(
                id: replacer2Id,
                firstName: 'Charlie',
                lastName: 'Replacer2',
              ),
            );

        // Créer le planning
        await fakeFirestore.collection('plannings').doc('planning-123').set(
              createTestPlanning(
                id: 'planning-123',
                agentsId: [],
              ),
            );

        // ACT - Tenter deux acceptations simultanées
        // On lance les deux appels en parallèle avec Future.wait
        final results = await Future.wait([
          service
              .acceptReplacementRequest(
                requestId: requestId,
                replacerId: replacer1Id,
              )
              .then((_) => 'success')
              .catchError((e) => 'error: $e'),
          service
              .acceptReplacementRequest(
                requestId: requestId,
                replacerId: replacer2Id,
              )
              .then((_) => 'success')
              .catchError((e) => 'error: $e'),
        ]);

        // ASSERT - Vérifier qu'un seul a réussi
        final successCount = results.where((r) => r == 'success').length;
        final errorCount = results.where((r) => r.startsWith('error')).length;

        expect(
          successCount,
          equals(1),
          reason: 'Un seul utilisateur devrait pouvoir accepter',
        );
        expect(
          errorCount,
          equals(1),
          reason: 'Le second utilisateur devrait recevoir une erreur',
        );

        // Vérifier que l'erreur contient le bon message
        final errorMessage = results.firstWhere((r) => r.startsWith('error'));
        expect(
          errorMessage,
          contains('Cette demande a déjà été acceptée'),
          reason: 'L\'erreur devrait indiquer que la demande est déjà acceptée',
        );

        // Vérifier que le statut de la demande est 'accepted'
        final requestDoc = await fakeFirestore
            .collection('replacementRequests')
            .doc(requestId)
            .get();

        expect(requestDoc.data()?['status'], equals('accepted'));

        // Vérifier qu'un seul replacerId est enregistré
        final replacerId = requestDoc.data()?['replacerId'] as String?;
        expect(replacerId, isNotNull);
        expect(
          replacerId,
          anyOf(equals(replacer1Id), equals(replacer2Id)),
          reason: 'Le replacerId devrait être celui qui a accepté en premier',
        );

        // Vérifier qu'un seul subshift a été créé
        final subshifts = await fakeFirestore.collection('subshifts').get();
        expect(
          subshifts.docs.length,
          equals(1),
          reason: 'Un seul subshift devrait être créé',
        );

        // Vérifier que le subshift a le bon replacerId
        final subshift = subshifts.docs.first;
        expect(subshift.data()['replacerId'], equals(replacerId));
      },
    );

    test(
      'Acceptation après modification manuelle du statut échoue',
      () async {
        // ARRANGE
        final requestId = 'test-request-race-2';
        final replacerId = 'user-replacer';

        // Créer la demande
        final requestData = createTestReplacementRequest(
          id: requestId,
          requesterId: 'user-requester',
        );

        await fakeFirestore
            .collection('replacementRequests')
            .doc(requestId)
            .set(requestData);

        // Créer les utilisateurs et planning
        await fakeFirestore.collection('users').doc('user-requester').set(
              createTestUser(id: 'user-requester'),
            );
        await fakeFirestore.collection('users').doc(replacerId).set(
              createTestUser(id: replacerId),
            );
        await fakeFirestore.collection('plannings').doc('planning-123').set(
              createTestPlanning(id: 'planning-123'),
            );

        // Modifier manuellement le statut à 'accepted' (simuler qu'un autre utilisateur a accepté)
        await fakeFirestore
            .collection('replacementRequests')
            .doc(requestId)
            .update({
          'status': 'accepted',
          'replacerId': 'other-user',
        });

        // ACT - Tenter d'accepter
        Object? caughtError;
        try {
          await service.acceptReplacementRequest(
            requestId: requestId,
            replacerId: replacerId,
          );
        } catch (e) {
          caughtError = e;
        }

        // ASSERT
        expect(caughtError, isNotNull, reason: 'Une erreur devrait être levée');
        expect(
          caughtError.toString(),
          contains('Cette demande a déjà été acceptée'),
        );

        // Vérifier que le statut n'a pas changé
        final requestDoc = await fakeFirestore
            .collection('replacementRequests')
            .doc(requestId)
            .get();

        expect(requestDoc.data()?['status'], equals('accepted'));
        expect(
          requestDoc.data()?['replacerId'],
          equals('other-user'),
          reason: 'Le replacerId ne devrait pas avoir changé',
        );
      },
    );

    test(
      'Trois utilisateurs tentent d\'accepter - un seul réussit',
      () async {
        // ARRANGE
        final requestId = 'test-request-race-3';
        final replacer1Id = 'user-replacer-1';
        final replacer2Id = 'user-replacer-2';
        final replacer3Id = 'user-replacer-3';

        // Créer la demande
        final requestData = createTestReplacementRequest(
          id: requestId,
          requesterId: 'user-requester',
          startTime: DateTime(2025, 12, 26, 8, 0),
          endTime: DateTime(2025, 12, 26, 20, 0),
        );

        await fakeFirestore
            .collection('replacementRequests')
            .doc(requestId)
            .set(requestData);

        // Créer les utilisateurs
        for (final userId in [
          'user-requester',
          replacer1Id,
          replacer2Id,
          replacer3Id
        ]) {
          await fakeFirestore.collection('users').doc(userId).set(
                createTestUser(id: userId),
              );
        }

        await fakeFirestore.collection('plannings').doc('planning-123').set(
              createTestPlanning(id: 'planning-123'),
            );

        // ACT - Lancer trois acceptations en parallèle
        final results = await Future.wait([
          service
              .acceptReplacementRequest(
                requestId: requestId,
                replacerId: replacer1Id,
              )
              .then((_) => 'success')
              .catchError((e) => 'error'),
          service
              .acceptReplacementRequest(
                requestId: requestId,
                replacerId: replacer2Id,
              )
              .then((_) => 'success')
              .catchError((e) => 'error'),
          service
              .acceptReplacementRequest(
                requestId: requestId,
                replacerId: replacer3Id,
              )
              .then((_) => 'success')
              .catchError((e) => 'error'),
        ]);

        // ASSERT
        final successCount = results.where((r) => r == 'success').length;
        final errorCount = results.where((r) => r == 'error').length;

        expect(successCount, equals(1), reason: 'Un seul devrait réussir');
        expect(errorCount, equals(2), reason: 'Deux devraient échouer');

        // Vérifier qu'un seul subshift existe
        final subshifts = await fakeFirestore.collection('subshifts').get();
        expect(subshifts.docs.length, equals(1));
      },
    );
  });
}
