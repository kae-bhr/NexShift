import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/data/models/team_event_model.dart';
import 'package:nexshift_app/core/services/team_event_service.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';
import 'package:nexshift_app/features/team_events/presentation/pages/team_event_page.dart';

/// Tuile affichant un événement d'équipe dans l'onglet Événements de Recherches.
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
    final name = await StationNameCache()
        .getStationName(sdisId, widget.event.stationId);
    if (mounted) setState(() => _stationName = name);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final event = widget.event;
    final userId = widget.currentUserId ?? '';
    final hasAccepted = event.acceptedUserIds.contains(userId);
    final hasDeclined = event.declinedUserIds.contains(userId);
    final isPending = !hasAccepted && !hasDeclined;
    final isOrganizer = event.createdById == userId;
    final isPast = event.endTime.isBefore(DateTime.now());
    final fmt = DateFormat('dd/MM HH:mm');

    return Opacity(
      opacity: isPast ? 0.6 : 1.0,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.shade200,
          ),
        ),
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TeamEventPage(event: event)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ligne 1 : caserne + badge statut
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _stationName ?? event.stationId,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white38
                              : Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    _StatusBadge(
                      hasAccepted: hasAccepted,
                      hasDeclined: hasDeclined,
                      isOrganizer: isOrganizer,
                      isPast: isPast,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Ligne 2 : icône + titre
                Row(
                  children: [
                    if (event.iconCodePoint != null) ...[
                      Icon(
                        IconData(event.iconCodePoint!,
                            fontFamily: 'MaterialIcons'),
                        size: 18,
                        color: KColors.appNameColor.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: KColors.appNameColor,
                          letterSpacing: -0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Horaire
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: isDark
                          ? Colors.white38
                          : Colors.grey.shade500,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${fmt.format(event.startTime)} → ${fmt.format(event.endTime)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white54
                            : Colors.grey.shade600,
                      ),
                    ),
                    const Spacer(),
                    // Compteur acceptés
                    Icon(Icons.people_rounded,
                        size: 13,
                        color: KColors.appNameColor.withValues(alpha: 0.7)),
                    const SizedBox(width: 4),
                    Text(
                      '${event.acceptedUserIds.length} accepté(s)',
                      style: TextStyle(
                        fontSize: 12,
                        color: KColors.appNameColor.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                // Actions : Accepter / Refuser (si invité et pas répondu)
                if (isPending && !isOrganizer && !isPast) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            await TeamEventService().respondToEvent(
                              event: event,
                              userId: userId,
                              accepted: false,
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade400,
                            side: BorderSide(color: Colors.red.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          child: const Text('Décliner'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            await TeamEventService().respondToEvent(
                              event: event,
                              userId: userId,
                              accepted: true,
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: KColors.appNameColor,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          child: const Text('Accepter'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool hasAccepted;
  final bool hasDeclined;
  final bool isOrganizer;
  final bool isPast;

  const _StatusBadge({
    required this.hasAccepted,
    required this.hasDeclined,
    required this.isOrganizer,
    required this.isPast,
  });

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;

    if (isOrganizer) {
      label = 'Organisateur';
      color = KColors.appNameColor;
    } else if (hasAccepted) {
      label = 'Accepté';
      color = Colors.green.shade600;
    } else if (hasDeclined) {
      label = 'Décliné';
      color = Colors.red.shade400;
    } else if (isPast) {
      label = 'Passé';
      color = Colors.grey.shade500;
    } else {
      label = 'En attente';
      color = Colors.orange.shade600;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
