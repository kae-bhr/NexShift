import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/availability_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/repositories/availability_repository.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/repositories/station_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/utils/constants.dart';

// ---------------------------------------------------------------------------
// Modèle de stats par agent
// ---------------------------------------------------------------------------

class _AgentStats {
  final User agent;

  // Heures en tant que titulaire (PlanningAgent sans replacedAgentId)
  // Inclut : garde standard, ajout d'agent (AgentQuery)
  double baseHours = 0;

  // Heures où l'agent a été remplacé par quelqu'un d'autre
  double replacedHours = 0;

  // Astreinte nette = baseHours - replacedHours (plancher 0)
  double get dutyHours =>
      (baseHours - replacedHours).clamp(0.0, double.infinity);

  // Heures de remplacement effectuées (remplacement classique + échanges)
  double replacementHours = 0;

  // Heures de disponibilité déclarées
  double availabilityHours = 0;

  // Heures de planning d'équipe auxquelles l'agent était absent
  double absenceHours = 0;

  // Ratio (dutyHours + replacementHours) / (dutyHours + replacedHours)
  double get activityRate {
    final numerator = dutyHours + replacementHours;
    final denominator = dutyHours + replacedHours;
    if (denominator == 0) return numerator > 0 ? double.infinity : 0;
    return (numerator / denominator).clamp(0.0, 10.0);
  }

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

      // Initialiser la map des stats (TOUS les agents à afficher)
      final Map<String, _AgentStats> statsMap = {
        for (final u in agentsToShow) u.id: _AgentStats(agent: u),
      };

      // Calculer les stats sur TOUS les plannings (pas seulement l'équipe filtrée)
      for (final planning in plannings) {
        _processPlanningForStats(planning, statsMap);
      }

      // Charger les disponibilités
      final availRepo = AvailabilityRepository(stationId: stationId);
      final availabilities = await availRepo.getInRange(_startDate, _endDate);
      for (final avail in availabilities) {
        final stats = statsMap[avail.agentId];
        if (stats == null) continue;
        final start = avail.start.isAfter(_startDate)
            ? avail.start
            : _startDate;
        final end = avail.end.isBefore(_endDate) ? avail.end : _endDate;
        if (end.isAfter(start)) {
          stats.availabilityHours += end.difference(start).inMinutes / 60.0;
        }
      }

      final sorted = statsMap.values.toList();
      _applySort(sorted);

      setState(() {
        _station = station;
        _scope = scope;
        _allTeams = teams;
        _selectedTeam = resolvedTeam;
        _stats = sorted;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _processPlanningForStats(
    Planning planning,
    Map<String, _AgentStats> statsMap,
  ) {
    final planningDurationH =
        planning.endTime.difference(planning.startTime).inMinutes / 60.0;
    final presentAgentIds = <String>{};

    for (final pa in planning.agents) {
      final durationH = pa.end.difference(pa.start).inMinutes / 60.0;
      final stats = statsMap[pa.agentId];
      if (stats == null) continue;

      presentAgentIds.add(pa.agentId);

      if (pa.replacedAgentId == null) {
        // Titulaire de base
        stats.baseHours += durationH;
      } else {
        // Remplaçant (remplacement classique ou échange — traitement identique)
        stats.replacementHours += durationH;
        statsMap[pa.replacedAgentId]?.replacedHours += durationH;
      }
    }

    // Absences : agents de l'équipe du planning absents de ce planning
    for (final entry in statsMap.entries) {
      final agent = entry.value.agent;
      if (agent.team == planning.team && !presentAgentIds.contains(agent.id)) {
        entry.value.absenceHours += planningDurationH;
      }
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
          cmp = a.dutyHours.compareTo(b.dutyHours);
        case _SortColumn.availabilityHours:
          cmp = a.availabilityHours.compareTo(b.availabilityHours);
        case _SortColumn.absenceHours:
          cmp = a.absenceHours.compareTo(b.absenceHours);
        case _SortColumn.replacementHours:
          cmp = a.replacementHours.compareTo(b.replacementHours);
        case _SortColumn.replacedHours:
          cmp = a.replacedHours.compareTo(b.replacedHours);
        case _SortColumn.activity:
          cmp = a.activityRate.compareTo(b.activityRate);
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
        setState(() {
          _startDate = DateTime(_startDate.year, _startDate.month - 1, 1);
          _endDate = DateTime(_startDate.year, _startDate.month + 1, 1);
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
        setState(() {
          _startDate = DateTime(_startDate.year, _startDate.month + 1, 1);
          _endDate = DateTime(_startDate.year, _startDate.month + 2, 1);
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

    return Scaffold(
      appBar: _buildAppBar(isDark, scheme),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError()
          : _stats.isEmpty
          ? _buildEmpty()
          : _buildTable(isDark, scheme),
    );
  }

  // ---------------------------------------------------------------------------
  // AppBar
  // ---------------------------------------------------------------------------

  AppBar _buildAppBar(bool isDark, ColorScheme scheme) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: scheme.primary),
      titleSpacing: 0,
      title: Row(
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

          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Table (header fixe + body scrollable)
  // ---------------------------------------------------------------------------

  Widget _buildTable(bool isDark, ColorScheme scheme) {
    return Column(
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
              label: 'Activité',
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

    return Container(
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
            // ── Nom + pastille équipe ──────────────────────────────
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

            // ── Astreinte (avec tooltip) ───────────────────────────
            Expanded(
              flex: 2,
              child: _DutyCell(
                stats: s,
                subtitleColor: subtitleColor,
                scheme: scheme,
              ),
            ),

            // ── Disponibilité ──────────────────────────────────────
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

            // ── Absence ───────────────────────────────────────────
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

            // ── Remplaçant ────────────────────────────────────────
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

            // ── Remplacé ──────────────────────────────────────────
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

            // ── Activité ──────────────────────────────────────────
            Expanded(
              flex: 2,
              child: s.dutyHours == 0 && s.replacementHours == 0
                  ? Text(
                      '—',
                      style: TextStyle(fontSize: 13, color: subtitleColor),
                      textAlign: TextAlign.center,
                    )
                  : _ActivityBar(stats: s),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    final totalDuty = _stats.fold<double>(0, (s, a) => s + a.dutyHours);
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
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
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
    return 'Titulaire : ${stats.baseHours.toStringAsFixed(1)} h\n'
        'Remplacé : −${stats.replacedHours.toStringAsFixed(1)} h\n'
        'Net : ${stats.dutyHours.toStringAsFixed(1)} h';
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
        stats.dutyHours == 0 ? '—' : '${stats.dutyHours.toStringAsFixed(1)} h',
        style: TextStyle(
          fontSize: 13,
          color: stats.dutyHours > 0 ? scheme.primary : subtitleColor,
          fontWeight: stats.dutyHours > 0 ? FontWeight.w600 : FontWeight.normal,
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

  const _ActivityBar({required this.stats});

  Color _baseColor(double rate) {
    if (rate >= 1.0) return Colors.green.shade600;
    if (rate >= 0.5) return Colors.orange.shade600;
    return Colors.red.shade600;
  }

  String _tooltip() {
    final duty = stats.dutyHours;
    final repl = stats.replacementHours;
    final replaced = stats.replacedHours;
    final pct = duty == 0 ? '—' : '${(stats.activityRate * 100).round()}%';
    return 'Astreinte : ${duty.toStringAsFixed(1)} h\n'
        'Remplaçant : +${repl.toStringAsFixed(1)} h\n'
        'Remplacé : −${replaced.toStringAsFixed(1)} h\n'
        'Ratio : $pct';
  }

  @override
  Widget build(BuildContext context) {
    final rate = stats.activityRate;
    final baseColor = _baseColor(rate);
    final overflowRate = (rate - 1.0).clamp(0.0, 1.0);
    final baseRate = rate.clamp(0.0, 1.0);
    final hasOverflow = rate > 1.0;
    final pct = stats.dutyHours == 0 && stats.replacementHours > 0
        ? '∞'
        : '${(rate * 100).round()}%';

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
    final fitsBelow = offset.dy + size.height + 6 + estimatedOverlayHeight <= screenSize.height;
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
          width: 46,
          height: 56,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
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
      child = Icon(Icons.groups_rounded, size: 20, color: color);
    } else if (team != null) {
      child = Text(
        team!.id,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      );
    } else {
      child = Icon(Icons.groups_rounded, size: 20, color: color);
    }

    return Container(
      width: 46,
      height: 56,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.25 : 0.15),
        borderRadius: BorderRadius.circular(10),
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
