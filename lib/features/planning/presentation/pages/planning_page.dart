import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/availability_model.dart';
import 'package:nexshift_app/features/planning/presentation/widgets/planning_bar.dart';
import 'package:nexshift_app/features/planning/presentation/pages/planning_team_details_page.dart';
import 'package:nexshift_app/features/planning/presentation/widgets/planning_header_widget.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/utils/subshift_normalizer.dart';
import 'package:nexshift_app/features/app_shell/presentation/widgets/absence_menu_overlay.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/features/planning/presentation/widgets/view_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key});

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage> {
  List<Planning> _plannings = [];
  List<Subshift> _subshifts = [];
  List<Availability> _availabilities = [];
  User? _currentUser;
  Map<String, Color> _teamColorById = {};
  List<Team> _availableTeams = [];
  Color? _userTeamColor;
  bool _isLoading = false;
  String? _lastLoadedUserId;

  // Vue mensuelle
  List<Planning> _monthPlannings = [];
  bool _isMonthLoading = false;

  // Variables pour l'infobulle de long press
  OverlayEntry? _tooltipOverlay;
  DateTime? _selectedTime;
  Offset? _tooltipPosition;
  double? _containerTopY; // Position Y du haut du container de planning

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR', null).then((_) {
      _loadUserAndPlanning();
    });
    stationViewNotifier.addListener(_onStationViewChanged);
    teamDataChangedNotifier.addListener(_onTeamDataChanged);
    userNotifier.addListener(_onUserChanged);
    viewModeNotifier.addListener(_onViewModeChanged);
    currentMonthNotifier.addListener(_onCurrentMonthChanged);
    selectedTeamNotifier.addListener(_onSelectedTeamChanged);
  }

  void _onUserChanged() {
    // Recharger uniquement si l'utilisateur a réellement changé
    final u = userNotifier.value;
    if (u == null) return;
    if (_lastLoadedUserId == u.id) return;
    _loadUserAndPlanning();
  }

  @override
  void dispose() {
    _removeTooltip();
    stationViewNotifier.removeListener(_onStationViewChanged);
    teamDataChangedNotifier.removeListener(_onTeamDataChanged);
    userNotifier.removeListener(_onUserChanged);
    viewModeNotifier.removeListener(_onViewModeChanged);
    currentMonthNotifier.removeListener(_onCurrentMonthChanged);
    selectedTeamNotifier.removeListener(_onSelectedTeamChanged);
    super.dispose();
  }

  void _onViewModeChanged() {
    if (viewModeNotifier.value == ViewMode.month && _monthPlannings.isEmpty) {
      _reloadPlanningsForMonth(currentMonthNotifier.value);
    } else {
      setState(() {});
    }
  }

  void _onCurrentMonthChanged() {
    setState(() => _monthPlannings = []);
    _reloadPlanningsForMonth(currentMonthNotifier.value);
  }

  void _onSelectedTeamChanged() => setState(() {});

  void _onStationViewChanged() {
    // when the toggle changes, reload plannings to reflect personal/centre view
    setState(() => _monthPlannings = []);
    selectedTeamNotifier.value = null;
    _loadUserAndPlanning();
  }

  void _onTeamDataChanged() {
    // Reload team colors when teams are modified
    _loadUserAndPlanning();
  }

  // Méthodes de gestion de l'infobulle
  void _removeTooltip() {
    _tooltipOverlay?.remove();
    _tooltipOverlay = null;
    _selectedTime = null;
    _tooltipPosition = null;
    _containerTopY = null;
  }

  void _showTooltip(DateTime at, Offset globalPosition) {
    _removeTooltip();
    _selectedTime = at;
    _tooltipPosition = globalPosition;

    // Calculer la position Y du haut du container (globalPosition.dy est la position du touch)
    // On va fixer l'infobulle 40px au-dessus de la barre de planning
    _containerTopY = globalPosition.dy;

    _tooltipOverlay = OverlayEntry(
      builder: (context) => _TooltipWidget(
        positionX: _tooltipPosition!.dx,
        containerTopY: _containerTopY!,
        selectedTime: _selectedTime!,
      ),
    );

    Overlay.of(context).insert(_tooltipOverlay!);
  }

  void _updateTooltip(DateTime at, Offset globalPosition) {
    if (_tooltipOverlay == null || _containerTopY == null) return;

    // Supprimer l'ancien overlay et en créer un nouveau avec les nouvelles valeurs
    _tooltipOverlay!.remove();
    _selectedTime = at;
    _tooltipPosition = globalPosition;

    _tooltipOverlay = OverlayEntry(
      builder: (context) => _TooltipWidget(
        positionX: _tooltipPosition!.dx,
        containerTopY: _containerTopY!,
        selectedTime: _selectedTime!,
      ),
    );

    Overlay.of(context).insert(_tooltipOverlay!);
  }

  Future<void> _showShiftDetails(DateTime at, Planning? planning) async {
    _removeTooltip();

    if (planning == null) {
      // Aucun planning sur ce créneau
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[600]),
                  const SizedBox(width: 12),
                  Text(
                    'Aucune astreinte',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Aucune astreinte sur ce créneau horaire',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              // Bouton "Afficher la vue opérationnelle"
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlanningTeamDetailsPage(at: at),
                      ),
                    );
                  },
                  icon: const Icon(Icons.visibility),
                  label: const Text('Afficher la vue opérationnelle'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fermer'),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    // Chercher le subshift correspondant à l'heure sélectionnée
    Subshift? relevantSubshift;
    try {
      relevantSubshift = _subshifts.firstWhere(
        (s) =>
            s.planningId == planning.id &&
            s.start.isBefore(at) &&
            s.end.isAfter(at),
      );
    } catch (_) {
      // Pas de subshift trouvé, utiliser les dates du planning
      relevantSubshift = null;
    }

    String title;
    String startFormatted;
    String endFormatted;

    if (relevantSubshift != null) {
      final teamName = planning.team;
      startFormatted = DateFormat('dd/MM HH:mm').format(relevantSubshift.start);
      endFormatted = DateFormat('dd/MM HH:mm').format(relevantSubshift.end);
      title = 'Équipe $teamName';
    } else {
      // Utiliser les dates du planning
      final teamName = planning.team;
      startFormatted = DateFormat('dd/MM HH:mm').format(planning.startTime);
      endFormatted = DateFormat('dd/MM HH:mm').format(planning.endTime);
      title = 'Équipe $teamName';
    }

    // Vérifier si l'utilisateur est en astreinte ou remplaçant
    final user = _currentUser;
    if (user == null) return;

    // Trouver tous les subshifts pour ce planning
    final planningSubshifts = _subshifts
        .where((s) => s.planningId == planning.id)
        .toList();

    // Vérifier si l'utilisateur est agent sur ce planning
    final isOnGuard = planning.agentsId.contains(user.id);

    // Vérifier si l'utilisateur est remplaçant sur un subshift
    final replacerSubshift = planningSubshifts
        .where((s) => s.replacerId == user.id)
        .firstOrNull;

    // Vérifier si l'utilisateur est entièrement remplacé
    bool isReplacedFully = false;
    if (isOnGuard) {
      final userReplacements = planningSubshifts
          .where((s) => s.replacedId == user.id)
          .toList();

      if (userReplacements.isNotEmpty) {
        // Vérifier si toute la période du planning est couverte
        userReplacements.sort((a, b) => a.start.compareTo(b.start));

        final firstReplStart = userReplacements.first.start;
        final lastReplEnd = userReplacements.last.end;

        if (!firstReplStart.isAfter(planning.startTime) &&
            !lastReplEnd.isBefore(planning.endTime)) {
          // Vérifier qu'il n'y a pas de trous
          bool hasGaps = false;
          for (int i = 0; i < userReplacements.length - 1; i++) {
            if (userReplacements[i].end.isBefore(userReplacements[i + 1].start)) {
              hasGaps = true;
              break;
            }
          }
          isReplacedFully = !hasGaps;
        }
      }
    }

    // Vérifier s'il existe une demande de remplacement active
    final hasActiveRequest = await _hasActiveReplacementRequest(planning, user.id, user.station);

    // Afficher un BottomSheet avec les actions
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (_teamColorById[planning.team] ?? Colors.grey)
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.groups,
                    color: _teamColorById[planning.team] ?? Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time, color: Colors.grey[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$startFormatted → $endFormatted',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Bouton "Afficher la vue opérationnelle"
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlanningTeamDetailsPage(at: at),
                    ),
                  );
                },
                icon: const Icon(Icons.visibility),
                label: const Text('Afficher la vue opérationnelle'),
              ),
            ),

            // Bouton "Je souhaite m'absenter" - affiché si l'utilisateur est en astreinte ou remplaçant et pas entièrement remplacé
            if ((isOnGuard && !isReplacedFully) || replacerSubshift != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (hasActiveRequest && user.status == KConstants.statusAgent)
                      ? null
                      : () {
                          Navigator.pop(context);
                          // Afficher le menu d'absence avec les trois options
                          AbsenceMenuOverlay.showAsBottomSheet(
                            context: context,
                            planning: planning,
                            user: user,
                            parentSubshift: replacerSubshift,
                          );
                        },
                  icon: const Icon(Icons.event_busy),
                  label: const Text("Je souhaite m'absenter"),
                  style: (hasActiveRequest && user.status == KConstants.statusAgent)
                      ? OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey,
                          side: const BorderSide(color: Colors.grey),
                        )
                      : null,
                ),
              ),
            ],

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadUserAndPlanning() async {
    if (_isLoading) return;
    _isLoading = true;

    // Lire depuis le notifier en priorité pour éviter de le re-déclencher
    final user = userNotifier.value ?? await UserStorageHelper.loadUser();
    if (user != null) {
      // S'assurer que le SDIS Context est initialisé (filet de sécurité)
      await SDISContext().ensureInitialized();

      final repo = LocalRepository();
      final isStationView = stationViewNotifier.value;
      debugPrint('📅 [PLANNING_PAGE] _loadUserAndPlanning() - user: ${user.firstName} ${user.lastName}, station: ${user.station}, stationView: $isStationView');
      debugPrint('📅 [PLANNING_PAGE] _loadUserAndPlanning() - SDIS Context: ${SDISContext().currentSDISId}');
      // Load subshifts first (used to include extra plannings for replacer mode)
      final rawSubshifts = await SubshiftRepository().getAll(stationId: user.station);
      debugPrint('📅 [PLANNING_PAGE] _loadUserAndPlanning() - Loaded ${rawSubshifts.length} raw subshifts');
      // Résoudre les cascades de remplacements pour affichage correct
      final subshifts = resolveReplacementCascades(rawSubshifts);
      debugPrint('📅 [PLANNING_PAGE] _loadUserAndPlanning() - After cascade resolution: ${subshifts.length} subshifts');
      // Load teams to colorize bars by team in station view
      Color? userTeamColor;
      List<Team> availableTeams = [];
      try {
        final teams = await TeamRepository().getByStation(user.station);
        teams.sort((a, b) => a.order.compareTo(b.order));
        availableTeams = teams;
        _teamColorById = {for (final t in teams) t.id: t.color};
        // Récupérer la couleur de l'équipe de l'utilisateur
        final userTeam = teams.firstWhere(
          (t) => t.id == user.team,
          orElse: () => teams.first,
        );
        userTeamColor = userTeam.color;
      } catch (_) {
        _teamColorById = {};
        userTeamColor = null;
      }
      final weekStart = currentWeekStartNotifier.value;
      final weekEnd = weekStart.add(const Duration(days: 7));

      List<Planning> plannings;
      List<Availability> availabilities = [];
      if (isStationView) {
        // Centre view: show plannings of current station that overlap the selected week
        plannings = await repo.getPlanningsByStationInRange(
          user.station,
          weekStart,
          weekEnd,
        );
      } else {
        // Personal view: start with user's own plannings in the selected week
        plannings = await repo.getPlanningsForUserInRange(
          user,
          true,
          weekStart,
          weekEnd,
        );
        // Ensure we also include plannings where the user is a replacer
        final replacerPlanningIds = subshifts
            .where((s) => s.replacerId == user.id)
            .map((s) => s.planningId)
            .toSet();
        debugPrint('📅 [PLANNING_PAGE] Replacer planning IDs for user ${user.id}: $replacerPlanningIds');
        debugPrint('📅 [PLANNING_PAGE] Current plannings loaded: ${plannings.map((p) => p.id).toList()}');
        final missingIds = replacerPlanningIds
            .where((id) => !plannings.any((p) => p.id == id))
            .toList();
        debugPrint('📅 [PLANNING_PAGE] Missing planning IDs to load: $missingIds');
        for (final id in missingIds) {
          final p = await repo.getPlanningById(id, stationId: user.station);
          debugPrint('📅 [PLANNING_PAGE] Loaded missing planning $id: ${p != null ? "SUCCESS (${p.team} ${p.startTime})" : "NULL"}');
          if (p != null) plannings.add(p);
        }
        debugPrint('📅 [PLANNING_PAGE] Final plannings count after adding replacer plannings: ${plannings.length}');

        // Load user's availabilities for personal view
        final allAvailabilities = await repo.getAvailabilities(stationId: user.station);
        final userAvailabilities = allAvailabilities
            .where(
              (a) =>
                  a.agentId == user.id &&
                  a.end.isAfter(weekStart) &&
                  a.start.isBefore(weekEnd),
            )
            .toList();

        // Fusionner les disponibilités qui se chevauchent
        availabilities = _mergeOverlappingAvailabilities(userAvailabilities);
      }

      debugPrint('📅 [PLANNING_PAGE] setState() - plannings: ${plannings.length}, subshifts: ${subshifts.length}, availabilities: ${availabilities.length}');
      if (!mounted) {
        _isLoading = false;
        return;
      }
      setState(() {
        _plannings = plannings;
        _subshifts = subshifts;
        _availabilities = availabilities;
        _currentUser = user;
        _userTeamColor = userTeamColor;
        _availableTeams = availableTeams;
        _isLoading = false;
        _lastLoadedUserId = user.id;
      });
      debugPrint('📅 [PLANNING_PAGE] setState() completed - _subshifts in state: ${_subshifts.length}');
      // Si on arrive en mode mois, charger maintenant que _currentUser est initialisé
      if (viewModeNotifier.value == ViewMode.month && _monthPlannings.isEmpty) {
        _reloadPlanningsForMonth(currentMonthNotifier.value);
      }
    } else {
      _isLoading = false;
    }
  }


  Future<void> _reloadPlanningsForMonth(DateTime month) async {
    setState(() => _isMonthLoading = true);
    final user = _currentUser;
    if (user == null) {
      setState(() => _isMonthLoading = false);
      return;
    }
    final repo = LocalRepository();
    final isStationView = stationViewNotifier.value;
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    List<Planning> plannings;
    if (isStationView) {
      plannings = await repo.getPlanningsByStationInRange(
        user.station,
        monthStart,
        monthEnd,
      );
    } else {
      plannings = await repo.getPlanningsForUserInRange(
        user,
        true,
        monthStart,
        monthEnd,
      );
    }
    if (!mounted) return;
    setState(() {
      _monthPlannings = plannings;
      _isMonthLoading = false;
    });
  }

  // Week navigation is handled by [PlanningHeader]; PlanningPage keeps
  // the current week state and passes handlers into the header.

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Découpe un planning traversant minuit en segments journaliers
  List<Map<String, dynamic>> _splitPlanningByDay(Planning planning) {
    List<Map<String, dynamic>> segments = [];

    DateTime currentStart = planning.startTime;
    DateTime end = planning.endTime;
    bool isFirstSegment = true;

    while (currentStart.isBefore(end)) {
      // Calculer la fin de la journée courante (lendemain à 00:00)
      DateTime nextDayStart = DateTime(
        currentStart.year,
        currentStart.month,
        currentStart.day + 1,
        0,
        0,
      );

      bool crossesMidnight = end.isAfter(nextDayStart);

      DateTime segmentEnd;
      if (crossesMidnight) {
        // Le planning continue après minuit
        segmentEnd = nextDayStart;
      } else {
        // Le planning se termine ce jour
        segmentEnd = end;
      }

      segments.add({
        'day': DateTime(
          currentStart.year,
          currentStart.month,
          currentStart.day,
        ),
        'start': currentStart,
        'end': segmentEnd,
        'planning': planning,
        'isRealStart': isFirstSegment,
        'isRealEnd': !crossesMidnight,
      });

      isFirstSegment = false;
      currentStart = nextDayStart;
    }

    return segments;
  }

  /// Génère les barres à afficher pour un jour donné selon le mode
  /// En mode utilisateur : segments de l'utilisateur moins ses remplacements + ses remplacements
  /// En mode caserne : tous les plannings
  List<Map<String, dynamic>> _generateBarsForDay(DateTime day) {
    final stationView = stationViewNotifier.value;
    final bars = <Map<String, dynamic>>[];

    debugPrint('📊 [PLANNING_PAGE] _generateBarsForDay(${DateFormat('dd/MM').format(day)}) - stationView: $stationView, plannings: ${_plannings.length}, subshifts: ${_subshifts.length}');

    if (stationView) {
      // Mode caserne : afficher toutes les astreintes
      for (final planning in _plannings) {
        final segments = _splitPlanningByDay(planning);
        for (final seg in segments) {
          if (_isSameDay(seg['day'], day)) {
            // Use team color from loaded map, fallback to grey if not found
            final teamColor =
                _teamColorById[planning.team] ?? const Color(0xFF757575);
            bars.add({
              'start': seg['start'],
              'end': seg['end'],
              'planning': planning,
              'type': 'station', // Pour identification si besoin
              'color': teamColor,
              'isRealStart': seg['isRealStart'] ?? true,
              'isRealEnd': seg['isRealEnd'] ?? true,
            });
          }
        }
      }
      // Appliquer le filtre équipe si actif
      if (selectedTeamNotifier.value != null) {
        bars.removeWhere((b) =>
            (b['planning'] as Planning?)?.team != selectedTeamNotifier.value);
      }
    } else {
      // Mode utilisateur
      if (_currentUser == null) return bars;

      for (final planning in _plannings) {
        final segments = _splitPlanningByDay(planning);
        for (final seg in segments) {
          if (!_isSameDay(seg['day'], day)) continue;

          final segStart = seg['start'] as DateTime;
          final segEnd = seg['end'] as DateTime;

          // Vérifier si l'utilisateur est agent sur ce planning
          final isAgent = planning.agentsId.contains(_currentUser!.id);

          if (isAgent) {
            // Trouver les remplacements qui affectent ce segment
            final replacements =
                _subshifts
                    .where(
                      (s) =>
                          s.planningId == planning.id &&
                          s.replacedId == _currentUser!.id &&
                          s.end.isAfter(segStart) &&
                          s.start.isBefore(segEnd),
                    )
                    .toList()
                  ..sort((a, b) => a.start.compareTo(b.start));

            if (replacements.isEmpty) {
              // Aucun remplacement : afficher la barre complète
              final teamColor =
                  _teamColorById[planning.team] ?? const Color(0xFF757575);
              bars.add({
                'start': segStart,
                'end': segEnd,
                'planning': planning,
                'type': 'agent',
                'color': teamColor,
                'isRealStart': seg['isRealStart'] ?? true,
                'isRealEnd': seg['isRealEnd'] ?? true,
              });
            } else {
              // Découper selon les remplacements
              DateTime currentTime = segStart;
              final isRealSegStart = seg['isRealStart'] ?? true;
              final isRealSegEnd = seg['isRealEnd'] ?? true;
              final teamColor =
                  _teamColorById[planning.team] ?? const Color(0xFF757575);

              for (final replacement in replacements) {
                final replStart = replacement.start.isBefore(segStart)
                    ? segStart
                    : replacement.start;
                final replEnd = replacement.end.isAfter(segEnd)
                    ? segEnd
                    : replacement.end;

                // Ajouter la période avant le remplacement
                if (currentTime.isBefore(replStart)) {
                  bars.add({
                    'start': currentTime,
                    'end': replStart,
                    'planning': planning,
                    'type': 'agent',
                    'color': teamColor,
                    'isRealStart': currentTime == segStart && isRealSegStart,
                    'isRealEnd':
                        true, // fin de cette période avant le remplacement
                  });
                }

                currentTime = replEnd.isAfter(currentTime)
                    ? replEnd
                    : currentTime;
              }

              // Ajouter la période après le dernier remplacement
              if (currentTime.isBefore(segEnd)) {
                bars.add({
                  'start': currentTime,
                  'end': segEnd,
                  'planning': planning,
                  'type': 'agent',
                  'color': teamColor,
                  'isRealStart':
                      true, // début de cette période après le remplacement
                  'isRealEnd': isRealSegEnd,
                });
              }
            }
          }

          // Ajouter les périodes où l'utilisateur est remplaçant
          final replacerShifts = _subshifts
              .where(
                (s) =>
                    s.planningId == planning.id &&
                    s.replacerId == _currentUser!.id &&
                    s.end.isAfter(segStart) &&
                    s.start.isBefore(segEnd),
              )
              .toList();

          debugPrint('📊 [PLANNING_PAGE] Replacer shifts for planning ${planning.id}: ${replacerShifts.length}');

          for (final shift in replacerShifts) {
            final shiftStart = shift.start.isBefore(segStart)
                ? segStart
                : shift.start;
            final shiftEnd = shift.end.isAfter(segEnd) ? segEnd : shift.end;
            final teamColor =
                _teamColorById[planning.team] ?? const Color(0xFF757575);

            bars.add({
              'start': shiftStart,
              'end': shiftEnd,
              'planning': planning,
              'type': 'replacer',
              'color': teamColor,
              // Les barres de remplaçant montrent uniquement les bordures où elles commencent/finissent vraiment
              'isRealStart': shiftStart == shift.start,
              'isRealEnd': shiftEnd == shift.end,
            });
          }
        }
      }

      // Ajouter les disponibilités de l'utilisateur en mode personnel
      for (final availability in _availabilities) {
        final segments = _splitAvailabilityByDay(availability);
        for (final seg in segments) {
          if (_isSameDay(seg['day'], day)) {
            bars.add({
              'start': seg['start'],
              'end': seg['end'],
              'availability': availability,
              'type': 'availability',
              'color': _getShade400(
                _userTeamColor ?? Colors.grey,
              ), // Couleur de l'équipe de l'utilisateur en shade400
              'isRealStart': seg['isRealStart'] ?? true,
              'isRealEnd': seg['isRealEnd'] ?? true,
            });
          }
        }
      }
    }

    return bars;
  }

  /// Découpe une disponibilité traversant minuit en segments journaliers
  List<Map<String, dynamic>> _splitAvailabilityByDay(
    Availability availability,
  ) {
    List<Map<String, dynamic>> segments = [];

    DateTime currentStart = availability.start;
    DateTime end = availability.end;
    bool isFirstSegment = true;

    while (currentStart.isBefore(end)) {
      // Calculer la fin de la journée courante (lendemain à 00:00)
      DateTime nextDayStart = DateTime(
        currentStart.year,
        currentStart.month,
        currentStart.day + 1,
        0,
        0,
      );

      bool crossesMidnight = end.isAfter(nextDayStart);

      DateTime segmentEnd;
      if (crossesMidnight) {
        // La disponibilité continue après minuit
        segmentEnd = nextDayStart;
      } else {
        // La disponibilité se termine ce jour
        segmentEnd = end;
      }

      segments.add({
        'day': DateTime(
          currentStart.year,
          currentStart.month,
          currentStart.day,
        ),
        'start': currentStart,
        'end': segmentEnd,
        'availability': availability,
        'isRealStart': isFirstSegment,
        'isRealEnd': !crossesMidnight,
      });

      isFirstSegment = false;
      currentStart = nextDayStart;
    }

    return segments;
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

  Color _barColorForType(BuildContext context, String? type) {
    final scheme = Theme.of(context).colorScheme;
    switch (type) {
      case 'replacer':
      case 'agent':
        return scheme.primary;
      case 'station':
      default:
        return scheme.primaryContainer;
    }
  }

  DateTime _timeFromLocalDx(double dx, double leftMargin, double totalWidth, DateTime day) {
    final clamped = (dx - leftMargin).clamp(0.0, totalWidth);
    final ratio = (totalWidth > 0) ? (clamped / totalWidth) : 0.0;
    final hourDouble = ratio * 24.0;
    final hour = hourDouble.floor();
    final minute = ((hourDouble - hour) * 60).round();
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  @override
  Widget build(BuildContext context) {
    final daysOfWeek = List.generate(
      7,
      (i) => currentWeekStartNotifier.value.add(Duration(days: i)),
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();

    return Scaffold(
      body: ValueListenableBuilder<bool>(
        valueListenable: stationViewNotifier,
        builder: (context, stationView, _) {
          return Column(
            children: [
              PlanningHeader(
                onWeekChanged: (dt) {
                  currentWeekStartNotifier.value = dt;
                  _loadUserAndPlanning();
                },
                availableTeams: _availableTeams,
              ),
              if (viewModeNotifier.value == ViewMode.month)
                _buildMonthView(stationView, isDark)
              else ...[
              const SizedBox(height: 8),
              // Time legend at top
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: ['0h', '6h', '12h', '18h', '24h']
                      .map((label) => Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade400,
                            ),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: RefreshIndicator(
                  color: KColors.appNameColor,
                  onRefresh: _loadUserAndPlanning,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 80),
                    child: Column(
                      children: daysOfWeek.map((currentDay) {
                        final dailyBars = _generateBarsForDay(currentDay);
                        final isToday = _isSameDay(currentDay, now);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    if (isToday)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          color: KColors.appNameColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    Text(
                                      _capitalizeFirst(DateFormat.EEEE('fr_FR').format(currentDay)),
                                      style: TextStyle(
                                        fontWeight: isToday
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        fontSize: 14,
                                        color: isToday
                                            ? KColors.appNameColor
                                            : Theme.of(context).colorScheme.tertiary,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      DateFormat('d MMM', 'fr_FR').format(currentDay),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.grey.shade500
                                            : Colors.grey.shade400,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: 38,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTapUp: (details) {
                                    final leftMargin = 16.0;
                                    final totalWidth = MediaQuery.of(context).size.width - (leftMargin * 2);
                                    final at = _timeFromLocalDx(details.localPosition.dx, leftMargin, totalWidth, currentDay);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PlanningTeamDetailsPage(at: at),
                                      ),
                                    );
                                  },
                                  onLongPressStart: (details) {
                                    final leftMargin = 16.0;
                                    final totalWidth = MediaQuery.of(context).size.width - (leftMargin * 2);
                                    final at = _timeFromLocalDx(details.localPosition.dx, leftMargin, totalWidth, currentDay);
                                    _showTooltip(at, details.globalPosition);
                                  },
                                  onLongPressMoveUpdate: (details) {
                                    final leftMargin = 16.0;
                                    final totalWidth = MediaQuery.of(context).size.width - (leftMargin * 2);
                                    final at = _timeFromLocalDx(details.localPosition.dx, leftMargin, totalWidth, currentDay);
                                    _updateTooltip(at, details.globalPosition);
                                  },
                                  onLongPressEnd: (details) {
                                    final leftMargin = 16.0;
                                    final totalWidth = MediaQuery.of(context).size.width - (leftMargin * 2);
                                    final at = _timeFromLocalDx(details.localPosition.dx, leftMargin, totalWidth, currentDay);
                                    Planning? planning;
                                    for (final bar in dailyBars) {
                                      final barStart = bar['start'] as DateTime;
                                      final barEnd = bar['end'] as DateTime;
                                      if (at.isAfter(barStart) && at.isBefore(barEnd)) {
                                        planning = bar['planning'] as Planning?;
                                        break;
                                      }
                                    }
                                    _showShiftDetails(at, planning);
                                  },
                                  child: Stack(
                                    children: [
                                      // Background container
                                      Container(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white.withValues(alpha: 0.04)
                                              : Colors.grey.shade50,
                                          border: Border.all(
                                            color: isDark
                                                ? Colors.white.withValues(alpha: 0.08)
                                                : Colors.grey.shade200,
                                          ),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                      // Planning bars
                                      for (final bar in dailyBars)
                                        PlanningBar(
                                          start: bar['start'],
                                          end: bar['end'],
                                          color:
                                              (bar['color'] as Color?) ??
                                              _barColorForType(
                                                context,
                                                bar['type'] as String?,
                                              ),
                                          isSubtle: true,
                                          showLeftBorder:
                                              bar['isRealStart'] ?? true,
                                          showRightBorder: bar['isRealEnd'] ?? true,
                                          isAvailability:
                                              bar['type'] == 'availability',
                                          onTap: (at) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    PlanningTeamDetailsPage(at: at),
                                              ),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              ], // fin else (vue semaine)
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // VUE MENSUELLE (grille calendrier)
  // ─────────────────────────────────────────────────────────

  Widget _buildMonthView(bool stationView, bool isDark) {
    if (_isMonthLoading) {
      return Expanded(
        child: Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: KColors.appNameColor,
            ),
          ),
        ),
      );
    }

    final month = currentMonthNotifier.value;

    // Filtrer les plannings du mois selon le mode et le filtre équipe
    List<Planning> plannings = _monthPlannings;
    if (stationView && selectedTeamNotifier.value != null) {
      plannings = plannings
          .where((p) => p.team == selectedTeamNotifier.value)
          .toList();
    } else if (!stationView && _currentUser != null) {
      plannings = plannings.where((p) {
        final isAgent = p.agentsId.contains(_currentUser!.id);
        return isAgent ||
            _subshifts.any(
              (s) => s.planningId == p.id && s.replacerId == _currentUser!.id,
            );
      }).toList();
    }

    return Expanded(
      child: _buildMonthGrid(month, plannings, isDark),
    );
  }

  Widget _buildMonthGrid(
      DateTime month, List<Planning> plannings, bool isDark) {
    final firstDay = DateTime(month.year, month.month, 1);
    final startOffset = firstDay.weekday - 1; // lundi = 0
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final totalCells = startOffset + daysInMonth;
    final rowCount = (totalCells / 7).ceil();
    final now = DateTime.now();
    const dayHeaders = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(left: 12, right: 12, top: 4, bottom: 80),
      child: Column(
        children: [
          // Header jours de la semaine
          Row(
            children: dayHeaders
                .map((h) => Expanded(
                      child: Center(
                        child: Text(
                          h,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          // Grille des jours
          for (int row = 0; row < rowCount; row++)
            Row(
              children: List.generate(7, (col) {
                final cellIndex = row * 7 + col;
                final dayNumber = cellIndex - startOffset + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const Expanded(child: SizedBox(height: 56));
                }
                final day = DateTime(month.year, month.month, dayNumber);
                final dayStart = DateTime(day.year, day.month, day.day);
                final dayEnd = DateTime(day.year, day.month, day.day + 1);
                final dayPlannings = plannings
                    .where((p) =>
                        p.endTime.isAfter(dayStart) &&
                        p.startTime.isBefore(dayEnd))
                    .toList();
                final isToday = day.year == now.year &&
                    day.month == now.month &&
                    day.day == now.day;
                return Expanded(
                  child: _buildMonthDayCell(
                      day, dayPlannings, isToday, isDark),
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildMonthDayCell(
    DateTime day,
    List<Planning> dayPlannings,
    bool isToday,
    bool isDark,
  ) {
    final dots = dayPlannings.take(3).map((p) {
      final color = _teamColorById[p.team] ?? Colors.grey.shade400;
      return Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }).toList();

    return GestureDetector(
      onTap: dayPlannings.isEmpty
          ? null
          : () => _showDayPlannings(day, dayPlannings, isDark),
      child: Container(
        margin: const EdgeInsets.all(2),
        height: 56,
        decoration: BoxDecoration(
          color: isToday
              ? KColors.appNameColor.withValues(alpha: 0.1)
              : (dayPlannings.isNotEmpty
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.grey.shade50)
                  : Colors.transparent),
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: KColors.appNameColor.withValues(alpha: 0.4))
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              day.day.toString(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                color: isToday
                    ? KColors.appNameColor
                    : (dayPlannings.isEmpty
                        ? (isDark
                            ? Colors.grey.shade600
                            : Colors.grey.shade400)
                        : null),
              ),
            ),
            if (dots.isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: dots),
            ],
          ],
        ),
      ),
    );
  }

  void _showDayPlannings(
      DateTime day, List<Planning> dayPlannings, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // En-tête avec date
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: KColors.appNameColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            day.day.toString(),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: KColors.appNameColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _capitalizeFirst(
                                DateFormat('EEEE', 'fr_FR').format(day)),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            DateFormat('d MMMM yyyy', 'fr_FR').format(day),
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${dayPlannings.length} astreinte${dayPlannings.length > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.grey.shade100,
                ),

                // Liste des plannings
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    children: dayPlannings.map((p) {
                      final teamColor =
                          _teamColorById[p.team] ?? Colors.grey.shade400;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PlanningTeamDetailsPage(at: p.startTime),
                                ),
                              );
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.04)
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.grey.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Barre de couleur latérale
                                  Container(
                                    width: 4,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: teamColor,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(14),
                                        bottomLeft: Radius.circular(14),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  // Contenu
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Équipe ${p.team}',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: teamColor,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          // Badge horaire style _DateTimeChip
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? Colors.white
                                                      .withValues(alpha: 0.06)
                                                  : Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.schedule_rounded,
                                                  size: 13,
                                                  color: isDark
                                                      ? Colors.grey.shade400
                                                      : Colors.grey.shade500,
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  _fmtDateTime(p.startTime),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color: isDark
                                                        ? Colors.grey.shade300
                                                        : Colors.grey.shade700,
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(horizontal: 5),
                                                  child: Icon(
                                                    Icons.arrow_forward_rounded,
                                                    size: 11,
                                                    color: isDark
                                                        ? Colors.grey.shade500
                                                        : Colors.grey.shade400,
                                                  ),
                                                ),
                                                Text(
                                                  _fmtDateTime(p.endTime),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color: isDark
                                                        ? Colors.grey.shade300
                                                        : Colors.grey.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Flèche de navigation
                                  Padding(
                                    padding: const EdgeInsets.only(right: 14),
                                    child: Icon(
                                      Icons.chevron_right_rounded,
                                      size: 20,
                                      color: isDark
                                          ? Colors.grey.shade600
                                          : Colors.grey.shade400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _fmtDateTime(DateTime dt) =>
      "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

  String _capitalizeFirst(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  /// Vérifie s'il existe une demande de remplacement active pour un planning donné
  Future<bool> _hasActiveReplacementRequest(Planning planning, String userId, String stationId) async {
    try {
      // Construire le chemin vers les demandes de remplacement
      final requestsPath = EnvironmentConfig.getCollectionPath(
          'replacements/automatic/replacementRequests', stationId);

      // Chercher les demandes de remplacement pour ce planning et cet utilisateur
      final snapshot = await FirebaseFirestore.instance
          .collection(requestsPath)
          .where('planningId', isEqualTo: planning.id)
          .where('requesterId', isEqualTo: userId)
          .where('status', whereIn: ['pending', 'accepted'])
          .get();

      // Vérifier s'il y a des demandes qui couvrent l'intégralité du planning
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final startTime = (data['startTime'] as Timestamp).toDate();
        final endTime = (data['endTime'] as Timestamp).toDate();

        // Vérifier si la demande couvre toute la période du planning
        if (!startTime.isAfter(planning.startTime) && !endTime.isBefore(planning.endTime)) {
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('Error checking active replacement requests: $e');
      return false;
    }
  }
}

/// Fonction helper pour convertir une couleur en shade400 (version plus douce)
Color _getShade400(Color color) {
  // Si c'est déjà un MaterialColor, utiliser shade400
  if (color is MaterialColor) {
    return color.shade400;
  }
  // Sinon, éclaircir la couleur en mélangeant avec du blanc
  return Color.lerp(color, Colors.white, 0.4) ?? color;
}

/// Widget d'infobulle flottante affichant l'heure sélectionnée
class _TooltipWidget extends StatelessWidget {
  final double positionX;
  final double containerTopY;
  final DateTime selectedTime;

  const _TooltipWidget({
    required this.positionX,
    required this.containerTopY,
    required this.selectedTime,
  });

  @override
  Widget build(BuildContext context) {
    final timeFormatted = DateFormat('HH:mm').format(selectedTime);

    // Décaler l'infobulle horizontalement pour la centrer sur le curseur
    // et la fixer verticalement 45px au-dessus du container de planning
    final offsetX = -30.0; // Centrer approximativement
    final offsetY = -45.0; // Au-dessus du container

    return Positioned(
      left: positionX + offsetX,
      top: containerTopY + offsetY,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              timeFormatted,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
