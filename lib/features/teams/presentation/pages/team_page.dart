import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
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

class _TeamPageState extends State<TeamPage> {
  final LocalRepository _repo = LocalRepository();
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  String? _error;
  List<User> _teamUsers = [];
  List<User> _filteredUsers = [];
  String _teamId = '';
  String _teamName = 'Équipe';
  Color? _teamColor;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _teamId = widget.teamId ?? userNotifier.value?.team ?? '';
    _init();
    // Listen to team data changes
    teamDataChangedNotifier.addListener(_onTeamDataChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    teamDataChangedNotifier.removeListener(_onTeamDataChanged);
    super.dispose();
  }

  void _onTeamDataChanged() {
    // Reload team data when notified of changes
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final users = await _repo.getAllUsers();
      final filtered = users.where((u) => u.team == _teamId).toList();
      filtered.sort((a, b) => a.lastName.compareTo(b.lastName));
      final team = await TeamRepository().getById(_teamId);
      setState(() {
        _teamUsers = filtered;
        _filteredUsers = filtered;
        _teamName = team?.name ?? 'Équipe $_teamId';
        _teamColor = team?.color;
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
      setState(() {
        _filteredUsers = _teamUsers;
      });
    } else {
      final query = _searchQuery.toLowerCase();
      setState(() {
        _filteredUsers = _teamUsers.where((user) {
          final fullName = '${user.firstName} ${user.lastName}'.toLowerCase();
          return fullName.contains(query);
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _teamColor ?? Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: CustomAppBar(
        title: _teamName,
        onTitleTap: () => _showTeamPicker(context),
        bottomColor: accent,
      ),
      body: _loading
          ? const TeamPageSkeleton()
          : _error != null
          ? custom.ErrorWidget(message: _error, onRetry: _init)
          : RefreshIndicator(onRefresh: _init, child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
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

    final totalCount = _filteredUsers.length;
    final leaderCount = leaders.length;
    final agentCount = agents.length;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: KSpacing.paddingL,
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
              _applySearch();
            },
            decoration: InputDecoration(
              hintText: 'Rechercher un agent...',
              hintStyle: KTypography.body(
                color: Theme.of(context).colorScheme.tertiary,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: Theme.of(context).colorScheme.tertiary,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                        _applySearch();
                      },
                    )
                  : null,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: KBorderRadius.circularM,
                borderSide: BorderSide.none,
              ),
              contentPadding: KSpacing.paddingM,
            ),
          ),
        ),
        // Stats badge
        if (_searchQuery.isEmpty) ...[
          SizedBox(height: KSpacing.m),
          Padding(
            padding: KSpacing.paddingHorizontalL,
            child: Container(
              padding: KSpacing.paddingM,
              decoration: BoxDecoration(
                color: (_teamColor ?? Theme.of(context).colorScheme.primary)
                    .withOpacity(0.1),
                borderRadius: KBorderRadius.circularM,
                border: Border.all(
                  color: (_teamColor ?? Theme.of(context).colorScheme.primary)
                      .withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(context, Icons.groups, '$totalCount', 'Total'),
                  Container(width: 1, height: 24, color: Colors.grey[300]),
                  _buildStatItem(
                    context,
                    Icons.shield_moon,
                    '$leaderCount',
                    'Chefs',
                  ),
                  Container(width: 1, height: 24, color: Colors.grey[300]),
                  _buildStatItem(
                    context,
                    Icons.person,
                    '$agentCount',
                    'Agents',
                  ),
                ],
              ),
            ),
          ),
        ],
        SizedBox(height: KSpacing.l),
        // List
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
                  padding: KSpacing.paddingL,
                  children: [
                    if (leaders.isNotEmpty) ...[
                      _sectionHeader(
                        context,
                        'Chef de garde',
                        icon: Icons.shield_moon,
                      ),
                      SizedBox(height: KSpacing.s),
                      ...leaders.map(
                        (u) => _userTile(context, u, isLeader: true),
                      ),
                      SizedBox(height: KSpacing.l),
                    ],
                    if (agents.isNotEmpty) ...[
                      _sectionHeader(context, 'Agents', icon: Icons.group),
                      SizedBox(height: KSpacing.s),
                      ...agents.map((u) => _userTile(context, u)),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) {
    final color = _teamColor ?? Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Icon(icon, size: KIconSize.m, color: color),
        SizedBox(height: KSpacing.xs),
        Text(
          value,
          style: KTypography.headline(
            color: color,
            fontWeight: KTypography.fontWeightBold,
          ),
        ),
        Text(
          label,
          style: KTypography.caption(
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String label, {IconData? icon}) {
    final accent = _teamColor ?? Theme.of(context).colorScheme.primary;
    final isDark = isDarkModeNotifier.value;
    Color headerTextColor;
    double luminance = accent.computeLuminance();
    Color darkenColor(Color color, [double amount = .1]) {
      final hsl = HSLColor.fromColor(color);
      final hslDark = hsl.withLightness(
        (hsl.lightness - amount).clamp(0.0, 1.0),
      );
      return hslDark.toColor();
    }

    if (isDark) {
      if (luminance > 0.85) {
        headerTextColor = Colors.black;
      } else if (luminance > 0.5) {
        headerTextColor = darkenColor(accent, 0.35);
      } else {
        headerTextColor = Colors.white;
      }
    } else {
      if (luminance > 0.85) {
        headerTextColor = Colors.black;
      } else if (luminance > 0.5) {
        headerTextColor = darkenColor(accent, 0.35);
      } else {
        headerTextColor = darkenColor(accent, 0.35);
      }
    }
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: KIconSize.s, color: accent),
          SizedBox(width: KSpacing.s / 2),
        ],
        Text(
          label,
          style: KTypography.body(
            color: headerTextColor,
            fontWeight: KTypography.fontWeightBold,
          ),
        ),
        SizedBox(width: KSpacing.s),
        Expanded(child: Divider(thickness: 1, color: accent.withOpacity(0.4))),
      ],
    );
  }

  Widget _userTile(BuildContext context, User user, {bool isLeader = false}) {
    final accent = _teamColor ?? Theme.of(context).colorScheme.primary;
    final isDark = isDarkModeNotifier.value;
    Color avatarTextColor;
    double luminance = accent.computeLuminance();
    Color darkenColor(Color color, [double amount = .1]) {
      final hsl = HSLColor.fromColor(color);
      final hslDark = hsl.withLightness(
        (hsl.lightness - amount).clamp(0.0, 1.0),
      );
      return hslDark.toColor();
    }

    if (isDark) {
      if (luminance > 0.85) {
        avatarTextColor = Colors.black;
      } else if (luminance > 0.5) {
        avatarTextColor = darkenColor(accent, 0.35);
      } else {
        avatarTextColor = Colors.white;
      }
    } else {
      if (luminance > 0.85) {
        avatarTextColor = Colors.black;
      } else if (luminance > 0.5) {
        avatarTextColor = darkenColor(accent, 0.35);
      } else {
        avatarTextColor = darkenColor(accent, 0.35);
      }
    }

    return Card(
      margin: EdgeInsets.symmetric(vertical: KSpacing.s / 2),
      elevation: KElevation.low,
      shape: RoundedRectangleBorder(borderRadius: KBorderRadius.circularM),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          _openSkills(context, user);
        },
        borderRadius: KBorderRadius.circularM,
        child: Padding(
          padding: KSpacing.paddingM,
          child: Row(
            children: [
              Hero(
                tag: 'avatar_${user.id}',
                child: CircleAvatar(
                  radius: KAvatarSize.s / 2,
                  backgroundColor: accent.withOpacity(isLeader ? 0.25 : 0.15),
                  child: Text(
                    _initials(user.firstName, user.lastName),
                    style: KTypography.body(
                      color: avatarTextColor,
                      fontWeight: KTypography.fontWeightBold,
                    ),
                  ),
                ),
              ),
              SizedBox(width: KSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${user.firstName} ${user.lastName}',
                      style: KTypography.body(
                        fontWeight: KTypography.fontWeightSemiBold,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.tertiary,
                size: KIconSize.m,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String first, String last) {
    final f = first.isNotEmpty ? first[0] : '';
    final l = last.isNotEmpty ? last[0] : '';
    return (f + l).toUpperCase();
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

  void _showTeamPicker(BuildContext context) async {
    HapticFeedback.mediumImpact();

    // Load teams from repository
    final teams = await TeamRepository().getAll();

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: KBorderRadius.circularXL),
        child: Padding(
          padding: KSpacing.paddingXL,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.groups,
                    color: Theme.of(context).colorScheme.primary,
                    size: KIconSize.l,
                  ),
                  SizedBox(width: KSpacing.m),
                  Text(
                    'Choisir une équipe',
                    style: KTypography.headline(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: KSpacing.xl),
              ...teams.map((team) {
                final isSelected = team.id == _teamId;
                return Padding(
                  padding: EdgeInsets.only(bottom: KSpacing.m),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context);
                      if (team.id != _teamId) {
                        setState(() {
                          _teamId = team.id;
                          _teamName = team.name;
                          _teamColor = team.color;
                        });
                        _init();
                      }
                    },
                    borderRadius: KBorderRadius.circularM,
                    child: AnimatedContainer(
                      duration: KAnimations.durationFast,
                      padding: KSpacing.paddingM,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? team.color.withOpacity(0.15)
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? team.color
                              : Theme.of(context).dividerColor.withOpacity(0.3),
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: KBorderRadius.circularM,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: KAvatarSize.m,
                            height: KAvatarSize.m,
                            decoration: BoxDecoration(
                              color: team.color,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: team.color.withOpacity(0.4),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                team.id,
                                style: KTypography.title(
                                  color: _getTextColorForBackground(team.color),
                                  fontWeight: KTypography.fontWeightBold,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: KSpacing.l),
                          Expanded(
                            child: Text(
                              team.name,
                              style: KTypography.bodyLarge(
                                color: isSelected
                                    ? team.color
                                    : Theme.of(
                                        context,
                                      ).textTheme.bodyLarge?.color,
                                fontWeight: isSelected
                                    ? KTypography.fontWeightBold
                                    : KTypography.fontWeightMedium,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle,
                              color: team.color,
                              size: KIconSize.m,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
              SizedBox(height: KSpacing.s),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Annuler',
                    style: KTypography.body(
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getTextColorForBackground(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}
