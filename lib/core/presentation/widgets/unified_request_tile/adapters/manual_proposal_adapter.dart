import '../unified_tile_data.dart';
import '../unified_tile_enums.dart';
import '../../../../../features/replacement/presentation/widgets/filtered_requests_view.dart';

/// Adaptateur pour convertir ManualReplacementProposal en UnifiedTileData
class ManualProposalAdapter {
  /// Convertit une proposition de remplacement manuel en données unifiées
  ///
  /// [proposal] - La proposition manuelle
  /// [station] - Station (optionnel, si connu)
  static UnifiedTileData fromManualProposal({
    required ManualReplacementProposal proposal,
    String? station,
  }) {
    return UnifiedTileData(
      id: proposal.id,
      requestType: UnifiedRequestType.manualReplacement,
      status: _mapStatus(proposal.status),
      createdAt: proposal.createdAt ?? DateTime.now(),
      leftColumn: AgentColumnData(
        agentId: proposal.replacedId,
        agentName: proposal.replacedName,
        team: proposal.replacedTeam,
        startTime: proposal.startTime,
        endTime: proposal.endTime,
        station: station ?? '',
      ),
      rightColumn: AgentColumnData(
        agentId: proposal.replacerId,
        agentName: proposal.replacerName,
        team: proposal.replacerTeam,
        startTime: proposal.startTime,
        endTime: proposal.endTime,
        station: station ?? '',
      ),
      extraData: {
        'proposerId': proposal.proposerId,
        'proposerName': proposal.proposerName,
        'planningId': proposal.planningId,
      },
    );
  }

  /// Mappe le statut string vers TileStatus
  static TileStatus _mapStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return TileStatus.pending;
      case 'accepted':
        return TileStatus.accepted;
      case 'declined':
        return TileStatus.declined;
      case 'cancelled':
        return TileStatus.cancelled;
      case 'expired':
        return TileStatus.expired;
      default:
        return TileStatus.pending;
    }
  }
}

/// Extension pour conversion directe depuis ManualReplacementProposal
extension ManualProposalToUnifiedTile on ManualReplacementProposal {
  /// Convertit en UnifiedTileData
  UnifiedTileData toUnifiedTileData({String? station}) {
    return ManualProposalAdapter.fromManualProposal(
      proposal: this,
      station: station,
    );
  }
}
