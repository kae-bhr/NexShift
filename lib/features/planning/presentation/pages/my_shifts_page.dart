import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/utils/constants.dart';

class MyShiftsPage extends StatefulWidget {
  const MyShiftsPage({super.key});

  @override
  State<MyShiftsPage> createState() => _MyShiftsPageState();
}

class _MyShiftsPageState extends State<MyShiftsPage> {
  bool _isLoading = true;
  List<Planning> _upcomingPlannings = [];
  List<Team> _teams = [];
  List<User> _allUsers = [];
  User? _currentUser;
  Map<String, bool> _expandedTeams = {}; // Track expanded state per team
  Map<String, bool> _expandedMonths =
      {}; // Track expanded state per team-month (teamId_year_month)
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
    initializeDateFormatting('fr_FR', null).then((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    _currentUser = await UserStorageHelper.loadUser();
    if (_currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }

    final repo = LocalRepository();
    final teamRepo = TeamRepository();

    // Charger les plannings de l'année sélectionnée pour la station de l'utilisateur
    final yearStart = DateTime(_selectedYear, 1, 1);
    final yearEnd = DateTime(_selectedYear, 12, 31, 23, 59, 59);
    final allPlannings = await repo.getPlanningsByStationInRange(
      _currentUser!.station,
      yearStart,
      yearEnd,
    );

    // Debug: Afficher le nombre de plannings chargés
    debugPrint(
      'DEBUG MyShiftsPage: ${allPlannings.length} plannings chargés pour l\'année $_selectedYear',
    );

    // Trier les plannings par date
    allPlannings.sort((a, b) => a.startTime.compareTo(b.startTime));

    // Charger les équipes de la station
    final teams = await teamRepo.getByStation(_currentUser!.station);

    // Charger les utilisateurs de la station
    final userRepo = UserRepository();
    final users = await userRepo.getByStation(_currentUser!.station);

    setState(() {
      _upcomingPlannings = allPlannings;
      _teams = teams;
      _allUsers = users;
      // Initialiser toutes les équipes comme pliées
      for (final team in teams) {
        _expandedTeams[team.id] = false;
      }
      _isLoading = false;
    });
  }

  void _changeYear(int delta) {
    setState(() {
      _selectedYear += delta;
      _expandedTeams.clear();
      _expandedMonths.clear();
    });
    _loadData();
  }

  bool _canManageTeam(String teamId) {
    if (_currentUser == null) return false;
    if (_currentUser!.admin) return true;
    if (_currentUser!.status == KConstants.statusLeader) return true;
    if (_currentUser!.status == KConstants.statusChief &&
        _currentUser!.team == teamId)
      return true;
    return false;
  }

  List<Planning> _getPlanningsForTeam(String teamId) {
    return _upcomingPlannings.where((p) => p.team == teamId).toList();
  }

  /// Groupe les plannings par mois/année
  Map<String, List<Planning>> _groupPlanningsByMonth(List<Planning> plannings) {
    final grouped = <String, List<Planning>>{};

    for (final planning in plannings) {
      final key =
          '${planning.startTime.year}-${planning.startTime.month.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(planning);
    }

    // Trier les plannings dans chaque groupe
    for (final list in grouped.values) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
    }

    return grouped;
  }

  String _getMonthYearLabel(String key) {
    final parts = key.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final date = DateTime(year, month);
    // Ne pas afficher l'année dans le label du mois
    return DateFormat('MMMM', 'fr_FR').format(date);
  }

  List<Team> _getVisibleTeams() {
    // Filtrer selon les droits
    if (_currentUser!.admin ||
        _currentUser!.status == KConstants.statusLeader) {
      return _teams..sort((a, b) => a.order.compareTo(b.order));
    } else if (_currentUser!.status == KConstants.statusChief) {
      return _teams.where((t) => t.id == _currentUser!.team).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Scaffold(
        appBar: CustomAppBar(
          title: Text(
            'Gestion des astreintes',
            style: TextStyle(color: Theme.of(context).primaryColor),
          ),
          bottomColor: KColors.appNameColor,
        ),
        body: const Center(
          child: Text('Vous devez être connecté pour accéder à cette page'),
        ),
      );
    }

    final visibleTeams = _getVisibleTeams();

    return Scaffold(
      appBar: CustomAppBar(
        title: Text(
          'Gestion des astreintes',
          style: TextStyle(color: Theme.of(context).primaryColor),
        ),
        bottomColor: KColors.appNameColor,
      ),
      body: Column(
        children: [
          // Sélecteur d'année
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeYear(-1),
                  tooltip: 'Année précédente',
                ),
                const SizedBox(width: 16),
                Text(
                  _selectedYear.toString(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _changeYear(1),
                  tooltip: 'Année suivante',
                ),
              ],
            ),
          ),
          // Liste des astreintes
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildTeamsList(visibleTeams),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamsList(List<Team> teams) {
    if (teams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Aucune équipe accessible',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: teams.length,
      itemBuilder: (context, index) {
        final team = teams[index];
        final plannings = _getPlanningsForTeam(team.id);
        final isExpanded = _expandedTeams[team.id] ?? false;

        return _buildTeamCard(team, plannings, isExpanded);
      },
    );
  }

  Widget _buildTeamCard(Team team, List<Planning> plannings, bool isExpanded) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Column(
        children: [
          // Header cliquable
          InkWell(
            onTap: () {
              setState(() {
                _expandedTeams[team.id] = !isExpanded;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: team.color.withOpacity(0.1),
                borderRadius: isExpanded
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      )
                    : BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: team.color,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        team.id,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          team.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${plannings.length} astreinte${plannings.length > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: team.color,
                  ),
                ],
              ),
            ),
          ),
          // Contenu déplié
          if (isExpanded) ...[
            if (plannings.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Aucune astreinte à venir',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              )
            else
              ..._buildMonthSections(team, plannings),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildMonthSections(Team team, List<Planning> plannings) {
    final groupedByMonth = _groupPlanningsByMonth(plannings);
    final sortedKeys = groupedByMonth.keys.toList()..sort();

    final widgets = <Widget>[];

    for (final monthKey in sortedKeys) {
      final monthPlannings = groupedByMonth[monthKey]!;
      final expandKey = '${team.id}_$monthKey';
      final isMonthExpanded = _expandedMonths[expandKey] ?? false;
      final monthLabel = _getMonthYearLabel(monthKey);

      // Header du mois
      widgets.add(
        InkWell(
          onTap: () {
            setState(() {
              _expandedMonths[expandKey] = !isMonthExpanded;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.grey[100],
            child: Row(
              children: [
                Icon(
                  isMonthExpanded ? Icons.expand_less : Icons.expand_more,
                  color: team.color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  monthLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: team.color,
                  ),
                ),
                const Spacer(),
                Text(
                  '${monthPlannings.length}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      );

      // Plannings du mois (si déplié)
      if (isMonthExpanded) {
        for (final planning in monthPlannings) {
          widgets.add(_buildPlanningTile(planning, team));
        }
      }

      // Divider entre les mois
      if (monthKey != sortedKeys.last) {
        widgets.add(const Divider(height: 1));
      }
    }

    return widgets;
  }

  Widget _buildPlanningTile(Planning planning, Team team) {
    final currentCount = planning.agentsId.length;
    final maxCount = planning.maxAgents;
    final now = DateTime.now();
    final isPast = planning.endTime.isBefore(now);
    final canManage = _canManageTeam(planning.team) && !isPast;

    // Déterminer la couleur selon la logique
    Color statusColor;
    IconData statusIcon;
    if (currentCount == maxCount) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (currentCount < maxCount) {
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
    } else {
      statusColor = Colors.red;
      statusIcon = Icons.error;
    }

    return ListTile(
      enabled: !isPast,
      leading: Icon(statusIcon, color: isPast ? Colors.grey : statusColor),
      title: Text(
        DateFormat('EEEE d MMMM', 'fr_FR').format(planning.startTime),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isPast ? Colors.grey : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.event, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Début: ${DateFormat('dd/MM HH:mm', 'fr_FR').format(planning.startTime)}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.event, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Fin: ${DateFormat('dd/MM HH:mm', 'fr_FR').format(planning.endTime)}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.group,
                size: 14,
                color: isPast ? Colors.grey : statusColor,
              ),
              const SizedBox(width: 4),
              Text(
                '$currentCount / $maxCount agents',
                style: TextStyle(
                  color: isPast ? Colors.grey : statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: canManage
          ? IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _editPlanning(planning, team),
            )
          : (isPast ? Icon(Icons.lock, color: Colors.grey[400]) : null),
      onTap: canManage ? () => _editPlanning(planning, team) : null,
    );
  }

  Future<void> _editPlanning(Planning planning, Team team) async {
    final result = await showDialog<Planning>(
      context: context,
      builder: (context) => _EditPlanningDialog(
        planning: planning,
        team: team,
        allUsers: _allUsers,
        allTeams: _teams,
      ),
    );

    if (result != null) {
      // Sauvegarder les modifications
      final planningRepo = PlanningRepository();
      await planningRepo.save(result);
      _loadData();
    }
  }
}

class _EditPlanningDialog extends StatefulWidget {
  final Planning planning;
  final Team team;
  final List<User> allUsers;
  final List<Team> allTeams;

  const _EditPlanningDialog({
    required this.planning,
    required this.team,
    required this.allUsers,
    required this.allTeams,
  });

  @override
  State<_EditPlanningDialog> createState() => _EditPlanningDialogState();
}

class _EditPlanningDialogState extends State<_EditPlanningDialog> {
  late List<String> _selectedAgents;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedAgents = List<String>.from(widget.planning.agentsId);
  }

  List<User> _getFilteredUsers() {
    final query = _searchQuery.toLowerCase();
    final filtered = widget.allUsers.where((user) {
      final fullName = '${user.firstName} ${user.lastName}'.toLowerCase();
      return fullName.contains(query);
    }).toList();

    // Séparer les agents de l'équipe et les autres
    final teamMembers = <User>[];
    final otherMembers = <User>[];

    for (final user in filtered) {
      if (user.team == widget.team.id) {
        teamMembers.add(user);
      } else {
        otherMembers.add(user);
      }
    }

    // Trier chaque groupe alphabétiquement (nom de famille puis prénom)
    teamMembers.sort((a, b) {
      final lastNameCompare = a.lastName.compareTo(b.lastName);
      if (lastNameCompare != 0) return lastNameCompare;
      return a.firstName.compareTo(b.firstName);
    });
    otherMembers.sort((a, b) {
      final lastNameCompare = a.lastName.compareTo(b.lastName);
      if (lastNameCompare != 0) return lastNameCompare;
      return a.firstName.compareTo(b.firstName);
    });

    // Retourner d'abord l'équipe, puis les autres
    return [...teamMembers, ...otherMembers];
  }

  @override
  Widget build(BuildContext context) {
    final hasOverflow = _selectedAgents.length > widget.planning.maxAgents;
    final filteredUsers = _getFilteredUsers();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: widget.team.color.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Éditer l\'astreinte',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.group, size: 16, color: Colors.grey[700]),
                      const SizedBox(width: 8),
                      Text(
                        widget.team.name,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.event, size: 16, color: Colors.grey[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Début: ${DateFormat('dd/MM HH:mm', 'fr_FR').format(widget.planning.startTime)}',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.event, size: 16, color: Colors.grey[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Fin: ${DateFormat('dd/MM HH:mm', 'fr_FR').format(widget.planning.endTime)}',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasOverflow
                          ? Colors.orange.withOpacity(0.1)
                          : Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: hasOverflow ? Colors.orange : Colors.green,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasOverflow ? Icons.warning : Icons.check_circle,
                          color: hasOverflow ? Colors.orange : Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_selectedAgents.length} / ${widget.planning.maxAgents} agents',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: hasOverflow ? Colors.orange : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Rechercher un agent',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
            // Liste des agents
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filteredUsers.length,
                itemBuilder: (context, index) {
                  final user = filteredUsers[index];
                  final isSelected = _selectedAgents.contains(user.id);
                  final isFromTeam = user.team == widget.team.id;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: isSelected ? 2 : 0,
                    color: isSelected
                        ? widget.team.color.withOpacity(0.05)
                        : Colors.grey[50],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected
                            ? widget.team.color
                            : Colors.grey[300]!,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: CheckboxListTile(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedAgents.add(user.id);
                          } else {
                            _selectedAgents.remove(user.id);
                          }
                        });
                      },
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      title: Text(
                        '${user.firstName} ${user.lastName}',
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Row(
                        children: [
                          Icon(
                            Icons.group,
                            size: 14,
                            color: isFromTeam
                                ? widget.team.color
                                : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isFromTeam
                                ? widget.team.name
                                : widget.allTeams.firstWhere(
                                    (t) => t.id == user.team,
                                    orElse: () => Team(
                                      id: user.team,
                                      name: 'Équipe ${user.team}',
                                      stationId: '',
                                      color: Colors.grey,
                                    ),
                                  ).name,
                            style: TextStyle(
                              color: isFromTeam
                                  ? widget.team.color
                                  : Colors.grey[600],
                              fontWeight: isFromTeam
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      secondary: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isFromTeam
                                ? [
                                    widget.team.color.withOpacity(0.7),
                                    widget.team.color,
                                  ]
                                : [Colors.grey[400]!, Colors.grey[600]!],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color:
                                        (isFromTeam
                                                ? widget.team.color
                                                : Colors.grey)
                                            .withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '${user.firstName[0]}${user.lastName[0]}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      activeColor: widget.team.color,
                      checkColor: Colors.white,
                    ),
                  );
                },
              ),
            ),
            // Actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final updated = widget.planning.copyWith(
                          agentsId: _selectedAgents,
                        );
                        Navigator.of(context).pop(updated);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.team.color,
                      ),
                      child: const Text('Enregistrer'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
