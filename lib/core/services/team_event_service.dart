import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/data/models/team_event_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/repositories/team_event_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';

/// Service gérant le cycle de vie des événements d'équipe/caserne ([TeamEvent]).
///
/// Contrairement aux AgentQuery, plusieurs agents peuvent accepter un événement
/// (pas de transaction "premier arrivé"). L'organisateur est automatiquement
/// dans [acceptedUserIds] à la création.
class TeamEventService {
  final TeamEventRepository _eventRepository;
  final UserRepository _userRepository;
  final PlanningRepository _planningRepository;

  TeamEventService({
    TeamEventRepository? eventRepository,
    UserRepository? userRepository,
    PlanningRepository? planningRepository,
  })  : _eventRepository = eventRepository ?? TeamEventRepository(),
        _userRepository = userRepository ?? UserRepository(),
        _planningRepository = planningRepository ?? PlanningRepository();

  // ============================================================================
  // PATH HELPER
  // ============================================================================

  String _getNotificationTriggersPath(String stationId) {
    return EnvironmentConfig.getCollectionPath('notificationTriggers', stationId);
  }

  // ============================================================================
  // CRÉATION
  // ============================================================================

  /// Crée un événement et notifie les agents ciblés.
  ///
  /// La résolution des invités suit [draft.scope] :
  /// - [TeamEventScope.station] : tous les agents actifs de la caserne, sauf le créateur
  /// - [TeamEventScope.team]    : filtré par équipe [draft.teamId]
  /// - [TeamEventScope.agents]  : [draft.targetAgentIds] directement
  /// - Si [draft.planningId] est renseigné : agents du planning lié (intra-planning)
  ///
  /// L'organisateur est toujours dans [acceptedUserIds] dès la création.
  Future<TeamEvent> createEvent({
    required TeamEvent draft,
    required User createdBy,
  }) async {
    final stationId = draft.stationId;
    List<String> invitedIds;

    // 1. Résoudre les agents invités
    if (draft.planningId != null && draft.planningId!.isNotEmpty) {
      // Intra-planning : inviter les agents du planning lié
      invitedIds = await _resolveAgentsFromPlanning(draft.planningId!, stationId, createdBy.id);
    } else {
      invitedIds = await _resolveAgentsByScope(draft, stationId, createdBy.id);
    }

    // 2. Construire l'événement final
    final eventId = 'te_${DateTime.now().millisecondsSinceEpoch}';
    final event = draft.copyWith(
      id: eventId,
      invitedUserIds: invitedIds,
      acceptedUserIds: [createdBy.id], // organisateur présent par défaut
    );

    // 3. Persister
    await _eventRepository.create(event: event, stationId: stationId);

    // 4. Notifier les invités (hors créateur, déjà accepté)
    final toNotify = invitedIds.where((id) => id != createdBy.id).toList();
    if (toNotify.isNotEmpty) {
      await _triggerNotifications(event: event, targetUserIds: toNotify);
    }

    return event;
  }

  // ============================================================================
  // RÉPONSE RSVP
  // ============================================================================

  /// Enregistre la réponse d'un agent (accepter ou refuser).
  ///
  /// Contrairement à AgentQuery, plusieurs agents peuvent accepter sans transaction.
  /// Un changement d'avis est possible (l'agent peut passer de accepté à refusé ou vice versa).
  Future<void> respondToEvent({
    required TeamEvent event,
    required String userId,
    required bool accepted,
  }) async {
    final Map<String, dynamic> fields;
    if (accepted) {
      fields = {
        'acceptedUserIds': FieldValue.arrayUnion([userId]),
        'declinedUserIds': FieldValue.arrayRemove([userId]),
      };
    } else {
      fields = {
        'declinedUserIds': FieldValue.arrayUnion([userId]),
        'acceptedUserIds': FieldValue.arrayRemove([userId]),
      };
    }
    await _eventRepository.updateFields(
      eventId: event.id,
      stationId: event.stationId,
      fields: fields,
    );
  }

  // ============================================================================
  // PRÉSENCE PHYSIQUE
  // ============================================================================

  /// Coche ou décoche la présence physique d'un agent (organisateur/admin uniquement).
  Future<void> checkPresence({
    required String eventId,
    required String stationId,
    required String agentId,
    required bool checked,
  }) async {
    await _eventRepository.updateFields(
      eventId: eventId,
      stationId: stationId,
      fields: {
        'checkedUserIds': checked
            ? FieldValue.arrayUnion([agentId])
            : FieldValue.arrayRemove([agentId]),
      },
    );
  }

  // ============================================================================
  // AJOUT D'AGENT
  // ============================================================================

  /// Ajoute un agent oublié à l'événement (ajout direct sans invitation distincte).
  /// L'agent est ajouté dans invitedUserIds ET acceptedUserIds.
  Future<void> addAgent({
    required String eventId,
    required String stationId,
    required String agentId,
  }) async {
    await _eventRepository.updateFields(
      eventId: eventId,
      stationId: stationId,
      fields: {
        'invitedUserIds': FieldValue.arrayUnion([agentId]),
        'acceptedUserIds': FieldValue.arrayUnion([agentId]),
        'declinedUserIds': FieldValue.arrayRemove([agentId]),
      },
    );
  }

  /// Retire un agent de l'événement (retrait de toutes les listes).
  Future<void> removeAgent({
    required String eventId,
    required String stationId,
    required String agentId,
  }) async {
    await _eventRepository.updateFields(
      eventId: eventId,
      stationId: stationId,
      fields: {
        'invitedUserIds': FieldValue.arrayRemove([agentId]),
        'acceptedUserIds': FieldValue.arrayRemove([agentId]),
        'declinedUserIds': FieldValue.arrayRemove([agentId]),
        'checkedUserIds': FieldValue.arrayRemove([agentId]),
      },
    );
  }

  // ============================================================================
  // ÉTAT "VU"
  // ============================================================================

  /// Marque l'événement comme vu par un agent (déclenché par VisibilityDetector).
  Future<void> markAsSeen({
    required String eventId,
    required String stationId,
    required String userId,
  }) async {
    await _eventRepository.updateFields(
      eventId: eventId,
      stationId: stationId,
      fields: {
        'seenByUserIds': FieldValue.arrayUnion([userId]),
      },
    );
  }

  // ============================================================================
  // ANNULATION
  // ============================================================================

  /// Annule un événement. Seul l'organisateur, un leader ou un admin peut annuler.
  Future<void> cancelEvent({required TeamEvent event}) async {
    await _eventRepository.cancel(
      eventId: event.id,
      stationId: event.stationId,
    );
  }

  // ============================================================================
  // LOGIQUE INTERNE
  // ============================================================================

  /// Résout les agents invités en fonction du scope de l'événement.
  Future<List<String>> _resolveAgentsByScope(
    TeamEvent draft,
    String stationId,
    String creatorId,
  ) async {
    switch (draft.scope) {
      case TeamEventScope.station:
        final allUsers = await _userRepository.getByStation(stationId);
        return allUsers
            .where((u) => u.id != creatorId)
            .map((u) => u.id)
            .toList();

      case TeamEventScope.team:
        final allUsers = await _userRepository.getByStation(stationId);
        return allUsers
            .where((u) => u.id != creatorId && u.team == draft.teamId)
            .map((u) => u.id)
            .toList();

      case TeamEventScope.agents:
        return draft.targetAgentIds.where((id) => id != creatorId).toList();
    }
  }

  /// Résout les agents invités depuis un planning lié (intra-planning).
  Future<List<String>> _resolveAgentsFromPlanning(
    String planningId,
    String stationId,
    String creatorId,
  ) async {
    try {
      final planning = await _planningRepository.getById(planningId, stationId: stationId);
      if (planning == null) return [];
      return planning.agentsId.where((id) => id != creatorId).toList();
    } catch (e) {
      debugPrint('TeamEventService._resolveAgentsFromPlanning error: $e');
      return [];
    }
  }

  /// Crée le document trigger pour la Cloud Function de notification.
  Future<void> _triggerNotifications({
    required TeamEvent event,
    required List<String> targetUserIds,
  }) async {
    try {
      final triggersPath = _getNotificationTriggersPath(event.stationId);
      final triggerId = 'ten_${event.id}_${DateTime.now().millisecondsSinceEpoch}';

      await FirebaseFirestore.instance
          .collection(triggersPath)
          .doc(triggerId)
          .set({
        'type': 'team_event_invitation',
        'eventId': event.id,
        'createdById': event.createdById,
        'title': event.title,
        'startTime': Timestamp.fromDate(event.startTime),
        'endTime': Timestamp.fromDate(event.endTime),
        'stationId': event.stationId,
        'scope': event.scope.toString().split('.').last,
        if (event.teamId != null) 'teamId': event.teamId,
        if (event.planningId != null) 'planningId': event.planningId,
        'targetUserIds': targetUserIds,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
    } catch (e) {
      debugPrint('TeamEventService._triggerNotifications error: $e');
    }
  }
}
