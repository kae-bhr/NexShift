import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/trucks_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
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
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/features/app_shell/presentation/widgets/absence_menu_overlay.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/repositories/shift_exchange_repository.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/filtered_requests_view.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/presentation/widgets/request_actions_bottom_sheet.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/unified_tile_enums.dart';

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
  List<ReplacementRequest> _pendingRequests = [];
  List<ShiftExchangeRequest> _pendingExchanges = [];
  List<ManualReplacementProposal> _pendingManualProposals = [];
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
    debugPrint('🏠 [HOME_PAGE] initState() called');
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
    debugPrint(
      '🏠 [HOME_PAGE] _onUserChanged() - user=${u != null ? '${u.firstName} ${u.lastName} (${u.id})' : 'NULL'}',
    );
    // Only reload if the user actually changed
    if (u == null) {
      debugPrint('🏠 [HOME_PAGE] _onUserChanged() - user is null, returning');
      return;
    }
    if (_lastUserId == u.id && !_isLoading) {
      debugPrint('🏠 [HOME_PAGE] _onUserChanged() - same user, not loading');
      return;
    }
    debugPrint('🏠 [HOME_PAGE] _onUserChanged() - calling _loadData()');
    _loadData();
  }

  Future<void> _loadData() async {
    debugPrint('🏠 [HOME_PAGE] _loadData() started');
    setState(() => _isLoading = true);

    // Prefer the notifier to avoid re-setting it during loadUser, which can
    // cause a reload loop. Fallback to storage only if not available.
    final user = userNotifier.value ?? await UserStorageHelper.loadUser();
    debugPrint(
      '🏠 [HOME_PAGE] _loadData() - user=${user != null ? '${user.firstName} ${user.lastName} (${user.station})' : 'NULL'}',
    );
    if (user != null) {
      // Initialiser le SDIS Context avec le SDIS ID de l'utilisateur
      // pour que tous les repositories utilisent les bons chemins
      // IMPORTANT: Charger le SDIS ID du storage local (sauvegardé lors de la connexion)
      var sdisId = await UserStorageHelper.loadSdisId();
      if (sdisId == null || sdisId.isEmpty) {
        // Fallback: extraire le SDIS ID de l'email Firebase
        final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
        if (firebaseUser != null && firebaseUser.email != null) {
          final email = firebaseUser.email!;
          if (email.endsWith('@nexshift.app')) {
            final parts = email.split('@')[0].split('_');
            if (parts.isNotEmpty) {
              sdisId = parts[0];
              debugPrint(
                '🏠 [HOME_PAGE] Extracted SDIS ID from Firebase email: $sdisId',
              );
              // Sauvegarder pour éviter cette extraction au prochain chargement
              await UserStorageHelper.saveSdisId(sdisId);
            }
          }
        }

        // Si toujours null, utiliser une valeur par défaut (ne devrait jamais arriver)
        if (sdisId == null || sdisId.isEmpty) {
          sdisId = '50';
          debugPrint(
            '⚠️ [HOME_PAGE] Could not extract SDIS ID, using default: $sdisId',
          );
          await UserStorageHelper.saveSdisId(sdisId);
        }
      }
      SDISContext().setCurrentSDISId(sdisId);
      debugPrint(
        '🏠 [HOME_PAGE] SDIS Context initialized with SDIS ID: $sdisId',
      );

      final repo = LocalRepository();
      // Charger les plannings de la semaine courante (on filtrera ensuite côté client)
      final weekEnd = _currentWeekStart.add(const Duration(days: 7));

      final allPlannings = await repo.getPlanningsByStationInRange(
        user.station,
        _currentWeekStart,
        weekEnd,
      );

      final userRepo = UserRepository();
      final allUsers = await userRepo.getByStation(user.station);
      final shifts = await SubshiftRepository().getAll(stationId: user.station);
      final availabilities = await repo.getAvailabilities();

      // Charger la couleur de l'équipe de l'utilisateur
      Color? teamColor;
      try {
        final team = await TeamRepository().getById(
          user.team,
          stationId: user.station,
        );
        teamColor = team?.color;
      } catch (_) {
        teamColor = null;
      }

      // Charger les demandes de remplacement en attente
      List<ReplacementRequest> pendingRequests = [];
      try {
        final notificationService = ReplacementNotificationService();
        pendingRequests = await notificationService
            .getPendingRequestsForStation(user.station)
            .first;
      } catch (e) {
        debugPrint('⚠️ [HOME_PAGE] Error loading pending requests: $e');
      }

      // Charger les demandes d'échange en attente
      List<ShiftExchangeRequest> pendingExchanges = [];
      try {
        final exchangeRepo = ShiftExchangeRepository();
        pendingExchanges = await exchangeRepo.getOpenRequests(
          stationId: user.station,
        );
      } catch (e) {
        debugPrint('⚠️ [HOME_PAGE] Error loading pending exchanges: $e');
      }

      // Charger les propositions de remplacement manuel en attente
      List<ManualReplacementProposal> pendingManualProposals = [];
      try {
        final sdisId = SDISContext().currentSDISId;
        // Chemin correct : replacements/manual/proposals
        final proposalsPath =
            'sdis/$sdisId/stations/${user.station}/replacements/manual/proposals';
        debugPrint(
          '🔍 [HOME_PAGE] Loading manual proposals from: $proposalsPath',
        );
        final snapshot = await FirebaseFirestore.instance
            .collection(proposalsPath)
            .where('status', isEqualTo: 'pending')
            .get();
        pendingManualProposals = snapshot.docs
            .map((doc) => ManualReplacementProposal.fromJson(doc.data()))
            .toList();
        debugPrint(
          '🔍 [HOME_PAGE] Found ${pendingManualProposals.length} pending manual proposals',
        );
      } catch (e) {
        debugPrint('⚠️ [HOME_PAGE] Error loading pending manual proposals: $e');
      }

      if (!mounted) return;
      setState(() {
        _allPlannings = allPlannings;
        _allSubshifts = shifts;
        _allAvailabilities = availabilities;
        _allUsers = allUsers;
        _pendingRequests = pendingRequests;
        _pendingExchanges = pendingExchanges;
        _pendingManualProposals = pendingManualProposals;
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
    final plannings = await repo.getPlanningsByStationInRange(
      _user.station,
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
        if ((availStart.isBefore(sampleUtc) ||
                availStart.isAtSameMomentAs(sampleUtc)) &&
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
      MaterialPageRoute(
        builder: (_) => ReplacementPage(
          planning: planning,
          currentUser: _user,
          isManualMode: true, // Mode manuel
        ),
      ),
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

  /// Toggle le statut "checkedByChief" d'un subshift
  Future<void> _toggleSubshiftCheck(Subshift subshift) async {
    final newChecked = !subshift.checkedByChief;
    final subRepo = SubshiftRepository();

    try {
      await subRepo.toggleCheck(
        subshift.id,
        checked: newChecked,
        checkedBy: _user.id,
        stationId: _user.station, // Passer le stationId pour le chemin SDIS
      );

      if (!mounted) return;
      setState(() {
        // Mettre à jour localement
        final index = _allSubshifts.indexWhere((s) => s.id == subshift.id);
        if (index != -1) {
          _allSubshifts[index] = subshift.copyWith(
            checkedByChief: newChecked,
            checkedAt: newChecked ? DateTime.now() : null,
            checkedBy: newChecked ? _user.id : null,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  /// Compte le nombre de demandes en attente pour un planning
  int _getPendingRequestCount(Planning planning) {
    final planningRequests = _pendingRequests
        .where(
          (r) =>
              r.planningId == planning.id &&
              r.status == ReplacementRequestStatus.pending,
        )
        .length;

    final planningExchanges = _pendingExchanges
        .where(
          (e) =>
              e.initiatorPlanningId == planning.id &&
              (e.status == ShiftExchangeRequestStatus.open ||
                  e.status == ShiftExchangeRequestStatus.proposalSelected),
        )
        .length;

    final planningManualProposals = _pendingManualProposals
        .where((p) => p.planningId == planning.id && p.status == 'pending')
        .length;

    return planningRequests + planningExchanges + planningManualProposals;
  }

  /// Filtre et retourne les demandes en cours liées à un planning
  List<Widget> _buildPendingRequestsSection(Planning planning) {
    // Filtrer les demandes de remplacement pour ce planning
    final planningRequests = _pendingRequests
        .where(
          (r) =>
              r.planningId == planning.id &&
              r.status == ReplacementRequestStatus.pending,
        )
        .toList();

    // Filtrer les demandes d'échange pour ce planning
    final planningExchanges = _pendingExchanges
        .where(
          (e) =>
              e.initiatorPlanningId == planning.id &&
              (e.status == ShiftExchangeRequestStatus.open ||
                  e.status == ShiftExchangeRequestStatus.proposalSelected),
        )
        .toList();

    // Filtrer les propositions manuelles pour ce planning
    final planningManualProposals = _pendingManualProposals
        .where((p) => p.planningId == planning.id && p.status == 'pending')
        .toList();

    // Si aucune demande, ne rien afficher
    if (planningRequests.isEmpty &&
        planningExchanges.isEmpty &&
        planningManualProposals.isEmpty) {
      return [];
    }

    final List<Widget> widgets = [];

    // Divider et titre
    widgets.add(const Divider(height: 24));
    widgets.add(
      const Center(
        child: Text(
          "Demandes en cours :",
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    );
    widgets.add(const SizedBox(height: 8));

    // Afficher les demandes de remplacement
    for (final request in planningRequests) {
      final requester = _allUsers.firstWhere(
        (u) => u.id == request.requesterId,
        orElse: () => noneUser,
      );

      // Déterminer l'icône selon le mode
      IconData icon;
      Color iconColor;
      String? targetName;

      if (request.isSOS) {
        // Mode SOS
        icon = Icons.warning;
        iconColor = Colors.red;
      } else if (request.mode == ReplacementMode.manual) {
        // Remplacement manuel - chercher la cible si disponible
        icon = Icons.person;
        iconColor = Colors.purple;
        // Pour le manuel, on pourrait avoir un replacerId déjà défini
        if (request.replacerId != null) {
          final target = _allUsers.firstWhere(
            (u) => u.id == request.replacerId,
            orElse: () => noneUser,
          );
          targetName = "${target.firstName} ${target.lastName}";
        }
      } else {
        // Remplacement automatique (similarity)
        icon = Icons.autorenew;
        iconColor = Colors.blue;
      }

      final canDelete = _canDeleteRequest(request.requesterId, planning.team);

      final item = _buildRequestItem(
        icon: icon,
        iconColor: iconColor,
        requesterName: "${requester.firstName} ${requester.lastName}",
        targetName: targetName,
        startTime: request.startTime,
        endTime: request.endTime,
        onLongPress: canDelete
            ? () => _showReplacementRequestActionsBottomSheet(request)
            : null,
      );

      if (canDelete) {
        widgets.add(
          Dismissible(
            key: ValueKey('request_${request.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              color: Colors.redAccent,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) => _cancelReplacementRequest(request),
            child: item,
          ),
        );
      } else {
        widgets.add(item);
      }
    }

    // Afficher les demandes d'échange
    for (final exchange in planningExchanges) {
      final initiator = _allUsers.firstWhere(
        (u) => u.id == exchange.initiatorId,
        orElse: () => noneUser,
      );

      final canDelete = _canDeleteRequest(exchange.initiatorId, planning.team);

      final item = _buildRequestItem(
        icon: Icons.swap_horiz,
        iconColor: Colors.green,
        requesterName: "${initiator.firstName} ${initiator.lastName}",
        targetName: null,
        startTime: exchange.initiatorStartTime,
        endTime: exchange.initiatorEndTime,
        onLongPress: canDelete
            ? () => _showExchangeRequestActionsBottomSheet(exchange)
            : null,
      );

      if (canDelete) {
        widgets.add(
          Dismissible(
            key: ValueKey('exchange_${exchange.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              color: Colors.redAccent,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) => _cancelExchangeRequest(exchange),
            child: item,
          ),
        );
      } else {
        widgets.add(item);
      }
    }

    // Afficher les propositions manuelles
    for (final proposal in planningManualProposals) {
      // Pour les propositions manuelles, on utilise replacedId comme demandeur
      // et replacerId comme cible
      final canDelete = _canDeleteRequest(proposal.replacedId, planning.team);

      final item = _buildRequestItem(
        icon: Icons.person,
        iconColor: Colors.purple,
        requesterName: proposal.replacedName,
        targetName: proposal.replacerName,
        startTime: proposal.startTime,
        endTime: proposal.endTime,
        onLongPress: canDelete
            ? () => _showManualProposalActionsBottomSheet(proposal)
            : null,
      );

      if (canDelete) {
        widgets.add(
          Dismissible(
            key: ValueKey('manual_${proposal.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              color: Colors.redAccent,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) => _cancelManualProposal(proposal),
            child: item,
          ),
        );
      } else {
        widgets.add(item);
      }
    }

    return widgets;
  }

  /// Vérifie si l'utilisateur peut supprimer une demande
  bool _canDeleteRequest(String requesterId, String planningTeam) {
    // L'initiateur peut supprimer sa propre demande
    if (_user.id == requesterId) return true;
    // Admin peut tout supprimer
    if (_user.admin) return true;
    // Chef de centre peut supprimer
    if (_user.status == KConstants.statusLeader) return true;
    // Chef d'équipe peut supprimer pour son équipe
    if (_user.status == KConstants.statusChief && _user.team == planningTeam) {
      return true;
    }
    return false;
  }

  /// Affiche le BottomSheet d'actions pour une demande de remplacement automatique
  void _showReplacementRequestActionsBottomSheet(ReplacementRequest request) {
    // Déterminer si le bouton de renotification doit être affiché
    // Pour les remplacements automatiques : seulement à partir de la vague 5
    final showResendButton = request.currentWave >= 5;

    // Récupérer le nom du demandeur
    final requester = _allUsers.firstWhere(
      (u) => u.id == request.requesterId,
      orElse: () => _allUsers.first,
    );
    final initiatorName = '${requester.firstName} ${requester.lastName}';

    RequestActionsBottomSheet.show(
      context: context,
      requestType: request.isSOS
          ? UnifiedRequestType.sosReplacement
          : UnifiedRequestType.automaticReplacement,
      initiatorName: initiatorName,
      team: request.team,
      station: request.station,
      startTime: request.startTime,
      endTime: request.endTime,
      onResendNotifications: showResendButton
          ? () => _resendReplacementNotifications(request)
          : null,
      onDelete: () => _cancelReplacementRequest(request),
    );
  }

  /// Affiche le BottomSheet d'actions pour une demande d'échange
  void _showExchangeRequestActionsBottomSheet(ShiftExchangeRequest exchange) {
    RequestActionsBottomSheet.show(
      context: context,
      requestType: UnifiedRequestType.exchange,
      initiatorName: exchange.initiatorName,
      team: exchange.initiatorTeam,
      station: exchange.station,
      startTime: exchange.initiatorStartTime,
      endTime: exchange.initiatorEndTime,
      onResendNotifications: () => _resendExchangeNotifications(exchange),
      onDelete: () => _cancelExchangeRequest(exchange),
    );
  }

  /// Affiche le BottomSheet d'actions pour une proposition de remplacement manuel
  void _showManualProposalActionsBottomSheet(
    ManualReplacementProposal proposal,
  ) {
    RequestActionsBottomSheet.show(
      context: context,
      requestType: UnifiedRequestType.manualReplacement,
      initiatorName: proposal.replacedName,
      team: proposal.replacedTeam,
      station: _user.station,
      startTime: proposal.startTime,
      endTime: proposal.endTime,
      onResendNotifications: () => _resendManualProposalNotifications(proposal),
      onDelete: () => _cancelManualProposal(proposal),
    );
  }

  /// Relance les notifications pour une demande de remplacement automatique
  Future<void> _resendReplacementNotifications(
    ReplacementRequest request,
  ) async {
    // TODO: Implémenter la logique de renotification
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notification de relance envoyée'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  /// Relance les notifications pour une demande d'échange
  Future<void> _resendExchangeNotifications(
    ShiftExchangeRequest exchange,
  ) async {
    // TODO: Implémenter la logique de renotification
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notification de relance envoyée'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  /// Relance les notifications pour une proposition de remplacement manuel
  Future<void> _resendManualProposalNotifications(
    ManualReplacementProposal proposal,
  ) async {
    // TODO: Implémenter la logique de renotification
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notification de relance envoyée'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  /// Construit un item de demande en cours
  Widget _buildRequestItem({
    required IconData icon,
    required Color iconColor,
    required String requesterName,
    String? targetName,
    required DateTime startTime,
    required DateTime endTime,
    VoidCallback? onLongPress,
  }) {
    final dateFormat = DateFormat('dd/MM HH:mm');

    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (targetName != null)
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                        children: [
                          TextSpan(
                            text: targetName,
                            style: const TextStyle(
                              color: Colors.purple,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const TextSpan(text: ' ← '),
                          TextSpan(
                            text: requesterName,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.tertiary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      requesterName,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.tertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '${dateFormat.format(startTime)} → ${dateFormat.format(endTime)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Annule une demande de remplacement
  Future<bool> _cancelReplacementRequest(ReplacementRequest request) async {
    final ctx = context;
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text("Annuler la demande ?"),
        content: const Text(
          "Voulez-vous vraiment annuler cette demande de remplacement ?",
        ),
        actions: [
          TextButton(
            child: const Text("Non"),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Annuler la demande"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final notificationService = ReplacementNotificationService();
        await notificationService.cancelReplacementRequest(
          request.id,
          stationId: _user.station,
        );

        if (!mounted) return false;
        setState(() {
          _pendingRequests.removeWhere((r) => r.id == request.id);
        });
        return true;
      } catch (e) {
        debugPrint('❌ [HOME_PAGE] Error cancelling request: $e');
      }
    }
    return false;
  }

  /// Annule une demande d'échange
  Future<bool> _cancelExchangeRequest(ShiftExchangeRequest exchange) async {
    final ctx = context;
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text("Annuler la demande ?"),
        content: const Text(
          "Voulez-vous vraiment annuler cette demande d'échange ?",
        ),
        actions: [
          TextButton(
            child: const Text("Non"),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Annuler la demande"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final exchangeRepo = ShiftExchangeRepository();
        // Supprimer la demande d'échange (soft delete via status cancelled)
        await exchangeRepo.deleteRequest(exchange.id, stationId: _user.station);

        if (!mounted) return false;
        setState(() {
          _pendingExchanges.removeWhere((e) => e.id == exchange.id);
        });
        return true;
      } catch (e) {
        debugPrint('❌ [HOME_PAGE] Error cancelling exchange: $e');
      }
    }
    return false;
  }

  /// Annule une proposition de remplacement manuel
  Future<bool> _cancelManualProposal(ManualReplacementProposal proposal) async {
    final ctx = context;
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text("Annuler la proposition ?"),
        content: const Text(
          "Voulez-vous vraiment annuler cette proposition de remplacement manuel ?",
        ),
        actions: [
          TextButton(
            child: const Text("Non"),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Oui, annuler la proposition"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final sdisId = SDISContext().currentSDISId;
        // Chemin correct : replacements/manual/proposals
        final proposalsPath =
            'sdis/$sdisId/stations/${_user.station}/replacements/manual/proposals';
        await FirebaseFirestore.instance
            .collection(proposalsPath)
            .doc(proposal.id)
            .update({'status': 'cancelled'});

        if (!mounted) return false;
        setState(() {
          _pendingManualProposals.removeWhere((p) => p.id == proposal.id);
        });
        return true;
      } catch (e) {
        debugPrint('❌ [HOME_PAGE] Error cancelling manual proposal: $e');
      }
    }
    return false;
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
                                      // Vérifier si tous les remplacements sont checkés
                                      final allChecked = subList.isNotEmpty &&
                                          subList.every((s) => s.checkedByChief);
                                      return PlanningCard(
                                        planning: planning,
                                        onTap: () => _toggleExpanded(id),
                                        isExpanded: isExpanded,
                                        replacementCount: subList.length,
                                        pendingRequestCount:
                                            _getPendingRequestCount(planning),
                                        vehicleIconSpecs: specs,
                                        availabilityColor: _userTeamColor,
                                        allReplacementsChecked: allChecked,
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
                                              // Bouton "Je souhaite m'absenter" si l'utilisateur est dans l'astreinte
                                              if (!isAvailability &&
                                                  ((isOnGuard &&
                                                          !isReplacedFully) ||
                                                      replacerSubshift != null))
                                                _AbsenceMenuButton(
                                                  planning: planning,
                                                  user: _user,
                                                  replacerSubshift:
                                                      replacerSubshift,
                                                )
                                              // Bouton "Faire remplacer un agent" si user privilégié, PAS dans l'astreinte, et en stationView
                                              else if (!isAvailability &&
                                                  stationView &&
                                                  (!isOnGuard || isReplacedFully) &&
                                                  (_user.admin ||
                                                      _user.status == KConstants.statusLeader ||
                                                      (_user.status == KConstants.statusChief &&
                                                          _user.team.toLowerCase() == planning.team.toLowerCase())))
                                                _AdminReplaceButton(
                                                  planning: planning,
                                                  user: _user,
                                                ),
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
                                                  // Permissions pour voir/interagir avec le check
                                                  final canSeeCheck =
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
                                                      showCheckIcon: canSeeCheck,
                                                      onCheckTap: canSeeCheck
                                                          ? () => _toggleSubshiftCheck(s)
                                                          : null,
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
                                              // Section des demandes en cours
                                              ..._buildPendingRequestsSection(
                                                planning,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  // Padding après le container étendu
                                  if (!isAvailability && isExpanded)
                                    const SizedBox(height: 60),
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

/// Widget pour le bouton "Je souhaite m'absenter" avec menu déroulant
class _AbsenceMenuButton extends StatefulWidget {
  final Planning planning;
  final User user;
  final Subshift? replacerSubshift;

  const _AbsenceMenuButton({
    required this.planning,
    required this.user,
    this.replacerSubshift,
  });

  @override
  State<_AbsenceMenuButton> createState() => _AbsenceMenuButtonState();
}

class _AbsenceMenuButtonState extends State<_AbsenceMenuButton>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  late AnimationController _animationController;
  late Animation<double> _animation;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _animationController.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _animationController.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  void _toggleMenu() {
    if (_overlayEntry != null) {
      _removeOverlay();
    } else {
      _showMenu();
    }
  }

  void _showMenu() {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => GestureDetector(
        onTap: _removeOverlay,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            // Semi-transparent background
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.3)),
            ),
            // Menu options
            Positioned(
              width: size.width,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: Offset(0, size.height + 8),
                child: FadeTransition(
                  opacity: _animation,
                  child: ScaleTransition(
                    scale: _animation,
                    alignment: Alignment.topCenter,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      child: AbsenceMenuOverlay.buildMenuContent(
                        context: context,
                        planning: widget.planning,
                        user: widget.user,
                        parentSubshift: widget.replacerSubshift,
                        onOptionSelected: _removeOverlay,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: FilledButton.icon(
        onPressed: _toggleMenu,
        icon: const Icon(Icons.event_busy),
        label: const Text("Je souhaite m'absenter"),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 40.0),
        ),
      ),
    );
  }
}

/// Widget pour le bouton "Faire remplacer un agent" (pour admins/leaders/chiefs)
/// Affiché quand l'utilisateur privilégié n'est PAS dans l'astreinte
class _AdminReplaceButton extends StatefulWidget {
  final Planning planning;
  final User user;

  const _AdminReplaceButton({
    required this.planning,
    required this.user,
  });

  @override
  State<_AdminReplaceButton> createState() => _AdminReplaceButtonState();
}

class _AdminReplaceButtonState extends State<_AdminReplaceButton>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  late AnimationController _animationController;
  late Animation<double> _animation;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _animationController.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _animationController.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  void _toggleMenu() {
    if (_overlayEntry != null) {
      _removeOverlay();
    } else {
      _showMenu();
    }
  }

  void _showMenu() {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => GestureDetector(
        onTap: _removeOverlay,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            // Semi-transparent background
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.3)),
            ),
            // Menu options
            Positioned(
              width: size.width,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: Offset(0, size.height + 8),
                child: FadeTransition(
                  opacity: _animation,
                  child: ScaleTransition(
                    scale: _animation,
                    alignment: Alignment.topCenter,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      child: AbsenceMenuOverlay.buildMenuContent(
                        context: context,
                        planning: widget.planning,
                        user: widget.user,
                        parentSubshift: null,
                        onOptionSelected: _removeOverlay,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: FilledButton.icon(
        onPressed: _toggleMenu,
        icon: const Icon(Icons.admin_panel_settings),
        label: const Text("Faire remplacer un agent"),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 40.0),
          backgroundColor: Colors.deepPurple,
        ),
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
