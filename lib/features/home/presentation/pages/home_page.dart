import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/trucks_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/data/models/availability_model.dart';
import 'package:nexshift_app/features/planning/presentation/widgets/planning_card_widget.dart';
import 'package:nexshift_app/core/repositories/truck_repository.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/features/replacement/services/crew_allocator.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/repositories/vehicle_rules_repository.dart';
import 'package:nexshift_app/core/utils/default_vehicle_rules.dart';
import 'package:nexshift_app/core/data/models/vehicle_rule_set_model.dart';
import 'package:nexshift_app/core/data/models/crew_mode_model.dart';
import 'package:nexshift_app/features/replacement/presentation/pages/replacement_page.dart';
import 'package:nexshift_app/features/subshift/presentation/widgets/subshift_item.dart';
import 'package:nexshift_app/features/planning/presentation/widgets/planning_header_widget.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoading = true;
  late User _user;
  String? _lastUserId; // to avoid reload loops on same user
  List<User> _allUsers = [];
  List<Planning> _allPlannings = [];
  List<Subshift> _allSubshifts = [];
  List<Availability> _allAvailabilities = [];
  final Map<String, bool> _expanded = {};
  DateTime _currentWeekStart = _getStartOfWeek(DateTime.now());
  Color? _userTeamColor;

  final noneUser = User(
    id: "",
    firstName: "Inconnu",
    lastName: "",
    station: "",
    status: "",
    team: "",
    skills: [],
  );

  static DateTime _getStartOfWeek(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    // Normalize to 00:00 for deterministic week boundaries
    return DateTime(monday.year, monday.month, monday.day, 0, 0, 0);
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    stationViewNotifier.addListener(_onStationViewChanged);
    // Reload when the connected user changes
    userNotifier.addListener(_onUserChanged);
  }

  @override
  void dispose() {
    stationViewNotifier.removeListener(_onStationViewChanged);
    userNotifier.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onStationViewChanged() {
    // reload data when the global station/personnel toggle changes
    _loadData();
  }

  void _onUserChanged() {
    final u = userNotifier.value;
    // Only reload if the user actually changed
    if (u == null) return;
    if (_lastUserId == u.id && !_isLoading) return;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Prefer the notifier to avoid re-setting it during loadUser, which can
    // cause a reload loop. Fallback to storage only if not available.
    final user = userNotifier.value ?? await UserStorageHelper.loadUser();
    if (user != null) {
      final repo = LocalRepository();
      // Charger les plannings de la semaine courante (on filtrera ensuite côté client)
      final weekEnd = _currentWeekStart.add(const Duration(days: 7));

      final allPlannings = await repo.getAllPlanningsInRange(
        _currentWeekStart,
        weekEnd,
      );

      final allUsers = await repo.getAllUsers();
      final shifts = await SubshiftRepository().getAll();
      final availabilities = await repo.getAvailabilities();

      // Charger la couleur de l'équipe de l'utilisateur
      Color? teamColor;
      try {
        final team = await TeamRepository().getById(user.team);
        teamColor = team?.color;
      } catch (_) {
        teamColor = null;
      }

      if (!mounted) return;
      setState(() {
        _allPlannings = allPlannings;
        _allSubshifts = shifts;
        _allAvailabilities = availabilities;
        _allUsers = allUsers;
        _user = user;
        _userTeamColor = teamColor;
        _lastUserId = user.id;
        _isLoading = false;
      });
    }
  }

  void _onWeekChanged(DateTime newWeekStart) {
    setState(() {
      _currentWeekStart = newWeekStart;
    });
    // Recharger uniquement les plannings pour la semaine sélectionnée
    _reloadPlanningsForWeek(newWeekStart);
  }

  Future<void> _reloadPlanningsForWeek(DateTime weekStart) async {
    final repo = LocalRepository();
    // Normalize incoming weekStart to 00:00
    final normalizedStart = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
      0,
      0,
      0,
    );
    final weekEnd = normalizedStart.add(const Duration(days: 7));
    final plannings = await repo.getAllPlanningsInRange(
      normalizedStart,
      weekEnd,
    );
    final availabilities = await repo.getAvailabilities();
    if (!mounted) return;
    setState(() {
      _allPlannings = plannings;
      _allAvailabilities = availabilities;
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

  Future<List<Map<String, dynamic>>> _buildVehicleIconSpecs(
    Planning planning,
    List<Subshift> subList,
  ) async {
    final trucks = await TruckRepository().getByStation(planning.station);
    if (trucks.isEmpty) return [];

    // Base crew from planning
    final baseAgents = _allUsers
        .where((u) => planning.agentsId.contains(u.id))
        .toList();

    VehicleStatus worst(VehicleStatus a, VehicleStatus b) {
      int s(VehicleStatus x) => x == VehicleStatus.red
          ? 2
          : x == VehicleStatus.orange
          ? 1
          : 0;
      return s(a) >= s(b) ? a : b;
    }

    // Build list of critical time points to evaluate:
    // - Planning start and end
    // - Start and end of each subshift
    final criticalTimes = <DateTime>{
      planning.startTime,
      planning.endTime.subtract(const Duration(seconds: 1)),
    };

    for (final s in subList) {
      criticalTimes.add(s.start);
      criticalTimes.add(s.end.subtract(const Duration(seconds: 1)));
    }

    final samplePoints = criticalTimes.toList()..sort();

    final specs = <Map<String, dynamic>>[];
    // Track time ranges per vehicle: Map<vehicleKey, List<{start, end, status}>>
    final Map<String, List<Map<String, dynamic>>> timeRangesByVehicle = {};

    // We need to allocate vehicles sequentially like PlanningTeamDetailsPage does,
    // not independently. Each vehicle consumes agents from a shared pool per type.
    for (int i = 0; i < samplePoints.length; i++) {
      final sampleTime = samplePoints[i];
      final sampleUtc = sampleTime.toUtc();

      // Determine the end time for this range (start of next sample or planning end)
      // Skip ranges that are too short (< 2 minutes) - these are artifacts from end-1s points
      final rangeEnd = i < samplePoints.length - 1
          ? samplePoints[i + 1]
          : planning.endTime;

      // Skip if range is too short (less than 2 minutes)
      if (rangeEnd.difference(sampleTime).inMinutes < 2) {
        continue;
      }

      // Build effective crew at this time point
      final effectiveAgents = List<User>.from(baseAgents);

      // Apply active replacements at this specific time
      for (final s in subList) {
        final start = s.start.toUtc();
        final end = s.end.toUtc();
        if ((start.isBefore(sampleUtc) || start.isAtSameMomentAs(sampleUtc)) &&
            end.isAfter(sampleUtc)) {
          final idx = effectiveAgents.indexWhere((u) => u.id == s.replacedId);
          if (idx != -1) {
            final replacer = _allUsers.firstWhere(
              (u) => u.id == s.replacerId,
              orElse: () => effectiveAgents[idx],
            );
            effectiveAgents[idx] = replacer;
          }
        }
      }

      // Add agents in availability at this specific time (if they match the planning)
      for (final availability in _allAvailabilities) {
        // Check if availability matches this planning
        if (availability.planningId != planning.id) continue;

        final availStart = availability.start.toUtc();
        final availEnd = availability.end.toUtc();

        // Check if availability is active at this time point
        if ((availStart.isBefore(sampleUtc) || availStart.isAtSameMomentAs(sampleUtc)) &&
            availEnd.isAfter(sampleUtc)) {
          // Add the available agent if not already in the crew
          final agentId = availability.agentId;
          if (!effectiveAgents.any((u) => u.id == agentId)) {
            final availableAgent = _allUsers.firstWhere(
              (u) => u.id == agentId,
              orElse: () => noneUser,
            );
            if (availableAgent.id.isNotEmpty) {
              effectiveAgents.add(availableAgent);
            }
          }
        }
      }

      // Build agent pools per vehicle type (like PlanningTeamDetailsPage)
      final Map<String, List<User>> poolsByType = {};
      for (final truckType in KTrucks.vehicleTypeOrder) {
        poolsByType[truckType] = List<User>.from(effectiveAgents);
      }

      // Separate FPT from other trucks
      final fptTrucks = trucks.where((t) => t.type == KTrucks.fpt).toList();
      final otherTrucks = trucks.where((t) => t.type != KTrucks.fpt).toList();

      // Prefetch rule sets for all truck types present (station-specific first)
      final rulesRepo = VehicleRulesRepository();
      final types = trucks.map((t) => t.type).toSet().toList();
      final fetched = await Future.wait(
        types.map((type) async {
          final rs = await rulesRepo.getRules(
            vehicleType: type,
            stationId: planning.station,
          );
          return MapEntry(
            type,
            rs ?? KDefaultVehicleRules.getDefaultRuleSet(type),
          );
        }),
      );
      final Map<String, VehicleRuleSet?> ruleSets = {
        for (final e in fetched) e.key: e.value,
      };

      // Allocate standard trucks (non-FPT) with per-mode handling, sharing crew between modes of the SAME truck
      for (final truck in otherTrucks) {
        final pool = poolsByType[truck.type]!;
        final ruleSet = ruleSets[truck.type];
        if (ruleSet == null) continue;

        // Determine modes to evaluate for this truck
        final List<CrewMode> modes;
        if (truck.modeId != null) {
          final m = ruleSet.getModeById(truck.modeId!);
          modes = m != null ? [m] : [];
        } else {
          modes = List<CrewMode>.from(ruleSet.modes);
        }

        // Keep track of used agents across all modes for this truck
        final allUsedIds = <String>{};

        for (final mode in modes) {
          // Snapshot pool so modes of the same truck can reuse agents
          final thisModePool = List<User>.from(pool);
          final r = await CrewAllocator.allocateVehicleCrew(
            agents: thisModePool,
            truck: Truck(
              id: truck.id,
              displayNumber: truck.displayNumber,
              type: truck.type,
              station: truck.station,
              modeId: mode.id,
            ),
            stationId: planning.station,
          );

          // Collect used agents for removal after all modes processed
          for (final used in r.crew) {
            allUsedIds.add(used.id);
          }

          final displayKeySuffix = mode.displaySuffix.isNotEmpty
              ? mode.displaySuffix
              : 'DEF';
          final vehicleKey = '${truck.type}_${truck.id}_$displayKeySuffix';

          if (r.status == VehicleStatus.orange ||
              r.status == VehicleStatus.red) {
            timeRangesByVehicle.putIfAbsent(vehicleKey, () => []);
            timeRangesByVehicle[vehicleKey]!.add({
              'start': sampleTime,
              'end': rangeEnd,
              'status': r.status,
            });
          }

          // Find existing spec (by type, id, and period suffix)
          final existingIndex = specs.indexWhere(
            (s) =>
                s['type'] == truck.type &&
                s['id'] == truck.id &&
                s['period'] ==
                    (mode.displaySuffix.isNotEmpty ? mode.displaySuffix : null),
          );

          if (existingIndex != -1) {
            final currentStatusColor = specs[existingIndex]['color'];
            final currentStatus =
                currentStatusColor == _statusToColor(VehicleStatus.red)
                ? VehicleStatus.red
                : currentStatusColor == _statusToColor(VehicleStatus.orange)
                ? VehicleStatus.orange
                : VehicleStatus.green;
            final newWorst = worst(currentStatus, r.status);
            specs[existingIndex]['color'] = _statusToColor(newWorst);
          } else if (r.status == VehicleStatus.orange ||
              r.status == VehicleStatus.red) {
            specs.add({
              'type': truck.type,
              'id': truck.id,
              'displayNumber': truck.displayNumber,
              'period': mode.displaySuffix.isNotEmpty
                  ? mode.displaySuffix
                  : null,
              'color': _statusToColor(r.status),
              'vehicleKey': vehicleKey,
            });
          }
        }

        // After evaluating all modes for this truck, remove used agents once
        pool.removeWhere((a) => allUsedIds.contains(a.id));
      }

      // Allocate FPT trucks using the same generic multi-mode handling
      for (final truck in fptTrucks) {
        final pool = poolsByType[truck.type]!;
        final ruleSet = ruleSets[truck.type];
        if (ruleSet == null) continue;

        // Determine modes to evaluate for this truck
        final List<CrewMode> modes;
        if (truck.modeId != null) {
          final m = ruleSet.getModeById(truck.modeId!);
          modes = m != null ? [m] : [];
        } else {
          modes = List<CrewMode>.from(ruleSet.modes);
        }

        final allUsedIds = <String>{};

        for (final mode in modes) {
          final thisModePool = List<User>.from(pool);
          final r = await CrewAllocator.allocateVehicleCrew(
            agents: thisModePool,
            truck: Truck(
              id: truck.id,
              displayNumber: truck.displayNumber,
              type: truck.type,
              station: truck.station,
              modeId: mode.id,
            ),
            stationId: planning.station,
          );

          for (final used in r.crew) {
            allUsedIds.add(used.id);
          }

          final displayKeySuffix = mode.displaySuffix.isNotEmpty
              ? mode.displaySuffix
              : 'DEF';
          final vehicleKey = '${truck.type}_${truck.id}_$displayKeySuffix';

          if (r.status == VehicleStatus.orange ||
              r.status == VehicleStatus.red) {
            timeRangesByVehicle.putIfAbsent(vehicleKey, () => []);
            timeRangesByVehicle[vehicleKey]!.add({
              'start': sampleTime,
              'end': rangeEnd,
              'status': r.status,
            });
          }

          final existingIndex = specs.indexWhere(
            (s) =>
                s['type'] == truck.type &&
                s['id'] == truck.id &&
                s['period'] ==
                    (mode.displaySuffix.isNotEmpty ? mode.displaySuffix : null),
          );

          if (existingIndex != -1) {
            final currentStatusColor = specs[existingIndex]['color'];
            final currentStatus =
                currentStatusColor == _statusToColor(VehicleStatus.red)
                ? VehicleStatus.red
                : currentStatusColor == _statusToColor(VehicleStatus.orange)
                ? VehicleStatus.orange
                : VehicleStatus.green;
            final newWorst = worst(currentStatus, r.status);
            specs[existingIndex]['color'] = _statusToColor(newWorst);
          } else if (r.status == VehicleStatus.orange ||
              r.status == VehicleStatus.red) {
            specs.add({
              'type': truck.type,
              'id': truck.id,
              'displayNumber': truck.displayNumber,
              'period': mode.displaySuffix.isNotEmpty
                  ? mode.displaySuffix
                  : null,
              'color': _statusToColor(r.status),
              'vehicleKey': vehicleKey,
            });
          }
        }

        pool.removeWhere((a) => allUsedIds.contains(a.id));
      }
    }

    // Merge consecutive time ranges with same status for each vehicle
    final Map<String, List<Map<String, dynamic>>> mergedTimeRangesByVehicle =
        {};
    for (final entry in timeRangesByVehicle.entries) {
      final vehicleKey = entry.key;
      final ranges = entry.value;

      if (ranges.isEmpty) continue;

      // Sort ranges by start time
      ranges.sort(
        (a, b) => (a['start'] as DateTime).compareTo(b['start'] as DateTime),
      );

      final merged = <Map<String, dynamic>>[];
      Map<String, dynamic>? current;

      for (final range in ranges) {
        if (current == null) {
          current = Map<String, dynamic>.from(range);
        } else {
          final currentEnd = current['end'] as DateTime;
          final rangeStart = range['start'] as DateTime;
          final rangeEnd = range['end'] as DateTime;
          final currentStatus = current['status'] as VehicleStatus;
          final rangeStatus = range['status'] as VehicleStatus;

          // Merge if same status and consecutive (or overlapping)
          if (currentStatus == rangeStatus &&
              (currentEnd.isAfter(rangeStart) ||
                  currentEnd.isAtSameMomentAs(rangeStart) ||
                  rangeStart.difference(currentEnd).inMinutes < 2)) {
            // Extend current range
            current['end'] = rangeEnd;
          } else {
            // Save current and start new range
            merged.add(current);
            current = Map<String, dynamic>.from(range);
          }
        }
      }

      // Don't forget the last range
      if (current != null) {
        // If the last range ends very close to planning end (within 2 minutes),
        // extend it to planning.endTime for display purposes
        final currentEnd = current['end'] as DateTime;
        if (planning.endTime.difference(currentEnd).inMinutes < 2) {
          current['end'] = planning.endTime;
        }
        merged.add(current);
      }

      mergedTimeRangesByVehicle[vehicleKey] = merged;
    }

    // Add time ranges to specs
    for (final spec in specs) {
      final vehicleKey = spec['vehicleKey'] as String;
      spec['timeRanges'] = mergedTimeRangesByVehicle[vehicleKey] ?? [];
    }

    // Sort specs according to vehicle type order and ID
    return CrewAllocator.sortVehicleSpecs(specs);
  }

  List<Planning> _getFilteredPlannings() {
    final weekEnd = _currentWeekStart.add(const Duration(days: 7));
    final stationView = stationViewNotifier.value;

    // Filtrer par semaine
    final planningsInWeek = _allPlannings.where((p) {
      // Une planning est dans la semaine si elle chevauche la semaine courante
      return p.endTime.isAfter(_currentWeekStart) &&
          p.startTime.isBefore(weekEnd);
    }).toList();

    // Mode personnel : filtrer selon les règles spécifiques
    if (!stationView) {
      final userPlannings = planningsInWeek.where((planning) {
        // a) L'utilisateur est explicitement dans les agents ET NON remplacé entièrement
        final isAgent = planning.agentsId.contains(_user.id);
        final isReplacedEntirely = _isUserReplacedEntirely(planning, _user.id);

        if (isAgent && !isReplacedEntirely) {
          return true;
        }

        // b) L'utilisateur est remplaçant sur au moins une partie
        final isReplacer = _allSubshifts.any(
          (s) =>
              s.planningId == planning.id &&
              s.replacerId == _user.id &&
              s.end.isAfter(planning.startTime) &&
              s.start.isBefore(planning.endTime),
        );

        return isReplacer;
      }).toList();

      // Ajouter les disponibilités comme des plannings virtuels en mode personnel
      final availabilityPlannings = _getAvailabilityPlannings(weekEnd);

      // Trier par ordre chronologique (startTime)
      final allPlannings = [...userPlannings, ...availabilityPlannings];
      allPlannings.sort((a, b) => a.startTime.compareTo(b.startTime));
      return allPlannings;
    }

    // Mode centre : toutes les plannings de la semaine du centre de l'utilisateur
    final stationPlannings = planningsInWeek
        .where((p) => p.station == _user.station)
        .toList();
    // Trier par ordre chronologique (startTime)
    stationPlannings.sort((a, b) => a.startTime.compareTo(b.startTime));
    return stationPlannings;
  }

  List<Planning> _getAvailabilityPlannings(DateTime weekEnd) {
    // Filtrer les disponibilités de l'utilisateur dans la semaine
    final userAvailabilities = _allAvailabilities.where((a) {
      return a.agentId == _user.id &&
          a.end.isAfter(_currentWeekStart) &&
          a.start.isBefore(weekEnd);
    }).toList();

    // Fusionner les disponibilités qui se chevauchent
    final mergedAvailabilities = _mergeOverlappingAvailabilities(
      userAvailabilities,
    );

    // Convertir chaque disponibilité fusionnée en Planning virtuel
    return mergedAvailabilities.map((availability) {
      return Planning(
        id: 'availability_${availability.id}',
        team: 'Disponibilité',
        startTime: availability.start,
        endTime: availability.end,
        agentsId: [_user.id],
        station: _user.station,
        maxAgents: 1,
      );
    }).toList();
  }

  /// Fusionne les disponibilités qui se chevauchent ou sont adjacentes
  List<Availability> _mergeOverlappingAvailabilities(
    List<Availability> availabilities,
  ) {
    if (availabilities.isEmpty) return [];

    // Trier par heure de début
    final sorted = List<Availability>.from(availabilities)
      ..sort((a, b) => a.start.compareTo(b.start));

    final merged = <Availability>[];
    Availability current = sorted.first;

    for (int i = 1; i < sorted.length; i++) {
      final next = sorted[i];

      // Vérifier si les périodes se chevauchent ou sont adjacentes (écart < 1 minute)
      if (next.start.isBefore(current.end) ||
          next.start.difference(current.end).inMinutes < 1) {
        // Fusionner : étendre la période courante
        current = Availability(
          id: current.id, // Garder l'ID de la première disponibilité
          agentId: current.agentId,
          start: current.start,
          end: next.end.isAfter(current.end) ? next.end : current.end,
          planningId: current.planningId,
        );
      } else {
        // Pas de chevauchement : ajouter la période courante et commencer une nouvelle
        merged.add(current);
        current = next;
      }
    }

    // Ajouter la dernière période
    merged.add(current);

    return merged;
  }

  bool _isUserReplacedEntirely(Planning planning, String userId) {
    final planningStart = planning.startTime;
    final planningEnd = planning.endTime;

    final covered =
        _allSubshifts
            .where(
              (s) =>
                  s.replacedId == userId &&
                  s.planningId == planning.id &&
                  s.end.isAfter(planningStart) &&
                  s.start.isBefore(planningEnd),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));

    if (covered.isEmpty) return false;

    // normalize and merge
    final normalized = covered
        .map(
          (s) => {
            'start': s.start.isBefore(planningStart) ? planningStart : s.start,
            'end': s.end.isAfter(planningEnd) ? planningEnd : s.end,
          },
        )
        .toList();

    final List<Map<String, DateTime>> merged = [];
    for (final seg in normalized) {
      if (merged.isEmpty) {
        merged.add({
          'start': seg['start'] as DateTime,
          'end': seg['end'] as DateTime,
        });
        continue;
      }
      final last = merged.last;
      if ((seg['start'] as DateTime).isBefore(last['end']!) ||
          (seg['start'] as DateTime).isAtSameMomentAs(last['end']!)) {
        if ((seg['end'] as DateTime).isAfter(last['end']!)) {
          last['end'] = seg['end'] as DateTime;
        }
      } else {
        merged.add({
          'start': seg['start'] as DateTime,
          'end': seg['end'] as DateTime,
        });
      }
    }

    // If merged covers from planningStart..planningEnd without gaps => entirely replaced
    if (merged.isEmpty) return false;
    if (merged.first['start']!.isAfter(planningStart)) return false;
    if (merged.last['end']!.isBefore(planningEnd)) return false;

    // check for gaps
    var cursor = planningStart;
    for (final m in merged) {
      if (m['start']!.isAfter(cursor)) return false; // gap
      if (m['end']!.isAfter(cursor)) cursor = m['end']!;
    }
    return !cursor.isBefore(planningEnd);
  }

  void _toggleExpanded(String id) {
    setState(() {
      final newValue = !(_expanded[id] ?? false);
      // Ensure only one card can be expanded at a time
      _expanded.clear();
      if (newValue) {
        _expanded[id] = true;
      }
    });
  }

  Future<void> _openAddSubPlanningDialog(Planning planning) async {
    final sub = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReplacementPage(planning: planning)),
    );

    if (sub != null && mounted) {
      setState(() {
        _allSubshifts.add(sub);
      });
    }
  }

  Future<void> _deleteSubshift(Subshift subshift) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer le remplacement ?"),
        content: const Text(
          "Cette action est irréversible. Voulez-vous vraiment supprimer ce remplacement ?",
        ),
        actions: [
          TextButton(
            child: const Text("Annuler"),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final subRepo = SubshiftRepository();
      await subRepo.delete(subshift.id); // suppression en base

      if (!mounted) return;
      setState(() {
        _allSubshifts.removeWhere((s) => s.id == subshift.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Avoid accessing _user (late) while loading — return a simple loading
    // scaffold early so build doesn't reference [_user.id] before it's set.
    if (_isLoading) {
      return Scaffold(
        body: Container(
          color: Colors.black26,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Scaffold(
      body: ValueListenableBuilder<bool>(
        valueListenable: stationViewNotifier,
        builder: (context, stationView, _) {
          final filteredPlannings = _getFilteredPlannings();

          return Column(
            children: [
              PlanningHeader(
                currentWeekStart: _currentWeekStart,
                onWeekChanged: _onWeekChanged,
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadData,
                  child: filteredPlannings.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 16),
                          children: const [
                            SizedBox(height: 200),
                            Center(child: Text("Aucune astreinte à venir.")),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          key: ValueKey(filteredPlannings.length),
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 8,
                            bottom: 16,
                          ),
                          itemCount: filteredPlannings.length,
                          itemBuilder: (context, i) {
                            final planning = filteredPlannings[i];
                            final id = "${planning.team}_${planning.startTime}";
                            final isExpanded = _expanded[id] ?? false;

                            // subshifts that overlap this planning (any overlap)
                            final subList =
                                _allSubshifts
                                    .where(
                                      (s) =>
                                          s.planningId == planning.id &&
                                          s.end.isAfter(planning.startTime) &&
                                          s.start.isBefore(planning.endTime),
                                    )
                                    .toList()
                                  ..sort((a, b) => a.start.compareTo(b.start));

                            final isAvailability = planning.id.startsWith(
                              'availability_',
                            );
                            final isOnGuard = planning.agentsId.contains(
                              _user.id,
                            );
                            final isReplacedFully = _isUserReplacedEntirely(
                              planning,
                              _user.id,
                            );

                            Subshift? replacerSubshift;
                            for (final s in subList) {
                              if (s.replacerId == _user.id) {
                                replacerSubshift = s;
                                break;
                              }
                            }

                            return AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              alignment: Alignment.topCenter,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  FutureBuilder<List<Map<String, dynamic>>>(
                                    future: _buildVehicleIconSpecs(
                                      planning,
                                      subList,
                                    ),
                                    builder: (context, snapshotIcons) {
                                      final specs =
                                          snapshotIcons.data ?? const [];
                                      return PlanningCard(
                                        planning: planning,
                                        onTap: () => _toggleExpanded(id),
                                        isExpanded: isExpanded,
                                        replacementCount: subList.length,
                                        vehicleIconSpecs: specs,
                                        availabilityColor: _userTeamColor,
                                      );
                                    },
                                  ),
                                  // Contenu étendu avec AnimatedSize
                                  if (!isAvailability && isExpanded)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                      ),
                                      child: Material(
                                        elevation: 4,
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).cardColor,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .dividerColor
                                                  .withValues(alpha: 0.2),
                                            ),
                                          ),
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (!isAvailability &&
                                                  ((isOnGuard &&
                                                          !isReplacedFully) ||
                                                      replacerSubshift != null))
                                                FilledButton(
                                                  onPressed: () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            ReplacementPage(
                                                              planning:
                                                                  planning,
                                                              currentUser:
                                                                  _user,
                                                              parentSubshift:
                                                                  replacerSubshift,
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                  style: FilledButton.styleFrom(
                                                    minimumSize: const Size(
                                                      double.infinity,
                                                      40.0,
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    "Je souhaite m'absenter",
                                                  ),
                                                ),
                                              if ((_user.admin ||
                                                      (_user.status ==
                                                              KConstants
                                                                  .statusChief &&
                                                          _user.team ==
                                                              planning.team) ||
                                                      _user.status ==
                                                          KConstants
                                                              .statusLeader) &&
                                                  !isAvailability)
                                                TextButton(
                                                  onPressed: () =>
                                                      _openAddSubPlanningDialog(
                                                        planning,
                                                      ),
                                                  style: FilledButton.styleFrom(
                                                    minimumSize: const Size(
                                                      double.infinity,
                                                      40.0,
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    "Effectuer un remplacement manuel",
                                                  ),
                                                ),
                                              if (_user.admin ||
                                                  (_user.status ==
                                                          KConstants
                                                              .statusChief &&
                                                      _user.team ==
                                                          planning.team) ||
                                                  _user.status ==
                                                      KConstants.statusLeader)
                                                const SizedBox(height: 8),
                                              if (!isAvailability)
                                                Text(
                                                  subList.isNotEmpty
                                                      ? "Remplacements :"
                                                      : "Aucun remplacement pour cette astreinte.",
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              if (subList.isNotEmpty)
                                                ...subList.mapIndexed((
                                                  index,
                                                  s,
                                                ) {
                                                  final isFirst = index == 0;
                                                  final isLast =
                                                      index ==
                                                      subList.length - 1;
                                                  final canDelete =
                                                      _user.id ==
                                                          s.replacedId ||
                                                      _user.admin ||
                                                      _user.status ==
                                                          KConstants
                                                              .statusLeader ||
                                                      ((_user.status ==
                                                              KConstants
                                                                  .statusChief) &&
                                                          _user.team ==
                                                              planning.team);
                                                  final item = Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 6.0,
                                                        ),
                                                    child: SubShiftItem(
                                                      subShift: s,
                                                      planning: planning,
                                                      allUsers: _allUsers,
                                                      noneUser: noneUser,
                                                      isFirst: isFirst,
                                                      isLast: isLast,
                                                      highlight:
                                                          s.replacerId ==
                                                              _user.id ||
                                                          s.replacedId ==
                                                              _user.id,
                                                    ),
                                                  );

                                                  final Widget
                                                  itemWithOptionalReplaceButton =
                                                      Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [item],
                                                      );
                                                  if (canDelete) {
                                                    return Dismissible(
                                                      key: ValueKey(s.id),
                                                      direction:
                                                          DismissDirection
                                                              .endToStart,
                                                      background: Container(
                                                        alignment: Alignment
                                                            .centerRight,
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 20,
                                                            ),
                                                        color: Colors.redAccent,
                                                        child: const Icon(
                                                          Icons.delete,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      confirmDismiss: (_) async {
                                                        await _deleteSubshift(
                                                          s,
                                                        );
                                                        return false;
                                                      },
                                                      child:
                                                          itemWithOptionalReplaceButton,
                                                    );
                                                  } else {
                                                    return itemWithOptionalReplaceButton;
                                                  }
                                                }),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

extension IndexedMap<E> on Iterable<E> {
  Iterable<T> mapIndexed<T>(T Function(int i, E e) f) sync* {
    var i = 0;
    for (final e in this) {
      yield f(i++, e);
    }
  }
}
