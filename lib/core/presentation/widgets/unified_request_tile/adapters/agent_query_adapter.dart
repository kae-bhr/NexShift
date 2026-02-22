import '../unified_tile_data.dart';
import '../unified_tile_enums.dart';
import '../../../../../core/data/models/agent_query_model.dart';

/// Adaptateur pour convertir AgentQuery en UnifiedTileData
class AgentQueryAdapter {
  /// Convertit une recherche d'agent en données unifiées
  ///
  /// [query] - La recherche d'agent
  /// [resolvedStationName] - Nom de la caserne résolu (depuis StationNameCache)
  /// [matchedAgentName] - Nom de l'agent ayant accepté (si matched)
  /// [team] - Équipe du planning (chargée depuis PlanningRepository)
  static UnifiedTileData fromAgentQuery({
    required AgentQuery query,
    required String resolvedStationName,
    String? matchedAgentName,
    String? team,
  }) {
    final status = _mapStatus(query.status);
    final isHistory = status == TileStatus.accepted || status == TileStatus.cancelled;

    // En historique matched, la colonne gauche affiche l'agent trouvé
    // Sinon : texte fixe "Recherche agent" (le niveau d'astreinte n'est pas pertinent)
    final leftAgentName = isHistory && status == TileStatus.accepted
        ? (matchedAgentName ?? query.matchedAgentName ?? 'Recherche agent')
        : 'Recherche agent';

    return UnifiedTileData(
      id: query.id,
      requestType: UnifiedRequestType.agentQuery,
      status: status,
      createdAt: query.createdAt,
      leftColumn: AgentColumnData(
        agentId: isHistory && status == TileStatus.accepted
            ? (query.matchedAgentId ?? query.createdById)
            : query.createdById,
        agentName: leftAgentName,
        team: team,
        startTime: query.startTime,
        endTime: query.endTime,
        station: resolvedStationName,
      ),
      // Colonne droite : compétences requises sous forme de tags (si non vide)
      rightColumn: query.requiredSkills.isNotEmpty
          ? AgentColumnData(
              agentId: '',
              agentName: 'Compétences requises',
              startTime: query.startTime,
              endTime: query.endTime,
              station: resolvedStationName,
              tags: query.requiredSkills,
            )
          : null,
      validationChiefs: null,
      notifiedUserIds: query.notifiedUserIds,
      declinedByUserIds: query.declinedByUserIds,
      seenByUserIds: query.seenByUserIds,
      currentWave: null,
      extraData: {
        'onCallLevelId': query.onCallLevelId,
        'onCallLevelName': query.onCallLevelName,
        'requiredSkills': query.requiredSkills,
        'planningId': query.planningId,
        'createdById': query.createdById,
        'matchedAgentId': query.matchedAgentId,
      },
    );
  }

  /// Mappe le statut AgentQueryStatus vers TileStatus
  static TileStatus _mapStatus(AgentQueryStatus status) {
    switch (status) {
      case AgentQueryStatus.pending:
        return TileStatus.pending;
      case AgentQueryStatus.matched:
        return TileStatus.accepted;
      case AgentQueryStatus.cancelled:
        return TileStatus.cancelled;
    }
  }
}

/// Extension pour conversion directe depuis AgentQuery
extension AgentQueryToUnifiedTile on AgentQuery {
  UnifiedTileData toUnifiedTileData({
    required String resolvedStationName,
    String? matchedAgentName,
    String? team,
  }) {
    return AgentQueryAdapter.fromAgentQuery(
      query: this,
      resolvedStationName: resolvedStationName,
      matchedAgentName: matchedAgentName,
      team: team,
    );
  }
}
