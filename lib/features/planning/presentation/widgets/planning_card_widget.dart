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

class PlanningCard extends StatefulWidget {
  final Planning planning;
  final VoidCallback onTap;
  final bool showNote;
  final bool isExpanded;
  final int replacementCount;
  // Vehicle icons to display at the bottom of the card. Each item expects:
  // {'type': String, 'id': int, 'color': Color}
  final List<Map<String, dynamic>> vehicleIconSpecs;
  final Color? availabilityColor; // Couleur pour les disponibilités

  const PlanningCard({
    super.key,
    required this.planning,
    required this.onTap,
    this.showNote = false,
    this.isExpanded = false,
    this.replacementCount = 0,
    this.vehicleIconSpecs = const [],
    this.availabilityColor,
  });

  @override
  State<PlanningCard> createState() => _PlanningCardState();
}

class _PlanningCardState extends State<PlanningCard> {
  Team? _team;
  List<Map<String, dynamic>>? _userOnCallSlots;
  bool _loadingSlots = false;

  @override
  void initState() {
    super.initState();
    _loadTeam();
    _loadUserOnCallSlots();
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
    // Utiliser la couleur de l'équipe de l'utilisateur pour les disponibilités
    // Convertir en shade400 pour les disponibilités (moins voyant)
    final teamColor = isAvailability
        ? Colors.grey
        : (_team?.color ?? const Color(0xFF757575));

    return ValueListenableBuilder<bool>(
      valueListenable: stationViewNotifier,
      builder: (context, stationView, _) {
        return InkWell(
          onTap: widget.onTap,
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: teamColor, width: isAvailability ? 2 : 1),
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.planning.station,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: KTextStyle.regularTextStyle.fontSize,
                          fontFamily: KTextStyle.regularTextStyle.fontFamily,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (isAvailability)
                            Icon(
                              Icons.volunteer_activism,
                              size: 16,
                              color: teamColor,
                            ),
                          if (isAvailability) const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isAvailability
                                  ? 'Disponibilité'
                                  : (_team?.name ?? widget.planning.team),
                              style: TextStyle(
                                color: teamColor,
                                fontSize:
                                    KTextStyle.descriptionTextStyle.fontSize,
                                fontFamily:
                                    KTextStyle.descriptionTextStyle.fontFamily,
                                fontWeight: FontWeight.bold,
                                fontStyle: isAvailability
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: isAvailability
                                ? "Détails de la disponibilité"
                                : "Détails de l'astreinte",
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PlanningTeamDetailsPage(
                                    at: widget.planning.startTime,
                                  ),
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.search,
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (!stationView && !isAvailability)
                        _buildUserOnCallSlotsWidget()
                      else if (stationView || isAvailability) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: Colors.blueGrey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formatDateTime(widget.planning.startTime),
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward,
                              size: 14,
                              color: Colors.blueGrey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDateTime(widget.planning.endTime),
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (widget.showNote) ...[
                        const SizedBox(height: 8),
                        Text(
                          "Recherche de compétences en cours...",
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontStyle: FontStyle.italic,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (!isAvailability) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        SizedBox(
                          height: 28,
                          child: Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: !isAvailability
                                      ? _VehicleIconsRow(
                                          specs: widget.vehicleIconSpecs,
                                          planning: widget.planning,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                              Icon(
                                widget.isExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 20,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.replacementCount > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.replacementCount.toString(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // Ne peut pas trigger widget.replacementCount > 0 && isAvailability
                if (isAvailability)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 20,
                      ),
                      onPressed: () async {
                        await _deleteAvailability(widget.planning.id);
                      },
                    ),
                  ),
              ],
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
    // Si encore en chargement, ne rien afficher (pas de spinner pour éviter le blip)
    if (_userOnCallSlots == null) {
      return const SizedBox.shrink();
    }

    final slots = _userOnCallSlots!;
    if (slots.isEmpty) {
      return Text(
        "Aucune période de garde pour vous.",
        style: TextStyle(color: Colors.red.shade700, fontSize: 14),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final slot in slots) ...[
          Container(
            decoration: BoxDecoration(
              // Couleur de fond différente pour les disponibilités
              color: slot['type'] == 'available'
                  ? Colors.blue.shade50.withValues(alpha: 0.5)
                  : null,
              borderRadius: BorderRadius.circular(4),
              border: slot['type'] == 'available'
                  ? Border.all(
                      color: Colors.blue.shade300,
                      width: 1,
                      strokeAlign: BorderSide.strokeAlignInside,
                    )
                  : null,
            ),
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  slot['type'] == 'available'
                      ? Icons.volunteer_activism
                      : Icons.calendar_today,
                  size: 16,
                  color: slot['type'] == 'available'
                      ? Colors.blue.shade700
                      : Colors.blueGrey,
                ),
                const SizedBox(width: 6),
                Text(
                  _formatDateTime(slot['start']!),
                  style: TextStyle(
                    fontSize: 13,
                    color: slot['type'] == 'available'
                        ? Colors.blue.shade700
                        : Theme.of(context).colorScheme.tertiary,
                    fontStyle: slot['type'] == 'available'
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: slot['type'] == 'available'
                      ? Colors.blue.shade500
                      : Colors.blueGrey,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDateTime(slot['end']!),
                  style: TextStyle(
                    fontSize: 13,
                    color: slot['type'] == 'available'
                        ? Colors.blue.shade700
                        : Theme.of(context).colorScheme.tertiary,
                    fontStyle: slot['type'] == 'available'
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
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
    final rawSubshifts = await repo.getSubshifts();
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
    final allSubshifts = await repo.getSubshifts();

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
