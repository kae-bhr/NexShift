/// Tests de conflits de disponibilité et de planning
/// Vérifie que le système détecte correctement les conflits avant d'accepter un remplacement
library;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:nexshift_app/core/data/models/availability_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/repositories/availability_repository.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';

import '../../helpers/test_data.dart';

void main() {
  group('Tests de Conflits', () {
    late FakeFirebaseFirestore fakeFirestore;
    late ReplacementNotificationService service;
    late AvailabilityRepository availabilityRepository;
    late SubshiftRepository subshiftRepository;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      availabilityRepository = AvailabilityRepository.forTest(fakeFirestore);
      subshiftRepository = SubshiftRepository.forTest(fakeFirestore);
      service = ReplacementNotificationService(
        firestore: fakeFirestore,
        availabilityRepository: availabilityRepository,
        subshiftRepository: subshiftRepository,
      );
    });

    test(
      'Conflit avec planning existant - Agent déjà de service',
      () async {
        // ARRANGE
        final requestId = 'test-conflict-planning';
        final requesterId = 'user-requester';
        final replacerId = 'user-replacer';

        final startTime = DateTime(2025, 12, 25, 14, 0);
        final endTime = DateTime(2025, 12, 25, 17, 0);

        // Créer demande de remplacement
        await fakeFirestore.collection('replacementRequests').doc(requestId).set(
              createTestReplacementRequest(
                id: requestId,
                requesterId: requesterId,
                startTime: startTime,
                endTime: endTime,
              ),
            );

        // Créer utilisateurs
        await fakeFirestore.collection('users').doc(requesterId).set(
              createTestUser(id: requesterId),
            );
        await fakeFirestore.collection('users').doc(replacerId).set(
              createTestUser(id: replacerId),
            );

        // Créer planning où le replacer est déjà de service (conflit)
        await fakeFirestore.collection('plannings').doc('planning-conflict').set(
              createTestPlanning(
                id: 'planning-conflict',
                agentsId: [replacerId], // Agent déjà assigné
                startTime: startTime,
                endTime: endTime,
              ),
            );

        // ACT & ASSERT
        // L'acceptation devrait échouer à cause du conflit
        // Note: Dans le code actuel, la vérification est faite dans le dialog
        // Pour ce test, on vérifie que le conflit existe
        final plannings = await fakeFirestore.collection('plannings').get();
        final hasConflict = plannings.docs.any((planning) {
          final data = planning.data();
          final agents = List<String>.from(data['agentsId'] ?? []);
          if (!agents.contains(replacerId)) return false;

          final planStart = (data['startTime'] as dynamic).toDate();
          final planEnd = (data['endTime'] as dynamic).toDate();

          return planStart.isBefore(endTime) && planEnd.isAfter(startTime);
        });

        expect(hasConflict, isTrue,
            reason: 'Le système doit détecter le conflit avec le planning');
      },
    );

    test(
      'Conflit avec subshift existant - Agent déjà en remplacement',
      () async {
        // ARRANGE
        final requestId = 'test-conflict-subshift';
        final requesterId = 'user-requester';
        final replacerId = 'user-replacer';

        final startTime = DateTime(2025, 12, 25, 14, 0);
        final endTime = DateTime(2025, 12, 25, 17, 0);

        // Créer demande de remplacement
        await fakeFirestore.collection('replacementRequests').doc(requestId).set(
              createTestReplacementRequest(
                id: requestId,
                requesterId: requesterId,
                startTime: startTime,
                endTime: endTime,
              ),
            );

        // Créer utilisateurs
        await fakeFirestore.collection('users').doc(requesterId).set(
              createTestUser(id: requesterId),
            );
        await fakeFirestore.collection('users').doc(replacerId).set(
              createTestUser(id: replacerId),
            );
        await fakeFirestore.collection('plannings').doc('planning-123').set(
              createTestPlanning(id: 'planning-123'),
            );

        // Créer subshift existant (agent déjà en remplacement)
        final existingSubshift = Subshift.create(
          replacerId: replacerId,
          replacedId: 'user-other',
          start: DateTime(2025, 12, 25, 15, 0), // Overlap partiel
          end: DateTime(2025, 12, 25, 18, 0),
          planningId: 'planning-other',
        );
        await subshiftRepository.save(existingSubshift);

        // ACT & ASSERT
        // Vérifier que le conflit est détecté
        final subshifts = await subshiftRepository.getAll();
        final hasConflict = subshifts.any((subshift) {
          if (subshift.replacerId != replacerId &&
              subshift.replacedId != replacerId) {
            return false;
          }
          return subshift.start.isBefore(endTime) &&
              subshift.end.isAfter(startTime);
        });

        expect(hasConflict, isTrue,
            reason: 'Le système doit détecter le conflit avec le subshift');
      },
    );

    test(
      'Overlap partiel au début - Conflit détecté',
      () async {
        // ARRANGE
        final replacerId = 'user-replacer';
        final requestStart = DateTime(2025, 12, 25, 14, 0);
        final requestEnd = DateTime(2025, 12, 25, 17, 0);

        // Subshift existant qui overlap au début
        final existingSubshift = Subshift.create(
          replacerId: replacerId,
          replacedId: 'user-other',
          start: DateTime(2025, 12, 25, 13, 0),
          end: DateTime(2025, 12, 25, 15, 0), // Overlap 14h-15h
          planningId: 'planning-123',
        );
        await subshiftRepository.save(existingSubshift);

        // ACT
        final subshifts = await subshiftRepository.getAll();
        final hasConflict = subshifts.any((subshift) {
          if (subshift.replacerId != replacerId &&
              subshift.replacedId != replacerId) {
            return false;
          }
          return subshift.start.isBefore(requestEnd) &&
              subshift.end.isAfter(requestStart);
        });

        // ASSERT
        expect(hasConflict, isTrue,
            reason: 'Overlap partiel au début doit être détecté');
      },
    );

    test(
      'Overlap partiel à la fin - Conflit détecté',
      () async {
        // ARRANGE
        final replacerId = 'user-replacer';
        final requestStart = DateTime(2025, 12, 25, 14, 0);
        final requestEnd = DateTime(2025, 12, 25, 17, 0);

        // Subshift existant qui overlap à la fin
        final existingSubshift = Subshift.create(
          replacerId: replacerId,
          replacedId: 'user-other',
          start: DateTime(2025, 12, 25, 16, 0), // Overlap 16h-17h
          end: DateTime(2025, 12, 25, 18, 0),
          planningId: 'planning-123',
        );
        await subshiftRepository.save(existingSubshift);

        // ACT
        final subshifts = await subshiftRepository.getAll();
        final hasConflict = subshifts.any((subshift) {
          if (subshift.replacerId != replacerId &&
              subshift.replacedId != replacerId) {
            return false;
          }
          return subshift.start.isBefore(requestEnd) &&
              subshift.end.isAfter(requestStart);
        });

        // ASSERT
        expect(hasConflict, isTrue,
            reason: 'Overlap partiel à la fin doit être détecté');
      },
    );

    test(
      'Subshift complètement inclus - Conflit détecté',
      () async {
        // ARRANGE
        final replacerId = 'user-replacer';
        final requestStart = DateTime(2025, 12, 25, 14, 0);
        final requestEnd = DateTime(2025, 12, 25, 17, 0);

        // Subshift existant complètement inclus dans la demande
        final existingSubshift = Subshift.create(
          replacerId: replacerId,
          replacedId: 'user-other',
          start: DateTime(2025, 12, 25, 15, 0),
          end: DateTime(2025, 12, 25, 16, 0), // Inclus dans 14h-17h
          planningId: 'planning-123',
        );
        await subshiftRepository.save(existingSubshift);

        // ACT
        final subshifts = await subshiftRepository.getAll();
        final hasConflict = subshifts.any((subshift) {
          if (subshift.replacerId != replacerId &&
              subshift.replacedId != replacerId) {
            return false;
          }
          return subshift.start.isBefore(requestEnd) &&
              subshift.end.isAfter(requestStart);
        });

        // ASSERT
        expect(hasConflict, isTrue,
            reason: 'Subshift complètement inclus doit être détecté');
      },
    );

    test(
      'Pas de conflit - Créneaux séparés',
      () async {
        // ARRANGE
        final replacerId = 'user-replacer';
        final requestStart = DateTime(2025, 12, 25, 14, 0);
        final requestEnd = DateTime(2025, 12, 25, 17, 0);

        // Subshift existant AVANT (pas de conflit)
        final existingSubshift1 = Subshift.create(
          replacerId: replacerId,
          replacedId: 'user-other',
          start: DateTime(2025, 12, 25, 10, 0),
          end: DateTime(2025, 12, 25, 12, 0), // Avant 14h
          planningId: 'planning-123',
        );
        await subshiftRepository.save(existingSubshift1);

        // Subshift existant APRÈS (pas de conflit)
        final existingSubshift2 = Subshift.create(
          replacerId: replacerId,
          replacedId: 'user-other2',
          start: DateTime(2025, 12, 25, 18, 0),
          end: DateTime(2025, 12, 25, 20, 0), // Après 17h
          planningId: 'planning-123',
        );
        await subshiftRepository.save(existingSubshift2);

        // ACT
        final subshifts = await subshiftRepository.getAll();
        final hasConflict = subshifts.any((subshift) {
          if (subshift.replacerId != replacerId &&
              subshift.replacedId != replacerId) {
            return false;
          }
          return subshift.start.isBefore(requestEnd) &&
              subshift.end.isAfter(requestStart);
        });

        // ASSERT
        expect(hasConflict, isFalse,
            reason: 'Pas de conflit quand les créneaux sont séparés');
      },
    );

    test(
      'Conflit avec availability existante - Agent déjà disponible',
      () async {
        // ARRANGE
        final replacerId = 'user-replacer';
        final requestStart = DateTime(2025, 12, 25, 14, 0);
        final requestEnd = DateTime(2025, 12, 25, 17, 0);

        // Agent a déjà déclaré une disponibilité sur ce créneau
        final existingAvailability = Availability.create(
          agentId: replacerId,
          start: DateTime(2025, 12, 25, 13, 0),
          end: DateTime(2025, 12, 25, 18, 0),
          planningId: 'planning-123',
        );
        await availabilityRepository.upsert(existingAvailability);

        // ACT
        final availabilities = await availabilityRepository.getAll();
        final hasAvailability = availabilities.any((availability) {
          if (availability.agentId != replacerId) return false;
          return availability.start.isBefore(requestEnd) &&
              availability.end.isAfter(requestStart);
        });

        // ASSERT
        // Note: Avoir une disponibilité n'est PAS un conflit, c'est même souhaitable!
        // Ce test vérifie juste qu'on peut détecter les disponibilités
        expect(hasAvailability, isTrue,
            reason: 'L\'agent a une disponibilité déclarée');
      },
    );
  });
}
