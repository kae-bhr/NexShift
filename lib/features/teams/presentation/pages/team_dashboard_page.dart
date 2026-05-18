import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:releve/core/data/models/planning_model.dart';
import 'package:releve/core/data/models/station_model.dart';
import 'package:releve/core/data/models/user_model.dart';
import 'package:releve/core/data/models/team_model.dart';
import 'package:releve/core/repositories/availability_repository.dart';
import 'package:releve/core/repositories/planning_repository.dart';
import 'package:releve/core/repositories/station_repository.dart';
import 'package:releve/core/repositories/user_repository.dart';
import 'package:releve/core/repositories/team_repository.dart';
import 'package:releve/core/data/datasources/sdis_context.dart';
import 'package:releve/core/utils/constants.dart';

// ---------------------------------------------------------------------------
// Entrées détaillées (pour le déroulé par colonne)
// ---------------------------------------------------------------------------

class _DutyEntry {
  final DateTime start;
  final DateTime end;
  final double hours;

  _DutyEntry({required this.start, required this.end, required this.hours});
}

class _ReplacementEntry {
  final DateTime start;
  final DateTime end;
  final double hours;
  final String replacedAgentName; // nom de l'agent remplacé

  _ReplacementEntry({
    required this.start,
    required this.end,
    required this.hours,
    required this.replacedAgentName,
  });
}

class _ReplacedEntry {
  final DateTime start;
  final DateTime end;
  final double hours;
  final String replacementAgentName; // nom du remplaçant

  _ReplacedEntry({
    required this.start,
    required this.end,
    required this.hours,
    required this.replacementAgentName,
  });
}

class _AbsenceEntry {
  final DateTime start;
  final DateTime end;
  final double hours;
  final String? label;

  _AbsenceEntry({
    required this.start,
    required this.end,
    required this.hours,
    this.label,
  });
}

class _AvailabilityEntry {
  final DateTime start;
  final DateTime end;
  final double hours;

  _AvailabilityEntry({
    required this.start,
    required this.end,
    required this.hours,
  });
}

// ---------------------------------------------------------------------------
// Modèle de stats par agent
// ---------------------------------------------------------------------------

class _AgentStats {
  final User agent;

  // Astreinte = titulaire non remplacé + remplacement intra-équipe
  double baseHours = 0;

  // Remplacé = remplacé par un agent d'une autre équipe (inter-équipe uniquement)
  double replacedHours = 0;

  // Remplaçant = remplace quelqu'un d'une autre équipe (inter-équipe uniquement)
  double replacementHours = 0;

  // Disponibilité = dispo hors planning de son équipe
  double availabilityHours = 0;

  // Absence = absent de l'effectif équipe OU remplacé intra OU dispo pendant planning équipe
  double absenceHours = 0;

  // Détail des astreintes (titulaire + remplaçant intra)
  final List<_DutyEntry> duties = [];

  // Détail des remplacements inter-équipe effectués
  final List<_ReplacementEntry> replacements = [];

  // Détail des créneaux remplacés par inter-équipe
  final List<_ReplacedEntry> replacedEntries = [];

  // Détail des absences
  final List<_AbsenceEntry> absences = [];

  // Détail des disponibilités hors planning équipe
  final List<_AvailabilityEntry> availabilities = [];

  // Heures réalisées = astreinte + remplaçant inter-équipe
  double get performedHours => baseHours + replacementHours;

  // Créneaux d'absence issus de plannings (pour éviter double-compte avec les dispos)
  final List<(DateTime, DateTime)> absenceSlots = [];

  _AgentStats({required this.agent});

  String get displayName {
    final fn = agent.firstName.trim();
    final ln = agent.lastName.trim();
    if (fn.isEmpty && ln.isEmpty) return 'Agent ${agent.id}';
    return '$fn $ln'.trim();
  }
}

enum _SortColumn {
  name,
  dutyHours,
  availabilityHours,
  absenceHours,
  replacementHours,
  replacedHours,
  activity,
}

enum _Period { currentWeek, currentMonth, custom }

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class TeamDashboardPage extends StatefulWidget {
  final User currentUser;

  const TeamDashboardPage({super.key, required this.currentUser});

  @override
  State<TeamDashboardPage> createState() => _TeamDashboardPageState();
}

class _TeamDashboardPageState extends State<TeamDashboardPage> {
  final _planningRepo = PlanningRepository();
  final _userRepo = UserRepository();
  final _teamRepo = TeamRepository();
  final _stationRepo = StationRepository();

  // --- Period ---
  _Period _period = _Period.currentMonth;
  late DateTime _startDate;
  late DateTime _endDate;

  // --- Team filter ---
  String? _selectedTeamId; // null = toutes
  Team? _selectedTeam;

  // --- Sort ---
  _SortColumn _sortColumn = _SortColumn.name;
  bool _sortAscending = true;

  // --- Data ---
  bool _loading = true;
  String? _error;
  List<_AgentStats> _stats = [];
  List<Team> _allTeams = [];
  Station? _station;

  // --- Scope résolu ---
  DashboardScope _scope = DashboardScope.station;

  // --- Expansion des lignes ---
  final Set<String> _expandedAgents = {};

  // --- Génération de chargement (anti-concurrence) ---
  int _loadGeneration = 0;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initPeriod();
    _load();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Résolution du scope d'accès
  // ---------------------------------------------------------------------------

  DashboardScope _resolveScope(Station? station) {
    final user = widget.currentUser;
    if (user.admin || user.status == KConstants.statusLeader) {
      return DashboardScope.station;
    }
    if (user.status == KConstants.statusChief) {
      return station?.dashboardChiefScope ?? DashboardScope.team;
    }
    return station?.dashboardAgentScope ?? DashboardScope.personal;
  }

  bool get _canChangeTeam => _scope == DashboardScope.station;

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  void _initPeriod() {
    final now = DateTime.now();
    switch (_period) {
      case _Period.currentWeek:
        final weekDay = now.weekday;
        _startDate = DateTime(now.year, now.month, now.day - (weekDay - 1));
        _endDate = _startDate.add(const Duration(days: 7));
      case _Period.currentMonth:
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 1);
      case _Period.custom:
        break;
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await SDISContext().ensureInitialized();
      final stationId = widget.currentUser.station;

      // Charger en parallèle station + users + teams + plannings
      final results = await Future.wait([
        _stationRepo.getById(stationId),
        _userRepo.getByStation(stationId),
        _teamRepo.getByStation(stationId),
        _planningRepo.getByStationInRange(stationId, _startDate, _endDate),
      ]);

      final station = results[0] as Station?;
      final users = results[1] as List<User>;
      final teams = results[2] as List<Team>;
      final plannings = results[3] as List<Planning>;

      // Résoudre scope et appliquer contraintes
      final scope = _resolveScope(station);

      // Forcer la sélection d'équipe selon le scope (seulement au premier chargement)
      if (_station == null) {
        // Premier chargement : initialiser _selectedTeamId selon scope
        if (scope == DashboardScope.team) {
          _selectedTeamId = widget.currentUser.team;
        } else if (scope == DashboardScope.personal) {
          _selectedTeamId = null;
        }
        // DashboardScope.station → conserver _selectedTeamId tel quel
      }

      // Résoudre l'équipe sélectionnée
      final teamId = _selectedTeamId;
      final resolvedTeam = teamId != null
          ? teams.where((t) => t.id == teamId).firstOrNull
          : null;

      // Agents à afficher selon scope
      final List<User> agentsToShow;
      if (scope == DashboardScope.personal) {
        agentsToShow = [widget.currentUser];
      } else if (teamId != null) {
        agentsToShow = users.where((u) => u.team == teamId).toList();
      } else {
        agentsToShow = users;
      }

      // Initialiser la map avec TOUS les agents de la station pour un calcul fidèle
      // (les remplacements inter-équipes sont ainsi correctement comptabilisés)
      final Map<String, _AgentStats> allStatsMap = {
        for (final u in users) u.id: _AgentStats(agent: u),
      };

      // Calculer les stats sur TOUS les plannings et TOUS les agents
      // On capture les bornes localement pour éviter toute mutation concurrente
      final rangeStart = _startDate;
      final rangeEnd = _endDate;
      for (final planning in plannings) {
        _processPlanningForStats(planning, allStatsMap, rangeStart, rangeEnd);
      }

      // Index des plannings par équipe (pour le croisement avec les disponibilités)
      final planningsByTeam = <String, List<Planning>>{};
      for (final p in plannings) {
        planningsByTeam.putIfAbsent(p.team, () => []).add(p);
      }

      // Charger les disponibilités pour tous les agents
      final availRepo = AvailabilityRepository(stationId: stationId);
      final availabilities = await availRepo.getInRange(_startDate, _endDate);
      for (final avail in availabilities) {
        final stats = allStatsMap[avail.agentId];
        if (stats == null) continue;
        final start = avail.start.isAfter(_startDate)
            ? avail.start
            : _startDate;
        final end = avail.end.isBefore(_endDate) ? avail.end : _endDate;
        if (!end.isAfter(start)) continue;

        // Chevauchement avec les plannings de l'équipe de l'agent
        final agentTeam = stats.agent.team;
        final teamPlannings = planningsByTeam[agentTeam] ?? [];
        double overlapH = 0;
        for (final p in teamPlannings) {
          final oStart = start.isAfter(p.startTime) ? start : p.startTime;
          final oEnd = end.isBefore(p.endTime) ? end : p.endTime;
          if (oEnd.isAfter(oStart)) {
            overlapH += oEnd.difference(oStart).inMinutes / 60.0;
          }
        }

        final availH = end.difference(start).inMinutes / 60.0;
        final netAvailH = (availH - overlapH).clamp(0.0, double.infinity);

        // Disponibilité hors planning d'équipe
        if (netAvailH > 0) {
          stats.availabilityHours += netAvailH;
          stats.availabilities.add(
            _AvailabilityEntry(start: start, end: end, hours: netAvailH),
          );
        }

        // Dispo pendant un planning d'équipe → Absence, sauf si déjà comptée
        // (remplacement intra ou absence totale déjà enregistrée via absenceSlots)
        if (overlapH > 0) {
          // Calculer la fraction réellement non encore comptabilisée
          double alreadyCounted = 0;
          for (final slot in stats.absenceSlots) {
            final oStart = start.isAfter(slot.$1) ? start : slot.$1;
            final oEnd = end.isBefore(slot.$2) ? end : slot.$2;
            if (oEnd.isAfter(oStart)) {
              alreadyCounted += oEnd.difference(oStart).inMinutes / 60.0;
            }
          }
          final newAbsenceH = (overlapH - alreadyCounted).clamp(
            0.0,
            double.infinity,
          );
          if (newAbsenceH > 0) {
            stats.absenceHours += newAbsenceH;
            stats.absences.add(
              _AbsenceEntry(
                start: start,
                end: end,
                hours: newAbsenceH,
                label: 'Disponibilité pendant planning équipe',
              ),
            );
          }
        }
      }

      // Trier toutes les listes de détail par date de début
      for (final s in allStatsMap.values) {
        s.duties.sort((a, b) => a.start.compareTo(b.start));
        s.replacements.sort((a, b) => a.start.compareTo(b.start));
        s.replacedEntries.sort((a, b) => a.start.compareTo(b.start));
        s.absences.sort((a, b) => a.start.compareTo(b.start));
        s.availabilities.sort((a, b) => a.start.compareTo(b.start));
      }

      // Filtrer pour l'affichage uniquement (après le calcul complet)
      final visibleIds = agentsToShow.map((u) => u.id).toSet();
      final sorted = allStatsMap.values
          .where((s) => visibleIds.contains(s.agent.id))
          .toList();
      _applySort(sorted);

      if (generation != _loadGeneration) return;
      setState(() {
        _station = station;
        _scope = scope;
        _allTeams = teams;
        _selectedTeam = resolvedTeam;
        _stats = sorted;
        _expandedAgents.clear();
        _loading = false;
      });
    } catch (e) {
      if (generation != _loadGeneration) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _processPlanningForStats(
    Planning planning,
    Map<String, _AgentStats> statsMap,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final pStart = planning.startTime.isAfter(rangeStart)
        ? planning.startTime
        : rangeStart;
    final pEnd = planning.endTime.isBefore(rangeEnd)
        ? planning.endTime
        : rangeEnd;
    if (!pEnd.isAfter(pStart)) return;
    final planningDurationH = pEnd.difference(pStart).inMinutes / 60.0;
    final planningTeam = planning.team;

    // Agents présents dans l'effectif (titulaires + remplaçants inter)
    final presentAgentIds = <String>{};
    // Agents remplacés intra-équipe → absence (avec la durée exacte du remplacement)
    final replacedIntraMap = <String, double>{}; // agentId → heures remplacées

    for (final pa in planning.agents) {
      final aStart = pa.start.isAfter(rangeStart) ? pa.start : rangeStart;
      final aEnd = pa.end.isBefore(rangeEnd) ? pa.end : rangeEnd;
      if (!aEnd.isAfter(aStart)) continue;
      final durationH = aEnd.difference(aStart).inMinutes / 60.0;

      final stats = statsMap[pa.agentId];
      if (stats == null) continue;

      if (pa.replacedAgentId == null) {
        // Titulaire standard
        presentAgentIds.add(pa.agentId);
        stats.baseHours += durationH;
        stats.duties.add(
          _DutyEntry(start: aStart, end: aEnd, hours: durationH),
        );
      } else {
        final replacedStats = statsMap[pa.replacedAgentId];
        final replacerTeam = stats.agent.team;
        final replacedTeam = replacedStats?.agent.team;
        final isIntra =
            replacerTeam == planningTeam && replacedTeam == planningTeam;

        if (isIntra) {
          // Remplacement intra-équipe : le remplaçant compte en Astreinte
          presentAgentIds.add(pa.agentId);
          stats.baseHours += durationH;
          stats.duties.add(
            _DutyEntry(start: aStart, end: aEnd, hours: durationH),
          );
          // L'agent remplacé accumule du temps d'absence (exact, pas toute la durée du planning)
          replacedIntraMap[pa.replacedAgentId!] =
              (replacedIntraMap[pa.replacedAgentId!] ?? 0) + durationH;
          // Détail pour l'agent remplacé (colonne Absence, pas Remplacé)
          final replacerName = stats.displayName;
          replacedStats?.absences.add(
            _AbsenceEntry(
              start: aStart,
              end: aEnd,
              hours: durationH,
              label: 'Remplacé par $replacerName',
            ),
          );
          replacedStats?.absenceSlots.add((aStart, aEnd));
        } else {
          // Remplacement inter-équipe : le remplaçant compte en Remplaçant
          presentAgentIds.add(pa.agentId);
          stats.replacementHours += durationH;
          final replacedName =
              replacedStats?.displayName ?? pa.replacedAgentId!;
          stats.replacements.add(
            _ReplacementEntry(
              start: aStart,
              end: aEnd,
              hours: durationH,
              replacedAgentName: replacedName,
            ),
          );
          // L'agent remplacé inter est considéré présent (colonne Remplacé)
          presentAgentIds.add(pa.replacedAgentId!);
          replacedStats?.replacedHours += durationH;
          replacedStats?.replacedEntries.add(
            _ReplacedEntry(
              start: aStart,
              end: aEnd,
              hours: durationH,
              replacementAgentName: stats.displayName,
            ),
          );
        }
      }
    }

    // Absences intra-équipe exactes (déjà ajoutées dans absences, on cumule juste le total)
    for (final entry in replacedIntraMap.entries) {
      final s = statsMap[entry.key];
      if (s != null) s.absenceHours += entry.value;
    }

    // Absences pour agents totalement absents du planning de leur équipe
    for (final entry in statsMap.entries) {
      final agent = entry.value.agent;
      if (agent.team != planningTeam) continue;
      if (presentAgentIds.contains(agent.id)) continue;
      if (replacedIntraMap.containsKey(agent.id)) continue; // déjà traité
      // Agent complètement absent du planning de son équipe
      entry.value.absenceHours += planningDurationH;
      entry.value.absences.add(
        _AbsenceEntry(start: pStart, end: pEnd, hours: planningDurationH),
      );
      entry.value.absenceSlots.add((pStart, pEnd));
    }
  }

  // ---------------------------------------------------------------------------
  // Sorting
  // ---------------------------------------------------------------------------

  void _applySort(List<_AgentStats> list) {
    list.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case _SortColumn.name:
          cmp = a.displayName.compareTo(b.displayName);
        case _SortColumn.dutyHours:
          cmp = a.baseHours.compareTo(b.baseHours);
        case _SortColumn.availabilityHours:
          cmp = a.availabilityHours.compareTo(b.availabilityHours);
        case _SortColumn.absenceHours:
          cmp = a.absenceHours.compareTo(b.absenceHours);
        case _SortColumn.replacementHours:
          cmp = a.replacementHours.compareTo(b.replacementHours);
        case _SortColumn.replacedHours:
          cmp = a.replacedHours.compareTo(b.replacedHours);
        case _SortColumn.activity:
          cmp = a.performedHours.compareTo(b.performedHours);
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  void _onSort(_SortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = column == _SortColumn.name;
      }
      _applySort(_stats);
    });
  }

  // ---------------------------------------------------------------------------
  // Period
  // ---------------------------------------------------------------------------

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null && mounted) {
      setState(() {
        _period = _Period.custom;
        _startDate = picked.start;
        _endDate = picked.end.add(const Duration(days: 1));
      });
      _load();
    }
  }

  void _onPeriodChanged(_Period p) {
    setState(() => _period = p);
    _initPeriod();
    _load();
  }

  void _onTeamChanged(String? teamId) {
    setState(() => _selectedTeamId = teamId);
    _load();
  }

  void _goToPrevious() {
    switch (_period) {
      case _Period.currentWeek:
        setState(() {
          _startDate = _startDate.subtract(const Duration(days: 7));
          _endDate = _endDate.subtract(const Duration(days: 7));
        });
        _load();
      case _Period.currentMonth:
        final prevStart = DateTime(_startDate.year, _startDate.month - 1, 1);
        setState(() {
          _startDate = prevStart;
          _endDate = DateTime(prevStart.year, prevStart.month + 1, 1);
        });
        _load();
      case _Period.custom:
        break;
    }
  }

  void _goToNext() {
    switch (_period) {
      case _Period.currentWeek:
        setState(() {
          _startDate = _startDate.add(const Duration(days: 7));
          _endDate = _endDate.add(const Duration(days: 7));
        });
        _load();
      case _Period.currentMonth:
        final nextStart = DateTime(_startDate.year, _startDate.month + 1, 1);
        setState(() {
          _startDate = nextStart;
          _endDate = DateTime(nextStart.year, nextStart.month + 1, 1);
        });
        _load();
      case _Period.custom:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------

  String _fmtH(double h) => h == 0 ? '—' : '${h.toStringAsFixed(1)} h';

  double _quotaForPeriod() {
    final quota = (_station?.shiftMonthlyQuota ?? 100).toDouble();
    final periodDays = _endDate.difference(_startDate).inDays;
    return quota * periodDays / 30.0;
  }

  String get _periodLabel {
    switch (_period) {
      case _Period.currentWeek:
        final end = _endDate.subtract(const Duration(days: 1));
        return '${DateFormat('dd/MM', 'fr_FR').format(_startDate)} – ${DateFormat('dd/MM', 'fr_FR').format(end)}';
      case _Period.currentMonth:
        return DateFormat('MMMM yyyy', 'fr_FR').format(_startDate);
      case _Period.custom:
        final end = _endDate.subtract(const Duration(days: 1));
        return '${DateFormat('dd/MM', 'fr_FR').format(_startDate)} – ${DateFormat('dd/MM', 'fr_FR').format(end)}';
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    final sidePadding = MediaQuery.paddingOf(context);
    return Scaffold(
      appBar: _buildAppBar(isDark, scheme, sidePadding),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError()
          : _stats.isEmpty
          ? _buildEmpty()
          : _buildTable(isDark, scheme, sidePadding),
    );
  }

  // ---------------------------------------------------------------------------
  // AppBar
  // ---------------------------------------------------------------------------

  AppBar _buildAppBar(bool isDark, ColorScheme scheme, EdgeInsets sidePadding) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: scheme.primary),
      titleSpacing: 0,
      title: Padding(
        padding: EdgeInsets.only(right: sidePadding.right),
        child: Row(
          children: [
            // ── Titre ─────────────────────────────────────────────
            Expanded(
              child: Text(
                _scope == DashboardScope.personal
                    ? 'Mes statistiques'
                    : (_selectedTeam?.name ?? 'Tableau de bord'),
                style: TextStyle(
                  color: _selectedTeam?.color ?? scheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(width: 8),

            // ── Sélecteur / badge équipe ──────────────────────────
            if (_canChangeTeam)
              _TeamSelectorButton(
                selectedTeam: _selectedTeam,
                allTeams: _allTeams,
                isDark: isDark,
                onChanged: _onTeamChanged,
              )
            else
              _TeamBadge(
                team: _scope == DashboardScope.personal ? null : _selectedTeam,
                isDark: isDark,
                label: _scope == DashboardScope.personal
                    ? 'Toutes les équipes'
                    : null,
              ),

            const SizedBox(width: 8),

            // ── Navigation période ─────────────────────────────────
            if (_period != _Period.custom) ...[
              _AppBarNavButton(
                icon: Icons.chevron_left_rounded,
                onTap: _goToPrevious,
                isDark: isDark,
                scheme: scheme,
              ),
              const SizedBox(width: 6),
              Text(
                _periodLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                ),
              ),
              const SizedBox(width: 6),
              _AppBarNavButton(
                icon: Icons.chevron_right_rounded,
                onTap: _goToNext,
                isDark: isDark,
                scheme: scheme,
              ),
              const SizedBox(width: 8),
            ] else ...[
              Text(
                _periodLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.purple.shade400,
                ),
              ),
              const SizedBox(width: 8),
            ],

            // ── Sélecteur période ──────────────────────────────────
            _DashboardPeriodButton(
              period: _period,
              isDark: isDark,
              onChanged: _onPeriodChanged,
              onCustomTap: _pickCustomRange,
            ),

            const SizedBox(width: 6),

            // ── Aide / règles d'affichage ──────────────────────────
            _RulesButton(isDark: isDark),

            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Table (header fixe + body scrollable)
  // ---------------------------------------------------------------------------

  Widget _buildTable(bool isDark, ColorScheme scheme, EdgeInsets sidePadding) {
    return Padding(
      padding: EdgeInsets.only(
        left: sidePadding.left,
        right: sidePadding.right,
      ),
      child: Column(
        children: [
          _buildTableHeader(isDark, scheme),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _stats.length + 1, // +1 pour footer
              itemBuilder: (ctx, i) {
                if (i < _stats.length) {
                  return _buildAgentRow(_stats[i], isDark, scheme);
                }
                return _buildFooter(isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(bool isDark, ColorScheme scheme) {
    final labelColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _SortableHeader(
              label: 'Agent',
              column: _SortColumn.name,
              current: _sortColumn,
              ascending: _sortAscending,
              color: labelColor,
              onSort: _onSort,
            ),
          ),
          Expanded(
            flex: 2,
            child: _SortableHeader(
              label: 'Astreinte',
              column: _SortColumn.dutyHours,
              current: _sortColumn,
              ascending: _sortAscending,
              color: labelColor,
              onSort: _onSort,
            ),
          ),
          Expanded(
            flex: 2,
            child: _SortableHeader(
              label: 'Disponibilité',
              column: _SortColumn.availabilityHours,
              current: _sortColumn,
              ascending: _sortAscending,
              color: labelColor,
              onSort: _onSort,
            ),
          ),
          Expanded(
            flex: 2,
            child: _SortableHeader(
              label: 'Absence',
              column: _SortColumn.absenceHours,
              current: _sortColumn,
              ascending: _sortAscending,
              color: labelColor,
              onSort: _onSort,
            ),
          ),
          Expanded(
            flex: 2,
            child: _SortableHeader(
              label: 'Remplaçant',
              column: _SortColumn.replacementHours,
              current: _sortColumn,
              ascending: _sortAscending,
              color: labelColor,
              onSort: _onSort,
            ),
          ),
          Expanded(
            flex: 2,
            child: _SortableHeader(
              label: 'Remplacé',
              column: _SortColumn.replacedHours,
              current: _sortColumn,
              ascending: _sortAscending,
              color: labelColor,
              onSort: _onSort,
            ),
          ),
          Expanded(
            flex: 2,
            child: _SortableHeader(
              label: 'Quota',
              column: _SortColumn.activity,
              current: _sortColumn,
              ascending: _sortAscending,
              color: labelColor,
              onSort: _onSort,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentRow(_AgentStats s, bool isDark, ColorScheme scheme) {
    final subtitleColor = Colors.grey.shade500;
    final teamColor = _allTeams
        .where((t) => t.id == s.agent.team)
        .firstOrNull
        ?.color;
    final isExpanded = _expandedAgents.contains(s.agent.id);
    final hasDuties =
        s.duties.isNotEmpty ||
        s.replacements.isNotEmpty ||
        s.replacedEntries.isNotEmpty ||
        s.absences.isNotEmpty ||
        s.availabilities.isNotEmpty;

    return Column(
      children: [
        InkWell(
          onTap: hasDuties
              ? () => setState(() {
                  if (isExpanded) {
                    _expandedAgents.remove(s.agent.id);
                  } else {
                    _expandedAgents.add(s.agent.id);
                  }
                })
              : null,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // ── Nom + pastille équipe + chevron ───────────────
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        if (teamColor != null)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: teamColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        if (hasDuties)
                          Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 14,
                            color: subtitleColor,
                          ),
                        if (hasDuties) const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            s.displayName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Astreinte (avec tooltip) ───────────────────────
                  Expanded(
                    flex: 2,
                    child: _DutyCell(
                      stats: s,
                      subtitleColor: subtitleColor,
                      scheme: scheme,
                    ),
                  ),

                  // ── Disponibilité ──────────────────────────────────
                  Expanded(
                    flex: 2,
                    child: Text(
                      _fmtH(s.availabilityHours),
                      style: TextStyle(
                        fontSize: 13,
                        color: s.availabilityHours > 0
                            ? Colors.blue.shade600
                            : subtitleColor,
                        fontWeight: s.availabilityHours > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // ── Absence ───────────────────────────────────────
                  Expanded(
                    flex: 2,
                    child: Text(
                      _fmtH(s.absenceHours),
                      style: TextStyle(
                        fontSize: 13,
                        color: s.absenceHours > 0
                            ? Colors.blueGrey.shade400
                            : subtitleColor,
                        fontWeight: s.absenceHours > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // ── Remplaçant ────────────────────────────────────
                  Expanded(
                    flex: 2,
                    child: Text(
                      _fmtH(s.replacementHours),
                      style: TextStyle(
                        fontSize: 13,
                        color: s.replacementHours > 0
                            ? Colors.teal.shade600
                            : subtitleColor,
                        fontWeight: s.replacementHours > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // ── Remplacé ──────────────────────────────────────
                  Expanded(
                    flex: 2,
                    child: Text(
                      _fmtH(s.replacedHours),
                      style: TextStyle(
                        fontSize: 13,
                        color: s.replacedHours > 0
                            ? Colors.orange.shade700
                            : subtitleColor,
                        fontWeight: s.replacedHours > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // ── Quota ─────────────────────────────────────────
                  Expanded(
                    flex: 2,
                    child: s.performedHours == 0
                        ? Text(
                            '—',
                            style: TextStyle(
                              fontSize: 13,
                              color: subtitleColor,
                            ),
                            textAlign: TextAlign.center,
                          )
                        : _ActivityBar(stats: s, quota: _quotaForPeriod()),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isExpanded) _buildDutyDetail(s, isDark, scheme),
      ],
    );
  }

  Widget _buildDutyDetail(_AgentStats s, bool isDark, ColorScheme scheme) {
    final bgColor = isDark ? Colors.grey.shade900 : Colors.grey.shade50;
    final textColor = isDark ? Colors.grey.shade300 : Colors.grey.shade700;
    final fmt = DateFormat('dd/MM HH:mm');
    final fmtEnd = DateFormat('HH:mm');

    // Construit une sous-ligne alignée sur les 7 colonnes du header
    Widget detailRow({
      required Color accent,
      required String label, // colonne Nom (créneau ou info)
      String? col1, // Astreinte
      String? col2, // Disponibilité
      String? col3, // Absence
      String? col4, // Remplaçant
      String? col5, // Remplacé
    }) {
      Widget cell(String? val, Color color) => Expanded(
        flex: 2,
        child: val == null
            ? const SizedBox()
            : Text(
                val,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
      );

      return GestureDetector(
        onLongPress: () {
          final overlay = Overlay.of(context);
          late OverlayEntry entry;
          entry = OverlayEntry(
            builder: (_) =>
                _TooltipOverlay(text: label, onDismiss: () => entry.remove()),
          );
          overlay.insert(entry);
        },
        child: Container(
          color: bgColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Container(
                        width: 2,
                        height: 14,
                        margin: const EdgeInsets.only(left: 8, right: 10),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(fontSize: 12, color: textColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                cell(col1, scheme.primary),
                cell(col2, Colors.blue.shade600),
                cell(col3, Colors.blueGrey.shade400),
                cell(col4, Colors.teal.shade600),
                cell(col5, Colors.orange.shade700),
                const Expanded(flex: 2, child: SizedBox()), // Quota
              ],
            ),
          ),
        ),
      );
    }

    String fmtSlot(DateTime start, DateTime end) =>
        '${fmt.format(start)} → ${fmtEnd.format(end)}';
    String fmtH(double h) => '${h.toStringAsFixed(1)} h';

    final rows = <Widget>[];

    // ── Astreintes titulaires (heures brutes) ────────────────────────────────
    for (final d in s.duties) {
      rows.add(
        detailRow(
          accent: scheme.primary,
          label: fmtSlot(d.start, d.end),
          col1: fmtH(d.hours),
        ),
      );
    }

    // ── Disponibilités ────────────────────────────────────────────────────────
    for (final a in s.availabilities) {
      rows.add(
        detailRow(
          accent: Colors.blue.shade600,
          label: fmtSlot(a.start, a.end),
          col2: fmtH(a.hours),
        ),
      );
    }

    // ── Absences ──────────────────────────────────────────────────────────────
    for (final a in s.absences) {
      final absLabel = a.label != null
          ? '${fmtSlot(a.start, a.end)} · ${a.label}'
          : fmtSlot(a.start, a.end);
      rows.add(
        detailRow(
          accent: Colors.blueGrey.shade400,
          label: absLabel,
          col3: fmtH(a.hours),
        ),
      );
    }

    // ── Remplaçant (agent remplacé par cet agent) ─────────────────────────────
    for (final r in s.replacements) {
      rows.add(
        detailRow(
          accent: Colors.teal.shade600,
          label: '${fmtSlot(r.start, r.end)} · ${r.replacedAgentName}',
          col4: fmtH(r.hours),
        ),
      );
    }

    // ── Remplacé (agent qui a remplacé cet agent) ─────────────────────────────
    for (final r in s.replacedEntries) {
      rows.add(
        detailRow(
          accent: Colors.orange.shade700,
          label: '${fmtSlot(r.start, r.end)} · ${r.replacementAgentName}',
          col5: fmtH(r.hours),
        ),
      );
    }

    return Column(children: rows);
  }

  Widget _buildFooter(bool isDark) {
    final totalDuty = _stats.fold<double>(0, (s, a) => s + a.baseHours);
    final totalAvail = _stats.fold<double>(
      0,
      (s, a) => s + a.availabilityHours,
    );
    final totalAbsence = _stats.fold<double>(0, (s, a) => s + a.absenceHours);
    final totalRepl = _stats.fold<double>(0, (s, a) => s + a.replacementHours);
    final totalReplaced = _stats.fold<double>(0, (s, a) => s + a.replacedHours);
    final color = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              '${_stats.length} agent${_stats.length > 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _fmtH(totalDuty),
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _fmtH(totalAvail),
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _fmtH(totalAbsence),
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _fmtH(totalRepl),
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _fmtH(totalReplaced),
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const Expanded(flex: 2, child: SizedBox()),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty / Error
  // ---------------------------------------------------------------------------

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Aucune donnée',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Aucun planning trouvé pour cette période.',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.help_outline_rounded,
              size: 48,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              'Erreur de chargement',
              style: TextStyle(fontSize: 16, color: Colors.red.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RulesButton — bouton d'aide affichant les règles de calcul
// ---------------------------------------------------------------------------

class _RulesButton extends StatelessWidget {
  final bool isDark;
  const _RulesButton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _showRules(context),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey.shade200,
          ),
        ),
        child: Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: scheme.primary,
        ),
      ),
    );
  }

  static void _showRules(BuildContext context) {
    showDialog(context: context, builder: (_) => const _RulesDialog());
  }
}

class _RulesDialog extends StatelessWidget {
  const _RulesDialog();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final bg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final titleColor = isDark ? Colors.grey.shade200 : Colors.grey.shade800;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    Widget rule({
      required IconData icon,
      required Color color,
      required String title,
      required String description,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: subtitleColor,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final screenH = MediaQuery.of(context).size.height;
    final lottieH = (screenH * 0.18).clamp(60.0, 100.0);

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screenH * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── En-tête Lottie + bouton fermer ──────────────────────────────
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: Stack(
                children: [
                  SizedBox(
                    height: lottieH,
                    width: double.infinity,
                    child: Lottie.asset(
                      'assets/lotties/question.json',
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: subtitleColor,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ),
            ),
            // ── Corps scrollable ─────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Règles de calcul',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Chaque heure appartient à une seule colonne.',
                      style: TextStyle(fontSize: 12, color: subtitleColor),
                    ),
                    const SizedBox(height: 16),
                    rule(
                      icon: Icons.shield_rounded,
                      color: scheme.primary,
                      title: 'Astreinte',
                      description:
                          'Titulaire non remplacé, OU remplaçant intra-équipe (coéquipier dans un planning de sa propre équipe).',
                    ),
                    rule(
                      icon: Icons.swap_horiz_rounded,
                      color: Colors.teal.shade600,
                      title: 'Remplaçant',
                      description:
                          'Remplace un agent d\'une autre équipe (inter-équipe uniquement).',
                    ),
                    rule(
                      icon: Icons.person_off_outlined,
                      color: Colors.orange.shade700,
                      title: 'Remplacé',
                      description:
                          'Remplacé par un agent d\'une autre équipe dans son propre planning.',
                    ),
                    rule(
                      icon: Icons.event_busy_rounded,
                      color: Colors.blueGrey.shade400,
                      title: 'Absence',
                      description:
                          '• Absent de l\'effectif de son équipe\n'
                          '• OU remplacé par un coéquipier (durée exacte)\n'
                          '• OU en disponibilité pendant un planning équipe',
                    ),
                    rule(
                      icon: Icons.volunteer_activism_rounded,
                      color: Colors.blue.shade600,
                      title: 'Disponibilité',
                      description:
                          'Disponibilité déclarée hors planning de son équipe.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _DutyCell — cellule Astreinte avec tooltip au long-press
// ---------------------------------------------------------------------------

class _DutyCell extends StatelessWidget {
  final _AgentStats stats;
  final Color subtitleColor;
  final ColorScheme scheme;

  const _DutyCell({
    required this.stats,
    required this.subtitleColor,
    required this.scheme,
  });

  String _tooltip() {
    return 'Astreinte (titulaire + intra) : ${stats.baseHours.toStringAsFixed(1)} h';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        final overlay = Overlay.of(context);
        late OverlayEntry entry;
        entry = OverlayEntry(
          builder: (_) => _TooltipOverlay(
            text: _tooltip(),
            onDismiss: () => entry.remove(),
          ),
        );
        overlay.insert(entry);
      },
      child: Text(
        stats.baseHours == 0 ? '—' : '${stats.baseHours.toStringAsFixed(1)} h',
        style: TextStyle(
          fontSize: 13,
          color: stats.baseHours > 0 ? scheme.primary : subtitleColor,
          fontWeight: stats.baseHours > 0 ? FontWeight.w600 : FontWeight.normal,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ActivityBar — barre avec overflow et tooltip au long press
// ---------------------------------------------------------------------------

class _ActivityBar extends StatelessWidget {
  final _AgentStats stats;
  final double quota; // quota proratisé sur la période

  const _ActivityBar({required this.stats, required this.quota});

  Color _baseColor(double rate) {
    if (rate >= 1.0) return Colors.green.shade600;
    if (rate >= 0.5) return Colors.orange.shade600;
    return Colors.red.shade600;
  }

  String _tooltip() {
    final performed = stats.performedHours;
    final pct = quota == 0 ? '—' : '${(performed / quota * 100).round()}%';
    return 'Astreinte : ${stats.baseHours.toStringAsFixed(1)} h\n'
        'Remplaçant : +${stats.replacementHours.toStringAsFixed(1)} h\n'
        'Total réalisé : ${performed.toStringAsFixed(1)} h\n'
        'Quota période : ${quota.toStringAsFixed(1)} h\n'
        'Ratio : $pct';
  }

  @override
  Widget build(BuildContext context) {
    final rate = quota == 0
        ? 0.0
        : (stats.performedHours / quota).clamp(0.0, 10.0);
    final baseColor = _baseColor(rate);
    final overflowRate = (rate - 1.0).clamp(0.0, 1.0);
    final baseRate = rate.clamp(0.0, 1.0);
    final hasOverflow = rate > 1.0;
    final pct = '${(rate * 100).round()}%';

    return GestureDetector(
      onLongPress: () {
        final overlay = Overlay.of(context);
        late OverlayEntry entry;
        entry = OverlayEntry(
          builder: (_) => _TooltipOverlay(
            text: _tooltip(),
            onDismiss: () => entry.remove(),
          ),
        );
        overlay.insert(entry);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pct,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: baseColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 5,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalW = constraints.maxWidth;
                return Stack(
                  children: [
                    Container(
                      width: totalW,
                      decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Container(
                      width: totalW * baseRate,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    if (hasOverflow)
                      Container(
                        width: totalW * overflowRate,
                        decoration: BoxDecoration(
                          color: Colors.green.shade800,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _TooltipOverlay
// ---------------------------------------------------------------------------

class _TooltipOverlay extends StatelessWidget {
  final String text;
  final VoidCallback onDismiss;

  const _TooltipOverlay({required this.text, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onDismiss,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey.shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: isDark ? Colors.grey.shade200 : Colors.grey.shade800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SortableHeader
// ---------------------------------------------------------------------------

class _SortableHeader extends StatelessWidget {
  final String label;
  final _SortColumn column;
  final _SortColumn current;
  final bool ascending;
  final Color color;
  final void Function(_SortColumn) onSort;

  const _SortableHeader({
    required this.label,
    required this.column,
    required this.current,
    required this.ascending,
    required this.color,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = current == column;
    return GestureDetector(
      onTap: () => onSort(column),
      child: Row(
        mainAxisAlignment: column == _SortColumn.name
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
              color: color,
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: 2),
            Icon(
              ascending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 11,
              color: color,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AppBarNavButton
// ---------------------------------------------------------------------------

class _AppBarNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;
  final ColorScheme scheme;

  const _AppBarNavButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey.shade200,
          ),
        ),
        child: Icon(icon, size: 18, color: scheme.primary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _DashboardPeriodButton
// ---------------------------------------------------------------------------

class _DashboardPeriodButton extends StatefulWidget {
  final _Period period;
  final bool isDark;
  final ValueChanged<_Period> onChanged;
  final VoidCallback onCustomTap;

  const _DashboardPeriodButton({
    required this.period,
    required this.isDark,
    required this.onChanged,
    required this.onCustomTap,
  });

  @override
  State<_DashboardPeriodButton> createState() => _DashboardPeriodButtonState();
}

class _DashboardPeriodButtonState extends State<_DashboardPeriodButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _closeOverlay();
    super.dispose();
  }

  void _closeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _openOverlay() {
    if (_overlayEntry != null) {
      _closeOverlay();
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenSize = MediaQuery.of(context).size;

    // ~3 options × 52px + padding
    const estimatedOverlayHeight = 3 * 52.0 + 16.0;
    final fitsBelow =
        offset.dy + size.height + 6 + estimatedOverlayHeight <=
        screenSize.height;
    final right = screenSize.width - (offset.dx + size.width);

    _overlayEntry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeOverlay,
              behavior: HitTestBehavior.opaque,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned(
            right: right,
            top: fitsBelow ? offset.dy + size.height + 6 : null,
            bottom: fitsBelow ? null : screenSize.height - offset.dy + 6,
            child: _PeriodDropdown(
              current: widget.period,
              isDark: widget.isDark,
              onClose: _closeOverlay,
              onChanged: (p) {
                if (p == _Period.custom) {
                  _closeOverlay();
                  widget.onCustomTap();
                } else {
                  widget.onChanged(p);
                  _closeOverlay();
                }
              },
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    IconData icon;
    switch (widget.period) {
      case _Period.currentWeek:
        icon = Icons.view_week_rounded;
      case _Period.currentMonth:
        icon = Icons.calendar_month_rounded;
      case _Period.custom:
        icon = Icons.date_range_rounded;
    }

    return GestureDetector(
      onTap: _openOverlay,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: widget.isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.shade200,
            ),
          ),
          child: Icon(icon, size: 18, color: scheme.primary),
        ),
      ),
    );
  }
}

class _PeriodDropdown extends StatelessWidget {
  final _Period current;
  final bool isDark;
  final VoidCallback onClose;
  final ValueChanged<_Period> onChanged;

  const _PeriodDropdown({
    required this.current,
    required this.isDark,
    required this.onClose,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 180,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PeriodRow(
                icon: Icons.view_week_rounded,
                label: 'Semaine courante',
                isSelected: current == _Period.currentWeek,
                isDark: isDark,
                onTap: () => onChanged(_Period.currentWeek),
              ),
              Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.grey.shade100,
              ),
              _PeriodRow(
                icon: Icons.calendar_month_rounded,
                label: 'Mois courant',
                isSelected: current == _Period.currentMonth,
                isDark: isDark,
                onTap: () => onChanged(_Period.currentMonth),
              ),
              Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.grey.shade100,
              ),
              _PeriodRow(
                icon: Icons.date_range_rounded,
                label: 'Période personnalisée',
                isSelected: current == _Period.custom,
                isDark: isDark,
                onTap: () => onChanged(_Period.custom),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _PeriodRow({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? scheme.primary : Colors.grey.shade500,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? scheme.primary
                      : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                ),
              ),
            ),
            if (isSelected) Icon(Icons.check, size: 14, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _TeamSelectorButton — dropdown interactif (pour station scope)
// ---------------------------------------------------------------------------

class _TeamSelectorButton extends StatefulWidget {
  final Team? selectedTeam;
  final List<Team> allTeams;
  final bool isDark;
  final ValueChanged<String?> onChanged;

  const _TeamSelectorButton({
    required this.selectedTeam,
    required this.allTeams,
    required this.isDark,
    required this.onChanged,
  });

  @override
  State<_TeamSelectorButton> createState() => _TeamSelectorButtonState();
}

class _TeamSelectorButtonState extends State<_TeamSelectorButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _closeOverlay();
    super.dispose();
  }

  void _closeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _openOverlay() {
    if (_overlayEntry != null) {
      _closeOverlay();
      return;
    }
    _overlayEntry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeOverlay,
              behavior: HitTestBehavior.opaque,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 62),
            child: Align(
              alignment: Alignment.topLeft,
              child: _TeamDropdown(
                allTeams: widget.allTeams,
                selectedTeam: widget.selectedTeam,
                isDark: widget.isDark,
                onClose: _closeOverlay,
                onChanged: widget.onChanged,
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final team = widget.selectedTeam;
    final Color bgColor;
    final Color borderColor;
    final Color contentColor;

    if (team != null) {
      bgColor = team.color.withValues(alpha: widget.isDark ? 0.25 : 0.15);
      borderColor = team.color.withValues(alpha: 0.4);
      contentColor = team.color;
    } else {
      bgColor = KColors.appNameColor.withValues(
        alpha: widget.isDark ? 0.2 : 0.12,
      );
      borderColor = KColors.appNameColor.withValues(alpha: 0.25);
      contentColor = KColors.appNameColor;
    }

    final Widget inner = team != null
        ? FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              team.id,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: contentColor,
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
          )
        : FittedBox(
            fit: BoxFit.scaleDown,
            child: Icon(Icons.groups_rounded, size: 20, color: contentColor),
          );

    return GestureDetector(
      onTap: _openOverlay,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Center(child: inner),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _TeamBadge — non-interactif (pour personal et team scope)
// ---------------------------------------------------------------------------

class _TeamBadge extends StatelessWidget {
  final Team? team;
  final bool isDark;
  final String? label; // libellé texte alternatif (pour mode personal)

  const _TeamBadge({required this.team, required this.isDark, this.label});

  @override
  Widget build(BuildContext context) {
    final color = team?.color ?? KColors.appNameColor;
    Widget child;
    if (label != null) {
      // Mode personal : icône groupes + label "Toutes les équipes"
      child = Icon(Icons.groups_rounded, size: 18, color: color);
    } else if (team != null) {
      child = FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          team!.id,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: -0.5,
            height: 1,
          ),
        ),
      );
    } else {
      child = Icon(Icons.groups_rounded, size: 18, color: color);
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.25 : 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Center(child: child),
    );
  }
}

// ---------------------------------------------------------------------------
// _TeamDropdown
// ---------------------------------------------------------------------------

class _TeamDropdown extends StatelessWidget {
  final List<Team> allTeams;
  final Team? selectedTeam;
  final bool isDark;
  final VoidCallback onClose;
  final ValueChanged<String?> onChanged;

  const _TeamDropdown({
    required this.allTeams,
    required this.selectedTeam,
    required this.isDark,
    required this.onClose,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedTeamId = selectedTeam?.id;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // "Toutes les équipes"
              _DropdownRow(
                isDark: isDark,
                isSelected: selectedTeamId == null,
                onTap: () {
                  onChanged(null);
                  onClose();
                },
                leading: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: selectedTeamId == null
                        ? KColors.appNameColor.withValues(alpha: 0.15)
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.grey.shade100),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.group_rounded,
                    size: 15,
                    color: selectedTeamId == null
                        ? KColors.appNameColor
                        : (isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade500),
                  ),
                ),
                label: 'Toutes les équipes',
                labelColor: selectedTeamId == null
                    ? KColors.appNameColor
                    : null,
                checkColor: KColors.appNameColor,
              ),
              if (allTeams.isNotEmpty)
                Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.grey.shade100,
                ),
              ...allTeams.map((t) {
                final isSel = selectedTeamId == t.id;
                return _DropdownRow(
                  isDark: isDark,
                  isSelected: isSel,
                  onTap: () {
                    onChanged(isSel ? null : t.id);
                    onClose();
                  },
                  leading: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isSel
                          ? t.color.withValues(alpha: 0.15)
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.grey.shade100),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        t.id,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isSel
                              ? t.color
                              : (isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade500),
                        ),
                      ),
                    ),
                  ),
                  label: t.name,
                  labelColor: isSel ? t.color : null,
                  checkColor: t.color,
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget leading;
  final String label;
  final Color? labelColor;
  final Color checkColor;

  const _DropdownRow({
    required this.isDark,
    required this.isSelected,
    required this.onTap,
    required this.leading,
    required this.label,
    this.labelColor,
    required this.checkColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color:
                      labelColor ??
                      (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected) Icon(Icons.check, size: 14, color: checkColor),
          ],
        ),
      ),
    );
  }
}
