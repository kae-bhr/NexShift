import '../unified_tile_data.dart';
import '../unified_tile_enums.dart';
import '../../../../../core/data/models/shift_exchange_request_model.dart';
import '../../../../../core/data/models/shift_exchange_proposal_model.dart';
import '../../../../../core/data/models/planning_model.dart';

/// Adaptateur pour convertir ShiftExchangeRequest en UnifiedTileData
class ExchangeRequestAdapter {
  /// Convertit une demande d'échange en données unifiées
  ///
  /// [request] - La demande d'échange
  /// [selectedProposal] - La proposition sélectionnée (si existante)
  /// [proposerPlanning] - Le planning du proposeur (pour les dates)
  /// [initiatorTeam] - L'équipe de l'initiateur
  /// [proposerTeam] - L'équipe du proposeur
  /// [validationChiefs] - Liste des chefs pour validation
  static UnifiedTileData fromExchangeRequest({
    required ShiftExchangeRequest request,
    ShiftExchangeProposal? selectedProposal,
    Planning? proposerPlanning,
    String? initiatorTeam,
    String? proposerTeam,
    List<ChiefValidationData>? validationChiefs,
  }) {
    // Colonne gauche : initiateur
    final leftColumn = AgentColumnData(
      agentId: request.initiatorId,
      agentName: request.initiatorName,
      team: initiatorTeam,
      startTime: request.initiatorStartTime,
      endTime: request.initiatorEndTime,
      station: request.station,
    );

    // Colonne droite : proposeur sélectionné (si existant)
    AgentColumnData? rightColumn;
    if (selectedProposal != null && proposerPlanning != null) {
      rightColumn = AgentColumnData(
        agentId: selectedProposal.proposerId,
        agentName: selectedProposal.proposerName,
        team: proposerTeam,
        startTime: proposerPlanning.startTime,
        endTime: proposerPlanning.endTime,
        station: request.station,
      );
    }

    return UnifiedTileData(
      id: request.id,
      requestType: UnifiedRequestType.exchange,
      status: _mapStatus(request.status, selectedProposal),
      createdAt: request.createdAt,
      leftColumn: leftColumn,
      rightColumn: rightColumn,
      validationChiefs: validationChiefs,
      proposalCount: request.proposalIds.length,
      extraData: {
        'initiatorPlanningId': request.initiatorPlanningId,
        'selectedProposalId': request.selectedProposalId,
        'proposalIds': request.proposalIds,
        'refusedByUserIds': request.refusedByUserIds,
        'requiredKeySkills': request.requiredKeySkills,
        'selectedProposal': selectedProposal,
      },
    );
  }

  /// Mappe le statut de ShiftExchangeRequestStatus vers TileStatus
  static TileStatus _mapStatus(
    ShiftExchangeRequestStatus status,
    ShiftExchangeProposal? selectedProposal,
  ) {
    // Si une proposition est sélectionnée et en attente de validation
    if (selectedProposal != null) {
      if (selectedProposal.status ==
          ShiftExchangeProposalStatus.selectedByInitiator) {
        return TileStatus.pendingValidation;
      }
      if (selectedProposal.status == ShiftExchangeProposalStatus.validated) {
        return TileStatus.validated;
      }
      if (selectedProposal.status == ShiftExchangeProposalStatus.rejected) {
        return TileStatus.declined;
      }
    }

    switch (status) {
      case ShiftExchangeRequestStatus.open:
        return TileStatus.pending;
      case ShiftExchangeRequestStatus.proposalSelected:
        return TileStatus.pendingValidation;
      case ShiftExchangeRequestStatus.accepted:
        return TileStatus.validated;
      case ShiftExchangeRequestStatus.cancelled:
        return TileStatus.cancelled;
    }
  }

  /// Construit les données de validation des chefs à partir d'une proposition
  static List<ChiefValidationData> buildValidationChiefs({
    required ShiftExchangeProposal proposal,
    required Map<String, String> teamToChiefName,
  }) {
    final chiefs = <ChiefValidationData>[];

    for (final entry in proposal.leaderValidations.entries) {
      final teamId = entry.key;
      final validation = entry.value;
      final chiefName = teamToChiefName[teamId] ?? 'Chef équipe $teamId';

      // LeaderValidation utilise approved: bool
      final hasValidated = validation.approved;

      chiefs.add(ChiefValidationData(
        chiefId: validation.leaderId,
        chiefName: chiefName,
        team: teamId,
        hasValidated: hasValidated,
      ));
    }

    return chiefs;
  }
}

/// Extension pour conversion directe depuis ShiftExchangeRequest
extension ShiftExchangeRequestToUnifiedTile on ShiftExchangeRequest {
  /// Convertit en UnifiedTileData
  UnifiedTileData toUnifiedTileData({
    ShiftExchangeProposal? selectedProposal,
    Planning? proposerPlanning,
    String? initiatorTeam,
    String? proposerTeam,
    List<ChiefValidationData>? validationChiefs,
  }) {
    return ExchangeRequestAdapter.fromExchangeRequest(
      request: this,
      selectedProposal: selectedProposal,
      proposerPlanning: proposerPlanning,
      initiatorTeam: initiatorTeam,
      proposerTeam: proposerTeam,
      validationChiefs: validationChiefs,
    );
  }
}
