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

enum TeamViewMode { rolesBased, positionsBased }

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

      final positions =
          await _positionRepo.getPositionsByStation(stationId).first;

      setState(() {
        _teamUsers = filtered;
        _filteredUsers = filtered;
        _positions = positions;
        _teamColors = colorsMap;
        _teamName =
            _showAllStaff ? 'Effectif complet' : (team?.name ?? 'Équipe $_teamId');
        _teamColor = _showAllStaff ? KColors.appNameColor : team?.color;
        _loading = false;
      });
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
          IconButton(
            icon: Icon(
              _viewMode == TeamViewMode.rolesBased
                  ? Icons.work_outline
                  : Icons.shield_moon,
              color: accent,
            ),
            tooltip: _viewMode == TeamViewMode.rolesBased
                ? 'Vue par postes'
                : 'Vue par rôles',
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                _viewMode = _viewMode == TeamViewMode.rolesBased
                    ? TeamViewMode.positionsBased
                    : TeamViewMode.rolesBased;
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
    return _viewMode == TeamViewMode.rolesBased
        ? _buildRolesView(context)
        : _buildPositionsView(context);
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
          Icon(Icons.search_rounded,
              size: 18,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade500),
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
              child: Icon(Icons.close_rounded,
                  size: 16,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade400),
            ),
        ],
      ),
    );
  }

  // ── Stats badge ─────────────────────────────────────────────────────────────
  Widget _buildStatsBadge(
      BuildContext context, int total, int leaders, int agents) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _teamColor ?? Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: accent.withValues(alpha: isDark ? 0.25 : 0.18)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(icon: Icons.groups_rounded, value: '$total', label: 'Total', color: accent),
          Container(width: 1, height: 28, color: accent.withValues(alpha: 0.20)),
          _StatItem(icon: Icons.shield_moon_rounded, value: '$leaders', label: 'Chefs', color: accent),
          Container(width: 1, height: 28, color: accent.withValues(alpha: 0.20)),
          _StatItem(icon: Icons.person_rounded, value: '$agents', label: 'Agents', color: accent),
        ],
      ),
    );
  }

  // ── Section header ──────────────────────────────────────────────────────────
  Widget _buildSectionHeader(BuildContext context, String label,
      {IconData? icon}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _teamColor ?? Theme.of(context).colorScheme.primary;
    final textColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: textColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: accent.withValues(alpha: 0.20),
            ),
          ),
        ],
      ),
    );
  }

  // ── Vue par rôles ───────────────────────────────────────────────────────────
  Widget _buildRolesView(BuildContext context) {
    final leaders = _filteredUsers
        .where((u) =>
            u.status == KConstants.statusLeader ||
            u.status == KConstants.statusChief)
        .toList()
      ..sort((a, b) => a.lastName.compareTo(b.lastName));
    final agents = _filteredUsers
        .where((u) => u.status == KConstants.statusAgent)
        .toList()
      ..sort((a, b) => a.lastName.compareTo(b.lastName));

    return Column(
      children: [
        _buildSearchBar(context),
        if (_searchQuery.isEmpty)
          _buildStatsBadge(
              context, _filteredUsers.length, leaders.length, agents.length),
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
                      _buildSectionHeader(context, 'Chef de garde',
                          icon: Icons.shield_moon_rounded),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: leaders
                              .map((u) => _buildUserTile(context, u, isLeader: true))
                              .toList(),
                        ),
                      ),
                    ],
                    if (agents.isNotEmpty) ...[
                      _buildSectionHeader(context, 'Agents',
                          icon: Icons.groups_rounded),
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
      usersByPosition.putIfAbsent(user.positionId, () => []).add(user);
    }
    for (final users in usersByPosition.values) {
      users.sort((a, b) => a.lastName.compareTo(b.lastName));
    }

    return Column(
      children: [
        _buildSearchBar(context),
        if (_searchQuery.isEmpty)
          _buildStatsBadge(context, _filteredUsers.length, 0, 0),
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
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            position.name,
                            icon: position.iconName != null
                                ? KSkills.positionIcons[position.iconName]
                                : Icons.work_outline,
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
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
                      _buildSectionHeader(context, 'Sans poste défini',
                          icon: Icons.person_outline),
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

  // ── Tuile utilisateur ───────────────────────────────────────────────────────
  Widget _buildUserTile(BuildContext context, User user,
      {bool isLeader = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _showAllStaff
        ? (_teamColors[user.team] ?? Theme.of(context).colorScheme.primary)
        : (_teamColor ?? Theme.of(context).colorScheme.primary);

    final avatarTextColor = _getTextColorForBackground(accent);

    // En mode "Effectif complet", afficher un point coloré de l'équipe
    final teamDot = _showAllStaff
        ? Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
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
                  backgroundColor:
                      accent.withValues(alpha: isLeader ? 0.25 : 0.15),
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
                  child: Icon(Icons.shield_moon_rounded,
                      size: 14,
                      color: accent.withValues(alpha: 0.7)),
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
                Icon(Icons.groups_rounded,
                    size: 18,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
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
              dotContent: Icon(Icons.groups_rounded,
                  color: Colors.white, size: 14),
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
              // Point/cercle coloré
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
