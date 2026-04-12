import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';

/// Service gérant les changements d'appartenance à l'effectif (équipe).
///
/// Le changement d'équipe est d'abord appliqué localement (UserRepository),
/// puis un trigger Firestore déclenche la Cloud Function [handleAgentTeamChange]
/// qui synchronise les plannings futurs (retrait ancienne équipe + ajout nouvelle équipe).
///
/// Chemin du trigger :
///   /sdis/{sdisId}/stations/{stationId}/replacements/automatic/teamChangeTriggers/{triggerId}
class AgentRosterService {
  final UserRepository _userRepository;

  AgentRosterService({UserRepository? userRepository})
      : _userRepository = userRepository ?? UserRepository();

  String _getTeamChangeTriggersPath(String stationId) =>
      EnvironmentConfig.getCollectionPath(
        'replacements/automatic/teamChangeTriggers',
        stationId,
      );

  /// Change l'équipe d'un agent et synchronise les plannings via Cloud Function.
  ///
  /// - Si [agent.team] == "" → pas de retrait, juste ajout aux plannings de [newTeamId]
  /// - Si [newTeamId] == "" → juste retrait des plannings de l'ancienne équipe, pas d'ajout
  /// - [currentUser] est passé pour mettre à jour le stockage local si c'est l'utilisateur connecté
  Future<void> changeAgentTeam({
    required User agent,
    required String newTeamId,
    User? currentUser,
  }) async {
    final oldTeamId = agent.team;
    if (oldTeamId == newTeamId) return;

    final effectiveDate = DateTime.now();

    // 1. Mettre à jour le user en Firestore
    final updatedAgent = agent.copyWith(team: newTeamId);
    await _userRepository.upsert(updatedAgent);

    // 2. Mettre à jour le stockage local si c'est l'utilisateur courant
    if (currentUser?.id == agent.id) {
      await UserStorageHelper.saveUser(updatedAgent);
    }

    // 3. Trigger Cloud Function pour la synchronisation des plannings
    try {
      final triggerId =
          'teamchange_${agent.id}_${effectiveDate.millisecondsSinceEpoch}';
      await FirebaseFirestore.instance
          .collection(_getTeamChangeTriggersPath(agent.station))
          .doc(triggerId)
          .set({
        'type': 'agent_team_changed',
        'agentId': agent.id,
        'station': agent.station,
        'oldTeamId': oldTeamId,
        'newTeamId': newTeamId,
        'effectiveDate': Timestamp.fromDate(effectiveDate),
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
    } catch (e) {
      // Le trigger a échoué mais le changement d'équipe a déjà été appliqué.
      // La Cloud Function peut être redéclenchée manuellement si nécessaire.
      debugPrint('AgentRosterService: teamChange trigger CF failed: $e');
    }
  }
}
