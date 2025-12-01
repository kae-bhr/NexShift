/// Tests de race conditions avec Firebase Emulator
/// Vérifie que les transactions atomiques RÉELLES empêchent les doubles acceptations
///
/// IMPORTANT: Ce test nécessite Firebase Emulator en cours d'exécution
/// Lancer avec: firebase emulators:exec --only firestore "flutter test test/integration/replacement/race_condition_emulator_test.dart"
@Tags(['emulator'])
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';

import '../../helpers/test_data.dart';

void main() {
  group('Race Condition Tests - Firebase Emulator (vraies transactions)', () {
    late FirebaseFirestore firestore;
    late ReplacementNotificationService service;

    setUpAll(() async {
      // Initialiser Firebase pour les tests
      TestWidgetsFlutterBinding.ensureInitialized();

      // Initialiser Firebase avec une configuration minimale pour les tests
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'test-api-key',
          appId: 'test-app-id',
          messagingSenderId: 'test-sender-id',
          projectId: 'nexshift-82473',
        ),
      );

      // Configurer Firestore pour utiliser l'émulateur
      // L'émulateur tourne par défaut sur localhost:8080
      firestore = FirebaseFirestore.instance;
      firestore.useFirestoreEmulator('localhost', 8080);
    });

    setUp(() async {
      // Créer le service avec Firestore émulateur
      service = ReplacementNotificationService(firestore: firestore);

      // Nettoyer la base de données avant chaque test
      await _clearFirestore(firestore);
    });

    tearDown(() async {
      // Nettoyer après chaque test
      await _clearFirestore(firestore);
    });

    test(
      'EMULATOR: Deux utilisateurs ne peuvent pas accepter la même demande simultanément',
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

        await firestore
            .collection('replacementRequests')
            .doc(requestId)
            .set(requestData);

        // Créer les utilisateurs
        await firestore.collection('users').doc('user-requester').set(
              createTestUser(
                id: 'user-requester',
                firstName: 'Alice',
                lastName: 'Demandeur',
              ),
            );

        await firestore.collection('users').doc(replacer1Id).set(
              createTestUser(
                id: replacer1Id,
                firstName: 'Bob',
                lastName: 'Replacer1',
              ),
            );

        await firestore.collection('users').doc(replacer2Id).set(
              createTestUser(
                id: replacer2Id,
                firstName: 'Charlie',
                lastName: 'Replacer2',
              ),
            );

        // Créer le planning
        await firestore.collection('plannings').doc('planning-123').set(
              createTestPlanning(
                id: 'planning-123',
                agentsId: [],
              ),
            );

        // ACT - Tenter deux acceptations simultanées
        // Avec le vrai émulateur, la transaction devrait empêcher les doubles acceptations
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
          reason: 'Un seul utilisateur devrait pouvoir accepter avec transaction atomique',
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
        final requestDoc = await firestore
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
        final subshifts = await firestore.collection('subshifts').get();
        expect(
          subshifts.docs.length,
          equals(1),
          reason: 'Un seul subshift devrait être créé grâce à la transaction',
        );

        // Vérifier que le subshift a le bon replacerId
        final subshift = subshifts.docs.first;
        expect(subshift.data()['replacerId'], equals(replacerId));
      },
    );

    test(
      'EMULATOR: Trois utilisateurs tentent d\'accepter - un seul réussit',
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

        await firestore
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
          await firestore.collection('users').doc(userId).set(
                createTestUser(id: userId),
              );
        }

        await firestore.collection('plannings').doc('planning-123').set(
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

        expect(
          successCount,
          equals(1),
          reason: 'Un seul devrait réussir avec transaction atomique',
        );
        expect(
          errorCount,
          equals(2),
          reason: 'Deux devraient échouer',
        );

        // Vérifier qu'un seul subshift existe
        final subshifts = await firestore.collection('subshifts').get();
        expect(
          subshifts.docs.length,
          equals(1),
          reason: 'Un seul subshift grâce à la transaction',
        );
      },
    );
  });
}

/// Nettoie toutes les collections de Firestore Emulator
Future<void> _clearFirestore(FirebaseFirestore firestore) async {
  // Nettoyer les collections utilisées dans les tests
  final collections = [
    'replacementRequests',
    'users',
    'plannings',
    'subshifts',
    'availabilities',
  ];

  for (final collectionName in collections) {
    final snapshot = await firestore.collection(collectionName).get();
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }
}
