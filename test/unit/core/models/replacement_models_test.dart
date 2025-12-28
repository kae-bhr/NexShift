/// Tests de sérialisation des nouveaux modèles de remplacement
/// Phase 1 - Fondations
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexshift_app/core/data/models/replacement_acceptance_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_proposal_model.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';

void main() {
  group('ReplacementAcceptance Model', () {
    test('toJson: Convertit ReplacementAcceptance en JSON', () {
      // ARRANGE
      final acceptance = ReplacementAcceptance(
        id: 'acceptance-1',
        requestId: 'request-1',
        userId: 'user-1',
        userName: 'Jean Dupont',
        acceptedStartTime: DateTime(2025, 12, 15, 10, 0),
        acceptedEndTime: DateTime(2025, 12, 15, 18, 0),
        status: ReplacementAcceptanceStatus.pendingValidation,
        createdAt: DateTime(2025, 12, 10, 14, 0),
      );

      // ACT
      final json = acceptance.toJson();

      // ASSERT
      expect(json['id'], equals('acceptance-1'));
      expect(json['requestId'], equals('request-1'));
      expect(json['userId'], equals('user-1'));
      expect(json['userName'], equals('Jean Dupont'));
      expect(json['status'], equals('pendingValidation'));
      expect(json['acceptedStartTime'], isA<Timestamp>());
      expect(json['acceptedEndTime'], isA<Timestamp>());
      expect(json['createdAt'], isA<Timestamp>());
    });

    test('fromJson: Parse ReplacementAcceptance depuis JSON', () {
      // ARRANGE
      final json = {
        'id': 'acceptance-2',
        'requestId': 'request-2',
        'userId': 'user-2',
        'userName': 'Marie Martin',
        'acceptedStartTime': Timestamp.fromDate(DateTime(2025, 12, 16, 8, 0)),
        'acceptedEndTime': Timestamp.fromDate(DateTime(2025, 12, 16, 16, 0)),
        'status': 'validated',
        'validatedBy': 'chief-1',
        'validationComment': 'OK pour le remplacement',
        'createdAt': Timestamp.fromDate(DateTime(2025, 12, 11, 9, 0)),
        'validatedAt': Timestamp.fromDate(DateTime(2025, 12, 11, 15, 0)),
      };

      // ACT
      final acceptance = ReplacementAcceptance.fromJson(json);

      // ASSERT
      expect(acceptance.id, equals('acceptance-2'));
      expect(acceptance.requestId, equals('request-2'));
      expect(acceptance.userName, equals('Marie Martin'));
      expect(acceptance.status, equals(ReplacementAcceptanceStatus.validated));
      expect(acceptance.validatedBy, equals('chief-1'));
      expect(acceptance.validationComment, equals('OK pour le remplacement'));
      expect(acceptance.acceptedStartTime, equals(DateTime(2025, 12, 16, 8, 0)));
      expect(acceptance.validatedAt, equals(DateTime(2025, 12, 11, 15, 0)));
    });

    test('copyWith: Crée une copie avec modifications', () {
      // ARRANGE
      final acceptance = ReplacementAcceptance(
        id: 'acceptance-3',
        requestId: 'request-3',
        userId: 'user-3',
        userName: 'Pierre Durand',
        acceptedStartTime: DateTime(2025, 12, 17, 10, 0),
        acceptedEndTime: DateTime(2025, 12, 17, 18, 0),
        status: ReplacementAcceptanceStatus.pendingValidation,
        createdAt: DateTime(2025, 12, 12, 10, 0),
      );

      // ACT
      final validated = acceptance.copyWith(
        status: ReplacementAcceptanceStatus.validated,
        validatedBy: 'chief-2',
        validatedAt: DateTime(2025, 12, 12, 16, 0),
      );

      // ASSERT
      expect(validated.id, equals('acceptance-3'));
      expect(validated.status, equals(ReplacementAcceptanceStatus.validated));
      expect(validated.validatedBy, equals('chief-2'));
      expect(validated.validatedAt, equals(DateTime(2025, 12, 12, 16, 0)));
    });
  });

  group('ShiftExchangeRequest Model', () {
    test('toJson: Convertit ShiftExchangeRequest en JSON', () {
      // ARRANGE
      final request = ShiftExchangeRequest(
        id: 'exchange-1',
        requesterId: 'user-1',
        requesterName: 'Alice Moreau',
        proposedPlanningId: 'planning-1',
        proposedStartTime: DateTime(2025, 12, 20, 8, 0),
        proposedEndTime: DateTime(2025, 12, 20, 20, 0),
        stationId: 'station-1',
        teamId: 'team-A',
        status: ShiftExchangeRequestStatus.pending,
        mode: ReplacementMode.similarity,
        createdAt: DateTime(2025, 12, 13, 11, 0),
      );

      // ACT
      final json = request.toJson();

      // ASSERT
      expect(json['id'], equals('exchange-1'));
      expect(json['requesterId'], equals('user-1'));
      expect(json['requesterName'], equals('Alice Moreau'));
      expect(json['status'], equals('pending'));
      expect(json['mode'], equals('similarity'));
      expect(json['currentWave'], equals(0));
      expect(json['notifiedUserIds'], isA<List>());
      expect(json['proposedStartTime'], isA<Timestamp>());
    });

    test('fromJson: Parse ShiftExchangeRequest depuis JSON', () {
      // ARRANGE
      final json = {
        'id': 'exchange-2',
        'requesterId': 'user-2',
        'requesterName': 'Bob Lemoine',
        'proposedPlanningId': 'planning-2',
        'proposedStartTime': Timestamp.fromDate(DateTime(2025, 12, 21, 8, 0)),
        'proposedEndTime': Timestamp.fromDate(DateTime(2025, 12, 21, 20, 0)),
        'stationId': 'station-2',
        'teamId': 'team-B',
        'status': 'completed',
        'currentWave': 2,
        'notifiedUserIds': ['user-3', 'user-4'],
        'mode': 'similarity',
        'createdAt': Timestamp.fromDate(DateTime(2025, 12, 14, 10, 0)),
        'completedAt': Timestamp.fromDate(DateTime(2025, 12, 14, 18, 0)),
      };

      // ACT
      final request = ShiftExchangeRequest.fromJson(json);

      // ASSERT
      expect(request.id, equals('exchange-2'));
      expect(request.requesterName, equals('Bob Lemoine'));
      expect(request.status, equals(ShiftExchangeRequestStatus.completed));
      expect(request.currentWave, equals(2));
      expect(request.notifiedUserIds.length, equals(2));
      expect(request.mode, equals(ReplacementMode.similarity));
      expect(request.completedAt, equals(DateTime(2025, 12, 14, 18, 0)));
    });
  });

  group('ShiftExchangeProposal Model', () {
    test('toJson: Convertit ShiftExchangeProposal en JSON', () {
      // ARRANGE
      final proposal = ShiftExchangeProposal(
        id: 'proposal-1',
        exchangeRequestId: 'exchange-1',
        proposerId: 'user-3',
        proposerName: 'Charlie Dubois',
        proposedPlanningId: 'planning-3',
        proposedStartTime: DateTime(2025, 12, 22, 8, 0),
        proposedEndTime: DateTime(2025, 12, 22, 20, 0),
        status: ShiftExchangeProposalStatus.pendingRequester,
        createdAt: DateTime(2025, 12, 15, 12, 0),
      );

      // ACT
      final json = proposal.toJson();

      // ASSERT
      expect(json['id'], equals('proposal-1'));
      expect(json['exchangeRequestId'], equals('exchange-1'));
      expect(json['proposerId'], equals('user-3'));
      expect(json['proposerName'], equals('Charlie Dubois'));
      expect(json['status'], equals('pendingRequester'));
      expect(json['requesterResponse'], equals('pending'));
      expect(json['proposedStartTime'], isA<Timestamp>());
    });

    test('fromJson: Parse ShiftExchangeProposal depuis JSON', () {
      // ARRANGE
      final json = {
        'id': 'proposal-2',
        'exchangeRequestId': 'exchange-2',
        'proposerId': 'user-4',
        'proposerName': 'Diana Rousseau',
        'proposedPlanningId': 'planning-4',
        'proposedStartTime': Timestamp.fromDate(DateTime(2025, 12, 23, 8, 0)),
        'proposedEndTime': Timestamp.fromDate(DateTime(2025, 12, 23, 20, 0)),
        'status': 'acceptedByRequester',
        'requesterResponse': 'accepted',
        'requesterResponseAt': Timestamp.fromDate(DateTime(2025, 12, 16, 10, 0)),
        'leaderValidations': {},
        'createdAt': Timestamp.fromDate(DateTime(2025, 12, 16, 9, 0)),
      };

      // ACT
      final proposal = ShiftExchangeProposal.fromJson(json);

      // ASSERT
      expect(proposal.id, equals('proposal-2'));
      expect(proposal.proposerName, equals('Diana Rousseau'));
      expect(proposal.status, equals(ShiftExchangeProposalStatus.acceptedByRequester));
      expect(proposal.requesterResponse, equals(RequesterResponse.accepted));
      expect(proposal.requesterResponseAt, equals(DateTime(2025, 12, 16, 10, 0)));
    });

    test('leaderValidations: Parse et convertit les validations', () {
      // ARRANGE
      final json = {
        'id': 'proposal-3',
        'exchangeRequestId': 'exchange-3',
        'proposerId': 'user-5',
        'proposerName': 'Eric Bernard',
        'proposedPlanningId': 'planning-5',
        'proposedStartTime': Timestamp.fromDate(DateTime(2025, 12, 24, 8, 0)),
        'proposedEndTime': Timestamp.fromDate(DateTime(2025, 12, 24, 20, 0)),
        'status': 'validatedByLeaders',
        'requesterResponse': 'accepted',
        'leaderValidations': {
          'chief-1': {
            'validated': true,
            'validatedAt': Timestamp.fromDate(DateTime(2025, 12, 17, 14, 0)),
            'comment': 'Approuvé',
          },
          'chief-2': {
            'validated': true,
            'validatedAt': Timestamp.fromDate(DateTime(2025, 12, 17, 15, 0)),
          },
        },
        'createdAt': Timestamp.fromDate(DateTime(2025, 12, 17, 9, 0)),
      };

      // ACT
      final proposal = ShiftExchangeProposal.fromJson(json);

      // ASSERT
      expect(proposal.leaderValidations.length, equals(2));
      expect(proposal.leaderValidations.containsKey('chief-1'), isTrue);
      expect(proposal.leaderValidations['chief-1']!.validated, isTrue);
      expect(proposal.leaderValidations['chief-1']!.comment, equals('Approuvé'));
      expect(proposal.allLeadersValidated, isTrue);
      expect(proposal.anyLeaderRejected, isFalse);
    });

    test('allLeadersValidated: Retourne true si 2 chefs ont validé', () {
      // ARRANGE
      final proposal = ShiftExchangeProposal(
        id: 'proposal-4',
        exchangeRequestId: 'exchange-4',
        proposerId: 'user-6',
        proposerName: 'Fanny Petit',
        proposedPlanningId: 'planning-6',
        proposedStartTime: DateTime(2025, 12, 25, 8, 0),
        proposedEndTime: DateTime(2025, 12, 25, 20, 0),
        status: ShiftExchangeProposalStatus.pendingLeaders,
        leaderValidations: {
          'chief-1': LeaderValidation(
            validated: true,
            validatedAt: DateTime(2025, 12, 18, 10, 0),
          ),
          'chief-2': LeaderValidation(
            validated: true,
            validatedAt: DateTime(2025, 12, 18, 11, 0),
          ),
        },
        createdAt: DateTime(2025, 12, 18, 9, 0),
      );

      // ACT & ASSERT
      expect(proposal.allLeadersValidated, isTrue);
      expect(proposal.anyLeaderRejected, isFalse);
    });

    test('anyLeaderRejected: Retourne true si au moins un chef a refusé', () {
      // ARRANGE
      final proposal = ShiftExchangeProposal(
        id: 'proposal-5',
        exchangeRequestId: 'exchange-5',
        proposerId: 'user-7',
        proposerName: 'Georges Leroy',
        proposedPlanningId: 'planning-7',
        proposedStartTime: DateTime(2025, 12, 26, 8, 0),
        proposedEndTime: DateTime(2025, 12, 26, 20, 0),
        status: ShiftExchangeProposalStatus.pendingLeaders,
        leaderValidations: {
          'chief-1': LeaderValidation(
            validated: true,
            validatedAt: DateTime(2025, 12, 19, 10, 0),
          ),
          'chief-2': LeaderValidation(
            validated: false,
            validatedAt: DateTime(2025, 12, 19, 11, 0),
            comment: 'Non compatible',
          ),
        },
        createdAt: DateTime(2025, 12, 19, 9, 0),
      );

      // ACT & ASSERT
      expect(proposal.allLeadersValidated, isFalse);
      expect(proposal.anyLeaderRejected, isTrue);
    });
  });

  group('ReplacementMode Enum', () {
    test('Conversion toString et parsing', () {
      expect(ReplacementMode.similarity.toString().split('.').last, equals('similarity'));
      expect(ReplacementMode.manual.toString().split('.').last, equals('manual'));
      expect(ReplacementMode.availability.toString().split('.').last, equals('availability'));
    });
  });
}
