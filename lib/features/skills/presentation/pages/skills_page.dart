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
  List<Position> _userPositions = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _showAcquiredOnly = false;
  bool _hasChanges = false;

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
        final user = await _repository.getUserProfile(widget.userId!);
        await _loadPosition(user);
        setState(() {
          _displayedUser = user;
          _isLoading = false;
        });
      } else {
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
    if (user.positionIds.isEmpty) {
      setState(() => _userPositions = []);
      return;
    }
    try {
      final positions = await _positionRepository
          .getPositionsByStation(user.station)
          .first;
      setState(() {
        _userPositions = positions
            .where((p) => user.positionIds.contains(p.id))
            .toList();
      });
    } catch (e) {
      setState(() => _userPositions = []);
    }
  }

  /// Retourne toutes les compétences possédées pour une catégorie, triées par niveau décroissant
  List<String> _getSkillsInCategory(List<String> userSkills, String category) {
    final levels = KSkills.skillLevels[category];
    if (levels == null) return [];

    final priorityOrder = [
      SkillLevelColor.chiefOfficer,
      SkillLevelColor.teamLeader,
      SkillLevelColor.equipier,
      SkillLevelColor.apprentice,
    ];

    final result = <String>[];
    for (final priority in priorityOrder) {
      for (final skillName in levels) {
        if (skillName.isNotEmpty &&
            userSkills.contains(skillName) &&
            KSkills.skillColors[skillName] == priority) {
          result.add(skillName);
        }
      }
    }
    return result;
  }

  /// Retourne le niveau le plus haut pour une catégorie (pour l'en-tête)
  SkillLevelColor? _getHighestLevel(List<String> userSkills, String category) {
    final skills = _getSkillsInCategory(userSkills, category);
    if (skills.isEmpty) return null;
    return KSkills.skillColors[skills.first];
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
    final String userName =
        _displayedUser != null ? _displayedUser!.displayName : "";

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (!didPop) Navigator.pop(context, _hasChanges);
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
                    builder: (context) =>
                        SimilarAgentsPage(targetUser: _displayedUser),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Construire la liste des catégories avec leur statut
    final List<MapEntry<int, String>> skillsData = [];
    for (final category in KSkills.skillCategoryOrder) {
      skillsData.add(
        MapEntry(KSkills.skillCategoryOrder.indexOf(category), category),
      );
    }

    // Trier : acquises en premier, puis par ordre défini
    skillsData.sort((a, b) {
      final levelA = _getHighestLevel(userSkills, a.value);
      final levelB = _getHighestLevel(userSkills, b.value);
      if (levelA == null && levelB != null) return 1;
      if (levelA != null && levelB == null) return -1;
      return a.key.compareTo(b.key);
    });

    // Filtrer si nécessaire
    final displayedSkills = _showAcquiredOnly
        ? skillsData.where((entry) {
            return _getHighestLevel(userSkills, entry.value) != null;
          }).toList()
        : skillsData;

    return Column(
      children: [
        // ── En-tête compact ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              // Postes
              if (_userPositions.isNotEmpty) ...[
                ..._userPositions.map((pos) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _PositionBanner(position: pos),
                )),
                const SizedBox(height: 4),
              ],

              // Toggle filtre
              Align(
                alignment: Alignment.centerRight,
                child: _FilterToggle(
                  active: _showAcquiredOnly,
                  onToggle: () {
                    HapticFeedback.selectionClick();
                    setState(() => _showAcquiredOnly = !_showAcquiredOnly);
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // ── Liste des catégories ───────────────────────────────────────────
        Expanded(
          child: displayedSkills.isEmpty
              ? custom.EmptyStateWidget(
                  message: 'Aucune compétence acquise',
                  icon: Icons.school_outlined,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: displayedSkills.length,
                  itemBuilder: (context, index) {
                    final category = displayedSkills[index].value;
                    final categorySkills =
                        _getSkillsInCategory(userSkills, category);
                    final highestLevel =
                        _getHighestLevel(userSkills, category);
                    final isAcquired = highestLevel != null;
                    final icon = KSkills.skillCategoryIcons[category] ??
                        Icons.workspace_premium;
                    final color = _getLevelColor(context, highestLevel);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SkillCategoryTile(
                        category: category,
                        icon: icon,
                        color: color,
                        isAcquired: isAcquired,
                        skills: categorySkills,
                        highestLevel: highestLevel,
                        highestLevelLabel:
                            _getLevelLabel(highestLevel, category),
                        isKeySkill: categorySkills.any(
                          (s) => user.keySkills.contains(s),
                        ),
                        keySkills: user.keySkills,
                        getLevelColor: (lc) => _getLevelColor(context, lc),
                        getLevelLabel: (lc) => _getLevelLabel(lc, category),
                        isDark: isDark,
                      ),
                    );
                  },
                ),
        ),
      ],
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
      _hasChanges = true;
      _loadUser();
    }
  }
}

// ── Widgets locaux ─────────────────────────────────────────────────────────────

class _PositionBanner extends StatelessWidget {
  final Position position;

  const _PositionBanner({required this.position});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = KColors.appNameColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary.withValues(alpha: isDark ? 0.14 : 0.08),
            primary.withValues(alpha: isDark ? 0.06 : 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: primary.withValues(alpha: isDark ? 0.28 : 0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(
            position.iconName != null
                ? KSkills.positionIcons[position.iconName] ?? Icons.work_outline
                : Icons.work_outline,
            size: 18,
            color: primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Poste',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: primary,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  position.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.grey.shade200 : Colors.grey.shade800,
                  ),
                ),
                if (position.description != null &&
                    position.description!.isNotEmpty)
                  Text(
                    position.description!,
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  final bool active;
  final VoidCallback onToggle;

  const _FilterToggle({required this.active, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = active
        ? KColors.appNameColor
        : (isDark ? Colors.grey.shade600 : Colors.grey.shade400);

    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: active
              ? KColors.appNameColor.withValues(alpha: isDark ? 0.18 : 0.10)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? KColors.appNameColor.withValues(alpha: 0.5)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.shade200),
          ),
        ),
        child: Icon(
          active ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
          size: 18,
          color: color,
        ),
      ),
    );
  }
}

/// Tuile de catégorie de compétences avec liste déroulante des compétences possédées.
class _SkillCategoryTile extends StatefulWidget {
  final String category;
  final IconData icon;
  final Color color;
  final bool isAcquired;
  final List<String> skills;
  final SkillLevelColor? highestLevel;
  final String highestLevelLabel;
  final bool isKeySkill;
  final List<String> keySkills;
  final Color Function(SkillLevelColor?) getLevelColor;
  final String Function(SkillLevelColor?) getLevelLabel;
  final bool isDark;

  const _SkillCategoryTile({
    required this.category,
    required this.icon,
    required this.color,
    required this.isAcquired,
    required this.skills,
    required this.highestLevel,
    required this.highestLevelLabel,
    required this.isKeySkill,
    required this.keySkills,
    required this.getLevelColor,
    required this.getLevelLabel,
    required this.isDark,
  });

  @override
  State<_SkillCategoryTile> createState() => _SkillCategoryTileState();
}

class _SkillCategoryTileState extends State<_SkillCategoryTile>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _controller;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!widget.isAcquired) return;
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final color = widget.color;

    // Couleurs adaptatives
    final containerColor = widget.isAcquired
        ? color.withValues(alpha: isDark ? 0.10 : 0.06)
        : (isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50);
    final borderColor = widget.isAcquired
        ? color.withValues(alpha: isDark ? 0.30 : 0.20)
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.grey.shade200);

    return GestureDetector(
      onTap: _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: [
            // ── En-tête ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Icône catégorie
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(
                          alpha: widget.isAcquired ? 0.15 : 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.isAcquired
                          ? color
                          : (isDark
                              ? Colors.grey.shade600
                              : Colors.grey.shade400),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Texte
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.category,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: widget.isAcquired
                                    ? (isDark
                                        ? Colors.grey.shade200
                                        : Colors.grey.shade800)
                                    : (isDark
                                        ? Colors.grey.shade600
                                        : Colors.grey.shade400),
                              ),
                            ),
                            if (widget.isKeySkill) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.star_rounded,
                                  size: 14, color: Colors.amber.shade600),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(
                                alpha: widget.isAcquired ? 0.18 : 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            widget.highestLevelLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontStyle: FontStyle.italic,
                              color: widget.isAcquired
                                  ? color
                                  : (isDark
                                      ? Colors.grey.shade600
                                      : Colors.grey.shade400),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Flèche déroulante ou point "non acquis"
                  if (widget.isAcquired)
                    RotationTransition(
                      turns: Tween(begin: 0.0, end: 0.5)
                          .animate(_expandAnimation),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: color.withValues(alpha: 0.7),
                        size: 20,
                      ),
                    )
                  else
                    Icon(
                      Icons.remove_rounded,
                      size: 16,
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade400,
                    ),
                ],
              ),
            ),

            // ── Liste déroulante des compétences ─────────────────────────
            SizeTransition(
              sizeFactor: _expandAnimation,
              child: Column(
                children: [
                  Divider(
                    height: 1,
                    color: color.withValues(alpha: isDark ? 0.15 : 0.12),
                    indent: 14,
                    endIndent: 14,
                  ),
                  ...widget.skills.asMap().entries.map((entry) {
                    final i = entry.key;
                    final skillName = entry.value;
                    final skillLevel = KSkills.skillColors[skillName];
                    final skillColor = widget.getLevelColor(skillLevel);
                    final skillLabel = widget.getLevelLabel(skillLevel);
                    final isKey = widget.keySkills.contains(skillName);

                    return _SkillRow(
                      skillName: skillName,
                      skillLabel: skillLabel,
                      skillColor: skillColor,
                      isKey: isKey,
                      isLast: i == widget.skills.length - 1,
                      isDark: isDark,
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  final String skillName;
  final String skillLabel;
  final Color skillColor;
  final bool isKey;
  final bool isLast;
  final bool isDark;

  const _SkillRow({
    required this.skillName,
    required this.skillLabel,
    required this.skillColor,
    required this.isKey,
    required this.isLast,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 10, 14, isLast ? 12 : 2),
      child: Row(
        children: [
          // Barre colorée verticale
          Container(
            width: 3,
            height: 36,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: skillColor.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        skillName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.grey.shade200
                              : Colors.grey.shade800,
                        ),
                      ),
                    ),
                    if (isKey)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(Icons.star_rounded,
                            size: 13, color: Colors.amber.shade600),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  skillLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: skillColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
