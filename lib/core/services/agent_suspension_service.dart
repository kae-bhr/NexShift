import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';

/// Service gérant la suspension d'engagement et les arrêts maladie des agents.
///
/// Le nettoyage des plannings, remplacements et échanges est déclenché via une
/// Cloud Function (pattern identique aux [notificationTriggers]) afin de garantir
/// l'atomicité même en cas de perte de connexion côté client.
///
/// Chemin du trigger :
///   /sdis/{sdisId}/stations/{stationId}/replacements/automatic/suspensionTriggers/{triggerId}
class AgentSuspensionService {
  final UserRepository _userRepository;

  AgentSuspensionService({UserRepository? userRepository})
      : _userRepository = userRepository ?? UserRepository();

  // ============================================================================
  // PATH HELPERS
  // ============================================================================

  String _getSuspensionTriggersPath(String stationId) {
    return EnvironmentConfig.getCollectionPath('replacements/automatic/suspensionTriggers', stationId);
  }

  // ============================================================================
  // SUSPENSION
  // ============================================================================

  /// Place un agent en suspension d'engagement ou en arrêt maladie.
  ///
  /// 1. Met à jour le champ [agentAvailabilityStatus] et [suspensionStartDate]
  ///    de l'agent dans Firestore via [UserRepository].
  /// 2. Crée un document dans la collection [suspensionTriggers] pour déclencher
  ///    la Cloud Function qui se charge de :
  ///    - Retirer l'agent de tous les plannings futurs (>= suspensionStartDate)
  ///    - Annuler ses demandes de remplacement actives (pending)
  ///    - Annuler ses échanges de garde actifs (open)
  ///
  /// [newStatus] doit être [AgentAvailabilityStatus.suspendedFromDuty]
  ///              ou [AgentAvailabilityStatus.sickLeave].
  Future<void> suspendAgent({
    required User agent,
    required String newStatus,
    required DateTime suspensionStartDate,
  }) async {
    assert(
      newStatus == AgentAvailabilityStatus.suspendedFromDuty ||
          newStatus == AgentAvailabilityStatus.sickLeave,
      'newStatus doit être suspendedFromDuty ou sickLeave',
    );

    final stationId = agent.station;

    // 1. Mise à jour du User en Firestore
    final updatedAgent = agent.copyWith(
      agentAvailabilityStatus: newStatus,
      suspensionStartDate: suspensionStartDate,
      // Retirer de l'équipe uniquement pour suspension d'engagement (pas pour arrêt maladie)
      team: newStatus == AgentAvailabilityStatus.suspendedFromDuty ? '' : agent.team,
    );
    await _userRepository.upsert(updatedAgent);

    // 2. Trigger Cloud Function pour le nettoyage des plannings/remplacements/échanges
    try {
      final triggersPath = _getSuspensionTriggersPath(stationId);
      final triggerId = 'suspension_${agent.id}_${DateTime.now().millisecondsSinceEpoch}';

      await FirebaseFirestore.instance
          .collection(triggersPath)
          .doc(triggerId)
          .set({
        'type': 'agent_suspended',
        'agentId': agent.id,
        'station': stationId,
        'newStatus': newStatus,
        'suspensionStartDate': Timestamp.fromDate(suspensionStartDate),
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
    } catch (e) {
      // Le trigger a échoué mais le statut a déjà été mis à jour.
      // La Cloud Function peut être redéclenchée manuellement si nécessaire.
      debugPrint('AgentSuspensionService: trigger CF failed: $e');
    }
  }

  // ============================================================================
  // RÉINTÉGRATION
  // ============================================================================

  /// Remet un agent en service actif.
  ///
  /// Seul le statut est réinitialisé. Les plannings retirés lors de la suspension
  /// ne sont PAS restaurés automatiquement — le leader doit les recréer manuellement.
  Future<void> reinstateAgent({required User agent}) async {
    final updatedAgent = agent.copyWith(
      agentAvailabilityStatus: AgentAvailabilityStatus.active,
      clearSuspensionStartDate: true,
    );
    await _userRepository.upsert(updatedAgent);
  }
}
