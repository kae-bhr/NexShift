import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_proposal_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/repositories/shift_exchange_repository.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:nexshift_app/core/services/shift_exchange_notification_service.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart'
    show SDISContext;
import 'package:nexshift_app/core/utils/constants.dart';

/// Service pour gérer les échanges d'astreinte
class ShiftExchangeService {
  final ShiftExchangeRepository _exchangeRepository;
  final SubshiftRepository _subshiftRepository;
  final UserRepository _userRepository;
  final PlanningRepository _planningRepository;
  final ShiftExchangeNotificationService _notificationService;

  ShiftExchangeService({
    ShiftExchangeRepository? exchangeRepository,
    SubshiftRepository? subshiftRepository,
    UserRepository? userRepository,
    PlanningRepository? planningRepository,
    ShiftExchangeNotificationService? notificationService,
  }) : _exchangeRepository = exchangeRepository ?? ShiftExchangeRepository(),
       _subshiftRepository = subshiftRepository ?? SubshiftRepository(),
       _userRepository = userRepository ?? UserRepository(),
       _planningRepository = planningRepository ?? PlanningRepository(),
       _notificationService =
           notificationService ?? ShiftExchangeNotificationService();

  /// Crée une demande d'échange d'astreinte
  ///
  /// 1. Agent A sélectionne son astreinte à échanger (planning future)
  /// 2. Créer ShiftExchangeRequest avec requiredKeySkills = keySkills de A
  /// 3. Demande devient visible dans "Demandes disponibles"
  Future<ShiftExchangeRequest> createExchangeRequest({
    required String initiatorId,
    required String planningId,
    required String station,
  }) async {
    try {
      // Récupérer l'utilisateur initiateur
      final initiator = await _userRepository.getById(
        initiatorId,
        stationId: station,
      );
      if (initiator == null) {
        throw Exception('Initiateur non trouvé: $initiatorId');
      }

      // Vérifier que l'initiateur n'est pas suspendu ou en arrêt maladie
      if (!initiator.isActiveForReplacement) {
        throw Exception(
            'Vous ne pouvez pas créer de demande d\'échange en raison de votre statut actuel.');
      }

      // Récupérer le planning
      final planning = await _planningRepository.getById(
        planningId,
        stationId: station,
      );
      if (planning == null) {
        throw Exception('Planning non trouvé: $planningId');
      }

      // Vérifier que le planning est dans le futur
      if (planning.startTime.isBefore(DateTime.now())) {
        throw Exception('Le planning doit être dans le futur');
      }

      // Vérifier qu'il n'y a pas de chevauchement avec des demandes existantes
      final hasOverlap = await _hasOverlappingRequests(
        userId: initiatorId,
        planningId: planningId,
        startTime: planning.startTime,
        endTime: planning.endTime,
        stationId: station,
      );
      if (hasOverlap) {
        throw Exception(
            'Vous avez déjà une demande en cours sur cette période.');
      }

      // Créer la demande
      final request = ShiftExchangeRequest(
        id: const Uuid().v4(),
        initiatorId: initiatorId,
        initiatorName: initiator.displayName,
        initiatorPlanningId: planningId,
        initiatorStartTime: planning.startTime,
        initiatorEndTime: planning.endTime,
        station: station,
        initiatorTeam: planning.team, // Équipe de l'initiateur pour filtrage badges
        requiredKeySkills: initiator.keySkills,
        status: ShiftExchangeRequestStatus.open,
        createdAt: DateTime.now(),
        proposalIds: [],
      );

      // Sauvegarder
      await _exchangeRepository.upsertRequest(request, stationId: station);

      debugPrint('✅ Demande d\'échange créée: ${request.id}');
      return request;
    } catch (e) {
      debugPrint('❌ Erreur lors de la création de la demande d\'échange: $e');
      rethrow;
    }
  }

  /// Vérifie s'il existe des demandes en cours qui chevauchent la période donnée
  /// Inclut les demandes automatiques, manuelles et les échanges
  Future<bool> _hasOverlappingRequests({
    required String userId,
    required String planningId,
    required DateTime startTime,
    required DateTime endTime,
    required String stationId,
  }) async {
    try {
      bool overlaps(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
        return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
      }

      // 1. Vérifier les demandes automatiques
      final automaticPath = EnvironmentConfig.getCollectionPath(
        'replacements/automatic/replacementRequests',
        stationId,
      );

      final automaticSnapshot = await FirebaseFirestore.instance
          .collection(automaticPath)
          .where('requesterId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .get();

      for (final doc in automaticSnapshot.docs) {
        final data = doc.data();
        final reqStart = (data['startTime'] as Timestamp).toDate();
        final reqEnd = (data['endTime'] as Timestamp).toDate();
        if (overlaps(startTime, endTime, reqStart, reqEnd)) {
          debugPrint('⚠️ Chevauchement détecté avec demande automatique: ${doc.id}');
          return true;
        }
      }

      // 2. Vérifier les demandes manuelles
      final manualPath = EnvironmentConfig.getCollectionPath(
        'replacements/manual/proposals',
        stationId,
      );

      final manualSnapshot = await FirebaseFirestore.instance
          .collection(manualPath)
          .where('replacedId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .get();

      for (final doc in manualSnapshot.docs) {
        final data = doc.data();
        final reqStart = (data['startTime'] as Timestamp).toDate();
        final reqEnd = (data['endTime'] as Timestamp).toDate();
        if (overlaps(startTime, endTime, reqStart, reqEnd)) {
          debugPrint('⚠️ Chevauchement détecté avec demande manuelle: ${doc.id}');
          return true;
        }
      }

      // 3. Vérifier les demandes d'échange existantes
      final exchangePath = EnvironmentConfig.getCollectionPath(
        'shiftExchangeRequests',
        stationId,
      );

      final exchangeSnapshot = await FirebaseFirestore.instance
          .collection(exchangePath)
          .where('initiatorId', isEqualTo: userId)
          .where('status', whereIn: ['open', 'proposalSelected'])
          .get();

      for (final doc in exchangeSnapshot.docs) {
        final data = doc.data();
        final reqStart = (data['initiatorStartTime'] as Timestamp).toDate();
        final reqEnd = (data['initiatorEndTime'] as Timestamp).toDate();
        if (overlaps(startTime, endTime, reqStart, reqEnd)) {
          debugPrint('⚠️ Chevauchement détecté avec demande d\'échange: ${doc.id}');
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('❌ Erreur lors de la vérification des chevauchements: $e');
      return false; // En cas d'erreur, permettre la création (fail-open)
    }
  }

  /// Annule une demande d'échange
  Future<void> cancelExchangeRequest({
    required String requestId,
    required String stationId,
  }) async {
    try {
      final request = await _exchangeRepository.getRequestById(
        requestId,
        stationId: stationId,
      );
      if (request == null) {
        throw Exception('Demande non trouvée: $requestId');
      }

      // Mettre à jour le statut
      final updated = request.copyWith(
        status: ShiftExchangeRequestStatus.cancelled,
      );

      await _exchangeRepository.upsertRequest(updated, stationId: stationId);

      // Supprimer toutes les propositions associées
      await _exchangeRepository.deleteProposalsByRequestId(
        requestId,
        stationId: stationId,
      );

      debugPrint('✅ Demande d\'échange annulée: $requestId');
    } catch (e) {
      debugPrint('❌ Erreur lors de l\'annulation de la demande: $e');
      rethrow;
    }
  }

  /// Refuse une demande d'échange pour un utilisateur donné
  /// L'utilisateur ne verra plus cette demande dans sa liste de demandes disponibles
  Future<void> refuseExchangeRequest({
    required String requestId,
    required String userId,
    required String stationId,
  }) async {
    try {
      final request = await _exchangeRepository.getRequestById(
        requestId,
        stationId: stationId,
      );
      if (request == null) {
        throw Exception('Demande non trouvée: $requestId');
      }

      // Vérifier que la demande est ouverte
      if (request.status != ShiftExchangeRequestStatus.open) {
        throw Exception('La demande n\'est plus ouverte');
      }

      // Vérifier que l'utilisateur n'a pas déjà refusé
      if (request.refusedByUserIds.contains(userId)) {
        debugPrint(
          '⚠️ L\'utilisateur $userId a déjà refusé la demande $requestId',
        );
        return;
      }

      // Ajouter l'utilisateur à la liste des refus
      final updatedRequest = request.copyWith(
        refusedByUserIds: [...request.refusedByUserIds, userId],
      );

      await _exchangeRepository.upsertRequest(
        updatedRequest,
        stationId: stationId,
      );

      debugPrint('✅ Demande $requestId refusée par l\'utilisateur $userId');
    } catch (e) {
      debugPrint('❌ Erreur lors du refus de la demande: $e');
      rethrow;
    }
  }

  /// Crée une proposition pour une demande d'échange
  ///
  /// 1. Agent B voit la demande et répond
  /// 2. Vérifier que B possède toutes les requiredKeySkills
  /// 3. B sélectionne PLUSIEURS astreintes futures
  /// 4. Créer ShiftExchangeProposal avec propositions multiples
  /// 5. Notifier agent A qu'une nouvelle proposition est arrivée
  Future<ShiftExchangeProposal> createProposal({
    required String requestId,
    required String proposerId,
    required List<String>
    planningIds, // MODIFIÉ: liste au lieu de string unique
    required String stationId,
  }) async {
    try {
      // Récupérer la demande
      final request = await _exchangeRepository.getRequestById(
        requestId,
        stationId: stationId,
      );
      if (request == null) {
        throw Exception('Demande non trouvée: $requestId');
      }

      if (request.status != ShiftExchangeRequestStatus.open) {
        throw Exception('La demande n\'est plus ouverte');
      }

      // Récupérer le proposeur
      final proposer = await _userRepository.getById(
        proposerId,
        stationId: stationId,
      );
      if (proposer == null) {
        throw Exception('Proposeur non trouvé: $proposerId');
      }

      // Vérifier que le proposeur n'est pas suspendu ou en arrêt maladie
      if (!proposer.isActiveForReplacement) {
        throw Exception(
            'Vous ne pouvez pas soumettre de proposition en raison de votre statut actuel.');
      }

      // Vérifier que le proposeur possède toutes les compétences requises
      // Utiliser skills au lieu de keySkills car requiredKeySkills contient les keySkills de l'initiateur,
      // mais on vérifie que le proposeur possède ces compétences dans ses skills standards
      final proposerSkillsSet = Set<String>.from(proposer.skills);
      final requiredSkillsSet = Set<String>.from(request.requiredKeySkills);
      final missingSkills = requiredSkillsSet.difference(proposerSkillsSet);

      if (missingSkills.isNotEmpty) {
        throw Exception('Compétences manquantes: ${missingSkills.join(", ")}');
      }

      // Vérifier que la liste de plannings n'est pas vide
      if (planningIds.isEmpty) {
        throw Exception('Au moins une astreinte doit être proposée');
      }

      // Valider tous les plannings proposés
      for (final planningId in planningIds) {
        final planning = await _planningRepository.getById(
          planningId,
          stationId: stationId,
        );
        if (planning == null) {
          throw Exception('Planning non trouvé: $planningId');
        }

        // Vérifier que le planning est dans le futur
        if (planning.startTime.isBefore(DateTime.now())) {
          throw Exception('Le planning $planningId doit être dans le futur');
        }

        // Vérifier que le proposeur fait partie des agents du planning
        if (!planning.agentsId.contains(proposerId)) {
          throw Exception(
            'Le planning $planningId n\'inclut pas le proposeur dans son équipe',
          );
        }
      }

      // Récupérer le premier planning pour extraire l'équipe du proposeur
      final firstPlanning = await _planningRepository.getById(
        planningIds.first,
        stationId: stationId,
      );
      final proposerTeamId = firstPlanning?.team;

      // Déterminer si le proposeur est chef de son équipe
      final isProposerChief =
          proposer.status == KConstants.statusChief ||
          proposer.status == KConstants.statusLeader;

      // Créer la proposition avec propositions multiples
      final proposal = ShiftExchangeProposal(
        id: const Uuid().v4(),
        requestId: requestId,
        proposerId: proposerId,
        proposerName: proposer.displayName,
        proposedPlanningIds: planningIds,
        isProposerChief: isProposerChief,
        proposerTeamId: proposerTeamId,
        status: ShiftExchangeProposalStatus
            .pendingSelection, // MODIFIÉ: en attente de sélection par A
        createdAt: DateTime.now(),
        leaderValidations: {},
        isFinalized: false,
      );

      // Sauvegarder
      await _exchangeRepository.upsertProposal(proposal, stationId: stationId);

      // Ajouter la proposition à la demande et marquer l'utilisateur comme ayant proposé
      final updatedRequest = request.copyWith(
        proposalIds: [...request.proposalIds, proposal.id],
        proposedByUserIds: [...request.proposedByUserIds, proposerId],
      );
      await _exchangeRepository.upsertRequest(
        updatedRequest,
        stationId: stationId,
      );

      debugPrint(
        '✅ Proposition créée: ${proposal.id} avec ${planningIds.length} astreinte(s)',
      );

      // Notifier l'agent A qu'une nouvelle proposition est arrivée
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null) {
        await _notificationService.notifyProposalCreated(
          request: request,
          proposal: proposal,
          sdisId: sdisId,
          stationId: stationId,
        );
      }

      return proposal;
    } catch (e) {
      debugPrint('❌ Erreur lors de la création de la proposition: $e');
      rethrow;
    }
  }

  /// Sélectionne une proposition parmi toutes celles reçues
  ///
  /// NOUVELLE ÉTAPE: Agent A choisit UNE proposition parmi toutes celles qu'il a reçues
  /// 1. Vérifier que l'agent est bien l'initiateur de la demande
  /// 2. Vérifier que la proposition existe et est en attente de sélection
  /// 3. Marquer la proposition comme sélectionnée
  /// 4. Mettre à jour la demande avec selectedProposalId
  /// 5. Notifier les chefs des 2 équipes concernées
  Future<void> selectProposal({
    required String requestId,
    required String proposalId,
    required String
    planningId, // NOUVEAU: ID de l'astreinte spécifique sélectionnée
    required String initiatorId,
    required String stationId,
  }) async {
    try {
      // Récupérer la demande
      final request = await _exchangeRepository.getRequestById(
        requestId,
        stationId: stationId,
      );
      if (request == null) {
        throw Exception('Demande non trouvée: $requestId');
      }

      // Vérifier que l'utilisateur est bien l'initiateur
      if (request.initiatorId != initiatorId) {
        throw Exception('Seul l\'initiateur peut sélectionner une proposition');
      }

      // Vérifier que la demande est ouverte
      if (request.status != ShiftExchangeRequestStatus.open) {
        throw Exception('La demande n\'est plus ouverte');
      }

      // Récupérer la proposition
      final proposal = await _exchangeRepository.getProposalById(
        proposalId,
        stationId: stationId,
      );
      if (proposal == null) {
        throw Exception('Proposition non trouvée: $proposalId');
      }

      // Vérifier que la proposition est en attente de sélection
      if (proposal.status != ShiftExchangeProposalStatus.pendingSelection) {
        throw Exception('La proposition n\'est pas en attente de sélection');
      }

      // Vérifier que la proposition appartient bien à cette demande
      if (proposal.requestId != requestId) {
        throw Exception('La proposition n\'appartient pas à cette demande');
      }

      // Récupérer l'initiateur et son équipe
      final initiator = await _userRepository.getById(
        initiatorId,
        stationId: stationId,
      );
      if (initiator == null) {
        throw Exception('Initiateur non trouvé: $initiatorId');
      }

      // Récupérer le planning de l'initiateur pour déterminer son équipe
      final initiatorPlanning = await _planningRepository.getById(
        request.initiatorPlanningId,
        stationId: stationId,
      );
      final initiatorTeamId = initiatorPlanning?.team;

      // Vérifier si l'initiateur est chef (chief ou leader)
      final isInitiatorChief =
          initiator.status == KConstants.statusChief ||
          initiator.status == KConstants.statusLeader;

      // Vérifier que le planningId fait bien partie de la proposition
      if (!proposal.proposedPlanningIds.contains(planningId)) {
        throw Exception(
          'Le planning $planningId ne fait pas partie de cette proposition',
        );
      }

      // IMPORTANT: Réinitialiser les validations si on resélectionne une proposition
      // (cela arrive quand un chef refuse et que l'initiateur choisit une autre astreinte)
      final shouldResetValidations = proposal.leaderValidations.isNotEmpty;

      // Mettre à jour la proposition: marquer comme sélectionnée + stocker info initiateur + planning sélectionné
      var updatedProposal = proposal.copyWith(
        status: ShiftExchangeProposalStatus.selectedByInitiator,
        selectedPlanningId: planningId,
        leaderValidations: shouldResetValidations
            ? {}
            : proposal.leaderValidations, // Réinitialiser les validations
        isInitiatorChief: isInitiatorChief,
        initiatorTeamId: initiatorTeamId,
      );

      if (shouldResetValidations) {
        debugPrint(
          '✅ Validations précédentes réinitialisées (nouvelle sélection après refus)',
        );
      }
      debugPrint(
        '✅ Planning $planningId sélectionné dans la proposition $proposalId',
      );

      // NOUVEAU: Vérifier si les deux parties sont des chefs (auto-validation des deux équipes)
      // Dans ce cas, l'échange peut être finalisé immédiatement sans attendre de validation
      if (updatedProposal.canBeFinalized) {
        debugPrint(
          '🎉 Les deux parties sont des chefs - Auto-finalisation de l\'échange',
        );

        // Créer les Subshifts pour l'échange
        await _createExchangeSubshifts(updatedProposal, stationId);

        // Marquer comme validé et finalisé
        updatedProposal = updatedProposal.copyWith(
          status: ShiftExchangeProposalStatus.validated,
          acceptedAt: DateTime.now(),
          isFinalized: true,
        );

        await _exchangeRepository.upsertProposal(
          updatedProposal,
          stationId: stationId,
        );

        // Mettre à jour la demande comme acceptée
        final updatedRequest = request.copyWith(
          status: ShiftExchangeRequestStatus.accepted,
          selectedProposalId: proposalId,
          completedAt: DateTime.now(),
        );
        await _exchangeRepository.upsertRequest(
          updatedRequest,
          stationId: stationId,
        );

        debugPrint('✅ Échange finalisé automatiquement (deux chefs)');

        // Notifier les agents A et B que l'échange a été validé
        final sdisId = SDISContext().currentSDISId;
        if (sdisId != null) {
          await _notificationService.notifyExchangeValidated(
            request: updatedRequest,
            proposal: updatedProposal,
            sdisId: sdisId,
            stationId: stationId,
          );
        }

        return; // Sortir ici car l'échange est déjà finalisé
      }

      // Cas normal: sauvegarder la proposition et envoyer aux chefs pour validation
      await _exchangeRepository.upsertProposal(
        updatedProposal,
        stationId: stationId,
      );

      // Mettre à jour la demande: marquer comme proposition sélectionnée
      final updatedRequest = request.copyWith(
        status: ShiftExchangeRequestStatus.proposalSelected,
        selectedProposalId: proposalId,
      );
      await _exchangeRepository.upsertRequest(
        updatedRequest,
        stationId: stationId,
      );

      debugPrint(
        '✅ Proposition $proposalId sélectionnée par ${request.initiatorName}',
      );

      // Notifier le proposeur que sa proposition a été sélectionnée
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null) {
        await _notificationService.notifyProposerSelected(
          request: updatedRequest,
          proposal: updatedProposal,
          sdisId: sdisId,
          stationId: stationId,
        );

        // Récupérer les chefs des 2 équipes concernées
        final chiefIds = await _getChiefIdsForProposal(
          updatedRequest,
          updatedProposal,
          stationId,
        );

        // Notifier les chefs des 2 équipes qu'une validation est requise
        await _notificationService.notifyProposalSelected(
          request: updatedRequest,
          proposal: updatedProposal,
          chiefIds: chiefIds,
          sdisId: sdisId,
          stationId: stationId,
        );
      }
    } catch (e) {
      debugPrint('❌ Erreur lors de la sélection de la proposition: $e');
      rethrow;
    }
  }

  /// Valide une proposition par un chef d'équipe (LOGIQUE MULTI-CHEFS OR)
  ///
  /// NOUVELLE LOGIQUE:
  /// - Validation OR: dès que 1 chef d'une équipe accepte → équipe validée temporairement
  /// - Refus prioritaire: si un autre chef de la même équipe refuse → annule l'acceptation
  /// - Finalisation: quand les 2 équipes sont validées → créer Subshifts et bloquer
  /// - Auto-validation: si proposeur est chef, son équipe est auto-validée (pas besoin de validation)
  Future<void> validateProposal({
    required String proposalId,
    required String leaderId,
    required String teamId,
    required String stationId,
    String? comment,
  }) async {
    try {
      final proposal = await _exchangeRepository.getProposalById(
        proposalId,
        stationId: stationId,
      );
      if (proposal == null) {
        throw Exception('Proposition non trouvée: $proposalId');
      }

      // Vérifier que la proposition est sélectionnée par l'initiateur
      if (proposal.status != ShiftExchangeProposalStatus.selectedByInitiator) {
        throw Exception(
          'La proposition doit être sélectionnée avant validation',
        );
      }

      // Vérifier que l'échange n'est pas déjà finalisé
      if (proposal.isFinalized) {
        throw Exception(
          'L\'échange est déjà finalisé, aucune modification possible',
        );
      }

      // Vérifier si l'équipe a déjà refusé
      final currentStates = proposal.teamValidationStates;
      if (currentStates[teamId] == TeamValidationState.rejected) {
        throw Exception('L\'équipe $teamId a déjà refusé cet échange');
      }

      // Ajouter la validation du chef
      final validation = LeaderValidation(
        leaderId: leaderId,
        team: teamId,
        approved: true,
        comment: comment,
        validatedAt: DateTime.now(),
      );

      final updatedValidations = Map<String, LeaderValidation>.from(
        proposal.leaderValidations,
      );

      // Ajouter la validation avec une clé unique (teamId + leaderId)
      final validationKey = '${teamId}_$leaderId';
      updatedValidations[validationKey] = validation;

      var updatedProposal = proposal.copyWith(
        leaderValidations: updatedValidations,
      );

      // Recalculer les états de validation
      final newStates = updatedProposal.teamValidationStates;

      // Vérifier si l'échange peut être finalisé
      if (updatedProposal.canBeFinalized) {
        // FINALISER: Créer les Subshifts
        await _createExchangeSubshifts(updatedProposal, stationId);

        // Marquer comme validé et finalisé
        updatedProposal = updatedProposal.copyWith(
          status: ShiftExchangeProposalStatus.validated,
          acceptedAt: DateTime.now(),
          isFinalized: true,
        );

        // Mettre à jour la demande comme acceptée
        final request = await _exchangeRepository.getRequestById(
          proposal.requestId,
          stationId: stationId,
        );
        if (request != null) {
          final updatedRequest = request.copyWith(
            status: ShiftExchangeRequestStatus.accepted,
            completedAt: DateTime.now(),
          );
          await _exchangeRepository.upsertRequest(
            updatedRequest,
            stationId: stationId,
          );
        }

        debugPrint('✅ Échange finalisé et Subshifts créés');

        // Notifier les agents A et B que l'échange a été validé
        final sdisId = SDISContext().currentSDISId;
        if (sdisId != null && request != null) {
          await _notificationService.notifyExchangeValidated(
            request: request,
            proposal: updatedProposal,
            sdisId: sdisId,
            stationId: stationId,
          );
        }
      } else {
        debugPrint(
          '✅ Validation enregistrée par chef $leaderId de l\'équipe $teamId',
        );
        debugPrint(
          '   États actuels: ${newStates.map((k, v) => MapEntry(k, v.name))}',
        );
      }

      await _exchangeRepository.upsertProposal(
        updatedProposal,
        stationId: stationId,
      );
    } catch (e) {
      debugPrint('❌ Erreur lors de la validation: $e');
      rethrow;
    }
  }

  /// Rejette une proposition par un chef d'équipe (REFUS PRIORITAIRE)
  ///
  /// NOUVELLE LOGIQUE:
  /// - Le refus ANNULE toute validation temporaire de l'équipe
  /// - Le refus BLOQUE l'échange immédiatement (pas besoin d'attendre l'autre équipe)
  /// - L'échange est marqué comme rejeté et finalisé (aucune modification ultérieure)
  /// - Le motif de refus est OBLIGATOIRE et visible pour l'agent A
  Future<void> rejectProposal({
    required String proposalId,
    required String leaderId,
    required String teamId,
    required String comment,
    required String stationId,
  }) async {
    try {
      if (comment.trim().isEmpty) {
        throw Exception('Le motif de refus est obligatoire');
      }

      final proposal = await _exchangeRepository.getProposalById(
        proposalId,
        stationId: stationId,
      );
      if (proposal == null) {
        throw Exception('Proposition non trouvée: $proposalId');
      }

      // Vérifier que la proposition est sélectionnée
      if (proposal.status != ShiftExchangeProposalStatus.selectedByInitiator) {
        throw Exception(
          'La proposition doit être sélectionnée avant validation/rejet',
        );
      }

      // Vérifier que l'échange n'est pas déjà finalisé
      if (proposal.isFinalized) {
        throw Exception(
          'L\'échange est déjà finalisé, aucune modification possible',
        );
      }

      // Ajouter la validation du chef (rejet)
      final validation = LeaderValidation(
        leaderId: leaderId,
        team: teamId,
        approved: false,
        comment: comment,
        validatedAt: DateTime.now(),
      );

      final updatedValidations = Map<String, LeaderValidation>.from(
        proposal.leaderValidations,
      );

      // Ajouter la validation avec clé unique
      final validationKey = '${teamId}_$leaderId';
      updatedValidations[validationKey] = validation;

      // NOUVEAU: Ajouter uniquement le planning sélectionné à la liste des refus
      final rejectedPlannings = List<String>.from(proposal.rejectedPlanningIds);
      if (proposal.selectedPlanningId != null &&
          !rejectedPlannings.contains(proposal.selectedPlanningId)) {
        rejectedPlannings.add(proposal.selectedPlanningId!);
      }

      // Vérifier s'il reste des astreintes disponibles
      final remainingPlannings = proposal.proposedPlanningIds
          .where((id) => !rejectedPlannings.contains(id))
          .toList();

      final allPlanningsRejected = remainingPlannings.isEmpty;

      // REFUS = Ajouter le planning à la liste des refusés
      // Si toutes les astreintes sont refusées, marquer la proposition comme rejected
      final updatedProposal = proposal.copyWith(
        leaderValidations: updatedValidations,
        rejectedPlanningIds: rejectedPlannings,
        selectedPlanningId:
            null, // Effacer la sélection pour permettre une nouvelle sélection
        status: allPlanningsRejected
            ? ShiftExchangeProposalStatus.rejected
            : ShiftExchangeProposalStatus
                  .pendingSelection, // Remettre en attente de sélection si d'autres astreintes sont disponibles
        rejectedAt: allPlanningsRejected ? DateTime.now() : null,
        isFinalized:
            allPlanningsRejected, // Finaliser uniquement si toutes les astreintes sont refusées
      );

      await _exchangeRepository.upsertProposal(
        updatedProposal,
        stationId: stationId,
      );

      debugPrint(
        '✅ Planning ${proposal.selectedPlanningId} rejeté par chef $leaderId de l\'équipe $teamId',
      );
      debugPrint('   Motif: $comment');
      debugPrint(
        '   Plannings restants: ${remainingPlannings.length}/${proposal.proposedPlanningIds.length}',
      );
      if (allPlanningsRejected) {
        debugPrint(
          '   ⚠️ Toutes les astreintes de cette proposition ont été refusées',
        );
      }

      // Récupérer la demande associée
      final request = await _exchangeRepository.getRequestById(
        proposal.requestId,
        stationId: stationId,
      );

      if (request != null) {
        // IMPORTANT: Remettre la demande au statut "open" pour que l'initiateur puisse sélectionner une autre proposition
        final updatedRequest = request.copyWith(
          status: ShiftExchangeRequestStatus.open,
          selectedProposalId: null, // Effacer la proposition sélectionnée
        );
        await _exchangeRepository.upsertRequest(
          updatedRequest,
          stationId: stationId,
        );
        debugPrint(
          '✅ Demande ${request.id} remise au statut "open" - l\'initiateur peut sélectionner une autre proposition',
        );

        // Notifier l'agent A avec le motif de refus
        final sdisId = SDISContext().currentSDISId;
        if (sdisId != null) {
          // Récupérer le nom du chef qui a rejeté
          final leader = await _userRepository.getById(
            leaderId,
            stationId: stationId,
          );
          final leaderName = leader != null
              ? '${leader.firstName} ${leader.lastName}'
              : 'Chef $leaderId';

          await _notificationService.notifyProposalRejected(
            request: updatedRequest,
            proposal: updatedProposal,
            leaderName: leaderName,
            rejectionReason: comment,
            sdisId: sdisId,
            stationId: stationId,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Erreur lors du rejet: $e');
      rethrow;
    }
  }

  /// Crée les Subshifts pour un échange validé (PROPOSITIONS MULTIPLES)
  ///
  /// NOUVELLE LOGIQUE:
  /// - 1 Subshift: B remplace A sur le planning de A (W)
  /// - N Subshifts: A remplace B sur chaque planning proposé (X1, X2, X3...)
  /// - Si proposition a plusieurs astreintes, créer 1 Subshift par astreinte
  Future<void> _createExchangeSubshifts(
    ShiftExchangeProposal proposal,
    String stationId,
  ) async {
    try {
      final request = await _exchangeRepository.getRequestById(
        proposal.requestId,
        stationId: stationId,
      );
      if (request == null) {
        throw Exception('Demande non trouvée');
      }

      // Subshift 1: B remplace A sur le planning de A (W)
      final subshift1 = Subshift.create(
        replacedId: request.initiatorId,
        replacerId: proposal.proposerId,
        start: request.initiatorStartTime,
        end: request.initiatorEndTime,
        planningId: request.initiatorPlanningId,
        isExchange: true,
      );
      await _subshiftRepository.save(subshift1, stationId: stationId);

      // Mettre à jour planning.agents pour le planning de A
      await ReplacementNotificationService.updatePlanningAgentsForReplacement(
        planningId: request.initiatorPlanningId,
        stationId: stationId,
        replacedId: request.initiatorId,
        replacerId: proposal.proposerId,
        start: request.initiatorStartTime,
        end: request.initiatorEndTime,
      );

      // Subshifts multiples: A remplace B sur chaque planning proposé
      int count = 0;
      for (final planningId in proposal.proposedPlanningIds) {
        // Récupérer les détails du planning
        final planning = await _planningRepository.getById(
          planningId,
          stationId: stationId,
        );
        if (planning == null) {
          debugPrint('⚠️ Planning $planningId non trouvé, ignoré');
          continue;
        }

        // Créer le Subshift: A remplace B sur ce planning
        final subshift = Subshift.create(
          replacedId: proposal.proposerId,
          replacerId: request.initiatorId,
          start: planning.startTime,
          end: planning.endTime,
          planningId: planningId,
          isExchange: true,
        );
        await _subshiftRepository.save(subshift, stationId: stationId);

        // Mettre à jour planning.agents pour le planning de B
        await ReplacementNotificationService.updatePlanningAgentsForReplacement(
          planningId: planningId,
          stationId: stationId,
          replacedId: proposal.proposerId,
          replacerId: request.initiatorId,
          start: planning.startTime,
          end: planning.endTime,
        );
        count++;
      }

      debugPrint('✅ ${count + 1} Subshifts créés pour l\'échange');
      debugPrint(
        '   - 1 Subshift: ${proposal.proposerName} → ${request.initiatorName}',
      );
      debugPrint(
        '   - $count Subshift(s): ${request.initiatorName} → ${proposal.proposerName}',
      );
    } catch (e) {
      debugPrint('❌ Erreur lors de la création des Subshifts: $e');
      rethrow;
    }
  }

  /// Récupère les demandes disponibles pour un utilisateur
  ///
  /// Filtre: demandes où l'utilisateur possède requiredKeySkills
  Future<List<ShiftExchangeRequest>> getAvailableRequestsForUser({
    required String userId,
    required String stationId,
  }) async {
    try {
      final user = await _userRepository.getById(userId, stationId: stationId);
      if (user == null) {
        throw Exception('Utilisateur non trouvé: $userId');
      }

      // Utiliser les skills standards de l'utilisateur, pas les keySkills
      // Car les requiredKeySkills dans la demande sont les keySkills de l'initiateur,
      // mais on vérifie si l'utilisateur possède ces compétences dans ses skills standards
      return await _exchangeRepository.getAvailableRequestsForUser(
        userId,
        user.skills, // Changé de user.keySkills à user.skills
        stationId: stationId,
      );
    } catch (e) {
      debugPrint(
        '❌ Erreur lors de la récupération des demandes disponibles: $e',
      );
      rethrow;
    }
  }

  /// Récupère les propositions en attente de validation pour un chef
  Future<List<ShiftExchangeProposal>> getPendingProposalsForLeader({
    required String teamId,
    required String stationId,
  }) async {
    try {
      return await _exchangeRepository.getPendingProposalsForTeam(
        teamId,
        stationId: stationId,
      );
    } catch (e) {
      debugPrint(
        '❌ Erreur lors de la récupération des propositions en attente: $e',
      );
      rethrow;
    }
  }

  /// Récupère les demandes d'un utilisateur avec leurs propositions
  /// OPTIMISÉ: Récupère d'abord les demandes, puis toutes les propositions en une seule requête
  Future<List<Map<String, dynamic>>> getUserRequestsWithProposals({
    required String userId,
    required String stationId,
  }) async {
    try {
      final requests = await _exchangeRepository.getRequestsByInitiator(
        userId,
        stationId: stationId,
      );

      if (requests.isEmpty) {
        return [];
      }

      // Récupérer toutes les propositions de la station et filtrer côté client
      // C'est plus efficace que N requêtes individuelles
      final allProposals = await _exchangeRepository.getAllProposals(
        stationId: stationId,
      );

      // Créer un index des propositions par requestId
      final requestIds = requests.map((r) => r.id).toSet();
      final proposalsByRequestId = <String, List<ShiftExchangeProposal>>{};
      for (final proposal in allProposals) {
        if (requestIds.contains(proposal.requestId)) {
          proposalsByRequestId.putIfAbsent(proposal.requestId, () => []);
          proposalsByRequestId[proposal.requestId]!.add(proposal);
        }
      }

      final results = <Map<String, dynamic>>[];
      for (final request in requests) {
        results.add({
          'request': request,
          'proposals': proposalsByRequestId[request.id] ?? [],
        });
      }

      return results;
    } catch (e) {
      debugPrint(
        '❌ Erreur lors de la récupération des demandes avec propositions: $e',
      );
      rethrow;
    }
  }

  /// Récupère TOUS les échanges de la caserne avec leurs propositions
  /// OPTIMISÉ: 2 requêtes au lieu de N+1 (1 pour les demandes, 1 pour toutes les propositions)
  Future<List<Map<String, dynamic>>> getAllStationExchangesWithProposals({
    required String stationId,
  }) async {
    try {
      // Récupérer TOUTES les demandes et propositions en parallèle (2 requêtes seulement)
      final futures = await Future.wait([
        _exchangeRepository.getAllRequests(stationId: stationId),
        _exchangeRepository.getAllProposals(stationId: stationId),
      ]);

      final allRequests = futures[0] as List<ShiftExchangeRequest>;
      final allProposals = futures[1] as List<ShiftExchangeProposal>;

      // Regrouper les propositions par requestId côté client
      final proposalsByRequestId = <String, List<ShiftExchangeProposal>>{};
      for (final proposal in allProposals) {
        proposalsByRequestId.putIfAbsent(proposal.requestId, () => []);
        proposalsByRequestId[proposal.requestId]!.add(proposal);
      }

      // Construire les résultats
      final results = <Map<String, dynamic>>[];
      for (final request in allRequests) {
        results.add({
          'request': request,
          'proposals': proposalsByRequestId[request.id] ?? [],
        });
      }

      return results;
    } catch (e) {
      debugPrint(
        '❌ Erreur lors de la récupération de tous les échanges de la caserne: $e',
      );
      rethrow;
    }
  }

  /// Récupère TOUS les échanges d'un utilisateur (initiateur OU proposeur) avec leurs propositions
  Future<List<Map<String, dynamic>>> getUserExchangesWithProposals({
    required String userId,
    required String stationId,
  }) async {
    try {
      final results = <Map<String, dynamic>>[];

      // 1. Récupérer les demandes où l'utilisateur est l'initiateur
      final requestsAsInitiator = await _exchangeRepository
          .getRequestsByInitiator(userId, stationId: stationId);

      for (final request in requestsAsInitiator) {
        final proposals = await _exchangeRepository.getProposalsByRequestId(
          request.id,
          stationId: stationId,
        );
        results.add({
          'request': request,
          'proposals': proposals,
          'userRole': 'initiator',
        });
      }

      // 2. Récupérer les propositions où l'utilisateur est le proposeur
      final proposalsAsProposer = await _exchangeRepository
          .getProposalsByProposer(userId, stationId: stationId);

      // Pour chaque proposition, récupérer la demande associée
      for (final proposal in proposalsAsProposer) {
        // Éviter les doublons: si la demande est déjà dans les résultats (user = initiateur ET proposeur), skip
        if (results.any(
          (r) =>
              (r['request'] as ShiftExchangeRequest).id == proposal.requestId,
        )) {
          continue;
        }

        final request = await _exchangeRepository.getRequestById(
          proposal.requestId,
          stationId: stationId,
        );

        if (request != null) {
          final allProposals = await _exchangeRepository
              .getProposalsByRequestId(request.id, stationId: stationId);
          results.add({
            'request': request,
            'proposals': allProposals,
            'userRole': 'proposer',
          });
        }
      }

      return results;
    } catch (e) {
      debugPrint(
        '❌ Erreur lors de la récupération des échanges utilisateur: $e',
      );
      rethrow;
    }
  }

  /// Récupère toutes les propositions pour une demande donnée
  Future<List<ShiftExchangeProposal>> getProposalsByRequestId({
    required String requestId,
    required String stationId,
  }) async {
    try {
      return await _exchangeRepository.getProposalsByRequestId(
        requestId,
        stationId: stationId,
      );
    } catch (e) {
      debugPrint('❌ Erreur lors de la récupération des propositions: $e');
      rethrow;
    }
  }

  /// Récupère les propositions sélectionnées nécessitant validation pour un chef
  /// Retourne les propositions où le chef fait partie de l'équipe de l'initiateur OU du proposeur
  Future<List<Map<String, dynamic>>> getProposalsRequiringValidationForLeader({
    required String userId,
    required String stationId,
  }) async {
    try {
      // Récupérer l'utilisateur pour connaître son équipe
      final user = await _userRepository.getById(userId, stationId: stationId);
      if (user == null) {
        throw Exception('Utilisateur non trouvé: $userId');
      }

      final userTeam = user.team;
      debugPrint(
        '🔍 [EXCHANGE_SERVICE] getProposalsRequiringValidationForLeader for user $userId, team: $userTeam',
      );

      // Seuls les chefs et leaders peuvent valider
      if (user.status != 'chief' && user.status != 'leader' && !user.admin) {
        return [];
      }

      // Récupérer toutes les propositions avec statut selectedByInitiator
      final allProposals = await _exchangeRepository.getProposalsByStatus(
        ShiftExchangeProposalStatus.selectedByInitiator,
        stationId: stationId,
      );

      debugPrint(
        '🔍 [EXCHANGE_SERVICE] Found ${allProposals.length} proposals with status selectedByInitiator',
      );

      final results = <Map<String, dynamic>>[];

      for (final proposal in allProposals) {
        // Récupérer la demande associée
        final request = await _exchangeRepository.getRequestById(
          proposal.requestId,
          stationId: stationId,
        );

        if (request == null) continue;

        // Vérifier si le chef fait partie des équipes concernées
        // 1. Récupérer l'équipe de l'initiateur via son planning
        String? initiatorTeam;
        try {
          final initiatorPlanning = await _planningRepository.getById(
            request.initiatorPlanningId,
            stationId: stationId,
          );
          initiatorTeam = initiatorPlanning?.team;
        } catch (e) {
          debugPrint(
            '❌ [EXCHANGE_SERVICE] Error getting initiator planning: $e',
          );
        }

        // 2. L'équipe du proposeur est dans la proposition
        final proposerTeam = proposal.proposerTeamId;

        debugPrint(
          '🔍 [EXCHANGE_SERVICE] Proposal ${proposal.id}: initiatorTeam=$initiatorTeam, proposerTeam=$proposerTeam, userTeam=$userTeam',
        );

        // Si le chef fait partie de l'une des deux équipes
        if (initiatorTeam == userTeam || proposerTeam == userTeam) {
          // Vérifier si CE leader spécifique a déjà validé (clé composée: teamId_userId)
          final leaderKey = '${userTeam}_$userId';
          final hasAlreadyValidated = proposal.leaderValidations.containsKey(leaderKey);

          if (!hasAlreadyValidated) {
            results.add({
              'request': request,
              'proposal': proposal,
              'initiatorTeam': initiatorTeam,
              'proposerTeam': proposerTeam,
            });
          } else {
            debugPrint(
              '  ✅ Leader $userId has already validated (key: $leaderKey)',
            );
          }
        }
      }

      debugPrint(
        '🔍 [EXCHANGE_SERVICE] Found ${results.length} proposals requiring validation for leader',
      );
      return results;
    } catch (e) {
      debugPrint(
        '❌ [EXCHANGE_SERVICE] Error getting proposals requiring validation: $e',
      );
      rethrow;
    }
  }

  /// Récupère les IDs des chefs concernés par une proposition
  ///
  /// Retourne les IDs de tous les chefs des 2 équipes (initiateur et proposeur)
  /// Exclut le proposeur s'il est chef (auto-validation)
  Future<List<String>> _getChiefIdsForProposal(
    ShiftExchangeRequest request,
    ShiftExchangeProposal proposal,
    String stationId,
  ) async {
    try {
      // Récupérer tous les utilisateurs de la station
      final allUsers = await _userRepository.getByStation(stationId);

      // Récupérer l'initiateur pour connaître son équipe
      final initiator = await _userRepository.getById(
        request.initiatorId,
        stationId: stationId,
      );
      if (initiator == null) {
        throw Exception('Initiateur non trouvé: ${request.initiatorId}');
      }

      final chiefIds = <String>[];

      // Récupérer les chefs de l'équipe de l'initiateur
      final initiatorTeamChiefs = allUsers
          .where(
            (user) =>
                user.team == initiator.team &&
                (user.status == 'chief' || user.status == 'leader'),
          )
          .map((user) => user.id)
          .toList();

      chiefIds.addAll(initiatorTeamChiefs);

      // Récupérer les chefs de l'équipe du proposeur
      if (proposal.proposerTeamId != null) {
        final proposerTeamChiefs = allUsers
            .where(
              (user) =>
                  user.team == proposal.proposerTeamId &&
                  (user.status == 'chief' || user.status == 'leader'),
            )
            .map((user) => user.id)
            .toList();

        chiefIds.addAll(proposerTeamChiefs);
      }

      // Retourner la liste unique (sans doublons)
      return chiefIds.toSet().toList();
    } catch (e) {
      debugPrint('❌ Erreur lors de la récupération des chefs: $e');
      rethrow;
    }
  }
}
