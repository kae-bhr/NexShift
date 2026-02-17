import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/trucks_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/data/models/crew_position_model.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/repositories/truck_repository.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/planning/presentation/pages/planning_team_details_page.dart';
import 'package:nexshift_app/features/planning/presentation/widgets/vehicle_detail_dialog.dart';
import 'package:nexshift_app/features/replacement/services/crew_allocator.dart';
import 'package:nexshift_app/core/repositories/vehicle_rules_repository.dart';
import 'package:nexshift_app/features/replacement/presentation/pages/skill_search_page.dart';
import 'package:nexshift_app/core/utils/subshift_normalizer.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';
import 'package:nexshift_app/core/services/on_call_disposition_service.dart';

class PlanningCard extends StatefulWidget {
  final Planning planning;
  final VoidCallback onTap;
  final bool showNote;
  final bool isExpanded;
  final int replacementCount;
  final int pendingRequestCount; // Nombre de demandes en attente
  // Vehicle icons to display at the bottom of the card. Each item expects:
  // {'type': String, 'id': int, 'color': Color}
  final List<Map<String, dynamic>> vehicleIconSpecs;
  final Color? availabilityColor; // Couleur pour les disponibilités
  final bool allReplacementsChecked; // Si tous les remplacements sont checkés
  // Agent count info for on-call levels badge
  final int? agentCountMin;
  final int? agentCountMax;
  final List<AgentCountIssue> agentCountIssues;

  const PlanningCard({
    super.key,
    required this.planning,
    required this.onTap,
    this.showNote = false,
    this.isExpanded = false,
    this.replacementCount = 0,
    this.pendingRequestCount = 0,
    this.vehicleIconSpecs = const [],
    this.availabilityColor,
    this.allReplacementsChecked = false,
    this.agentCountMin,
    this.agentCountMax,
    this.agentCountIssues = const [],
  });

  @override
  State<PlanningCard> createState() => _PlanningCardState();
}

class _PlanningCardState extends State<PlanningCard> {
  Team? _team;
  List<Map<String, dynamic>>? _userOnCallSlots;
  bool _loadingSlots = false;
  String? _stationName;

  @override
  void initState() {
    super.initState();
    _loadTeam();
    _loadUserOnCallSlots();
    _loadStationName();
    teamDataChangedNotifier.addListener(_onTeamDataChanged);
  }

  @override
  void dispose() {
    teamDataChangedNotifier.removeListener(_onTeamDataChanged);
    super.dispose();
  }

  void _onTeamDataChanged() {
    _loadTeam();
    _loadUserOnCallSlots();
  }

  Future<void> _loadTeam() async {
    final team = await TeamRepository().getById(
      widget.planning.team,
      stationId: widget.planning.station,
    );
    if (mounted) {
      setState(() {
        _team = team;
      });
    }
  }

  Future<void> _loadStationName() async {
    final sdisId = SDISContext().currentSDISId;
    if (sdisId != null) {
      final name = await StationNameCache().getStationName(
        sdisId,
        widget.planning.station,
      );
      if (mounted) {
        setState(() {
          _stationName = name;
        });
      }
    }
  }

  Future<void> _loadUserOnCallSlots() async {
    if (_loadingSlots) return;
    setState(() => _loadingSlots = true);
    final slots = await _getUserOnCallSlots();
    if (mounted) {
      setState(() {
        _userOnCallSlots = slots;
        _loadingSlots = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAvailability = widget.planning.id.startsWith('availability_');
    final teamColor = isAvailability
        ? Colors.grey
        : (_team?.color ?? const Color(0xFF757575));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPast = widget.planning.endTime.isBefore(DateTime.now());

    return ValueListenableBuilder<bool>(
      valueListenable: stationViewNotifier,
      builder: (context, stationView, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Opacity(
            opacity: isPast ? 0.5 : 1.0,
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
                    // Left accent bar
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 5,
                        decoration: BoxDecoration(
                          color: isAvailability
                              ? teamColor.withValues(alpha: 0.5)
                              : teamColor,
                          borderRadius: const BorderRadius.only(
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
                          // Station name + details button
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _stationName ?? widget.planning.station,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.tertiary
                                        .withValues(alpha: 0.5),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              // Badges
                              if (widget.pendingRequestCount > 0 ||
                                  widget.replacementCount > 0 ||
                                  widget.agentCountMin != null)
                                _BadgeRow(
                                  pendingCount: widget.pendingRequestCount,
                                  replacementCount: widget.replacementCount,
                                  allChecked: widget.allReplacementsChecked,
                                  agentCountMin: widget.agentCountMin,
                                  agentCountMax: widget.agentCountMax,
                                  agentCountIssues: widget.agentCountIssues,
                                  maxAgentsPerShift: widget.planning.maxAgents,
                                ),
                              // Delete for availabilities
                              if (isAvailability)
                                _DeleteIconButton(
                                  onPressed: () async {
                                    await _deleteAvailability(widget.planning.id);
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Team name row
                          Row(
                            children: [
                              if (isAvailability) ...[
                                Icon(
                                  Icons.volunteer_activism_rounded,
                                  size: 18,
                                  color: teamColor.withValues(alpha: 0.7),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  isAvailability
                                      ? 'Disponibilit\u00e9'
                                      : (_team?.name ?? widget.planning.team),
                                  style: TextStyle(
                                    color: isAvailability
                                        ? teamColor
                                        : teamColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    fontStyle: isAvailability
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ),
                              // Details button
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PlanningTeamDetailsPage(
                                          at: widget.planning.startTime,
                                        ),
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.06)
                                          : Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.open_in_new_rounded,
                                      size: 16,
                                      color: isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Date/time or on-call slots
                          if (!stationView && !isAvailability)
                            _buildUserOnCallSlotsWidget()
                          else if (stationView || isAvailability)
                            _DateTimeChip(
                              startTime: widget.planning.startTime,
                              endTime: widget.planning.endTime,
                              isDark: isDark,
                            ),
                          if (widget.showNote) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.search_rounded,
                                    size: 14,
                                    color: Colors.orange.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Recherche de comp\u00e9tences...",
                                    style: TextStyle(
                                      color: Colors.orange.shade700,
                                      fontStyle: FontStyle.italic,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // Vehicle icons + expand
                          if (!isAvailability) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.grey.shade100,
                                  ),
                                ),
                              ),
                              child: SizedBox(
                                height: 24,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _VehicleIconsRow(
                                        specs: widget.vehicleIconSpecs,
                                        planning: widget.planning,
                                      ),
                                    ),
                                    AnimatedRotation(
                                      turns: widget.isExpanded ? 0.5 : 0,
                                      duration: const Duration(milliseconds: 250),
                                      child: Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 22,
                                        color: isDark
                                            ? Colors.grey.shade500
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
      },
    );
  }

  Future<void> _deleteAvailability(String planningId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer la disponibilité ?"),
        content: const Text(
          "Voulez-vous vraiment supprimer cette disponibilité ?",
        ),
        actions: [
          TextButton(
            child: const Text("Annuler"),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Supprimer"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Extract availability ID from planning ID
        final availabilityId = planningId.replaceFirst('availability_', '');
        final repo = LocalRepository();
        await repo.deleteAvailability(availabilityId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Disponibilité supprimée'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          return;
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur : ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildUserOnCallSlotsWidget() {
    if (_userOnCallSlots == null) {
      return const SizedBox.shrink();
    }

    final slots = _userOnCallSlots!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (slots.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: isDark ? 0.15 : 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline_rounded, size: 14, color: Colors.red.shade400),
            const SizedBox(width: 6),
            Text(
              "Aucune p\u00e9riode de garde pour vous.",
              style: TextStyle(color: Colors.red.shade400, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final slot in slots) ...[
          Container(
            decoration: BoxDecoration(
              color: slot['type'] == 'available'
                  ? Colors.blue.withValues(alpha: isDark ? 0.12 : 0.06)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.grey.shade50),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  slot['type'] == 'available'
                      ? Icons.volunteer_activism_rounded
                      : Icons.schedule_rounded,
                  size: 14,
                  color: slot['type'] == 'available'
                      ? Colors.blue.shade400
                      : (isDark ? Colors.grey.shade400 : Colors.grey.shade500),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatDateTime(slot['start']!),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: slot['type'] == 'available'
                        ? Colors.blue.shade400
                        : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                    fontStyle: slot['type'] == 'available'
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 12,
                    color: slot['type'] == 'available'
                        ? Colors.blue.shade300
                        : (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
                  ),
                ),
                Text(
                  _formatDateTime(slot['end']!),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: slot['type'] == 'available'
                        ? Colors.blue.shade400
                        : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                    fontStyle: slot['type'] == 'available'
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Future<List<Map<String, dynamic>>> _getUserOnCallSlots() async {
    final user = await UserStorageHelper.loadUser();
    if (user == null) return [];
    final repo = LocalRepository();
    final rawSubshifts = await repo.getSubshifts(stationId: user.station);
    final availabilities = await repo.getAvailabilities();
    // Résoudre les cascades de remplacements
    final subshifts = resolveReplacementCascades(rawSubshifts);
    final planning = widget.planning;
    final userId = user.id;
    final List<Map<String, dynamic>> slots = [];

    // Cas 1: L'utilisateur est agent de garde
    final isAgent = planning.agentsId.contains(userId);
    if (isAgent) {
      // Découper la période de garde en créneaux où le user n'est PAS remplacé
      DateTime current = planning.startTime;
      final end = planning.endTime;

      // Filtrer les subshifts où cet utilisateur est remplacé
      final relevant = subshifts
          .where((s) => s.planningId == planning.id && s.replacedId == userId)
          .toList();
      relevant.sort((a, b) => a.start.compareTo(b.start));

      for (final s in relevant) {
        if (current.isBefore(s.start)) {
          slots.add({'start': current, 'end': s.start, 'type': 'onCall'});
        }
        current = current.isBefore(s.end) ? s.end : current;
      }
      if (current.isBefore(end)) {
        slots.add({'start': current, 'end': end, 'type': 'onCall'});
      }
    }

    // Cas 2: L'utilisateur est remplaçant (ajouter les créneaux de remplacement)
    final replacerShifts = subshifts
        .where((s) => s.planningId == planning.id && s.replacerId == userId)
        .toList();

    for (final shift in replacerShifts) {
      slots.add({
        'start': shift.start,
        'end': shift.end,
        'type': 'replacement',
      });
    }

    // Cas 3: L'utilisateur est en disponibilité pour ce planning
    final availableShifts = availabilities
        .where(
          (a) =>
              a.agentId == userId &&
              (a.planningId == null || a.planningId == planning.id),
        )
        .toList();

    for (final avail in availableShifts) {
      // Vérifier que la disponibilité chevauche le planning
      if (avail.end.isAfter(planning.startTime) &&
          avail.start.isBefore(planning.endTime)) {
        // Calculer l'intersection avec le planning
        final intersectionStart = avail.start.isAfter(planning.startTime)
            ? avail.start
            : planning.startTime;
        final intersectionEnd = avail.end.isBefore(planning.endTime)
            ? avail.end
            : planning.endTime;

        if (intersectionStart.isBefore(intersectionEnd)) {
          slots.add({
            'start': intersectionStart,
            'end': intersectionEnd,
            'type': 'available',
          });
        }
      }
    }

    // Trier les slots par ordre chronologique
    slots.sort((a, b) => a['start']!.compareTo(b['start']!));

    return slots
        .where((slot) => slot['start']!.isBefore(slot['end']!))
        .toList();
  }
}

/// Chip showing start → end time in a subtle rounded container
class _DateTimeChip extends StatelessWidget {
  final DateTime startTime;
  final DateTime endTime;
  final bool isDark;

  const _DateTimeChip({
    required this.startTime,
    required this.endTime,
    required this.isDark,
  });

  String _fmt(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 14,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
          ),
          const SizedBox(width: 6),
          Text(
            _fmt(startTime),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 12,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
            ),
          ),
          Text(
            _fmt(endTime),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Row of badges for pending requests, replacement count, and agent count
class _BadgeRow extends StatelessWidget {
  final int pendingCount;
  final int replacementCount;
  final bool allChecked;
  final int? agentCountMin;
  final int? agentCountMax;
  final List<AgentCountIssue> agentCountIssues;
  final int maxAgentsPerShift;

  const _BadgeRow({
    required this.pendingCount,
    required this.replacementCount,
    required this.allChecked,
    this.agentCountMin,
    this.agentCountMax,
    this.agentCountIssues = const [],
    this.maxAgentsPerShift = 6,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Déterminer l'état du badge d'agents
    final hasAgentCount = agentCountMin != null;
    final hasIssues = agentCountIssues.isNotEmpty;
    final isConstant = agentCountMin == agentCountMax;
    final agentCountText = hasAgentCount
        ? (isConstant ? '$agentCountMin' : '$agentCountMin-$agentCountMax')
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pendingCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isDark
                  ? KColors.appNameColor.withValues(alpha: 0.2)
                  : KColors.appNameColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.refresh_rounded,
                  size: 12,
                  color: KColors.appNameColor,
                ),
                const SizedBox(width: 3),
                Text(
                  pendingCount.toString(),
                  style: TextStyle(
                    color: KColors.appNameColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        if (pendingCount > 0 && (replacementCount > 0 || hasAgentCount))
          const SizedBox(width: 4),
        // Badge compteur d'agents (remplace le badge de remplacement quand disponible)
        if (hasAgentCount)
          GestureDetector(
            onTap: hasIssues
                ? () => _showAgentCountDiagnostic(context)
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: hasIssues
                    ? Colors.orange.withValues(alpha: isDark ? 0.25 : 0.15)
                    : (allChecked
                        ? Colors.green.withValues(alpha: isDark ? 0.25 : 0.15)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.grey.shade100)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_rounded,
                    size: 12,
                    color: hasIssues
                        ? Colors.orange.shade700
                        : (allChecked
                            ? Colors.green.shade600
                            : (isDark ? Colors.grey.shade300 : Colors.grey.shade600)),
                  ),
                  const SizedBox(width: 3),
                  if (allChecked && !hasIssues)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: Colors.green.shade600,
                      ),
                    ),
                  Text(
                    agentCountText!,
                    style: TextStyle(
                      color: hasIssues
                          ? Colors.orange.shade700
                          : (allChecked
                              ? Colors.green.shade600
                              : (isDark ? Colors.grey.shade300 : Colors.grey.shade600)),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (hasIssues) ...[
                    const SizedBox(width: 3),
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 13,
                      color: Colors.orange.shade700,
                    ),
                  ],
                ],
              ),
            ),
          )
        // Fallback: ancien badge de remplacements si pas de compteur d'agents
        else if (replacementCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: allChecked
                  ? Colors.green.withValues(alpha: isDark ? 0.25 : 0.15)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (allChecked)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: Colors.green.shade600,
                    ),
                  ),
                Text(
                  replacementCount.toString(),
                  style: TextStyle(
                    color: allChecked
                        ? Colors.green.shade600
                        : (isDark ? Colors.grey.shade300 : Colors.grey.shade600),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _showAgentCountDiagnostic(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isConstant = agentCountMin == agentCountMax;

    String message;
    if (isConstant && agentCountMin! > maxAgentsPerShift) {
      message =
          "Le nombre d'agents présents dans l'effectif de cette astreinte est trop important : "
          "$agentCountMin au lieu de $maxAgentsPerShift. "
          "Pensez à retirer ${agentCountMin! - maxAgentsPerShift} agent(s) de l'astreinte.";
    } else if (isConstant && agentCountMin! < maxAgentsPerShift) {
      message =
          "Le nombre d'agents présents dans l'effectif de cette astreinte est trop faible : "
          "$agentCountMin au lieu de $maxAgentsPerShift. "
          "Pensez à ajouter ${maxAgentsPerShift - agentCountMin!} agent(s) à cette astreinte.";
    } else {
      message =
          "Le nombre d'agents en astreinte est inconstant au cours de l'astreinte "
          "et différent de $maxAgentsPerShift.";
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                "Diagnostic d'effectif",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 14)),
            if (!isConstant && agentCountIssues.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Détail par plage :',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              ...agentCountIssues.map((issue) {
                final startStr =
                    "${issue.start.day.toString().padLeft(2, '0')}/${issue.start.month.toString().padLeft(2, '0')} "
                    "${issue.start.hour.toString().padLeft(2, '0')}:${issue.start.minute.toString().padLeft(2, '0')}";
                final endStr =
                    "${issue.end.day.toString().padLeft(2, '0')}/${issue.end.month.toString().padLeft(2, '0')} "
                    "${issue.end.hour.toString().padLeft(2, '0')}:${issue.end.minute.toString().padLeft(2, '0')}";
                final diff = issue.count - issue.expected;
                final diffStr = diff > 0 ? '+$diff' : '$diff';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        diff > 0
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 14,
                        color: diff > 0 ? Colors.orange.shade600 : Colors.red.shade400,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '$startStr → $endStr : ${issue.count} agent(s) ($diffStr)',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

/// Small delete button for availability cards
class _DeleteIconButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _DeleteIconButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: isDark ? 0.15 : 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.delete_outline_rounded,
            color: Colors.red.shade400,
            size: 16,
          ),
        ),
      ),
    );
  }
}

class _VehicleIconsRow extends StatelessWidget {
  final List<Map<String, dynamic>> specs;
  final Planning planning;

  const _VehicleIconsRow({required this.specs, required this.planning});

  @override
  Widget build(BuildContext context) {
    if (specs.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 0,
      children: specs
          .map((s) => _VehicleIcon(spec: s, planning: planning))
          .toList(),
    );
  }
}

class _VehicleIcon extends StatelessWidget {
  final Map<String, dynamic> spec;
  final Planning planning;

  const _VehicleIcon({required this.spec, required this.planning});

  Future<void> _showVehicleDialog(BuildContext context) async {
    final String type = spec['type'] as String;
    final int id = spec['id'] as int;
    final String? period =
        spec['period']
            as String?; // displaySuffix (e.g. '4H', '6H', 'PS', 'DEF')

    // Fetch the truck data for this planning's station
    final trucks = await TruckRepository().getByStation(planning.station);
    if (trucks.isEmpty) {
      debugPrint('⚠️ No trucks found for station ${planning.station}');
      return;
    }

    final truck = trucks.firstWhere(
      (t) => t.type == type && t.id == id,
      orElse: () => trucks.first,
    );

    // Get all users and subshifts
    final repo = LocalRepository();
    final allUsers = await repo.getAllUsers();
    final allSubshifts = await repo.getSubshifts(stationId: planning.station);

    final baseAgents = allUsers
        .where((u) => planning.agentsId.contains(u.id))
        .toList();

    // Filter subshifts for this planning
    final subshifts = allSubshifts
        .where((s) => s.planningId == planning.id)
        .toList();

    // Recalculate time ranges taking replacements into account
    // Build a truck clone tagged with a specific modeId if this icon represents a sub-mode.
    // We only know the display suffix; we need to resolve the matching CrewMode ID.
    Truck effectiveTruck = truck;
    String? resolvedModeId;
    if (period != null) {
      // Fetch rule set to map displaySuffix -> mode.id
      final rulesRepo = VehicleRulesRepository();
      final ruleSet = await rulesRepo.getRules(
        vehicleType: truck.type,
        stationId: planning.station,
      );
      if (ruleSet != null) {
        final matching = ruleSet.modes
            .where((m) => m.displaySuffix == period)
            .toList();
        if (matching.isNotEmpty) {
          resolvedModeId = matching.first.id;
        } else if (period == 'DEF') {
          resolvedModeId = ruleSet.defaultMode?.id;
        }
      }
      if (resolvedModeId != null) {
        effectiveTruck = Truck(
          id: truck.id,
          displayNumber: truck.displayNumber,
          type: truck.type,
          station: truck.station,
          modeId: resolvedModeId,
        );
      }
    }

    final timeRanges = await _calculateTimeRangesForVehicle(
      truck: effectiveTruck,
      period: period,
      baseAgents: baseAgents,
      allUsers: allUsers,
      subshifts: subshifts,
      planning: planning,
    );

    // Get effective agents at the first problematic time (or planning start)
    final evaluationTime = timeRanges.isNotEmpty
        ? timeRanges.first.start
        : planning.startTime;
    final evaluationUtc = evaluationTime.toUtc();

    final effectiveAgents = List<User>.from(baseAgents);
    for (final s in subshifts) {
      final start = s.start.toUtc();
      final end = s.end.toUtc();
      if ((start.isBefore(evaluationUtc) ||
              start.isAtSameMomentAs(evaluationUtc)) &&
          end.isAfter(evaluationUtc)) {
        final idx = effectiveAgents.indexWhere((u) => u.id == s.replacedId);
        if (idx != -1) {
          final replacer = allUsers.firstWhere(
            (u) => u.id == s.replacerId,
            orElse: () => effectiveAgents[idx],
          );
          effectiveAgents[idx] = replacer;
        }
      }
    }

    // Calculate the actual CrewResult with positions
    final crewResult = await CrewAllocator.allocateVehicleCrew(
      agents: effectiveAgents,
      truck: effectiveTruck,
      stationId: planning.station,
    );

    if (context.mounted) {
      final currentUser = await UserStorageHelper.loadUser();

      showVehicleDetailDialog(
        context: context,
        truck: effectiveTruck,
        crewResult: crewResult,
        fptMode: period, // generalized: now used for any multi-mode suffix
        timeRanges: timeRanges,
        currentUser: currentUser,
        currentPlanning: planning,
        onReplacementSearch: (truck, position) {
          Navigator.pop(context); // Close dialog first
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SkillSearchPage(
                planning: planning,
                preselectedSkills: position.requiredSkills,
              ),
            ),
          );
        },
      );
    }
  }

  Future<List<TimeRangeStatus>> _calculateTimeRangesForVehicle({
    required Truck truck,
    required String? period,
    required List<User> baseAgents,
    required List<User> allUsers,
    required List<Subshift> subshifts,
    required Planning planning,
  }) async {
    debugPrint(
      '\n=== CALCULATING TIME RANGES FOR ${truck.type}${truck.id}${period != null ? " $period" : ""} ===',
    );

    // Get all trucks at the station to simulate sequential allocation
    final allTrucks = await TruckRepository().getByStation(planning.station);
    if (allTrucks.isEmpty) return [];

    // Build critical time points: planning start/end + subshift boundaries
    final criticalTimes = <DateTime>{
      planning.startTime,
      planning.endTime.subtract(const Duration(seconds: 1)),
    };

    for (final s in subshifts) {
      criticalTimes.add(s.start);
      criticalTimes.add(s.end);
      debugPrint(
        'Subshift: ${s.start} to ${s.end} (replacedId: ${s.replacedId}, replacerId: ${s.replacerId})',
      );
    }

    final samplePoints = criticalTimes.toList()..sort();
    debugPrint(
      'Sample points: ${samplePoints.map((t) => "${t.hour}:${t.minute.toString().padLeft(2, "0")}").join(", ")}',
    );

    final List<Map<String, dynamic>> rawRanges = [];

    // Evaluate vehicle status at each time point WITH SEQUENTIAL ALLOCATION
    for (int i = 0; i < samplePoints.length; i++) {
      final sampleTime = samplePoints[i];
      final sampleUtc = sampleTime.toUtc();

      // Determine range end
      final rangeEnd = i < samplePoints.length - 1
          ? samplePoints[i + 1]
          : planning.endTime;

      // Skip very short ranges (< 2 minutes)
      if (rangeEnd.difference(sampleTime).inMinutes < 2) {
        debugPrint(
          'Skipping short range ${sampleTime.hour}:${sampleTime.minute.toString().padLeft(2, "0")} - ${rangeEnd.hour}:${rangeEnd.minute.toString().padLeft(2, "0")}',
        );
        continue;
      }

      debugPrint(
        '\n--- Evaluating at ${sampleTime.hour}:${sampleTime.minute.toString().padLeft(2, "0")} ---',
      );

      // Apply replacements at this time
      final effectiveAgents = List<User>.from(baseAgents);
      int replacementsApplied = 0;
      for (final s in subshifts) {
        final start = s.start.toUtc();
        final end = s.end.toUtc();
        if ((start.isBefore(sampleUtc) || start.isAtSameMomentAs(sampleUtc)) &&
            end.isAfter(sampleUtc)) {
          final idx = effectiveAgents.indexWhere((u) => u.id == s.replacedId);
          if (idx != -1) {
            final replacer = allUsers.firstWhere(
              (u) => u.id == s.replacerId,
              orElse: () => effectiveAgents[idx],
            );
            effectiveAgents[idx] = replacer;
            replacementsApplied++;
          }
        }
      }
      debugPrint('Replacements applied: $replacementsApplied');

      // SEQUENTIAL ALLOCATION: Build agent pools per vehicle type
      final Map<String, List<User>> poolsByType = {};
      for (final truckType in KTrucks.vehicleTypeOrder) {
        poolsByType[truckType] = List<User>.from(effectiveAgents);
      }

      // Separate FPT from other trucks
      final fptTrucks = allTrucks.where((t) => t.type == KTrucks.fpt).toList();
      final otherTrucks = allTrucks
          .where((t) => t.type != KTrucks.fpt)
          .toList();

      debugPrint('Allocating trucks in order:');
      for (final t in otherTrucks) {
        debugPrint('  - ${t.type}${t.id}');
      }

      VehicleStatus? targetStatus;
      CrewResult? targetResult;

      // Allocate standard trucks (non-FPT) sequentially until we reach our target
      for (final t in otherTrucks) {
        final pool = poolsByType[t.type]!;
        debugPrint(
          '  Allocating ${t.type}${t.id} with pool of ${pool.length} agents (type ${t.type})',
        );
        // If this is the target vehicle and a specific mode was requested (effectiveTruck.modeId set),
        // allocate using that mode. Otherwise allocate default/configured mode.
        final bool isTarget = (t.type == truck.type && t.id == truck.id);
        final Truck truckForAlloc = isTarget && truck.modeId != null
            ? Truck(
                id: t.id,
                displayNumber: t.displayNumber,
                type: t.type,
                station: t.station,
                modeId: truck.modeId,
              )
            : t;
        final r = await CrewAllocator.allocateVehicleCrew(
          agents: pool,
          truck: truckForAlloc,
          stationId: planning.station,
        );
        debugPrint('    Result: ${r.status}, crew size: ${r.crew.length}');

        // Remove used agents from the pool
        for (final used in r.crew) {
          pool.removeWhere((a) => a.id == used.id);
        }
        debugPrint('    Pool after allocation: ${pool.length} agents');

        // Check if this is our target vehicle (period may be null or a suffix)
        if (isTarget) {
          targetStatus = r.status;
          targetResult = r;
          debugPrint('Target vehicle ${t.type}${t.id}: status = ${r.status}');
          debugPrint('  Unfilled positions:');
          for (final assignment in r.positions.where((a) => !a.isFilled)) {
            debugPrint('    - ${assignment.position.label}');
          }
          break; // Stop after finding our vehicle
        }
      }

      // If target is FPT, handle FPT allocation with shared pool (supports any station-defined modes)
      if (truck.type == KTrucks.fpt && period != null) {
        final fptPool = poolsByType[KTrucks.fpt];
        if (fptPool != null) {
          // Sort FPT trucks by ID to ensure consistent allocation order
          fptTrucks.sort((a, b) => a.id.compareTo(b.id));

          for (final fpt in fptTrucks) {
            // Create a pool snapshot for this specific FPT (modes share crew)
            final thisFptPool = List<User>.from(fptPool);

            // Fetch rule set to iterate all defined modes
            final rulesRepo = VehicleRulesRepository();
            final ruleSet = await rulesRepo.getRules(
              vehicleType: KTrucks.fpt,
              stationId: planning.station,
            );
            final modes = ruleSet?.modes ?? const [];
            final allUsedIds = <String>{};

            for (final mode in modes) {
              final res = await CrewAllocator.allocateVehicleCrew(
                agents: thisFptPool,
                truck: Truck(
                  id: fpt.id,
                  displayNumber: fpt.displayNumber,
                  type: fpt.type,
                  station: fpt.station,
                  modeId: mode.id,
                ),
                stationId: planning.station,
              );

              for (final used in res.crew) {
                allUsedIds.add(used.id);
              }

              if (fpt.id == truck.id && period == mode.displaySuffix) {
                targetStatus = res.status;
                targetResult = res;
                debugPrint(
                  'Target FPT${fpt.id} ${mode.displaySuffix}: status = ${res.status}',
                );
                break;
              }
            }

            if (targetResult != null) break;

            // Remove from global pool the union of all used in modes for this FPT
            fptPool.removeWhere((a) => allUsedIds.contains(a.id));
          }
        }
      }

      // Only track problematic ranges (orange or red) with their unfilled positions
      if (targetStatus != null &&
          targetResult != null &&
          (targetStatus == VehicleStatus.orange ||
              targetStatus == VehicleStatus.red)) {
        // Get list of unfilled position labels (for red/incomplete vehicles)
        final unfilledPositionLabels =
            targetResult.positions
                .where((assignment) => !assignment.isFilled)
                .map((assignment) => assignment.position.label)
                .toList()
              ..sort(); // Sort for consistent comparison

        // Get complete CrewPosition objects for unfilled positions
        final unfilledCrewPositions = targetResult.positions
            .where((assignment) => !assignment.isFilled)
            .map((assignment) => assignment.position)
            .toList();

        // Get missing positions for full crew (for orange vehicles)
        final missingForFullLabels =
            targetResult.missingForFull.map((pos) => pos.label).toList()
              ..sort();

        // Combine all missing positions for comparison
        final allMissingLabels = [
          ...unfilledPositionLabels,
          ...missingForFullLabels,
        ]..sort();

        debugPrint(
          'Adding problematic range: ${sampleTime.hour}:${sampleTime.minute.toString().padLeft(2, "0")} - ${rangeEnd.hour}:${rangeEnd.minute.toString().padLeft(2, "0")}',
        );
        debugPrint(
          '  Unfilled positions: ${unfilledPositionLabels.join(", ")}',
        );
        debugPrint('  Missing for full: ${missingForFullLabels.join(", ")}');

        rawRanges.add({
          'start': sampleTime,
          'end': rangeEnd,
          'status': targetStatus,
          'unfilledPositions': unfilledPositionLabels,
          'unfilledCrewPositions': unfilledCrewPositions,
          'missingForFull': targetResult.missingForFull,
          'allMissingLabels': allMissingLabels, // For comparison
        });
      }
    }

    debugPrint('\n--- Raw ranges: ${rawRanges.length} ---');

    // Merge consecutive ranges with same status AND same missing positions
    final List<Map<String, dynamic>> mergedRanges = [];
    for (final range in rawRanges) {
      if (mergedRanges.isEmpty) {
        mergedRanges.add(range);
      } else {
        final last = mergedRanges.last;
        final lastPositions = last['allMissingLabels'] as List<String>;
        final currentPositions = range['allMissingLabels'] as List<String>;

        // Check if consecutive, same status, AND same missing positions (unfilled + missingForFull)
        final samePositions =
            lastPositions.length == currentPositions.length &&
            lastPositions.every((pos) => currentPositions.contains(pos));

        if (last['end'] == range['start'] &&
            last['status'] == range['status'] &&
            samePositions) {
          last['end'] = range['end'];
          // Keep the same positions (they're identical)
          debugPrint('Merged range (same positions)');
        } else {
          mergedRanges.add(range);
          if (last['end'] == range['start'] &&
              last['status'] == range['status']) {
            debugPrint('NOT merged: different positions');
          }
        }
      }
    }

    debugPrint('Merged ranges: ${mergedRanges.length}');

    // Extend last range to planning.endTime if within 2 minutes
    if (mergedRanges.isNotEmpty) {
      final last = mergedRanges.last;
      final endTime = last['end'] as DateTime;
      if (planning.endTime.difference(endTime).inMinutes < 2) {
        debugPrint('Extending last range to planning end time');
        last['end'] = planning.endTime;
      }
    }

    // Convert to TimeRangeStatus objects
    final result = mergedRanges.map((r) {
      return TimeRangeStatus(
        start: r['start'] as DateTime,
        end: r['end'] as DateTime,
        status: r['status'] as VehicleStatus,
        unfilledPositions: List<String>.from(r['unfilledPositions'] as List),
        unfilledCrewPositions: List<CrewPosition>.from(
          r['unfilledCrewPositions'] as List,
        ),
        missingForFull: List<CrewPosition>.from(r['missingForFull'] as List),
      );
    }).toList();

    debugPrint('=== FINAL TIME RANGES: ${result.length} ===\n');
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final String type = spec['type'] as String;
    final int id = spec['id'] as int;
    final int? displayNumber =
        spec['displayNumber'] as int?; // Get displayNumber from spec
    final String? period = spec['period'] as String?;
    final Color color = spec['color'] as Color? ?? Theme.of(context).hintColor;
    final iconData = KTrucks.vehicleIcons[type] ?? Icons.local_shipping;

    return GestureDetector(
      onTap: () => _showVehicleDialog(context),
      child: SizedBox(
        width: period != null ? 28 : 24,
        height: 20,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Icon
            Positioned(
              left: 0,
              top: 2,
              child: Icon(iconData, size: 16, color: color),
            ),
            // Superscript displayNumber (or fallback to id)
            Positioned(
              left: 14,
              top: 0,
              child: Text(
                (displayNumber ?? id).toString(),
                style: TextStyle(
                  fontSize: 10,
                  height: 1,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Subscript period (4H/6H)
            if (period != null)
              Positioned(
                left: 14,
                bottom: 0,
                child: Text(
                  period,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
