import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/data/models/team_event_model.dart';
import 'package:nexshift_app/core/presentation/widgets/tile_confirm_dialog.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/unified_request_tile.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/unified_tile_data.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/unified_tile_enums.dart';
import 'package:nexshift_app/core/services/team_event_service.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';
import 'package:nexshift_app/features/team_events/presentation/pages/team_event_page.dart';

/// Tuile affichant un événement d'équipe via UnifiedRequestTile.
class TeamEventTileWrapper extends StatefulWidget {
  final TeamEvent event;
  final String? currentUserId;

  const TeamEventTileWrapper({
    super.key,
    required this.event,
    required this.currentUserId,
  });

  @override
  State<TeamEventTileWrapper> createState() => _TeamEventTileWrapperState();
}

class _TeamEventTileWrapperState extends State<TeamEventTileWrapper> {
  String? _stationName;

  @override
  void initState() {
    super.initState();
    _loadStationName();
  }

  @override
  void didUpdateWidget(TeamEventTileWrapper old) {
    super.didUpdateWidget(old);
    if (old.event.stationId != widget.event.stationId) {
      _loadStationName();
    }
  }

  Future<void> _loadStationName() async {
    final sdisId = SDISContext().currentSDISId;
    if (sdisId == null) return;
    final name =
        await StationNameCache().getStationName(sdisId, widget.event.stationId);
    if (mounted) setState(() => _stationName = name);
  }

  TileViewMode _viewMode() {
    final uid = widget.currentUserId ?? '';
    final event = widget.event;
    final isPast = event.endTime.isBefore(DateTime.now());
    final isCancelled = event.status == TeamEventStatus.cancelled;

    if (isPast || isCancelled) return TileViewMode.history;
    if (event.createdById == uid) return TileViewMode.myRequests;
    return TileViewMode.pending;
  }

  TileStatus _tileStatus() {
    final uid = widget.currentUserId ?? '';
    final event = widget.event;

    if (event.status == TeamEventStatus.cancelled) return TileStatus.cancelled;
    if (event.acceptedUserIds.contains(uid)) return TileStatus.accepted;
    if (event.declinedUserIds.contains(uid)) return TileStatus.declined;
    return TileStatus.pending;
  }

  Future<void> _respond(bool accepted) async {
    await TeamEventService().respondToEvent(
      event: widget.event,
      userId: widget.currentUserId ?? '',
      accepted: accepted,
    );
  }

  Future<void> _cancelEvent() async {
    final confirmed = await TileConfirmDialog.show(
      context,
      icon: Icons.event_busy_rounded,
      iconColor: Colors.red.shade600,
      title: 'Annuler l\'événement',
      message: 'Voulez-vous vraiment annuler cet événement ? Les participants seront notifiés.',
      confirmLabel: 'Annuler l\'événement',
      confirmColor: Colors.red.shade600,
      confirmIcon: Icons.close_rounded,
    );
    if (confirmed == true && mounted) {
      await TeamEventService().cancelEvent(event: widget.event);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final uid = widget.currentUserId ?? '';
    final viewMode = _viewMode();
    final status = _tileStatus();
    final stationName = _stationName ?? event.stationId;

    final hasDeclined = event.declinedUserIds.contains(uid);
    final isOrganizer = event.createdById == uid;
    final isPast = event.endTime.isBefore(DateTime.now());
    final isCancelled = event.status == TeamEventStatus.cancelled;

    // Colonne unique : titre de l'événement + horaires
    // Le lieu remplace le nom de la caserne si défini
    final locationOrStation = (event.location != null && event.location!.isNotEmpty)
        ? event.location!
        : stationName;

    final leftColumn = AgentColumnData(
      agentId: event.createdById,
      agentName: event.title,
      startTime: event.startTime,
      endTime: event.endTime,
      station: locationOrStation,
      team: event.teamId,
      tags: [
        '${event.acceptedUserIds.length} accepté(s)',
      ],
    );

    final tileData = UnifiedTileData(
      id: event.id,
      requestType: UnifiedRequestType.teamEvent,
      status: status,
      createdAt: event.createdAt,
      leftColumn: leftColumn,
      notifiedUserIds: event.invitedUserIds,
      declinedByUserIds: event.declinedUserIds,
      seenByUserIds: event.seenByUserIds,
      extraData: {
        'iconCodePoint': event.iconCodePoint,
        'description': event.description,
        'location': event.location,
        'acceptedCount': event.acceptedUserIds.length,
      },
    );

    // canAct : peut répondre si invité, pas encore répondu, pas passé/annulé
    final isInvited = event.invitedUserIds.contains(uid) ||
        event.acceptedUserIds.contains(uid) ||
        event.declinedUserIds.contains(uid);
    final canAct = !isPast && !isCancelled && isInvited && !hasDeclined;

    return UnifiedRequestTile(
      data: tileData,
      viewMode: viewMode,
      currentUserId: uid,
      canAct: canAct,
      onViewDetails: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TeamEventPage(event: event)),
      ),
      onAccept: viewMode == TileViewMode.pending && !hasDeclined && !isOrganizer
          ? () => _respond(true)
          : null,
      onRefuse: viewMode == TileViewMode.pending && !hasDeclined && !isOrganizer
          ? () => _respond(false)
          : null,
      onDelete: viewMode == TileViewMode.myRequests && isOrganizer
          ? _cancelEvent
          : null,
      acceptButtonText: 'Accepter',
      refuseButtonText: 'Refuser',
    );
  }
}
