import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/position_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/position_repository.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/utils/design_system.dart';
import 'package:nexshift_app/features/skills/presentation/pages/edit_skills_page.dart';
import 'package:nexshift_app/core/presentation/widgets/error_widget.dart'
    as custom;
import 'package:nexshift_app/core/presentation/widgets/skeleton_loader.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/features/settings/presentation/pages/similar_agents_page.dart';

class SkillsPage extends StatefulWidget {
  final String? userId;

  const SkillsPage({super.key, this.userId});

  @override
  State<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends State<SkillsPage> {
  final LocalRepository _repository = LocalRepository();
  final PositionRepository _positionRepository = PositionRepository();
  User? _displayedUser;
  Position? _userPosition;
  bool _isLoading = true;
  String? _errorMessage;
  bool _showAcquiredOnly = false;
  bool _hasChanges = false; // Track if skills were modified

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (widget.userId != null) {
        // Autre utilisateur : charger via repository
        // Note: getUserProfile devrait utiliser Cloud Functions pour déchiffrer
        final user = await _repository.getUserProfile(widget.userId!);
        await _loadPosition(user);
        setState(() {
          _displayedUser = user;
          _isLoading = false;
        });
      } else {
        // Pour l'utilisateur connecté, utiliser directement userNotifier
        // Les données sont déjà déchiffrées après le login
        final currentUser = userNotifier.value;
        if (currentUser != null) {
          await _loadPosition(currentUser);
          setState(() {
            _displayedUser = currentUser;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = KErrorMessages.userNotFound;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = KErrorMessages.loadingError;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPosition(User user) async {
    if (user.positionId == null) {
      _userPosition = null;
      return;
    }

    try {
      final positions = await _positionRepository
          .getPositionsByStation(user.station)
          .first;
      _userPosition = positions.firstWhere(
        (p) => p.id == user.positionId,
        orElse: () => Position(id: '', name: '', stationId: '', order: 0),
      );
      if (_userPosition?.id.isEmpty ?? true) {
        _userPosition = null;
      }
    } catch (e) {
      _userPosition = null;
    }
  }

  /// Determine the highest skill level the user has for a given category
  /// Returns: (level color, skill name) or (null, '') if none
  (SkillLevelColor?, String) _getHighestSkillLevel(
    List<String> userSkills,
    String category,
  ) {
    final levels = KSkills.skillLevels[category];
    if (levels == null) return (null, '');

    // Define priority order for skill levels
    final priorityOrder = [
      SkillLevelColor.chiefOfficer,
      SkillLevelColor.teamLeader,
      SkillLevelColor.equipier,
      SkillLevelColor.apprentice,
    ];

    // Check from highest to lowest priority
    for (final priority in priorityOrder) {
      for (final skillName in levels) {
        if (skillName.isNotEmpty &&
            userSkills.contains(skillName) &&
            KSkills.skillColors[skillName] == priority) {
          return (priority, skillName);
        }
      }
    }
    return (null, ''); // No skill in this category
  }

  Color _getLevelColor(BuildContext context, SkillLevelColor? levelColor) {
    if (levelColor == null) return Colors.grey;
    return KSkills.getColorForSkillLevel(levelColor, context);
  }

  String _getLevelLabel(SkillLevelColor? levelColor, String category) {
    if (levelColor == null) return 'Non acquis';
    return KSkills.getLabelForSkillLevel(levelColor, category);
  }

  bool _canEditSkills() {
    final currentUser = userNotifier.value;
    if (currentUser == null || _displayedUser == null) return false;

    return currentUser.admin ||
        currentUser.status == KConstants.statusLeader ||
        currentUser.status == KConstants.statusChief &&
            currentUser.team == _displayedUser!.team;
  }

  @override
  Widget build(BuildContext context) {
    final String userName = _displayedUser != null
        ? _displayedUser!.displayName
        : "";

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          Navigator.pop(context, _hasChanges);
        }
      },
      child: Scaffold(
        appBar: CustomAppBar(
          title: Hero(
            tag: 'avatar_${widget.userId ?? "current"}',
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    userName,
                    textAlign: TextAlign.center,
                    style: KTypography.bodyLarge(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: KTypography.fontWeightBold,
                    ),
                  ),
                  if (_displayedUser != null)
                    Text(
                      "(${_displayedUser!.id})",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.tertiary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ),
          bottomColor: KColors.appNameColor,
          actions: [
            IconButton(
              icon: Icon(
                Icons.people_alt_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              tooltip: 'Voir les agents similaires',
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SimilarAgentsPage(
                      targetUser: _displayedUser,
                    ),
                  ),
                );
              },
            ),
            if (_canEditSkills())
              IconButton(
                icon: Icon(
                  Icons.edit_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  _navigateToEditSkills(context);
                },
              ),
          ],
        ),
        body: _isLoading
            ? const SkillsPageSkeleton()
            : _errorMessage != null
            ? custom.ErrorWidget(message: _errorMessage, onRetry: _loadUser)
            : _displayedUser == null
            ? custom.EmptyStateWidget(
                message: KErrorMessages.userNotFound,
                icon: Icons.person_off,
              )
            : _buildSkillsList(_displayedUser!),
      ),
    );
  }

  Widget _buildSkillsList(User user) {
    final userSkills = user.skills;

    // Séparer compétences acquises et non acquises
    final List<MapEntry<int, String>> skillsData = [];
    for (final category in KSkills.skillCategoryOrder) {
      final (level, skillName) = _getHighestSkillLevel(userSkills, category);
      skillsData.add(
        MapEntry(KSkills.skillCategoryOrder.indexOf(category), category),
      );
    }

    // Trier : compétences acquises en premier
    skillsData.sort((a, b) {
      final (levelA, _) = _getHighestSkillLevel(userSkills, a.value);
      final (levelB, _) = _getHighestSkillLevel(userSkills, b.value);
      // Acquis avant non acquis
      if (levelA == null && levelB != null) return 1;
      if (levelA != null && levelB == null) return -1;
      // Ordre défini dans skillCategoryOrder (SUAP, PPBE, INC, VPS, COD)
      return a.key.compareTo(b.key);
    });

    // Filtrer si nécessaire
    final displayedSkills = _showAcquiredOnly
        ? skillsData.where((entry) {
            final (level, _) = _getHighestSkillLevel(userSkills, entry.value);
            return level != null;
          }).toList()
        : skillsData;

    return Column(
      children: [
        // Position tile
        if (_userPosition != null)
          Padding(
            padding: KSpacing.paddingL,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: KSpacing.paddingM,
                    decoration: BoxDecoration(
                      color: KColors.appNameColor.withOpacity(0.1),
                      borderRadius: KBorderRadius.circularM,
                      border: Border.all(
                        color: KColors.appNameColor.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (_userPosition!.iconName != null)
                          Icon(
                            KSkills.positionIcons[_userPosition!.iconName],
                            size: KIconSize.m,
                            color: KColors.appNameColor,
                          )
                        else
                          Icon(
                            Icons.work_outline,
                            size: KIconSize.m,
                            color: KColors.appNameColor,
                          ),
                        SizedBox(width: KSpacing.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Poste',
                                style: KTypography.caption().copyWith(
                                  color: KColors.appNameColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _userPosition!.name,
                                style: KTypography.body().copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_userPosition!.description != null &&
                                  _userPosition!.description!.isNotEmpty)
                                Text(
                                  _userPosition!.description!,
                                  style: KTypography.caption().copyWith(
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_userPosition != null) Divider(height: 1.0),
        // Toggle filter
        Padding(
          padding: KSpacing.paddingL,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: KSpacing.paddingM,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: KBorderRadius.circularM,
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _showAcquiredOnly
                            ? Icons.filter_alt
                            : Icons.filter_alt_outlined,
                        size: KIconSize.s,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      SizedBox(width: KSpacing.s, height: 2.0),
                      Expanded(
                        child: Text(
                          'Compétences acquises uniquement',
                          style: KTypography.body(),
                        ),
                      ),
                      Switch(
                        value: _showAcquiredOnly,
                        onChanged: (value) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _showAcquiredOnly = value;
                          });
                        },
                        activeColor: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 2.0),
        // Skills list or empty state
        Expanded(
          child: displayedSkills.isEmpty
              ? custom.EmptyStateWidget(
                  message: 'Aucune compétence acquise',
                  icon: Icons.school_outlined,
                )
              : ListView.builder(
                  padding: KSpacing.paddingL,
                  itemCount: displayedSkills.length,
                  itemBuilder: (context, index) {
                    final category = displayedSkills[index].value;
                    final (level, skillName) = _getHighestSkillLevel(
                      userSkills,
                      category,
                    );

                    final icon =
                        KSkills.skillCategoryIcons[category] ??
                        Icons.workspace_premium;
                    final color = _getLevelColor(context, level);
                    final levelLabel = _getLevelLabel(level, category);
                    final isNotAcquired = level == null;

                    return Card(
                      margin: EdgeInsets.only(bottom: KSpacing.m),
                      elevation: KElevation.medium,
                      shape: RoundedRectangleBorder(
                        borderRadius: KBorderRadius.circularM,
                      ),
                      child: InkWell(
                        onTap: isNotAcquired
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                _showSkillDetails(
                                  context,
                                  category,
                                  level,
                                  skillName,
                                );
                              },
                        borderRadius: KBorderRadius.circularM,
                        child: Padding(
                          padding: KSpacing.paddingL,
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  icon,
                                  color: color,
                                  size: KIconSize.l,
                                ),
                              ),
                              SizedBox(width: KSpacing.l),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      category,
                                      style: KTypography.title(
                                        color: isNotAcquired
                                            ? Colors.grey
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                        fontWeight: KTypography.fontWeightBold,
                                      ),
                                    ),
                                    SizedBox(height: KSpacing.xs),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: KSpacing.s,
                                        vertical: KSpacing.xs / 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.2),
                                        borderRadius: KBorderRadius.circularS,
                                      ),
                                      child: Text(
                                        levelLabel,
                                        style: KTypography.caption(color: color)
                                            .copyWith(
                                              fontWeight:
                                                  KTypography.fontWeightMedium,
                                              fontStyle: FontStyle.italic,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Afficher étoile si c'est une keySkill
                              if (!isNotAcquired &&
                                  user.keySkills.contains(skillName))
                                Icon(
                                  Icons.star,
                                  color: Colors.amber,
                                  size: 24,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showSkillDetails(
    BuildContext context,
    String category,
    SkillLevelColor? level,
    String skillName,
  ) {
    final color = _getLevelColor(context, level);
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KBorderRadius.xl),
        ),
      ),
      builder: (context) => Padding(
        padding: KSpacing.paddingXL,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(KSpacing.m),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    KSkills.skillCategoryIcons[category],
                    color: color,
                    size: KIconSize.l,
                  ),
                ),
                SizedBox(width: KSpacing.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category,
                        style: KTypography.headline(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      SizedBox(height: KSpacing.xs),
                      Text(
                        skillName,
                        style: KTypography.body(
                          color: color,
                          fontWeight: KTypography.fontWeightMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: KSpacing.xl),
            Text(
              'Niveau actuel',
              style: KTypography.caption(
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
            SizedBox(height: KSpacing.s),
            Text(
              _getLevelLabel(level, category),
              style: KTypography.title(
                color: color,
                fontWeight: KTypography.fontWeightBold,
              ),
            ),
            SizedBox(height: KSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  padding: KSpacing.paddingM,
                  shape: RoundedRectangleBorder(
                    borderRadius: KBorderRadius.circularM,
                  ),
                ),
                child: const Text('Fermer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEditSkills(BuildContext context) async {
    if (_displayedUser == null) return;

    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            EditSkillsPage(user: _displayedUser!),
        transitionsBuilder: KAnimations.slideFromBottomTransition,
        transitionDuration: KAnimations.durationNormal,
      ),
    );

    if (result == true) {
      _hasChanges = true; // Mark that changes were made
      _loadUser();
    }
  }
}
