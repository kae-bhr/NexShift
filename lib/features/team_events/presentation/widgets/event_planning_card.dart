import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/data/models/team_event_model.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/team_events/presentation/widgets/create_team_event_dialog.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';

/// Carte affichant un événement d'équipe dans la home_page.
/// Format identique aux PlanningCard : barre gauche appNameColor,
/// badge participants en haut à droite, tap → TeamEventPage.
class EventPlanningCard extends StatefulWidget {
  final TeamEvent event;
  final VoidCallback onTap;

  const EventPlanningCard({
    super.key,
    required this.event,
    required this.onTap,
  });

  @override
  State<EventPlanningCard> createState() => _EventPlanningCardState();
}

class _EventPlanningCardState extends State<EventPlanningCard> {
  String? _stationName;

  @override
  void initState() {
    super.initState();
    _loadStationName();
  }

  @override
  void didUpdateWidget(EventPlanningCard old) {
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
    final isPast = widget.event.endTime.isBefore(DateTime.now());
    final isCancelled = widget.event.status == TeamEventStatus.cancelled;
    final acceptedCount = widget.event.acceptedUserIds.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Opacity(
        opacity: (isPast || isCancelled) ? 0.5 : 1.0,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey.shade200,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isDark ? Colors.black : Colors.grey.shade300)
                        .withValues(alpha: isDark ? 0.3 : 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // ── Barre gauche appNameColor ──
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 5,
                      decoration: const BoxDecoration(
                        color: KColors.appNameColor,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Ligne 1 : nom de la station + badge acceptés ──
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _stationName ?? widget.event.stationId,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .tertiary
                                      .withValues(alpha: 0.5),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            // Badge nombre d'acceptés (haut droite, comme PlanningCard)
                            if (acceptedCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: KColors.appNameColor
                                      .withValues(alpha: isDark ? 0.2 : 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.people_rounded,
                                      size: 13,
                                      color: KColors.appNameColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$acceptedCount',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: KColors.appNameColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 4),

                        // ── Ligne 2 : [icône?] titre de l'événement ──
                        Row(
                          children: [
                            if (widget.event.iconCodePoint != null) ...[
                              Icon(
                                resolveEventIcon(widget.event.iconCodePoint),
                                size: 18,
                                color: KColors.appNameColor
                                    .withValues(alpha: 0.8),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                widget.event.title,
                                style: const TextStyle(
                                  color: KColors.appNameColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // ── Horaires ──
                        _EventDateTimeChip(
                          startTime: widget.event.startTime,
                          endTime: widget.event.endTime,
                          isDark: isDark,
                        ),

                        // ── Lieu (optionnel) ──
                        if (widget.event.location != null &&
                            widget.event.location!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 13,
                                color: isDark
                                    ? Colors.white38
                                    : Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  widget.event.location!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.grey.shade500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Date/heure chip ───────────────────────────────────────────────────────────
class _EventDateTimeChip extends StatelessWidget {
  final DateTime startTime;
  final DateTime endTime;
  final bool isDark;

  const _EventDateTimeChip({
    required this.startTime,
    required this.endTime,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM HH:mm');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? KColors.appNameColor.withValues(alpha: 0.1)
            : KColors.appNameColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: KColors.appNameColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 13,
            color: KColors.appNameColor.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 6),
          Text(
            '${fmt.format(startTime)} → ${fmt.format(endTime)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KColors.appNameColor,
            ),
          ),
        ],
      ),
    );
  }
}
