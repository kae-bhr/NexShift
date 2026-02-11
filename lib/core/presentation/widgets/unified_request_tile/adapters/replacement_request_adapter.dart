import '../unified_tile_data.dart';
import '../unified_tile_enums.dart';
import '../../../../../core/services/replacement_notification_service.dart';
import '../../../../../core/data/models/user_model.dart';

/// Adaptateur pour convertir ReplacementRequest en UnifiedTileData
class ReplacementRequestAdapter {
  /// Convertit une demande de remplacement automatique en données unifiées
  ///
  /// [request] - La demande de remplacement
  /// [requesterName] - Nom du demandeur (doit être récupéré séparément)
  /// [replacer] - Utilisateur remplaçant si la demande est acceptée
  /// [validationChiefs] - Liste des chefs pour validation (optionnel)
  static UnifiedTileData fromReplacementRequest({
    required ReplacementRequest request,
    required String requesterName,
    User? replacer,
    List<ChiefValidationData>? validationChiefs,
  }) {
    return UnifiedTileData(
      id: request.id,
      requestType: request.isSOS
          ? UnifiedRequestType.sosReplacement
          : UnifiedRequestType.automaticReplacement,
      status: _mapStatus(request.status, request.pendingValidationUserIds),
      createdAt: request.createdAt,
      leftColumn: AgentColumnData(
        agentId: request.requesterId,
        agentName: requesterName,
        team: request.team,
        startTime: request.startTime,
        endTime: request.endTime,
        station: request.station,
      ),
      rightColumn: replacer != null
          ? AgentColumnData(
              agentId: replacer.id,
              agentName: replacer.displayName,
              team: replacer.team,
              startTime: request.acceptedStartTime ?? request.startTime,
              endTime: request.acceptedEndTime ?? request.endTime,
              station: request.station,
            )
          : null,
      validationChiefs: validationChiefs,
      seenByUserIds: request.seenByUserIds,
      declinedByUserIds: request.declinedByUserIds,
      notifiedUserIds: request.notifiedUserIds,
      currentWave: request.currentWave > 0 ? request.currentWave : null,
      isSOS: request.isSOS,
      extraData: {
        'planningId': request.planningId,
        'requestType': request.requestType,
        'requiredSkills': request.requiredSkills,
        'mode': request.mode,
        'wavesSuspended': request.wavesSuspended,
        'pendingValidationUserIds': request.pendingValidationUserIds,
      },
    );
  }

  /// Mappe le statut de ReplacementRequestStatus vers TileStatus
  static TileStatus _mapStatus(
    ReplacementRequestStatus status,
    List<String> pendingValidationUserIds,
  ) {
    // Si des utilisateurs sont en attente de validation, c'est pendingValidation
    if (pendingValidationUserIds.isNotEmpty &&
        status == ReplacementRequestStatus.pending) {
      return TileStatus.pendingValidation;
    }

    switch (status) {
      case ReplacementRequestStatus.pending:
        return TileStatus.pending;
      case ReplacementRequestStatus.accepted:
        return TileStatus.accepted;
      case ReplacementRequestStatus.cancelled:
        return TileStatus.cancelled;
      case ReplacementRequestStatus.expired:
        return TileStatus.expired;
    }
  }
}

/// Extension pour conversion directe depuis ReplacementRequest
extension ReplacementRequestToUnifiedTile on ReplacementRequest {
  /// Convertit en UnifiedTileData avec les données minimales
  UnifiedTileData toUnifiedTileData({
    required String requesterName,
    User? replacer,
    List<ChiefValidationData>? validationChiefs,
  }) {
    return ReplacementRequestAdapter.fromReplacementRequest(
      request: this,
      requesterName: requesterName,
      replacer: replacer,
      validationChiefs: validationChiefs,
    );
  }
}
