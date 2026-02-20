import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/repositories/truck_repository.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/trucks_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/crew_position_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/data/models/availability_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/utils/default_vehicle_rules.dart';
import 'package:nexshift_app/core/repositories/vehicle_rules_repository.dart';
import 'package:nexshift_app/core/data/models/vehicle_rule_set_model.dart';
import 'package:nexshift_app/features/replacement/services/crew_allocator.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/features/replacement/presentation/pages/skill_search_page.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/features/planning/presentation/widgets/vehicle_detail_dialog.dart';
import 'package:nexshift_app/core/utils/subshift_normalizer.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';

class PlanningTeamDetailsPage extends StatefulWidget {
  final DateTime at;

  const PlanningTeamDetailsPage({super.key, required this.at});

  @override
  State<PlanningTeamDetailsPage> createState() =>
      _PlanningTeamDetailsPageState();
}

class _PlanningTeamDetailsPageState extends State<PlanningTeamDetailsPage> {
  bool _isLoading = true;
  List<User> _allUsers = [];
  List<User> _agents =
      []; // agents de la garde courante (vide si pas d'astreinte)
  List<User> _effectiveAgents =
      []; // agents effectifs avec remplacements appliqués
  List<User> _availableAgents = []; // agents en disponibilité
  Map<String, int> _skillsCount = {};
  List<Truck> _stationTrucks = [];
  Map<String, CrewResult> _crewResults = {};
  List<Subshift> _subshifts = [];
  List<Availability> _availabilities = [];
  DateTime _at = DateTime.now();
  Planning? _currentPlanning;
  Planning? _prevPlanning;
  Planning? _nextPlanning;
  String? _teamLabel;
  User? _currentUser; // L'utilisateur connecté
  List<Planning> _allPlannings = []; // Tous les plannings chargés
  // Cached rule sets for the current station, by vehicle type
  final Map<String, VehicleRuleSet> _ruleSetsByType = {};
  String? _stationName; // Nom de la station (déchiffré)

  @override
  void initState() {
    super.initState();
    _at = widget.at;
    _loadTeamDetails();
  }

  @override
  void didUpdateWidget(PlanningTeamDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recharger si le paramètre 'at' change
    if (widget.at != oldWidget.at) {
      _at = widget.at;
      _loadTeamDetails();
    }
  }

  Future<void> _loadTeamDetails() async {
    setState(() => _isLoading = true);
    final repo = LocalRepository();

    // Get currently logged in user first
    _currentUser = await UserStorageHelper.loadUser();
    if (_currentUser == null) {
      // Si aucun utilisateur n'est connecté, on ne peut pas continuer
      setState(() => _isLoading = false);
      return;
    }

    final users = await UserRepository().getByStation(_currentUser!.station);
    final subshifts = await repo.getSubshifts(stationId: _currentUser!.station);
    final availabilities = await repo.getAvailabilities();
    _allUsers = users;
    // Résoudre les cascades de remplacements pour toujours pointer vers l'agent original
    _subshifts = resolveReplacementCascades(subshifts);
    _availabilities = availabilities;

    // Find planning (garde) active at _at. Use UTC comparators with start <= at < end
    final atUtc = _at.toUtc();

    // Charger tous les plannings depuis le repository (utiliser une plage large)
    final startRange = _at.subtract(const Duration(days: 365));
    final endRange = _at.add(const Duration(days: 365));
    final allPlannings = await repo.getPlanningsByStationInRange(
      _currentUser!.station,
      startRange,
      endRange,
    );
    _allPlannings = allPlannings; // Stocker pour navigation

    Planning maybePlanning = Planning.empty();
    for (final p in allPlannings) {
      final s = p.startTime.toUtc();
      final e = p.endTime.toUtc();
      if ((s.isBefore(atUtc) || s.isAtSameMomentAs(atUtc)) &&
          e.isAfter(atUtc)) {
        maybePlanning = p;
        break;
      }
    }

    // Check if planning exists (empty Planning has empty id)
    final planningExists = maybePlanning.id.isNotEmpty;
    _currentPlanning = planningExists ? maybePlanning : null;

    // compute previous and next planning (for durations when outside a planning)
    allPlannings.sort((a, b) => a.startTime.compareTo(b.startTime));
    Planning? prev;
    Planning? next;
    for (final p in allPlannings) {
      if (p.endTime.toUtc().isBefore(atUtc) ||
          p.endTime.toUtc().isAtSameMomentAs(atUtc)) {
        prev = p;
      }
      if ((p.startTime.toUtc().isAfter(atUtc) ||
              p.startTime.toUtc().isAtSameMomentAs(atUtc)) &&
          next == null) {
        next = p;
      }
    }
    _prevPlanning = prev;
    _nextPlanning = next;

    // agents: if planning exists use its agents, otherwise show empty (no active garde)
    var agents = planningExists
        ? users.where((u) => maybePlanning.agentsId.contains(u.id)).toList()
        : <User>[];

    // fallback: only if planning explicitly declares agents but repository
    // lookup failed to resolve them (avoid showing full team when agentsId is empty)
    if (planningExists && agents.isEmpty && maybePlanning.agentsId.isNotEmpty) {
      agents = users.where((u) => u.team == maybePlanning.team).toList();
    }

    // choose station for vehicles: prefer active planning station, else previous, else next, else default
    final chosenStation = planningExists
        ? maybePlanning.station
        : (prev?.station ?? next?.station ?? KConstants.station);

    // always fetch trucks for chosen station so vehicles are visible even when no agents
    final trucks = await TruckRepository().getByStation(chosenStation);

    // Prefetch rule sets for all vehicle types at this station
    final rulesRepo = VehicleRulesRepository();
    final types = trucks.map((t) => t.type).toSet().toList();
    final fetched = await Future.wait(
      types.map((type) {
        return rulesRepo
            .getRules(vehicleType: type, stationId: chosenStation)
            .then((rs) => MapEntry(type, rs));
      }),
    );
    _ruleSetsByType
      ..clear()
      ..addEntries(
        fetched
            .where((e) => e.value != null)
            .map((e) => MapEntry(e.key, e.value!)),
      );

    // resolve team label via repository for UI
    String? teamLabel;
    if (planningExists) {
      try {
        final repo = TeamRepository();
        final team = await repo.getById(maybePlanning.team);
        teamLabel = team?.name ?? 'Équipe ${maybePlanning.team}';
      } catch (_) {
        teamLabel = 'Équipe ${maybePlanning.team}';
      }
    }

    // Build effective crew: apply active replacements
    // For each agent, if they are being replaced at _at, use the replacer instead
    final List<User> effectiveAgents = [];
    final Map<String, String> activeReplacementMap =
        {}; // replacedId -> replacerId

    // IMPORTANT: Utiliser _subshifts (après resolveReplacementCascades) pour être
    // cohérent avec le build() qui utilise aussi _subshifts
    for (final s in _subshifts) {
      final start = s.start.toUtc();
      final end = s.end.toUtc();
      if ((start.isBefore(atUtc) || start.isAtSameMomentAs(atUtc)) &&
          end.isAfter(atUtc)) {
        // Check if this replacement affects current planning
        final inAgents = agents.any((a) => a.id == s.replacedId);
        final inPlanning =
            planningExists && maybePlanning.agentsId.contains(s.replacedId);
        if (inAgents || inPlanning) {
          activeReplacementMap[s.replacedId] = s.replacerId;
        }
      }
    }

    // Build effective crew: swap replaced agents with replacers
    for (final agent in agents) {
      if (activeReplacementMap.containsKey(agent.id)) {
        final replacerId = activeReplacementMap[agent.id];
        final replacer = users.firstWhere(
          (u) => u.id == replacerId,
          orElse: () => agent, // fallback to original if replacer not found
        );
        effectiveAgents.add(replacer);
      } else {
        effectiveAgents.add(agent);
      }
    }

    // Find available agents at _at (agents with active availability slots)
    final List<User> availableAgents = [];
    for (final availability in availabilities) {
      final start = availability.start.toUtc();
      final end = availability.end.toUtc();
      // Check if availability is active at _at
      if ((start.isBefore(atUtc) || start.isAtSameMomentAs(atUtc)) &&
          end.isAfter(atUtc)) {
        final agent = users.firstWhereOrNull(
          (u) => u.id == availability.agentId,
        );
        if (agent != null && !effectiveAgents.any((a) => a.id == agent.id)) {
          // Only add if not already in effective agents (to avoid duplicates)
          availableAgents.add(agent);
        }
      }
    }

    // Intégrer les agents supplémentaires depuis planning.agents (source unique de vérité)
    final List<User> manualAgents = [];
    if (planningExists) {
      for (final entry in maybePlanning.agents) {
        final eStart = entry.start.toUtc();
        final eEnd = entry.end.toUtc();
        if ((eStart.isBefore(atUtc) || eStart.isAtSameMomentAs(atUtc)) &&
            eEnd.isAfter(atUtc)) {
          final alreadyCounted = effectiveAgents.any((a) => a.id == entry.agentId) ||
              availableAgents.any((a) => a.id == entry.agentId);
          if (!alreadyCounted) {
            final agent = users.firstWhereOrNull((u) => u.id == entry.agentId);
            if (agent != null) {
              manualAgents.add(agent);
            }
          }
        }
      }
    }

    // Combine effective agents + available agents + agents from planning.agents
    final allActiveAgents = [...effectiveAgents, ...availableAgents, ...manualAgents];

    // compute skill counts based on effective + available crew
    final Map<String, int> skillCount = {
      for (var skill in KSkills.listSkills) skill: 0,
    };

    for (final user in allActiveAgents) {
      for (final skill in user.skills) {
        if (skillCount.containsKey(skill)) {
          skillCount[skill] = (skillCount[skill] ?? 0) + 1;
        }
      }
    }

    // allocation for visible trucks (based on effective + available crew)
    final crewResults = await CrewAllocator.allocateAllVehicles(
      effectiveAgents: allActiveAgents,
      trucks: trucks,
      stationId: trucks.isNotEmpty ? trucks.first.station : '',
    );

    // Charger le nom de la station
    String? stationName;
    final sdisId = SDISContext().currentSDISId;
    if (sdisId != null) {
      stationName = await StationNameCache().getStationName(
        sdisId,
        chosenStation,
      );
    }

    setState(() {
      _agents = agents;
      _effectiveAgents = effectiveAgents;
      _availableAgents = availableAgents;
      _skillsCount = skillCount;
      _stationTrucks = trucks;
      _crewResults = crewResults;
      _teamLabel = teamLabel;
      _stationName = stationName;
      _isLoading = false;
    });
  }

  Color _statusToColor(VehicleStatus status) {
    switch (status) {
      case VehicleStatus.green:
        return KColors.strong;
      case VehicleStatus.orange:
        return KColors.medium;
      case VehicleStatus.red:
        return KColors.weak;
      case VehicleStatus.grey:
        return KColors.undefined;
    }
  }

  Color _getSkillColor(String skill) {
    final count = _skillsCount[skill] ?? 0;

    // Compter les besoins totaux et minimum pour cette compétence
    // en parcourant tous les véhicules disponibles et leurs modes
    int totalRequired =
        0; // Total de postes nécessitant cette compétence (tous modes)
    int minRequired = 9999; // Minimum pour armer au moins un mode d'un véhicule
    bool skillUsed = false;

    for (final truck in _stationTrucks) {
      // Utiliser les règles personnalisées si disponibles
      final ruleSet =
          _ruleSetsByType[truck.type] ??
          KDefaultVehicleRules.getDefaultRuleSet(truck.type);

      if (ruleSet == null) continue;

      // Déterminer les modes à considérer pour ce véhicule
      final List<String> modeIds;
      if (truck.modeId != null) {
        modeIds = [truck.modeId!];
      } else {
        modeIds = ruleSet.modes.map((m) => m.id).toList();
      }

      for (final modeId in modeIds) {
        final mode = ruleSet.getModeById(modeId);
        if (mode == null) continue;

        // Compter combien de postes obligatoires nécessitent cette compétence
        int positionsInMode = 0;
        for (final position in mode.mandatoryPositions) {
          if (position.requiredSkills.contains(skill)) {
            positionsInMode++;
            skillUsed = true;
          }
        }

        if (positionsInMode > 0) {
          totalRequired += positionsInMode;
          if (positionsInMode < minRequired) {
            minRequired = positionsInMode;
          }
        }
      }
    }

    // Si la compétence n'est utilisée nulle part
    if (!skillUsed) return Colors.grey;

    // VERT : On peut armer tous les véhicules dans tous leurs modes
    if (count >= totalRequired) return Colors.green;

    // ROUGE : Insuffisant même pour le mode le moins exigeant
    if (count < minRequired) return Colors.red;

    // ORANGE : Suffisant pour certains modes mais pas tous
    return Colors.orange;
  }

  Future<void> _pickAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(_at.year - 5),
      lastDate: DateTime(_at.year + 5),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (time == null) return;

    setState(() {
      _at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
    await _loadTeamDetails();
  }

  String _formatDate(DateTime dt) => DateFormat('dd/MM/yyyy').format(dt);
  String _formatTime(DateTime dt) => DateFormat('HH:mm').format(dt);

  TextStyle _replacedNameStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final color = Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    return base.copyWith(
      color: color,
      decoration: TextDecoration.lineThrough,
      decorationColor: color,
      decorationThickness: 1.5,
      decorationStyle: TextDecorationStyle.solid,
    );
  }

  /// Calcule tous les événements chronologiques (début/fin de plannings, subshifts et disponibilités)
  List<DateTime> _getAllEvents() {
    final events = <DateTime>[];

    // Ajouter les débuts et fins de plannings
    for (final p in _allPlannings) {
      events.add(p.startTime);
      events.add(p.endTime);
    }

    // Ajouter les débuts et fins de subshifts
    for (final s in _subshifts) {
      events.add(s.start);
      events.add(s.end);
    }

    // Ajouter les débuts et fins de disponibilités
    for (final a in _availabilities) {
      events.add(a.start);
      events.add(a.end);
    }

    // Trier chronologiquement
    events.sort();
    return events;
  }

  /// Returns true if the given replaced agent is covered by replacements
  /// over the entire current planning window (with a small tolerance).
  bool _isFullyReplacedForPlanning(String replacedId) {
    if (_currentPlanning == null) return false;

    final planStart = _currentPlanning!.startTime;
    final planEnd = _currentPlanning!.endTime;
    final totalDuration = planEnd.difference(planStart);
    if (totalDuration.isNegative || totalDuration == Duration.zero) {
      return false;
    }

    // Collect intervals for this replaced agent within the planning window
    final intervals = _subshifts
        .where(
          (s) =>
              s.planningId == _currentPlanning!.id &&
              s.replacedId == replacedId,
        )
        .map((s) {
          final start = s.start.isBefore(planStart) ? planStart : s.start;
          final end = s.end.isAfter(planEnd) ? planEnd : s.end;
          return end.isAfter(start) ? [start, end] : null;
        })
        .whereType<List<DateTime>>()
        .toList();

    if (intervals.isEmpty) return false;

    // Sort by start and merge overlaps to compute union coverage
    intervals.sort((a, b) => a[0].compareTo(b[0]));
    DateTime curStart = intervals.first[0];
    DateTime curEnd = intervals.first[1];
    var covered = Duration.zero;

    for (var i = 1; i < intervals.length; i++) {
      final s = intervals[i][0];
      final e = intervals[i][1];
      if (s.isAfter(curEnd)) {
        // disjoint interval: accumulate previous and start a new one
        covered += curEnd.difference(curStart);
        curStart = s;
        curEnd = e;
      } else {
        // overlapping: extend if needed
        if (e.isAfter(curEnd)) curEnd = e;
      }
    }
    // accumulate last interval
    covered += curEnd.difference(curStart);

    const tolerance = Duration(minutes: 1);
    return covered >= totalDuration - tolerance;
  }

  /// Navigue vers l'événement précédent
  void _goToPreviousEvent() {
    final events = _getAllEvents();
    final atUtc = _at.toUtc();

    // Chercher le premier événement strictement avant _at
    DateTime? previousEvent;
    for (final event in events.reversed) {
      if (event.toUtc().isBefore(atUtc)) {
        previousEvent = event;
        break;
      }
    }

    if (previousEvent != null) {
      setState(() {
        _at = previousEvent!.toLocal();
      });
      _loadTeamDetails();
    }
  }

  /// Navigue vers l'événement suivant
  void _goToNextEvent() {
    final events = _getAllEvents();
    final atUtc = _at.toUtc();

    // Chercher le premier événement strictement après _at
    DateTime? nextEvent;
    for (final event in events) {
      if (event.toUtc().isAfter(atUtc)) {
        nextEvent = event;
        break;
      }
    }

    if (nextEvent != null) {
      setState(() {
        _at = nextEvent!.toLocal();
      });
      _loadTeamDetails();
    }
  }

  void _openSkillRequestSearch(String skill) async {
    // Attendre le retour de la page et recharger les données
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SkillSearchPage(
          planning: _currentPlanning!,
          preselectedSkills: [skill],
        ),
      ),
    );
    // Recharger les données après le retour
    _loadTeamDetails();
  }

  @override
  Widget build(BuildContext context) {
    final stationLabel =
        _stationName ?? _currentPlanning?.station ?? KConstants.station;
    final teamLabel = _currentPlanning != null
        ? (_teamLabel ?? "Équipe ${_currentPlanning!.team}")
        : "Aucune astreinte";

    // Calculer si des événements précédents/suivants existent
    final events = _getAllEvents();
    final atUtc = _at.toUtc();
    final hasPreviousEvent = events.any((e) => e.toUtc().isBefore(atUtc));
    final hasNextEvent = events.any((e) => e.toUtc().isAfter(atUtc));

    // find replacements active at _at for agents in current garde
    final Map<String, Subshift> activeReplacementByReplaced = {};
    for (final s in _subshifts) {
      final start = s.start.toUtc();
      final end = s.end.toUtc();
      // consider subshift active when start <= at < end
      if ((start.isBefore(atUtc) || start.isAtSameMomentAs(atUtc)) &&
          end.isAfter(atUtc)) {
        final replacedId = s.replacedId;
        final inAgents = _agents.any((a) => a.id == replacedId);
        final inPlanning =
            _currentPlanning != null &&
            _currentPlanning!.agentsId.contains(replacedId);
        if (inAgents || inPlanning) {
          activeReplacementByReplaced[s.replacedId] = s;
        }
      }
    }

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Vue opérationnelle',
        bottomColor: KColors.appNameColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Bandeau navigation temporelle ───────────────────────
                _TimeNavBand(
                  at: _at,
                  hasPrevious: hasPreviousEvent,
                  hasNext: hasNextEvent,
                  onPrevious: _goToPreviousEvent,
                  onNext: _goToNextEvent,
                  onPickAt: _pickAt,
                  formatDate: _formatDate,
                  formatTime: _formatTime,
                ),
                // ── Contenu scrollable ───────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Info card planning ────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _PlanningInfoCard(
                      stationLabel: stationLabel,
                      teamLabel: teamLabel,
                      planning: _currentPlanning,
                      prevPlanning: _prevPlanning,
                      nextPlanning: _nextPlanning,
                      at: _at,
                      formatDate: _formatDate,
                      formatTime: _formatTime,
                      formatDuration: _formatDuration,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Agents en astreinte ─────────────────────────────────
                  _OperationalSection(
                    icon: Icons.shield_rounded,
                    title: 'Agents en astreinte',
                    count: _agents.length,
                    emptyMessage: 'Aucun agent en astreinte pour cet horaire.',
                    child: _agents.isEmpty
                        ? null
                        : Column(
                            children: _agents.map((a) {
                              final active = activeReplacementByReplaced[a.id];
                              if (active != null) {
                                final replacer = _findUserById(active.replacerId);
                                final isFullyReplaced =
                                    _isFullyReplacedForPlanning(a.id);
                                return _AgentReplacementRow(
                                  replaced: a,
                                  replacer: replacer,
                                  isFullyReplaced: isFullyReplaced,
                                  replacedStyle: _replacedNameStyle(context),
                                );
                              }
                              return _AgentRow(agent: a);
                            }).toList(),
                          ),
                  ),

                  const SizedBox(height: 12),

                  // ── Agents en disponibilité ─────────────────────────────
                  _OperationalSection(
                    icon: Icons.volunteer_activism_rounded,
                    title: 'Agents en disponibilité',
                    count: _availableAgents.length,
                    emptyMessage: 'Aucun agent en disponibilité.',
                    child: _availableAgents.isEmpty
                        ? null
                        : Column(
                            children: _availableAgents
                                .map((a) => _AgentRow(
                                      agent: a,
                                      isAvailable: true,
                                    ))
                                .toList(),
                          ),
                  ),

                  const SizedBox(height: 12),

                  // ── Véhicules ───────────────────────────────────────────
                  _OperationalSection(
                    icon: Icons.local_fire_department_rounded,
                    title: 'Véhicules',
                    count: null,
                    emptyMessage: 'Aucun véhicule configuré.',
                    child: _stationTrucks.isEmpty
                        ? null
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: () {
                              final sortedTrucks = _stationTrucks.toList()
                                ..sort((a, b) {
                                  final pA = KTrucks.vehicleTypePriority[a.type] ?? 999;
                                  final pB = KTrucks.vehicleTypePriority[b.type] ?? 999;
                                  if (pA != pB) return pA.compareTo(pB);
                                  return a.id.compareTo(b.id);
                                });
                              return [
                                for (final truck in sortedTrucks)
                                  ..._buildVehicleWidgets(truck),
                              ];
                            }(),
                          ),
                  ),

                  const SizedBox(height: 12),

                  // ── Compétences ─────────────────────────────────────────
                  _OperationalSection(
                    icon: Icons.workspace_premium_rounded,
                    title: 'Compétences',
                    count: null,
                    emptyMessage: '',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: KSkills.listSkills.map((skill) {
                        final color = _getSkillColor(skill);
                        final count = _skillsCount[skill] ?? 0;
                        return GestureDetector(
                          onTap: () => _showSkillDialog(context, skill),
                          child: _buildSkillBox(context, skill, count, 0, color),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  User? _findUserById(String? id) {
    if (id == null) return null;
    try {
      return _allUsers.firstWhere((u) => u.id == id);
    } catch (_) {
      return null;
    }
  }

  Widget _buildSkillBox(
    BuildContext context,
    String label,
    int count,
    int requiredCount,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (count >= 0) ...[
            const Text(" : "),
            Text("$count", style: TextStyle(color: color)),
          ],
        ],
      ),
    );
  }

  void _showSkillDialog(BuildContext context, String skill) {
    // Séparer les agents d'astreinte et les agents en disponibilité
    final onCallAgents = _effectiveAgents
        .where((a) => a.skills.contains(skill))
        .toList();

    final availableAgents = _availableAgents
        .where((a) => a.skills.contains(skill))
        .toList();

    final totalCount = onCallAgents.length + availableAgents.length;
    final color = _getSkillColor(skill);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: BackButton(onPressed: () => Navigator.pop(context)),
          title: Text(skill, style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badge de statut avec compteur
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        totalCount > 0 ? Icons.person : Icons.person_off,
                        color: color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          totalCount > 0
                              ? "$totalCount agent${totalCount > 1 ? 's' : ''} (${onCallAgents.length} astreinte${onCallAgents.length > 1 ? 's' : ''}, ${availableAgents.length} dispo)"
                              : "Aucun agent disponible",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Agents d'astreinte
                if (onCallAgents.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    "Agents d'astreinte :",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  ...onCallAgents.map(
                    (a) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.person,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              a.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                // Agents en disponibilité
                if (availableAgents.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    "Agents en disponibilité :",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  ...availableAgents.map(
                    (a) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.volunteer_activism,
                              size: 16,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              a.displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: Colors.blue.shade700,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // Bouton d'action - visible uniquement si l'utilisateur a les droits
                if (_currentUser != null &&
                    (_currentUser!.admin ||
                        (_currentUser!.status == KConstants.statusChief &&
                            _currentUser!.team == _currentPlanning?.team) ||
                        _currentUser!.status == KConstants.statusLeader))
                  FilledButton.icon(
                    onPressed: () => _openSkillRequestSearch(skill),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                    ),
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    label: const Text("Demander une compétence"),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildVehicleWidgets(Truck truck) {
    final widgets = <Widget>[];

    // Prefer station-specific rules if cached, else fall back to defaults
    final ruleSet =
        _ruleSetsByType[truck.type] ??
        KDefaultVehicleRules.getDefaultRuleSet(truck.type);

    if (ruleSet == null) {
      // Fallback: no rules defined, show just the truck name
      final result = _crewResults[truck.displayName];
      final color = _statusToColor(result?.status ?? VehicleStatus.red);
      widgets.add(
        GestureDetector(
          onTap: () => _showTruckDialog(context, truck),
          child: _buildSkillBox(context, truck.displayName, -1, -1, color),
        ),
      );
      return widgets;
    }

    // Get the modes to display (either truck's specific mode or all modes)
    final List<String> modeIds;
    if (truck.modeId != null) {
      // Truck has a specific mode configured
      modeIds = [truck.modeId!];
    } else {
      // No specific mode: show all modes
      modeIds = ruleSet.modes.map((m) => m.id).toList();
    }

    // Add a widget for each mode
    for (final modeId in modeIds) {
      final mode = ruleSet.getModeById(modeId);
      if (mode == null) continue;

      // Build the key for this mode
      final key = mode.displaySuffix.isNotEmpty
          ? '${truck.displayName}_${mode.displaySuffix}'
          : truck.displayName;

      final result = _crewResults[key];
      final color = _statusToColor(result?.status ?? VehicleStatus.red);

      widgets.add(
        GestureDetector(
          onTap: () => _showVehicleModeDialog(context, truck, mode.id, key),
          child: _buildSkillBox(context, key, -1, -1, color),
        ),
      );
    }

    return widgets;
  }

  void _showVehicleModeDialog(
    BuildContext context,
    Truck truck,
    String modeId,
    String displayKey,
  ) {
    final crewResult = _crewResults[displayKey];
    if (crewResult == null) return;

    // Extract mode label from key if it contains an underscore
    final String? fptMode = displayKey.contains('_')
        ? displayKey.split('_').last
        : null;

    showVehicleDetailDialog(
      context: context,
      truck: truck,
      crewResult: crewResult,
      fptMode: fptMode,
      currentUser: _currentUser,
      currentPlanning: _currentPlanning,
      onReplacementSearch: _openReplacementSearch,
    );
  }

  void _showTruckDialog(BuildContext context, Truck truck) {
    // Try to find the crew result with the correct key
    // First try exact match, then try with any suffix
    CrewResult? crewResult = _crewResults[truck.displayName];

    if (crewResult == null) {
      // Look for keys starting with truck.displayName followed by underscore
      final matchingKey = _crewResults.keys.firstWhere(
        (key) => key.startsWith('${truck.displayName}_'),
        orElse: () => '',
      );
      if (matchingKey.isNotEmpty) {
        crewResult = _crewResults[matchingKey];
      }
    }

    if (crewResult == null) return;

    showVehicleDetailDialog(
      context: context,
      truck: truck,
      crewResult: crewResult,
      currentUser: _currentUser,
      currentPlanning: _currentPlanning,
      onReplacementSearch: _openReplacementSearch,
    );
  }

  void _openReplacementSearch(Truck truck, CrewPosition position) async {
    // Attendre le retour de la page et recharger les données
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SkillSearchPage(
          planning: _currentPlanning!,
          preselectedSkills: position.requiredSkills,
        ),
      ),
    );
    // Recharger les données après le retour
    _loadTeamDetails();
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) d = d.abs();
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    if (days > 0) return '${days}j ${hours}h ${minutes}m';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

// ── Widgets locaux ────────────────────────────────────────────────────────────

/// En-tête de section avec icône, titre et compteur optionnel
/// Bandeau de navigation temporelle (précédent / date+heure / suivant)
class _TimeNavBand extends StatelessWidget {
  final DateTime at;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPickAt;
  final String Function(DateTime) formatDate;
  final String Function(DateTime) formatTime;

  const _TimeNavBand({
    required this.at,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
    required this.onPickAt,
    required this.formatDate,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = KColors.appNameColor;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.shade200,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // Bouton précédent
          IconButton(
            iconSize: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: hasPrevious ? onPrevious : null,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: hasPrevious
                  ? primary
                  : primary.withValues(alpha: 0.3),
            ),
            tooltip: 'Évènement précédent',
          ),
          // Bouton date/heure centré
          Expanded(
            child: GestureDetector(
              onTap: onPickAt,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: isDark ? 0.14 : 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: primary.withValues(alpha: isDark ? 0.28 : 0.20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time_rounded, size: 14, color: primary),
                    const SizedBox(width: 6),
                    Text(
                      formatDate(at),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 1,
                      height: 14,
                      color: primary.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatTime(at),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bouton suivant
          IconButton(
            iconSize: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: hasNext ? onNext : null,
            icon: Icon(
              Icons.chevron_right_rounded,
              color: hasNext
                  ? primary
                  : primary.withValues(alpha: 0.3),
            ),
            tooltip: 'Évènement suivant',
          ),
        ],
      ),
    );
  }
}

class _OperationalSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final int? count;
  final String emptyMessage;
  final Widget? child;

  const _OperationalSection({
    required this.icon,
    required this.title,
    required this.count,
    required this.emptyMessage,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              if (count != null && count! > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.grey.shade300 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // Content container
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.shade200,
              ),
            ),
            child: child ??
                Text(
                  emptyMessage,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

/// Ligne d'un agent normal ou en disponibilité
class _AgentRow extends StatelessWidget {
  final User agent;
  final bool isAvailable;

  const _AgentRow({required this.agent, this.isAvailable = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isAvailable
        ? (isDark ? Colors.blue.shade300 : Colors.blue.shade600)
        : (isDark ? Colors.grey.shade200 : Colors.grey.shade800);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          // Avatar initiale
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isAvailable
                  ? Colors.blue.withValues(alpha: isDark ? 0.20 : 0.10)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey.shade100),
              shape: BoxShape.circle,
              border: isAvailable
                  ? Border.all(
                      color: Colors.blue.withValues(alpha: 0.35), width: 1)
                  : null,
            ),
            child: Center(
              child: Text(
                agent.displayName.isNotEmpty
                    ? agent.displayName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              agent.displayName,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isAvailable ? FontWeight.w400 : FontWeight.w500,
                color: color,
                fontStyle: isAvailable ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          if (isAvailable)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: isDark ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.3), width: 1),
              ),
              child: Text(
                'dispo',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.blue.shade300 : Colors.blue.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ligne montrant un agent remplacé → remplaçant
class _AgentReplacementRow extends StatelessWidget {
  final User replaced;
  final User? replacer;
  final bool isFullyReplaced;
  final TextStyle replacedStyle;

  const _AgentReplacementRow({
    required this.replaced,
    required this.replacer,
    required this.isFullyReplaced,
    required this.replacedStyle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final arrowColor =
        isFullyReplaced ? Colors.red.shade400 : Colors.orange.shade400;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          // Remplacé (barré)
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                replaced.displayName.isNotEmpty
                    ? replaced.displayName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              replaced.displayName,
              style: replacedStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward_rounded, size: 16, color: arrowColor),
          const SizedBox(width: 6),
          // Remplaçant
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: arrowColor.withValues(alpha: isDark ? 0.20 : 0.10),
              shape: BoxShape.circle,
              border: Border.all(color: arrowColor.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                replacer != null && replacer!.displayName.isNotEmpty
                    ? replacer!.displayName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: arrowColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              replacer?.displayName ?? 'Inconnu',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey.shade200 : Colors.grey.shade800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Card info du planning en cours
class _PlanningInfoCard extends StatelessWidget {
  final String stationLabel;
  final String teamLabel;
  final Planning? planning;
  final Planning? prevPlanning;
  final Planning? nextPlanning;
  final DateTime at;
  final String Function(DateTime) formatDate;
  final String Function(DateTime) formatTime;
  final String Function(Duration) formatDuration;

  const _PlanningInfoCard({
    required this.stationLabel,
    required this.teamLabel,
    required this.planning,
    required this.prevPlanning,
    required this.nextPlanning,
    required this.at,
    required this.formatDate,
    required this.formatTime,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = KColors.appNameColor;
    final hasPlanning = planning != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary.withValues(alpha: isDark ? 0.14 : 0.08),
            primary.withValues(alpha: isDark ? 0.07 : 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primary.withValues(alpha: isDark ? 0.28 : 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Station
          Row(
            children: [
              Icon(Icons.location_on_rounded, size: 16, color: primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  stationLabel,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
              ),
              if (hasPlanning)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    teamLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasPlanning) ...[
            // Plage horaire
            Row(
              children: [
                Icon(
                  Icons.play_circle_outline_rounded,
                  size: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  '${formatDate(planning!.startTime)}  ${formatTime(planning!.startTime)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.stop_circle_outlined,
                  size: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  '${formatDate(planning!.endTime)}  ${formatTime(planning!.endTime)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Text(
                  'Aucune astreinte active',
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
            // Durées depuis/jusqu'à
            if (prevPlanning != null || nextPlanning != null) ...[
              const SizedBox(height: 8),
              if (prevPlanning != null)
                _DurationRow(
                  icon: Icons.history_rounded,
                  label: 'Depuis fin astreinte',
                  value: formatDuration(
                    Duration(
                      milliseconds: at
                          .toUtc()
                          .difference(prevPlanning!.endTime.toUtc())
                          .inMilliseconds,
                    ),
                  ),
                ),
              if (nextPlanning != null)
                _DurationRow(
                  icon: Icons.update_rounded,
                  label: "Jusqu'à prochaine",
                  value: formatDuration(
                    Duration(
                      milliseconds: nextPlanning!.startTime
                          .toUtc()
                          .difference(at.toUtc())
                          .inMilliseconds,
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DurationRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DurationRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon,
              size: 13,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade500),
          const SizedBox(width: 5),
          Text(
            '$label : ',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
