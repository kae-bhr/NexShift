import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/data/models/agent_query_model.dart';
import 'package:nexshift_app/core/data/models/planning_agent_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/agent_query_repository.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';

/// Service gérant le cycle de vie des demandes de recherche automatique d'agent
/// ([AgentQuery]).
///
/// Règle métier clé : 1 demande = 1 agent.
/// Le premier agent qui accepte est retenu ; la demande passe immédiatement
/// en [AgentQueryStatus.matched] et est archivée. Les acceptations concurrentes
/// sont ignorées via une transaction Firestore atomique.
class AgentQueryService {
  final AgentQueryRepository _queryRepository;
  final PlanningRepository _planningRepository;
  final UserRepository _userRepository;

  AgentQueryService({
    AgentQueryRepository? queryRepository,
    PlanningRepository? planningRepository,
    UserRepository? userRepository,
  })  : _queryRepository = queryRepository ?? AgentQueryRepository(),
        _planningRepository = planningRepository ?? PlanningRepository(),
        _userRepository = userRepository ?? UserRepository();

  // ============================================================================
  // PATH HELPER (triggers)
  // ============================================================================

  String _getNotificationTriggersPath(String stationId) {
    return EnvironmentConfig.getCollectionPath('notificationTriggers', stationId);
  }

  // ============================================================================
  // CRÉATION DE DEMANDE
  // ============================================================================

  /// Crée une demande de recherche automatique d'agent et notifie les agents éligibles.
  ///
  /// Un agent est éligible si :
  /// - Son statut est [AgentAvailabilityStatus.active]
  /// - Il possède toutes les [requiredSkills] (si non vide)
  ///
  /// Retourne la [AgentQuery] créée.
  Future<AgentQuery> createQuery({
    required Planning planning,
    required String onCallLevelId,
    required String onCallLevelName,
    required List<String> requiredSkills,
    required User createdBy,
  }) async {
    final stationId = createdBy.station;

    // 1. Charger tous les agents de la caserne
    final allUsers = await _userRepository.getByStation(stationId);

    // 2. Filtrer les agents éligibles
    final eligibleUsers = _filterEligibleAgents(
      allUsers: allUsers,
      requiredSkills: requiredSkills,
      planningAgentIds: planning.agentsId,
    );

    final notifiedIds = eligibleUsers.map((u) => u.id).toList();

    // 3. Créer le document AgentQuery
    final queryId = 'aq_${DateTime.now().millisecondsSinceEpoch}';
    final query = AgentQuery(
      id: queryId,
      createdById: createdBy.id,
      createdByName: createdBy.displayName,
      planningId: planning.id,
      startTime: planning.startTime,
      endTime: planning.endTime,
      station: stationId,
      onCallLevelId: onCallLevelId,
      onCallLevelName: onCallLevelName,
      requiredSkills: requiredSkills,
      status: AgentQueryStatus.pending,
      createdAt: DateTime.now(),
      notifiedUserIds: notifiedIds,
    );

    await _queryRepository.create(query: query, stationId: stationId);

    // 4. Déclencher les notifications via Cloud Function
    if (notifiedIds.isNotEmpty) {
      await _triggerNotifications(query: query, targetUserIds: notifiedIds);
    }

    return query;
  }

  // ============================================================================
  // RÉPONSE D'UN AGENT
  // ============================================================================

  /// Enregistre la réponse d'un agent à une demande.
  ///
  /// Si [accepted] :
  ///   - Transaction atomique : vérifie que la demande est encore [pending],
  ///     puis la passe en [matched] et ajoute l'agent au planning.
  ///   - Retourne `true` si l'acceptation a réussi (premier arrivé).
  ///   - Retourne `false` si la demande était déjà matchée (un autre agent plus rapide).
  ///
  /// Si [!accepted] :
  ///   - Ajoute l'agent à [declinedByUserIds].
  Future<bool> respondToQuery({
    required AgentQuery query,
    required User respondingAgent,
    required bool accepted,
  }) async {
    final stationId = query.station;

    if (!accepted) {
      await _queryRepository.updateFields(
        queryId: query.id,
        stationId: stationId,
        fields: {
          'declinedByUserIds': FieldValue.arrayUnion([respondingAgent.id]),
        },
      );
      return true;
    }

    // Acceptation : transaction atomique pour éviter les acceptations concurrentes
    return await _acceptWithTransaction(
      query: query,
      respondingAgent: respondingAgent,
      stationId: stationId,
    );
  }

  // ============================================================================
  // ACCEPTATION PARTIELLE
  // ============================================================================

  /// Accepte une demande pour une plage horaire partielle.
  ///
  /// - Place l'agent sur le planning pour [acceptedStart..acceptedEnd].
  /// - Si la plage est partielle, crée de nouvelles AgentQuery pour les
  ///   périodes non couvertes (avant et/ou après).
  /// - Retourne `true` si l'acceptation a réussi, `false` si déjà matchée.
  Future<bool> acceptQueryPartial({
    required AgentQuery query,
    required User respondingAgent,
    required DateTime acceptedStart,
    required DateTime acceptedEnd,
  }) async {
    final stationId = query.station;

    try {
      bool success = false;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final queryDoc = await _getQueryDocument(query.id, stationId);
        if (queryDoc == null) return;

        final currentStatus = queryDoc['status'] as String? ?? '';
        if (currentStatus != 'pending') {
          success = false;
          return;
        }

        final now = DateTime.now();

        // 1. Marquer la demande originale comme matchée avec les horaires ACCEPTÉS
        // (Bug A fix : startTime/endTime mis à jour pour refléter la plage réelle acceptée)
        final docRef = _getQueryDocRef(query.id, stationId);
        transaction.update(docRef, {
          'status': 'matched',
          'matchedAgentId': respondingAgent.id,
          'completedAt': Timestamp.fromDate(now),
          'startTime': Timestamp.fromDate(acceptedStart),
          'endTime': Timestamp.fromDate(acceptedEnd),
        });

        // 2. Ajouter l'agent au planning pour la plage acceptée
        // (Bug B fix : transaction.update au lieu de transaction.set pour ne pas écraser le document)
        final planning = await _planningRepository.getById(
          query.planningId,
          stationId: stationId,
        );
        if (planning != null) {
          final newAgent = PlanningAgent(
            agentId: respondingAgent.id,
            start: acceptedStart,
            end: acceptedEnd,
            levelId: query.onCallLevelId,
          );
          final updatedAgents = [...planning.agents, newAgent];
          final planningPath = _getPlanningCollectionPath(stationId);
          final planningRef = FirebaseFirestore.instance
              .collection(planningPath)
              .doc(query.planningId);
          transaction.update(planningRef, {
            'agents': updatedAgents.map((a) => a.toJson()).toList(),
          });
        }

        success = true;
      });

      if (!success) return false;

      // 3. Créer des nouvelles queries pour les plages non couvertes
      // Les agents notifiés pour les sous-requêtes = ceux de la query originale
      // moins l'agent qui vient d'accepter et ceux qui ont décliné.
      // On réutilise query.notifiedUserIds pour garantir la visibilité aux mêmes agents.
      final excludeIds = {
        respondingAgent.id,
        ...query.declinedByUserIds,
      };
      final notifyIds = query.notifiedUserIds
          .where((id) => !excludeIds.contains(id))
          .toList();

      // Plage AVANT (si acceptedStart > query.startTime)
      // (Bug C fix : IDs générés par Firestore pour éviter les collisions)
      if (acceptedStart.isAfter(query.startTime)) {
        try {
          final beforeId = FirebaseFirestore.instance.collection(_getQueryCollectionPath(stationId)).doc().id;
          final before = AgentQuery(
            id: beforeId,
            createdById: query.createdById,
            createdByName: query.createdByName,
            planningId: query.planningId,
            startTime: query.startTime,
            endTime: acceptedStart,
            station: stationId,
            onCallLevelId: query.onCallLevelId,
            onCallLevelName: query.onCallLevelName,
            requiredSkills: query.requiredSkills,
            status: AgentQueryStatus.pending,
            createdAt: DateTime.now(),
            notifiedUserIds: notifyIds,
          );
          await _queryRepository.create(query: before, stationId: stationId);
          if (notifyIds.isNotEmpty) {
            await _triggerNotifications(query: before, targetUserIds: notifyIds);
          }
          debugPrint('AgentQueryService: created "before" sub-query $beforeId (${query.startTime} → $acceptedStart)');
        } catch (e) {
          debugPrint('AgentQueryService: failed to create "before" sub-query: $e');
        }
      }

      // Plage APRÈS (si acceptedEnd < query.endTime)
      if (acceptedEnd.isBefore(query.endTime)) {
        try {
          final afterId = FirebaseFirestore.instance.collection(_getQueryCollectionPath(stationId)).doc().id;
          final after = AgentQuery(
            id: afterId,
            createdById: query.createdById,
            createdByName: query.createdByName,
            planningId: query.planningId,
            startTime: acceptedEnd,
            endTime: query.endTime,
            station: stationId,
            onCallLevelId: query.onCallLevelId,
            onCallLevelName: query.onCallLevelName,
            requiredSkills: query.requiredSkills,
            status: AgentQueryStatus.pending,
            createdAt: DateTime.now(),
            notifiedUserIds: notifyIds,
          );
          await _queryRepository.create(query: after, stationId: stationId);
          if (notifyIds.isNotEmpty) {
            await _triggerNotifications(query: after, targetUserIds: notifyIds);
          }
          debugPrint('AgentQueryService: created "after" sub-query $afterId ($acceptedEnd → ${query.endTime})');
        } catch (e) {
          debugPrint('AgentQueryService: failed to create "after" sub-query: $e');
        }
      }

      return true;
    } catch (e) {
      debugPrint('AgentQueryService.acceptQueryPartial error: $e');
      rethrow;
    }
  }

  // ============================================================================
  // RELANCE NOTIFICATIONS
  // ============================================================================

  /// Relance les notifications vers les agents qui n'ont pas encore répondu.
  Future<void> resendNotifications({
    required AgentQuery query,
    required List<String> targetUserIds,
  }) async {
    await _triggerNotifications(query: query, targetUserIds: targetUserIds);
  }

  // ============================================================================
  // ÉTAT "VU"
  // ============================================================================

  /// Marque la demande comme vue par un agent (triggered par VisibilityDetector).
  Future<void> markQueryAsSeen({
    required String queryId,
    required String stationId,
    required String userId,
  }) async {
    await _queryRepository.updateFields(
      queryId: queryId,
      stationId: stationId,
      fields: {
        'seenByUserIds': FieldValue.arrayUnion([userId]),
      },
    );
  }

  // ============================================================================
  // ANNULATION
  // ============================================================================

  /// Annule une demande. Seul le créateur, un leader ou un admin peut annuler.
  Future<void> cancelQuery({
    required AgentQuery query,
  }) async {
    await _queryRepository.cancel(
      queryId: query.id,
      stationId: query.station,
    );
  }

  // ============================================================================
  // LOGIQUE INTERNE
  // ============================================================================

  /// Filtre les agents éligibles pour une demande de recherche.
  List<User> _filterEligibleAgents({
    required List<User> allUsers,
    required List<String> requiredSkills,
    required List<String> planningAgentIds,
  }) {
    return allUsers.where((user) {
      // Exclure les agents suspendus ou en arrêt maladie
      if (!user.isActiveForReplacement) return false;

      // Exclure les agents déjà sur ce planning (en astreinte)
      if (planningAgentIds.contains(user.id)) return false;

      // Vérifier les compétences requises
      if (requiredSkills.isNotEmpty) {
        final hasAllSkills = requiredSkills.every(
          (skill) => user.skills.contains(skill),
        );
        if (!hasAllSkills) return false;
      }

      return true;
    }).toList();
  }

  /// Transaction Firestore atomique pour l'acceptation.
  /// Garantit que seul le premier agent acceptant est retenu.
  Future<bool> _acceptWithTransaction({
    required AgentQuery query,
    required User respondingAgent,
    required String stationId,
  }) async {
    try {
      bool success = false;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // Relire le document pour vérifier l'état actuel
        final queryDoc = await _getQueryDocument(query.id, stationId);
        if (queryDoc == null) return;

        final currentStatus = queryDoc['status'] as String? ?? '';

        // Si déjà matché ou annulé, on abandonne
        if (currentStatus != 'pending') {
          success = false;
          return;
        }

        final now = DateTime.now();

        // 1. Marquer la demande comme matchée
        final docRef = _getQueryDocRef(query.id, stationId);
        transaction.update(docRef, {
          'status': 'matched',
          'matchedAgentId': respondingAgent.id,
          'completedAt': Timestamp.fromDate(now),
        });

        // 2. Ajouter l'agent au planning
        await _addAgentToPlanning(
          query: query,
          agent: respondingAgent,
          transaction: transaction,
        );

        success = true;
      });

      return success;
    } catch (e) {
      debugPrint('AgentQueryService._acceptWithTransaction error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _getQueryDocument(
    String queryId,
    String stationId,
  ) async {
    final path = _getQueryCollectionPath(stationId);
    final doc = await FirebaseFirestore.instance
        .collection(path)
        .doc(queryId)
        .get();
    return doc.exists ? doc.data() : null;
  }

  DocumentReference _getQueryDocRef(String queryId, String stationId) {
    final path = _getQueryCollectionPath(stationId);
    return FirebaseFirestore.instance.collection(path).doc(queryId);
  }

  String _getQueryCollectionPath(String stationId) {
    return EnvironmentConfig.getCollectionPath('replacements/queries/agentQueries', stationId);
  }

  String _getPlanningCollectionPath(String stationId) {
    return EnvironmentConfig.getCollectionPath('plannings', stationId);
  }

  /// Ajoute l'agent au planning dans la transaction.
  Future<void> _addAgentToPlanning({
    required AgentQuery query,
    required User agent,
    required Transaction transaction,
  }) async {
    final planning = await _planningRepository.getById(
      query.planningId,
      stationId: query.station,
    );
    if (planning == null) return;

    final newPlanningAgent = PlanningAgent(
      agentId: agent.id,
      start: query.startTime,
      end: query.endTime,
      levelId: query.onCallLevelId,
      // replacedAgentId = null : cet agent s'ajoute, il ne remplace personne
    );

    final updatedPlanning = planning.copyWith(
      agents: [...planning.agents, newPlanningAgent],
    );

    final planningPath = _getPlanningCollectionPath(query.station);
    final planningDocRef = FirebaseFirestore.instance
        .collection(planningPath)
        .doc(query.planningId);

    transaction.set(planningDocRef, updatedPlanning.toJson());
  }

  /// Crée le document trigger pour la Cloud Function de notification.
  Future<void> _triggerNotifications({
    required AgentQuery query,
    required List<String> targetUserIds,
    String? team,
  }) async {
    try {
      final triggersPath = _getNotificationTriggersPath(query.station);
      final triggerId = 'aqn_${query.id}_${DateTime.now().millisecondsSinceEpoch}';

      // Résoudre l'équipe depuis le planning si non fournie
      String resolvedTeam = team ?? '';
      if (resolvedTeam.isEmpty && query.planningId.isNotEmpty) {
        try {
          final planningPath = EnvironmentConfig.getCollectionPath('plannings', query.station);
          final planningDoc = await FirebaseFirestore.instance
              .collection(planningPath)
              .doc(query.planningId)
              .get();
          if (planningDoc.exists) {
            resolvedTeam = planningDoc.data()?['team'] as String? ?? '';
          }
        } catch (_) {}
      }

      await FirebaseFirestore.instance
          .collection(triggersPath)
          .doc(triggerId)
          .set({
        'type': 'agent_query_request',
        'queryId': query.id,
        'createdById': query.createdById,
        'planningId': query.planningId,
        'startTime': Timestamp.fromDate(query.startTime),
        'endTime': Timestamp.fromDate(query.endTime),
        'station': query.station,
        'team': resolvedTeam,
        'onCallLevelId': query.onCallLevelId,
        'requiredSkills': query.requiredSkills,
        'targetUserIds': targetUserIds,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
    } catch (e) {
      debugPrint('AgentQueryService._triggerNotifications error: $e');
    }
  }
}
