import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/position_model.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/repositories/position_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/utils/design_system.dart';
import 'package:nexshift_app/features/skills/presentation/pages/skills_page.dart';
import 'package:nexshift_app/core/presentation/widgets/error_widget.dart'
    as custom;
import 'package:nexshift_app/core/presentation/widgets/skeleton_loader.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';

class TeamPage extends StatefulWidget {
  final String? teamId;

  const TeamPage({super.key, this.teamId});

  @override
  State<TeamPage> createState() => _TeamPageState();
}

enum TeamViewMode { rolesBased, positionsBased, skillsBased }

class _TeamPageState extends State<TeamPage> {
  final PositionRepository _positionRepo = PositionRepository();
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  String? _error;
  List<User> _teamUsers = [];
  List<User> _filteredUsers = [];
  List<Position> _positions = [];
  String _teamId = '';
  String _teamName = 'Équipe';
  Color? _teamColor;
  String _searchQuery = '';
  TeamViewMode _viewMode = TeamViewMode.rolesBased;
  bool _showAllStaff = false;
  Map<String, Color> _teamColors = {};

  // Collapse / expand state
  Map<String, bool> _expandedSections = {};

  bool get _allExpanded =>
      _expandedSections.isEmpty || _expandedSections.values.every((v) => v);

  void _toggleAllExpanded() {
    final expand = !_allExpanded;
    setState(() {
      for (final key in _expandedSections.keys) {
        _expandedSections[key] = expand;
      }
    });
  }

  void _initSectionsForView(TeamViewMode mode) {
    final Map<String, bool> sections = {};
    switch (mode) {
      case TeamViewMode.rolesBased:
        sections['leaders'] = true;
        sections['agents'] = true;
      case TeamViewMode.positionsBased:
        for (final p in _positions) {
          sections[p.id] = true;
        }
        sections['no_position'] = true;
      case TeamViewMode.skillsBased:
        for (final cat in KSkills.skillCategoryOrder) {
          sections[cat] = false;
          final levels = KSkills.skillLevels[cat] ?? [];
          for (final skill in levels) {
            if (skill.isNotEmpty) sections['$cat::$skill'] = false;
          }
        }
    }
    _expandedSections = sections;
  }

  @override
  void initState() {
    super.initState();
    _teamId = widget.teamId ?? userNotifier.value?.team ?? '';
    _init();
    teamDataChangedNotifier.addListener(_onTeamDataChanged);
    userNotifier.addListener(_onUserChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    teamDataChangedNotifier.removeListener(_onTeamDataChanged);
    userNotifier.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onTeamDataChanged() => _init();

  void _onUserChanged() {
    final newTeamId = userNotifier.value?.team;
    if (newTeamId != null && newTeamId != _teamId) {
      setState(() => _teamId = newTeamId);
      _init();
    }
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final stationId = userNotifier.value?.station;
      if (stationId == null) throw Exception('User station is null');

      final users = await UserRepository().getByStation(stationId);
      final teams = await TeamRepository().getByStation(stationId);

      final colorsMap = <String, Color>{};
      for (final t in teams) {
        colorsMap[t.id] = t.color;
      }

      final List<User> filtered;
      if (_showAllStaff) {
        filtered = List<User>.from(users)
          ..sort((a, b) => a.lastName.compareTo(b.lastName));
      } else {
        filtered = users.where((u) => u.team == _teamId).toList()
          ..sort((a, b) => a.lastName.compareTo(b.lastName));
      }

      final team = _showAllStaff
          ? null
          : await TeamRepository().getById(_teamId, stationId: stationId);

      final positions = await _positionRepo
          .getPositionsByStation(stationId)
          .first;

      setState(() {
        _teamUsers = filtered;
        _filteredUsers = filtered;
        _positions = positions;
        _teamColors = colorsMap;
        _teamName = _showAllStaff
            ? 'Effectif complet'
            : (team?.name ?? 'Équipe $_teamId');
        _teamColor = _showAllStaff ? KColors.appNameColor : team?.color;
        _loading = false;
      });
      _initSectionsForView(_viewMode);
      _applySearch();
    } catch (e) {
      setState(() {
        _error = KErrorMessages.loadingError;
        _loading = false;
      });
    }
  }

  void _applySearch() {
    if (_searchQuery.isEmpty) {
      setState(() => _filteredUsers = _teamUsers);
    } else {
      final query = _searchQuery.toLowerCase();
      setState(() {
        _filteredUsers = _teamUsers.where((user) {
          return user.displayName.toLowerCase().contains(query);
        }).toList();
      });
    }
  }

  Color _getTextColorForBackground(Color bg) {
    return bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }


  @override
  Widget build(BuildContext context) {
    final accent = _teamColor ?? Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: CustomAppBar(
        title: _teamName,
        onTitleTap: () => _showTeamPicker(context),
        bottomColor: accent,
        actions: [
          _ViewModeButton(
            currentMode: _viewMode,
            accent: accent,
            onModeChanged: (mode) {
              HapticFeedback.lightImpact();
              setState(() {
                _viewMode = mode;
                _initSectionsForView(mode);
              });
            },
          ),
        ],
      ),
      body: _loading
          ? const TeamPageSkeleton()
          : _error != null
          ? custom.ErrorWidget(message: _error, onRetry: _init)
          : RefreshIndicator(onRefresh: _init, child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_viewMode) {
      case TeamViewMode.rolesBased:
        return _buildRolesView(context);
      case TeamViewMode.positionsBased:
        return _buildPositionsView(context);
      case TeamViewMode.skillsBased:
        return _buildSkillsView(context);
    }
  }

  // ── Barre de recherche commune ──────────────────────────────────────────────
  Widget _buildSearchBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 18,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _applySearch();
              },
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade200 : Colors.grey.shade800,
              ),
              decoration: InputDecoration(
                hintText: 'Rechercher un agent...',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade500,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
                _applySearch();
              },
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
              ),
            ),
        ],
      ),
    );
  }

  // ── Stats badge ─────────────────────────────────────────────────────────────
  Widget _buildStatsBadge(
    BuildContext context, {
    required _StatData col1,
    required _StatData col2,
    _StatData? col3,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _teamColor ?? Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.25 : 0.18),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatItem(
              icon: col1.icon,
              value: col1.value,
              label: col1.label,
              color: accent,
            ),
          ),
          Container(
            width: 1,
            height: 28,
            color: accent.withValues(alpha: 0.20),
          ),
          Expanded(
            child: _StatItem(
              icon: col2.icon,
              value: col2.value,
              label: col2.label,
              color: accent,
            ),
          ),
          if (col3 != null) ...[
            Container(
              width: 1,
              height: 28,
              color: accent.withValues(alpha: 0.20),
            ),
            Expanded(
              child: _StatItem(
                icon: col3.icon,
                value: col3.value,
                label: col3.label,
                color: accent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Header collapse/expand ──────────────────────────────────────────────────
  Widget _buildCollapseHeader(BuildContext context, String countLabel) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              countLabel,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _toggleAllExpanded,
            icon: Icon(
              _allExpanded
                  ? Icons.unfold_less_rounded
                  : Icons.unfold_more_rounded,
              size: 16,
            ),
            label: Text(
              _allExpanded ? 'Tout réduire' : 'Tout déplier',
              style: const TextStyle(fontSize: 12),
            ),
            style: TextButton.styleFrom(
              foregroundColor: KColors.appNameColor,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section header collapsible ───────────────────────────────────────────────
  Widget _buildCollapsibleSectionHeader(
    BuildContext context,
    String label,
    IconData icon,
    int count,
    bool isExpanded,
    VoidCallback onTap,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _teamColor ?? Theme.of(context).colorScheme.primary;
    final textColor = isDark ? Colors.grey.shade300 : Colors.grey.shade700;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: accent.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: textColor,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 1,
                color: accent.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              isExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 18,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  // ── Vue par rôles ───────────────────────────────────────────────────────────
  Widget _buildRolesView(BuildContext context) {
    final leaders =
        _filteredUsers
            .where(
              (u) =>
                  u.status == KConstants.statusLeader ||
                  u.status == KConstants.statusChief,
            )
            .toList()
          ..sort((a, b) => a.lastName.compareTo(b.lastName));
    final agents =
        _filteredUsers.where((u) => u.status == KConstants.statusAgent).toList()
          ..sort((a, b) => a.lastName.compareTo(b.lastName));

    final isLeadersExpanded = _expandedSections['leaders'] ?? true;
    final isAgentsExpanded = _expandedSections['agents'] ?? true;

    final total = _filteredUsers.length;
    final countLabel =
        '${leaders.length} chef${leaders.length > 1 ? 's' : ''} · ${agents.length} agent${agents.length > 1 ? 's' : ''}';

    return Column(
      children: [
        _buildSearchBar(context),
        if (_searchQuery.isEmpty)
          _buildStatsBadge(
            context,
            col1: _StatData(
              icon: Icons.groups_rounded,
              value: '$total',
              label: 'Total',
            ),
            col2: _StatData(
              icon: Icons.shield_moon_rounded,
              value: '${leaders.length}',
              label: 'Chefs',
            ),
            col3: _StatData(
              icon: Icons.person_rounded,
              value: '${agents.length}',
              label: 'Agents',
            ),
          ),
        _buildCollapseHeader(context, countLabel),
        Expanded(
          child: _filteredUsers.isEmpty
              ? custom.EmptyStateWidget(
                  message: _searchQuery.isEmpty
                      ? 'Aucun membre dans cette équipe'
                      : 'Aucun résultat pour "$_searchQuery"',
                  icon: _searchQuery.isEmpty
                      ? Icons.group_off
                      : Icons.search_off,
                )
              : ListView(
                  children: [
                    if (leaders.isNotEmpty) ...[
                      _buildCollapsibleSectionHeader(
                        context,
                        'Chef de garde',
                        Icons.shield_moon_rounded,
                        leaders.length,
                        isLeadersExpanded,
                        () => setState(
                          () =>
                              _expandedSections['leaders'] = !isLeadersExpanded,
                        ),
                      ),
                      if (isLeadersExpanded)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: leaders
                                .map(
                                  (u) => _buildUserTile(
                                    context,
                                    u,
                                    isLeader: true,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                    ],
                    if (agents.isNotEmpty) ...[
                      _buildCollapsibleSectionHeader(
                        context,
                        'Agents',
                        Icons.groups_rounded,
                        agents.length,
                        isAgentsExpanded,
                        () => setState(
                          () => _expandedSections['agents'] = !isAgentsExpanded,
                        ),
                      ),
                      if (isAgentsExpanded)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: agents
                                .map((u) => _buildUserTile(context, u))
                                .toList(),
                          ),
                        ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
        ),
      ],
    );
  }

  // ── Vue par postes ──────────────────────────────────────────────────────────
  Widget _buildPositionsView(BuildContext context) {
    final usersByPosition = <String?, List<User>>{};
    for (final user in _filteredUsers) {
      if (user.positionIds.isEmpty) {
        usersByPosition.putIfAbsent(null, () => []).add(user);
      } else {
        for (final posId in user.positionIds) {
          usersByPosition.putIfAbsent(posId, () => []).add(user);
        }
      }
    }
    for (final users in usersByPosition.values) {
      users.sort((a, b) => a.lastName.compareTo(b.lastName));
    }

    final withPosition = _filteredUsers
        .where((u) => u.positionIds.isNotEmpty)
        .length;
    final withoutPosition = _filteredUsers
        .where((u) => u.positionIds.isEmpty)
        .length;

    // Section count for label
    final occupiedCount = _positions
        .where((p) => (usersByPosition[p.id]?.isNotEmpty ?? false))
        .length;
    final countLabel =
        '$occupiedCount poste${occupiedCount > 1 ? 's' : ''} occupé${occupiedCount > 1 ? 's' : ''}';

    final isNoPosExpanded = _expandedSections['no_position'] ?? true;

    return Column(
      children: [
        _buildSearchBar(context),
        if (_searchQuery.isEmpty)
          _buildStatsBadge(
            context,
            col1: _StatData(
              icon: Icons.groups_rounded,
              value: '${_filteredUsers.length}',
              label: 'Total',
            ),
            col2: _StatData(
              icon: Icons.work_outline,
              value: '$withPosition',
              label: 'Avec poste',
            ),
            col3: _StatData(
              icon: Icons.work_off_outlined,
              value: '$withoutPosition',
              label: 'Sans poste',
            ),
          ),
        _buildCollapseHeader(context, countLabel),
        Expanded(
          child: _filteredUsers.isEmpty
              ? custom.EmptyStateWidget(
                  message: _searchQuery.isEmpty
                      ? 'Aucun membre dans cette équipe'
                      : 'Aucun résultat pour "$_searchQuery"',
                  icon: _searchQuery.isEmpty
                      ? Icons.group_off
                      : Icons.search_off,
                )
              : ListView(
                  children: [
                    ..._positions.map((position) {
                      final users = usersByPosition[position.id] ?? [];
                      if (users.isEmpty) return const SizedBox.shrink();
                      final isExpanded = _expandedSections[position.id] ?? true;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCollapsibleSectionHeader(
                            context,
                            position.name,
                            position.iconName != null
                                ? KSkills.positionIcons[position.iconName] ??
                                      Icons.work_outline
                                : Icons.work_outline,
                            users.length,
                            isExpanded,
                            () => setState(
                              () =>
                                  _expandedSections[position.id] = !isExpanded,
                            ),
                          ),
                          if (isExpanded)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                children: users
                                    .map((u) => _buildUserTile(context, u))
                                    .toList(),
                              ),
                            ),
                        ],
                      );
                    }),
                    if (usersByPosition[null]?.isNotEmpty ?? false) ...[
                      _buildCollapsibleSectionHeader(
                        context,
                        'Sans poste défini',
                        Icons.person_outline,
                        usersByPosition[null]!.length,
                        isNoPosExpanded,
                        () => setState(
                          () => _expandedSections['no_position'] =
                              !isNoPosExpanded,
                        ),
                      ),
                      if (isNoPosExpanded)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: usersByPosition[null]!
                                .map((u) => _buildUserTile(context, u))
                                .toList(),
                          ),
                        ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
        ),
      ],
    );
  }

  // ── Vue par compétences ─────────────────────────────────────────────────────
  Widget _buildSkillsView(BuildContext context) {
    // Calculer les counts par skill pour le badge stats
    final Map<String, int> skillCounts = {};
    for (final skill in KSkills.listSkills) {
      if (skill.isEmpty) continue;
      final count = _filteredUsers
          .where((u) => u.skills.contains(skill))
          .length;
      if (count > 0) skillCounts[skill] = count;
    }

    _StatData? col2;
    _StatData? col3;
    if (skillCounts.isNotEmpty) {
      final mostEntry = skillCounts.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      final leastEntry = skillCounts.entries.reduce(
        (a, b) => a.value <= b.value ? a : b,
      );
      col2 = _StatData(
        icon: Icons.trending_up_rounded,
        value: '${mostEntry.value}',
        label: _shortSkillLabel(mostEntry.key),
      );
      // Only show col3 if it differs from col2
      if (leastEntry.key != mostEntry.key) {
        col3 = _StatData(
          icon: Icons.trending_down_rounded,
          value: '${leastEntry.value}',
          label: _shortSkillLabel(leastEntry.key),
        );
      }
    }

    final totalLabel =
        '${_filteredUsers.length} agent${_filteredUsers.length > 1 ? 's' : ''}';

    return Column(
      children: [
        _buildSearchBar(context),
        if (_searchQuery.isEmpty && col2 != null)
          _buildStatsBadge(
            context,
            col1: _StatData(
              icon: Icons.groups_rounded,
              value: '${_filteredUsers.length}',
              label: 'Total',
            ),
            col2: col2,
            col3: col3,
          ),
        _buildCollapseHeader(context, totalLabel),
        Expanded(
          child: _filteredUsers.isEmpty
              ? custom.EmptyStateWidget(
                  message: _searchQuery.isEmpty
                      ? 'Aucun membre dans cette équipe'
                      : 'Aucun résultat pour "$_searchQuery"',
                  icon: _searchQuery.isEmpty
                      ? Icons.group_off
                      : Icons.search_off,
                )
              : ListView(
                  children: [
                    ...KSkills.skillCategoryOrder.map((cat) {
                      final icon =
                          KSkills.skillCategoryIcons[cat] ??
                          Icons.verified_outlined;
                      final levels = (KSkills.skillLevels[cat] ?? [])
                          .where((s) => s.isNotEmpty)
                          .toList()
                          .reversed
                          .toList();

                      final usersInCat =
                          _filteredUsers
                              .where(
                                (u) => levels.any(
                                  (skill) => u.skills.contains(skill),
                                ),
                              )
                              .toList()
                            ..sort((a, b) => a.lastName.compareTo(b.lastName));

                      if (usersInCat.isEmpty) return const SizedBox.shrink();

                      final isExpanded = _expandedSections[cat] ?? false;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCollapsibleSectionHeader(
                            context,
                            cat,
                            icon,
                            usersInCat.length,
                            isExpanded,
                            () => setState(
                              () => _expandedSections[cat] = !isExpanded,
                            ),
                          ),
                          if (isExpanded) ...[
                            ...levels.map((skill) {
                              final usersWithSkill =
                                  _filteredUsers
                                      .where((u) => u.skills.contains(skill))
                                      .toList()
                                    ..sort(
                                      (a, b) =>
                                          a.lastName.compareTo(b.lastName),
                                    );
                              if (usersWithSkill.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              final subKey = '$cat::$skill';
                              final isSubExpanded =
                                  _expandedSections[subKey] ?? false;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSkillLevelCollapsibleHeader(
                                    context,
                                    skill,
                                    usersWithSkill.length,
                                    isSubExpanded,
                                    () => setState(
                                      () => _expandedSections[subKey] =
                                          !isSubExpanded,
                                    ),
                                  ),
                                  if (isSubExpanded)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: Column(
                                        children: usersWithSkill
                                            .map(
                                              (u) => _buildUserTile(
                                                context,
                                                u,
                                                keySkillName: skill,
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                ],
                              );
                            }),
                          ],
                        ],
                      );
                    }),
                    const SizedBox(height: 24),
                  ],
                ),
        ),
      ],
    );
  }

  // ── Sous-header collapsible niveau de compétence ────────────────────────────
  Widget _buildSkillLevelCollapsibleHeader(
    BuildContext context,
    String skill,
    int count,
    bool isExpanded,
    VoidCallback onTap,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final levelColor = KSkills.skillColors[skill];
    final accent = _teamColor ?? Theme.of(context).colorScheme.primary;
    final Color dotColor = levelColor != null
        ? KSkills.getColorForSkillLevel(levelColor, context)
        : accent;
    final textColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 10, 12, 4),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              skill,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: dotColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: dotColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 1,
                color: dotColor.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              isExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 16,
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  // ── Label court pour une compétence (badge stats) ───────────────────────────
  String _shortSkillLabel(String skill) {
    // Truncate long skill names for the badge
    if (skill.length <= 10) return skill;
    // Abbreviate known patterns
    if (skill.startsWith('Chef d\'agrès')) {
      final cat = skill.replaceFirst('Chef d\'agrès ', '');
      return 'CA $cat';
    }
    if (skill.startsWith('Chef d\'équipe')) {
      final cat = skill.replaceFirst('Chef d\'équipe ', '');
      return 'CE $cat';
    }
    if (skill.startsWith('Apprenant')) {
      final cat = skill.replaceFirst('Apprenant ', '');
      return 'App. $cat';
    }
    return skill.substring(0, 10);
  }

  // ── Tuile utilisateur ───────────────────────────────────────────────────────
  Widget _buildUserTile(
    BuildContext context,
    User user, {
    bool isLeader = false,
    String? keySkillName,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _showAllStaff
        ? (_teamColors[user.team] ?? Theme.of(context).colorScheme.primary)
        : (_teamColor ?? Theme.of(context).colorScheme.primary);

    final avatarTextColor = _getTextColorForBackground(accent);

    final teamDot = _showAllStaff
        ? Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          )
        : const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          _openSkills(context, user);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
          child: Row(
            children: [
              Hero(
                tag: 'avatar_${user.id}',
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: accent.withValues(
                    alpha: isLeader ? 0.25 : 0.15,
                  ),
                  child: Text(
                    user.initials,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: avatarTextColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    if (_showAllStaff) teamDot,
                    Expanded(
                      child: Text(
                        user.displayName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.grey.shade200
                              : Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isLeader)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.shield_moon_rounded,
                    size: 14,
                    color: accent.withValues(alpha: 0.7),
                  ),
                ),
              if (keySkillName != null && user.keySkills.contains(keySkillName))
                const Padding(
                  padding: EdgeInsets.only(right: 5),
                  child: Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: Colors.amber,
                  ),
                ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSkills(BuildContext context, User user) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            SkillsPage(userId: user.id),
        transitionsBuilder: KAnimations.fadeTransition,
        transitionDuration: KAnimations.durationNormal,
      ),
    );
  }

  // ── Sélecteur d'équipe ──────────────────────────────────────────────────────
  void _showTeamPicker(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final userStation = userNotifier.value?.station ?? KConstants.station;
    final teams = await TeamRepository().getByStation(userStation);
    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Titre
            Row(
              children: [
                Icon(
                  Icons.groups_rounded,
                  size: 18,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  'CHOISIR UNE ÉQUIPE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Option "Effectif complet"
            _TeamPickerItem(
              label: 'Effectif complet',
              subtitle: 'Tous les agents de la caserne',
              color: KColors.appNameColor,
              dotContent: Icon(
                Icons.groups_rounded,
                color: Colors.white,
                size: 14,
              ),
              isSelected: _showAllStaff,
              isDark: isDark,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.pop(context);
                if (!_showAllStaff) {
                  setState(() {
                    _showAllStaff = true;
                    _teamName = 'Effectif complet';
                    _teamColor = KColors.appNameColor;
                  });
                  _init();
                }
              },
            ),

            Divider(
              height: 16,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.grey.shade200,
            ),

            ...teams.map((team) {
              final isSelected = !_showAllStaff && team.id == _teamId;
              return _TeamPickerItem(
                label: team.name,
                subtitle: 'Équipe ${team.id}',
                color: team.color,
                dotContent: Text(
                  team.id,
                  style: TextStyle(
                    color: _getTextColorForBackground(team.color),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                isSelected: isSelected,
                isDark: isDark,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(context);
                  if (team.id != _teamId || _showAllStaff) {
                    setState(() {
                      _showAllStaff = false;
                      _teamId = team.id;
                      _teamName = team.name;
                      _teamColor = team.color;
                    });
                    _init();
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── Data class pour les colonnes du badge stats ─────────────────────────────
class _StatData {
  final IconData icon;
  final String value;
  final String label;

  const _StatData({
    required this.icon,
    required this.value,
    required this.label,
  });
}

// ── Bouton de sélection de vue (avec overlay) ───────────────────────────────
class _ViewModeButton extends StatefulWidget {
  final TeamViewMode currentMode;
  final Color accent;
  final ValueChanged<TeamViewMode> onModeChanged;

  const _ViewModeButton({
    required this.currentMode,
    required this.accent,
    required this.onModeChanged,
  });

  @override
  State<_ViewModeButton> createState() => _ViewModeButtonState();
}

class _ViewModeButtonState extends State<_ViewModeButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  static const _views = [
    (
      mode: TeamViewMode.rolesBased,
      icon: Icons.shield_moon_outlined,
      label: 'Par rôles',
    ),
    (
      mode: TeamViewMode.positionsBased,
      icon: Icons.work_outline,
      label: 'Par postes',
    ),
    (
      mode: TeamViewMode.skillsBased,
      icon: Icons.verified_outlined,
      label: 'Par compétences',
    ),
  ];

  @override
  void dispose() {
    _closeOverlay();
    super.dispose();
  }

  void _closeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _openOverlay(BuildContext ctx) {
    if (_overlayEntry != null) {
      _closeOverlay();
      return;
    }

    const dropdownWidth = 190.0;
    const buttonHeight = 48.0;

    final isDark = Theme.of(ctx).brightness == Brightness.dark;

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
            offset: const Offset(-dropdownWidth + 48, buttonHeight + 4),
            child: Align(
              alignment: Alignment.topLeft,
              child: _ViewModeDropdown(
                currentMode: widget.currentMode,
                isDark: isDark,
                accent: widget.accent,
                views: _views,
                onSelect: (mode) {
                  _closeOverlay();
                  widget.onModeChanged(mode);
                },
                dropdownWidth: dropdownWidth,
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(ctx).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOpen = _overlayEntry != null;
    final currentView = _views.firstWhere(
      (v) => v.mode == widget.currentMode,
      orElse: () => _views.first,
    );

    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: () => _openOverlay(context),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: isDark ? 0.15 : 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: widget.accent.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(currentView.icon, size: 18, color: widget.accent),
              const SizedBox(width: 4),
              Icon(
                isOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 16,
                color: widget.accent.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewModeDropdown extends StatelessWidget {
  final TeamViewMode currentMode;
  final bool isDark;
  final Color accent;
  final List<({TeamViewMode mode, IconData icon, String label})> views;
  final ValueChanged<TeamViewMode> onSelect;
  final double dropdownWidth;

  const _ViewModeDropdown({
    required this.currentMode,
    required this.isDark,
    required this.accent,
    required this.views,
    required this.onSelect,
    required this.dropdownWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: dropdownWidth,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
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
            children: views.map((v) {
              final isSelected = v.mode == currentMode;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onSelect(v.mode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    color: isSelected
                        ? (isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : accent.withValues(alpha: 0.06))
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? accent.withValues(alpha: 0.15)
                                : (isDark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.grey.shade100),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            v.icon,
                            size: 15,
                            color: isSelected
                                ? accent
                                : (isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade500),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            v.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? accent
                                  : (isDark
                                        ? Colors.grey.shade300
                                        : Colors.grey.shade800),
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_rounded, size: 16, color: accent),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ── Widgets locaux ─────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: color.withValues(alpha: 0.7),
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _TeamPickerItem extends StatelessWidget {
  final String label;
  final String subtitle;
  final Color color;
  final Widget dotContent;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _TeamPickerItem({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.dotContent,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: isDark ? 0.15 : 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? color.withValues(alpha: 0.50)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.grey.shade200),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 6,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
                child: Center(child: dotContent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected
                            ? color
                            : (isDark
                                  ? Colors.grey.shade200
                                  : Colors.grey.shade800),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: color, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
