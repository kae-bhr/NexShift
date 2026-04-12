import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/data/models/agent_query_model.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/adapters/agent_query_adapter.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/components/history_dialog.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/unified_request_tile.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/unified_tile_enums.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/replacement_sub_tabs.dart';

/// Tuile AgentQuery unifiée — délègue à UnifiedRequestTile via AgentQueryAdapter.
class AgentQueryTileWrapper extends StatefulWidget {
  final AgentQuery query;
  final AgentQuerySubTab subTab;
  final String? currentUserId;
  final VoidCallback onCancel;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onShowNotified;
  final VoidCallback onResendNotifications;
  final Future<void> Function()? onMarkAsSeen;

  const AgentQueryTileWrapper({
    super.key,
    required this.query,
    required this.subTab,
    required this.currentUserId,
    required this.onCancel,
    required this.onAccept,
    required this.onDecline,
    required this.onShowNotified,
    required this.onResendNotifications,
    this.onMarkAsSeen,
  });

  @override
  State<AgentQueryTileWrapper> createState() => _AgentQueryTileWrapperState();
}

class _AgentQueryTileWrapperState extends State<AgentQueryTileWrapper> {
  String? _resolvedStationName;
  String? _resolvedTeam;

  @override
  void initState() {
    super.initState();
    _resolveStationName();
    _resolvePlanningTeam();
  }

  Future<void> _resolveStationName() async {
    final sdisId = SDISContext().currentSDISId;
    if (sdisId != null && widget.query.station.isNotEmpty) {
      final name =
          await StationNameCache().getStationName(sdisId, widget.query.station);
      if (mounted) {
        setState(() => _resolvedStationName = name);
      }
    }
  }

  Future<void> _resolvePlanningTeam() async {
    if (widget.query.planningId.isEmpty) return;
    try {
      final planning = await PlanningRepository().getById(
        widget.query.planningId,
        stationId: widget.query.station,
      );
      if (mounted && planning != null && planning.team.isNotEmpty) {
        setState(() => _resolvedTeam = planning.team);
      }
    } catch (_) {
      // Silencieux : l'équipe est optionnelle
    }
  }

  TileViewMode _viewMode() {
    if (widget.subTab == AgentQuerySubTab.history) return TileViewMode.history;
    if (widget.query.createdById == widget.currentUserId) {
      return TileViewMode.myRequests;
    }
    return TileViewMode.pending;
  }

  @override
  Widget build(BuildContext context) {
    final stationName = _resolvedStationName ?? widget.query.station;
    final viewMode = _viewMode();
    final data = AgentQueryAdapter.fromAgentQuery(
      query: widget.query,
      resolvedStationName: stationName,
      team: _resolvedTeam,
    );
    final canAct = widget.query.status == AgentQueryStatus.pending;

    // En mode myRequests : Accepter/Refuser SSI notifié et pas encore refusé
    final isNotified = widget.currentUserId != null &&
        widget.query.notifiedUserIds.contains(widget.currentUserId);
    final hasDeclined = widget.currentUserId != null &&
        widget.query.declinedByUserIds.contains(widget.currentUserId);
    final showActionsForCreator =
        viewMode == TileViewMode.myRequests && canAct && isNotified && !hasDeclined;

    // Badge "Historique" en mode history
    VoidCallback? onHistoryTap;
    if (viewMode == TileViewMode.history) {
      onHistoryTap = () => showHistoryDialog(
        context,
        HistoryDialogData(
          createdAt: widget.query.createdAt,
          acceptedAt: widget.query.completedAt,
          requestTypeLabel: 'Recherche d\'agent',
        ),
      );
    }

    return UnifiedRequestTile(
      data: data,
      viewMode: viewMode,
      currentUserId: widget.currentUserId ?? '',
      canAct: canAct,
      onDelete: viewMode == TileViewMode.myRequests && canAct
          ? widget.onCancel
          : null,
      onAccept: (viewMode == TileViewMode.pending || showActionsForCreator)
          ? widget.onAccept
          : null,
      onRefuse: (viewMode == TileViewMode.pending || showActionsForCreator)
          ? widget.onDecline
          : null,
      onWaveTap: widget.onShowNotified,
      onResendNotifications: viewMode == TileViewMode.myRequests && canAct
          ? widget.onResendNotifications
          : null,
      onMarkAsSeen: viewMode == TileViewMode.pending ? widget.onMarkAsSeen : null,
      onHistoryTap: onHistoryTap,
      acceptButtonText: 'Accepter',
      refuseButtonText: 'Refuser',
    );
  }
}
