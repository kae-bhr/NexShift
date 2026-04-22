import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/on_call_level_model.dart';
import 'package:nexshift_app/core/repositories/on_call_level_repository.dart';
import 'package:nexshift_app/core/repositories/truck_repository.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/trucks_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/crew_position_model.dart';
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
  List<({User user, Availability availability})> _availableAgents = []; // agents en disponibilité
  List<OnCallLevel> _onCallLevels = [];
  Map<String, int> _skillsCount = {};
  List<Truck> _stationTrucks = [];
  Map<String, CrewResult> _crewResults = {};
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
    final availabilities = await repo.getAvailabilities(stationId: _currentUser!.station);
    _allUsers = users;
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
    // Only include agents whose PlanningAgent window covers atUtc (start <= at < end).
    // Also include agents who were replaced at atUtc (their id appears as replacedAgentId
    // on a replacer entry that is active at atUtc) so replacements remain visible.
    var agents = planningExists
        ? () {
            final originalIds = <String>{};
            // Active base agents: window covers atUtc, not a replacer entry
            for (final a in maybePlanning.agents) {
              final aStart = a.start.toUtc();
              final aEnd = a.end.toUtc();
              final activeAtAt =
                  (aStart.isBefore(atUtc) || aStart.isAtSameMomentAs(atUtc)) &&
                  aEnd.isAfter(atUtc);
              if (activeAtAt && a.replacedAgentId == null) {
                originalIds.add(a.agentId);
              }
            }
            // Replaced agents: their replacer entry is active at atUtc
            for (final a in maybePlanning.agents) {
              if (a.replacedAgentId == null) continue;
              final aStart = a.start.toUtc();
              final aEnd = a.end.toUtc();
              final activeAtAt =
                  (aStart.isBefore(atUtc) || aStart.isAtSameMomentAs(atUtc)) &&
                  aEnd.isAfter(atUtc);
              if (activeAtAt) originalIds.add(a.replacedAgentId!);
            }
            return users.where((u) => originalIds.contains(u.id)).toList();
          }()
        : <User>[];

    // fallback: only if planning explicitly declares agents but repository
    // lookup failed to resolve them (avoid showing full team when agents is empty)
    if (planningExists && agents.isEmpty && maybePlanning.agents.isNotEmpty) {
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

    // Build effective crew directly from planning.agents (source of truth).
    // For each PlanningAgent entry active at atUtc:
    //   - replacedAgentId == null → base agent present at this time
    //   - replacedAgentId != null → replacer entry; the original is absent
    // Build a map replacedId→replacerId from active replacer entries, then
    // resolve the effective crew: for each base agent, use the replacer if one
    // exists, otherwise use the base agent itself.
    final List<User> effectiveAgents = [];
    final Map<String, String> activeReplacementMap = {}; // replacedId → replacerId

    if (planningExists) {
      for (final a in maybePlanning.agents) {
        if (a.replacedAgentId == null) continue; // only replacer entries
        final aStart = a.start.toUtc();
        final aEnd = a.end.toUtc();
        if ((aStart.isBefore(atUtc) || aStart.isAtSameMomentAs(atUtc)) &&
            aEnd.isAfter(atUtc)) {
          activeReplacementMap[a.replacedAgentId!] = a.agentId;
        }
      }
    }

    // agents already contains only the originals active at atUtc (built above)
    for (final agent in agents) {
      final replacerId = activeReplacementMap[agent.id];
      if (replacerId != null) {
        final replacer = users.firstWhere(
          (u) => u.id == replacerId,
          orElse: () => agent,
        );
        effectiveAgents.add(replacer);
      } else {
        effectiveAgents.add(agent);
      }
    }

    // Charger les niveaux d'astreinte/disponibilité (avant de construire availableAgents)
    final onCallLevels = await OnCallLevelRepository().getAll(chosenStation);
    final availabilityLevelIds = onCallLevels
        .where((l) => l.isAvailability)
        .map((l) => l.id)
        .toSet();

    // Retirer de la liste des astreintes les agents actifs à atUtc avec un niveau isAvailability
    if (planningExists && availabilityLevelIds.isNotEmpty) {
      final isAvailabilityAgentIds = maybePlanning.agents
          .where((a) {
            if (!availabilityLevelIds.contains(a.levelId)) return false;
            if (a.replacedAgentId != null) return false;
            final aStart = a.start.toUtc();
            final aEnd = a.end.toUtc();
            return (aStart.isBefore(atUtc) || aStart.isAtSameMomentAs(atUtc)) &&
                aEnd.isAfter(atUtc);
          })
          .map((a) => a.agentId)
          .toSet();
      agents = agents.where((u) => !isAvailabilityAgentIds.contains(u.id)).toList();
      effectiveAgents.removeWhere((u) => isAvailabilityAgentIds.contains(u.id));
    }

    // Find available agents at _at (agents with active availability slots)
    final List<({User user, Availability availability})> availableAgents = [];
    for (final availability in availabilities) {
      final start = availability.start.toUtc();
      final end = availability.end.toUtc();
      if ((start.isBefore(atUtc) || start.isAtSameMomentAs(atUtc)) &&
          end.isAfter(atUtc)) {
        final agent = users.where((u) => u.id == availability.agentId).firstOrNull;
        if (agent == null) continue;
        // Si l'agent a une disponibilité avec levelId (isAvailability), le retirer
        // de effectiveAgents et l'ajouter à availableAgents même s'il était déjà dedans
        final hasAvailLevel = availability.levelId != null &&
            availability.levelId!.isNotEmpty &&
            availabilityLevelIds.contains(availability.levelId);
        if (hasAvailLevel) {
          effectiveAgents.removeWhere((a) => a.id == agent.id);
          agents.removeWhere((a) => a.id == agent.id);
          if (!availableAgents.any((e) => e.user.id == agent.id)) {
            availableAgents.add((user: agent, availability: availability));
          }
        } else if (!effectiveAgents.any((a) => a.id == agent.id)) {
          availableAgents.add((user: agent, availability: availability));
        }
      }
    }

    // Inclure aussi les PlanningAgents dont le levelId pointe vers un niveau isAvailability
    if (planningExists) {
      final alreadyInAvailable = availableAgents.map((e) => e.user.id).toSet();
      for (final pa in maybePlanning.agents) {
        if (!availabilityLevelIds.contains(pa.levelId)) continue;
        final paStart = pa.start.toUtc();
        final paEnd = pa.end.toUtc();
        final activeAtAt =
            (paStart.isBefore(atUtc) || paStart.isAtSameMomentAs(atUtc)) &&
            paEnd.isAfter(atUtc);
        if (!activeAtAt) continue;
        if (effectiveAgents.any((a) => a.id == pa.agentId)) continue;
        if (alreadyInAvailable.contains(pa.agentId)) continue;
        final agent = users.where((u) => u.id == pa.agentId).firstOrNull;
        if (agent == null) continue;
        // Créer une Availability synthétique pour l'affichage
        final syntheticAvail = Availability(
          id: pa.agentId,
          agentId: pa.agentId,
          start: pa.start,
          end: pa.end,
          planningId: maybePlanning.id,
          levelId: pa.levelId,
        );
        availableAgents.add((user: agent, availability: syntheticAvail));
        alreadyInAvailable.add(pa.agentId);
      }
    }

    // Combine effective agents + available agents (planning.agents is already
    // fully represented via effectiveAgents above — no manualAgents needed)
    final allActiveAgents = [
      ...effectiveAgents,
      ...availableAgents.map((e) => e.user),
    ];

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
      _onCallLevels = onCallLevels;
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

  String _formatDate(DateTime dt) => DateFormat('dd/MM/yyyy').format(dt.toUtc());
  String _formatTime(DateTime dt) => DateFormat('HH:mm').format(dt.toUtc());

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

    // Ajouter les débuts et fins des entrées PlanningAgent (source de vérité)
    for (final p in _allPlannings) {
      for (final a in p.agents) {
        events.add(a.start);
        events.add(a.end);
      }
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

    // Build replacement map for UI display from planning.agents (source of truth).
    // Maps replacedId → replacerId for all replacer entries active at atUtc.
    final Map<String, String> activeReplacementByReplaced = {}; // replacedId → replacerId
    if (_currentPlanning != null) {
      for (final a in _currentPlanning!.agents) {
        if (a.replacedAgentId == null) continue;
        final aStart = a.start.toUtc();
        final aEnd = a.end.toUtc();
        if ((aStart.isBefore(atUtc) || aStart.isAtSameMomentAs(atUtc)) &&
            aEnd.isAfter(atUtc)) {
          activeReplacementByReplaced[a.replacedAgentId!] = a.agentId;
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _agents.map((a) {
                              final replacerId = activeReplacementByReplaced[a.id];
                              if (replacerId != null) {
                                final replacer = _findUserById(replacerId);
                                // Plage de présence de l'agent remplacé (entrée base)
                                final replacedEntry = _currentPlanning?.agents
                                    .where((pa) =>
                                        pa.agentId == a.id &&
                                        pa.replacedAgentId == null)
                                    .firstOrNull;
                                // Entrée du remplaçant active à atUtc
                                final replacerEntry = _currentPlanning?.agents
                                    .where((pa) =>
                                        pa.agentId == replacerId &&
                                        pa.replacedAgentId == a.id &&
                                        (pa.start.toUtc().isBefore(atUtc) ||
                                            pa.start.toUtc().isAtSameMomentAs(atUtc)) &&
                                        pa.end.toUtc().isAfter(atUtc))
                                    .firstOrNull;
                                // Niveau et couleur du remplaçant
                                final replacerRawLevelId = replacerEntry?.levelId;
                                final replacerEffectiveLevelId =
                                    replacerRawLevelId != null && replacerRawLevelId.isNotEmpty
                                        ? replacerRawLevelId
                                        : _onCallLevels
                                            .where((l) => !l.isAvailability)
                                            .map((l) => l.id)
                                            .firstOrNull;
                                final replacerLevel = replacerEffectiveLevelId != null
                                    ? _onCallLevels
                                        .where((l) => l.id == replacerEffectiveLevelId)
                                        .firstOrNull
                                    : null;
                                return _AgentReplacementRow(
                                  replaced: a,
                                  replacer: replacer,
                                  replacedStyle: _replacedNameStyle(context),
                                  replacedPresenceStart: replacedEntry?.start,
                                  replacedPresenceEnd: replacedEntry?.end,
                                  replacerLevelName: replacerLevel?.name,
                                  replacerLevelColor: replacerLevel?.color,
                                  replacerPresenceStart: replacerEntry?.start,
                                  replacerPresenceEnd: replacerEntry?.end,
                                );
                              }
                              final baseEntry = _currentPlanning?.agents
                                  .where((pa) =>
                                      pa.agentId == a.id &&
                                      pa.replacedAgentId == null &&
                                      (pa.start.toUtc().isBefore(atUtc) ||
                                          pa.start.toUtc().isAtSameMomentAs(atUtc)) &&
                                      pa.end.toUtc().isAfter(atUtc))
                                  .firstOrNull;
                              final rawLevelId = baseEntry?.levelId;
                              // Si levelId vide, fallback sur le premier niveau non-dispo
                              final effectiveLevelId =
                                  rawLevelId != null && rawLevelId.isNotEmpty
                                      ? rawLevelId
                                      : _onCallLevels
                                          .where((l) => !l.isAvailability)
                                          .map((l) => l.id)
                                          .firstOrNull;
                              final level = effectiveLevelId != null
                                  ? _onCallLevels
                                      .where((l) => l.id == effectiveLevelId)
                                      .firstOrNull
                                  : null;
                              return _AgentRow(
                                agent: a,
                                levelName: level?.name,
                                levelColor: level?.color,
                                presenceStart: baseEntry?.start,
                                presenceEnd: baseEntry?.end,
                              );
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _availableAgents
                                .map((e) {
                                  final level = _onCallLevels
                                      .where((l) => l.id == e.availability.levelId)
                                      .firstOrNull;
                                  return _AgentRow(
                                    agent: e.user,
                                    isAvailable: true,
                                    levelName: level?.name,
                                    levelColor: level?.color,
                                    presenceStart: e.availability.start,
                                    presenceEnd: e.availability.end,
                                  );
                                })
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
                    icon: Icons.verified_rounded,
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
        .where((e) => e.user.skills.contains(skill))
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
                    (e) => Container(
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
                              e.user.displayName,
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
  final String? levelName;
  final Color? levelColor;
  final DateTime? presenceStart;
  final DateTime? presenceEnd;

  const _AgentRow({
    required this.agent,
    this.isAvailable = false,
    this.levelName,
    this.levelColor,
    this.presenceStart,
    this.presenceEnd,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isAvailable
        ? (isDark ? Colors.blue.shade300 : Colors.blue.shade600)
        : (isDark ? Colors.grey.shade200 : Colors.grey.shade800);
    final badgeColor = isAvailable ? Colors.blue : (levelColor ?? Colors.grey);
    final hasSubline = presenceStart != null || levelName != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            agent.displayName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (hasSubline) ...[
            const SizedBox(height: 3),
            Wrap(
              spacing: 5,
              runSpacing: 3,
              children: [
                if (presenceStart != null && presenceEnd != null)
                  _PresencePill(start: presenceStart!, end: presenceEnd!),
                if (levelName != null)
                  _LevelBadge(
                      name: levelName!, color: badgeColor, isDark: isDark),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Ligne montrant un agent remplacé → remplaçant
class _AgentReplacementRow extends StatelessWidget {
  final User replaced;
  final User? replacer;
  final TextStyle replacedStyle;
  final DateTime? replacedPresenceStart;
  final DateTime? replacedPresenceEnd;
  final String? replacerLevelName;
  final Color? replacerLevelColor;
  final DateTime? replacerPresenceStart;
  final DateTime? replacerPresenceEnd;

  const _AgentReplacementRow({
    required this.replaced,
    required this.replacer,
    required this.replacedStyle,
    this.replacedPresenceStart,
    this.replacedPresenceEnd,
    this.replacerLevelName,
    this.replacerLevelColor,
    this.replacerPresenceStart,
    this.replacerPresenceEnd,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final arrowColor = isDark ? Colors.grey.shade500 : Colors.grey.shade400;
    final replacerNameColor =
        isDark ? Colors.grey.shade200 : Colors.grey.shade800;
    final badgeColor = replacerLevelColor ?? Colors.grey;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Remplacé ──────────────────────────────────────────
          Text(
            replaced.displayName,
            style: replacedStyle,
            overflow: TextOverflow.ellipsis,
          ),
          if (replacedPresenceStart != null && replacedPresenceEnd != null) ...[
            const SizedBox(height: 3),
            _PresencePill(
                start: replacedPresenceStart!, end: replacedPresenceEnd!),
          ],
          const SizedBox(height: 5),
          // ── Flèche + remplaçant ───────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ligne verticale + flèche
              Column(
                children: [
                  Icon(Icons.subdirectory_arrow_right_rounded,
                      size: 16, color: arrowColor),
                ],
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      replacer?.displayName ?? 'Inconnu',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: replacerNameColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (replacerPresenceStart != null ||
                        replacerLevelName != null) ...[
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 5,
                        runSpacing: 3,
                        children: [
                          if (replacerPresenceStart != null &&
                              replacerPresenceEnd != null)
                            _PresencePill(
                              start: replacerPresenceStart!,
                              end: replacerPresenceEnd!,
                            ),
                          if (replacerLevelName != null)
                            _LevelBadge(
                              name: replacerLevelName!,
                              color: badgeColor,
                              isDark: isDark,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Badge coloré affichant le nom d'un niveau d'astreinte
class _LevelBadge extends StatelessWidget {
  final String name;
  final Color color;
  final bool isDark;

  const _LevelBadge({
    required this.name,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Text(
        name,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color.withValues(alpha: isDark ? 0.85 : 0.9),
        ),
      ),
    );
  }
}

/// Petite capsule affichant la plage horaire de présence d'un agent
class _PresencePill extends StatelessWidget {
  final DateTime start;
  final DateTime end;

  const _PresencePill({required this.start, required this.end});

  String _fmt(DateTime dt, DateTime ref) {
    final local = dt.toLocal();
    final refLocal = ref.toLocal();
    final sameDay = local.year == refLocal.year &&
        local.month == refLocal.month &&
        local.day == refLocal.day;
    return sameDay
        ? DateFormat('HH:mm').format(local)
        : DateFormat('dd/MM HH:mm').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = '${_fmt(start, start)}–${_fmt(end, start)}';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
            letterSpacing: 0.1,
          ),
        ),
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
