import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/repositories/user_stations_repository.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/utils/design_system.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';

class EditSkillsPage extends StatefulWidget {
  final User user;

  const EditSkillsPage({super.key, required this.user});

  @override
  State<EditSkillsPage> createState() => _EditSkillsPageState();
}

class _EditSkillsPageState extends State<EditSkillsPage> {
  final LocalRepository _repository = LocalRepository();
  late Set<String> _selectedSkills;
  bool _isSaving = false;
  final Map<String, String> _warnings = {};

  @override
  void initState() {
    super.initState();
    _selectedSkills = Set.from(widget.user.skills);
  }

  Future<void> _saveSkills() async {
    // Vérifier les avertissements
    _checkSkillProgression();
    if (_warnings.isNotEmpty) {
      final proceed = await _showWarningDialog();
      if (!proceed) return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isSaving = true;
    });

    try {
      final updatedUser = User(
        id: widget.user.id,
        firstName: widget.user.firstName,
        lastName: widget.user.lastName,
        station: widget.user.station,
        team: widget.user.team,
        status: widget.user.status,
        skills: _selectedSkills.toList(),
      );

      await _repository.updateUserProfile(updatedUser);

      // Synchroniser les compétences sur toutes les stations de l'utilisateur
      await _syncSkillsAcrossStations(updatedUser);

      // Si c'est l'utilisateur actuel, mettre à jour le notifier
      if (userNotifier.value?.id == updatedUser.id) {
        userNotifier.value = updatedUser;
      }

      if (mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(KSuccessMessages.updated),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: KBorderRadius.circularM,
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(KErrorMessages.saveError),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: KBorderRadius.circularM,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// Synchronise les compétences de l'utilisateur sur toutes ses stations
  Future<void> _syncSkillsAcrossStations(User user) async {
    try {
      final userStationsRepo = UserStationsRepository();
      final userRepo = UserRepository();
      final sdisId = SDISContext().currentSDISId;

      // Récupérer toutes les stations de l'utilisateur
      final userStations = await userStationsRepo.getUserStations(
        user.id,
        sdisId: sdisId,
      );

      if (userStations == null || userStations.stations.length <= 1) {
        // L'utilisateur n'est que dans une seule station, pas besoin de synchroniser
        debugPrint('👤 User ${user.id} is only in one station, no sync needed');
        return;
      }

      debugPrint(
        '🔄 Syncing skills for user ${user.id} across ${userStations.stations.length} stations',
      );

      // Mettre à jour les compétences dans toutes les autres stations
      for (final stationId in userStations.stations) {
        if (stationId == user.station) {
          // Station actuelle déjà mise à jour
          continue;
        }

        try {
          // Récupérer l'utilisateur dans cette station
          final userInStation = await userRepo.getById(
            user.id,
            stationId: stationId,
          );

          if (userInStation != null) {
            // Mettre à jour uniquement les compétences
            final updatedUserInStation = User(
              id: userInStation.id,
              firstName: userInStation.firstName,
              lastName: userInStation.lastName,
              station: userInStation.station,
              team: userInStation.team,
              status: userInStation.status,
              skills: user.skills, // Compétences synchronisées
              admin: userInStation.admin,
              positionId: userInStation.positionId,
            );

            await userRepo.upsert(updatedUserInStation);
            debugPrint('✅ Skills synced for station $stationId');
          }
        } catch (e) {
          debugPrint('⚠️ Error syncing skills for station $stationId: $e');
          // Continue avec les autres stations même en cas d'erreur
        }
      }

      debugPrint('✅ Skills sync complete for user ${user.id}');
    } catch (e) {
      debugPrint('❌ Error during skills synchronization: $e');
      // Ne pas bloquer la sauvegarde principale si la sync échoue
    }
  }

  void _checkSkillProgression() {
    _warnings.clear();
    for (final category in KSkills.skillCategoryOrder) {
      final levels = KSkills.skillLevels[category];
      if (levels == null) continue;

      // Pour SUAP/PPBE/INC, apprenant et équipier/chef sont mutuellement exclusifs
      // donc pas de vérification de prérequis
      if (['SUAP', 'PPBE', 'INC'].contains(category)) {
        continue;
      }

      // Vérifier si un niveau supérieur est sélectionné sans le niveau inférieur
      // (uniquement pour VPS et COD)
      for (int i = levels.length - 1; i > 0; i--) {
        final higherSkill = levels[i];
        if (higherSkill.isEmpty) continue;

        if (_selectedSkills.contains(higherSkill)) {
          // Vérifier tous les niveaux inférieurs
          for (int j = i - 1; j >= 0; j--) {
            final lowerSkill = levels[j];
            if (lowerSkill.isEmpty) continue;

            if (!_selectedSkills.contains(lowerSkill)) {
              _warnings[category] =
                  'Niveau supérieur sélectionné sans les prérequis';
              break;
            }
          }
        }
      }
    }
  }

  Future<bool> _showWarningDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: KBorderRadius.circularL,
            ),
            title: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: KIconSize.l,
                ),
                SizedBox(width: KSpacing.m),
                const Text('Incohérence détectée'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Des compétences de niveau supérieur sont sélectionnées sans les prérequis :',
                  style: KTypography.body(),
                ),
                SizedBox(height: KSpacing.m),
                ..._warnings.entries.map(
                  (entry) => Padding(
                    padding: EdgeInsets.only(bottom: KSpacing.s),
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_right,
                          color: Colors.orange,
                          size: KIconSize.s,
                        ),
                        SizedBox(width: KSpacing.s),
                        Expanded(
                          child: Text(
                            '${entry.key}: ${entry.value}',
                            style: KTypography.body(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('Continuer quand même'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _toggleSkill(String skill, String category) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedSkills.contains(skill)) {
        _selectedSkills.remove(skill);
        // Auto-désélectionner les niveaux supérieurs
        _deselectHigherLevels(category, skill);
      } else {
        _selectedSkills.add(skill);
        // Logique spéciale pour SUAP/PPBE/INC
        if (['SUAP', 'PPBE', 'INC'].contains(category)) {
          _handleApprenticeEquipierLogic(category, skill);
        } else {
          // Pour VPS et COD, garder l'ancienne logique (auto-sélection)
          _selectLowerLevels(category, skill);
        }
      }
    });
  }

  /// Gère la logique mutuellement exclusive entre apprenant et équipier/chef
  /// Règle : on ne peut pas être apprenant ET équipier/chef en même temps
  void _handleApprenticeEquipierLogic(String category, String skill) {
    final levels = KSkills.skillLevels[category];
    if (levels == null || levels.isEmpty) return;

    final skillLevel = KSkills.skillColors[skill];
    if (skillLevel == null) return;

    // Si on coche "Équipier", on décoche "Apprenant"
    if (skillLevel == SkillLevelColor.equipier) {
      _removeSkillsWithLevel(levels, SkillLevelColor.apprentice);
    }
    // Si on coche "Chef d'équipe", on auto-coche "Équipier" et on décoche "Apprenant"
    else if (skillLevel == SkillLevelColor.teamLeader) {
      _addSkillsWithLevel(levels, SkillLevelColor.equipier);
      _removeSkillsWithLevel(levels, SkillLevelColor.apprentice);
    }
    // Si on coche "Chef d'agrès", on auto-coche les niveaux inférieurs
    else if (skillLevel == SkillLevelColor.chiefOfficer) {
      _addSkillsWithLevel(levels, SkillLevelColor.equipier);
      // Pour INC, auto-sélectionner aussi Chef d'équipe
      if (category == 'INC') {
        _addSkillsWithLevel(levels, SkillLevelColor.teamLeader);
      }
      _removeSkillsWithLevel(levels, SkillLevelColor.apprentice);
    }
    // Si on coche "Apprenant", on décoche tous les niveaux supérieurs
    else if (skillLevel == SkillLevelColor.apprentice) {
      _removeSkillsWithLevel(levels, SkillLevelColor.equipier);
      _removeSkillsWithLevel(levels, SkillLevelColor.teamLeader);
      _removeSkillsWithLevel(levels, SkillLevelColor.chiefOfficer);
    }
  }

  /// Ajoute les compétences d'un certain niveau si elles existent et ne sont pas déjà sélectionnées
  void _addSkillsWithLevel(List<String> levels, SkillLevelColor targetLevel) {
    for (final skill in levels) {
      if (skill.isNotEmpty &&
          KSkills.skillColors[skill] == targetLevel &&
          !_selectedSkills.contains(skill)) {
        _selectedSkills.add(skill);
      }
    }
  }

  /// Retire les compétences d'un certain niveau
  void _removeSkillsWithLevel(
    List<String> levels,
    SkillLevelColor targetLevel,
  ) {
    for (final skill in levels) {
      if (skill.isNotEmpty && KSkills.skillColors[skill] == targetLevel) {
        _selectedSkills.remove(skill);
      }
    }
  }

  void _selectLowerLevels(String category, String skill) {
    final levels = KSkills.skillLevels[category];
    if (levels == null) return;

    final skillIndex = levels.indexOf(skill);
    if (skillIndex == -1) return;

    // Ajouter automatiquement tous les niveaux inférieurs
    for (int i = 0; i < skillIndex; i++) {
      if (levels[i].isNotEmpty) {
        _selectedSkills.add(levels[i]);
      }
    }
  }

  void _deselectHigherLevels(String category, String skill) {
    final levels = KSkills.skillLevels[category];
    if (levels == null) return;

    final skillIndex = levels.indexOf(skill);
    if (skillIndex == -1) return;

    // Retirer automatiquement tous les niveaux supérieurs
    for (int i = skillIndex + 1; i < levels.length; i++) {
      if (levels[i].isNotEmpty) {
        _selectedSkills.remove(levels[i]);
      }
    }
  }

  // === Gestion des changements et confirmations ===
  bool _hasChanges() {
    final initial = widget.user.skills.toSet();
    return !_selectedSkills.containsAll(initial) ||
        !initial.containsAll(_selectedSkills);
  }

  List<String> _addedSkills() {
    final initial = widget.user.skills.toSet();
    return _selectedSkills.difference(initial).toList()..sort();
  }

  List<String> _removedSkills() {
    final initial = widget.user.skills.toSet();
    return initial.difference(_selectedSkills).toList()..sort();
  }

  Future<bool> _showSaveConfirmationDialog() async {
    final added = _addedSkills();
    final removed = _removedSkills();
    final count = added.length + removed.length;

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: KBorderRadius.circularL,
            ),
            title: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: Theme.of(context).colorScheme.primary,
                  size: KIconSize.l,
                ),
                SizedBox(width: KSpacing.m),
                Text('Confirmer l\'enregistrement'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Voulez-vous enregistrer ces modifications ?',
                    style: KTypography.body(),
                  ),
                  SizedBox(height: KSpacing.m),
                  if (added.isNotEmpty) ...[
                    Text(
                      'Ajoutées (${added.length})',
                      style: KTypography.body(
                        fontWeight: KTypography.fontWeightSemiBold,
                      ),
                    ),
                    SizedBox(height: KSpacing.xs),
                    ...added.map(
                      (s) => Padding(
                        padding: EdgeInsets.only(bottom: KSpacing.xs),
                        child: Row(
                          children: [
                            Icon(Icons.add, size: 16, color: Colors.green),
                            SizedBox(width: KSpacing.s),
                            Expanded(child: Text(s, style: KTypography.body())),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: KSpacing.s),
                  ],
                  if (removed.isNotEmpty) ...[
                    Text(
                      'Retirées (${removed.length})',
                      style: KTypography.body(
                        fontWeight: KTypography.fontWeightSemiBold,
                      ),
                    ),
                    SizedBox(height: KSpacing.xs),
                    ...removed.map(
                      (s) => Padding(
                        padding: EdgeInsets.only(bottom: KSpacing.xs),
                        child: Row(
                          children: [
                            Icon(Icons.remove, size: 16, color: Colors.red),
                            SizedBox(width: KSpacing.s),
                            Expanded(child: Text(s, style: KTypography.body())),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _showDiscardChangesDialog() async {
    final added = _addedSkills();
    final removed = _removedSkills();
    final count = added.length + removed.length;

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: KBorderRadius.circularL,
            ),
            title: Row(
              children: [
                Icon(
                  Icons.exit_to_app,
                  color: Theme.of(context).colorScheme.primary,
                  size: KIconSize.l,
                ),
                SizedBox(width: KSpacing.m),
                Text('Quitter sans enregistrer ?'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Vous avez des modifications non enregistrées. Êtes-vous sûr de vouloir quitter ?',
                    style: KTypography.body(),
                  ),
                  SizedBox(height: KSpacing.m),
                  if (added.isNotEmpty) ...[
                    Text(
                      'Ajoutées (${added.length})',
                      style: KTypography.body(
                        fontWeight: KTypography.fontWeightSemiBold,
                      ),
                    ),
                    SizedBox(height: KSpacing.xs),
                    ...added.map(
                      (s) => Padding(
                        padding: EdgeInsets.only(bottom: KSpacing.xs),
                        child: Row(
                          children: [
                            Icon(Icons.add, size: 16, color: Colors.green),
                            SizedBox(width: KSpacing.s),
                            Expanded(child: Text(s, style: KTypography.body())),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: KSpacing.s),
                  ],
                  if (removed.isNotEmpty) ...[
                    Text(
                      'Retirées (${removed.length})',
                      style: KTypography.body(
                        fontWeight: KTypography.fontWeightSemiBold,
                      ),
                    ),
                    SizedBox(height: KSpacing.xs),
                    ...removed.map(
                      (s) => Padding(
                        padding: EdgeInsets.only(bottom: KSpacing.xs),
                        child: Row(
                          children: [
                            Icon(Icons.remove, size: 16, color: Colors.red),
                            SizedBox(width: KSpacing.s),
                            Expanded(child: Text(s, style: KTypography.body())),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Quitter sans enregistrer'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _handleBackPressed() async {
    if (_hasChanges()) {
      final discard = await _showDiscardChangesDialog();
      if (discard && mounted) Navigator.pop(context);
    } else {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userName =
        "${widget.user.firstName} ${widget.user.lastName.toUpperCase()}";

    return WillPopScope(
      onWillPop: () async {
        if (_hasChanges()) {
          final discard = await _showDiscardChangesDialog();
          return discard;
        }
        return true;
      },
      child: Scaffold(
        appBar: CustomAppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Modifier les compétences',
                textAlign: TextAlign.center,
                style: KTypography.title(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Text(
                userName,
                textAlign: TextAlign.center,
                style: KTypography.caption(
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ],
          ),
          bottomColor: KColors.appNameColor,
          leading: BackButton(
            color: Theme.of(context).colorScheme.primary,
            onPressed: _handleBackPressed,
          ),
          actions: [
            if (!_isSaving)
              IconButton(
                icon: Icon(
                  Icons.check,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  if (!_hasChanges()) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Aucune modification à enregistrer'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: KBorderRadius.circularM,
                        ),
                      ),
                    );
                    return;
                  }
                  final ok = await _showSaveConfirmationDialog();
                  if (ok) {
                    await _saveSkills();
                  }
                },
              ),
            if (_isSaving)
              Padding(
                padding: const EdgeInsets.all(KSpacing.m),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(KSpacing.m),
          children: [
            _buildInfoBanner(),
            const SizedBox(height: KSpacing.m),
            ...KSkills.skillCategoryOrder.map((category) {
              return _buildCategorySection(category);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(KSpacing.s),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(KBorderRadius.m),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: KSpacing.xs),
          Expanded(
            child: Text(
              'Cochez les compétences acquises par l\'agent',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
                fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(String category) {
    final icon =
        KSkills.skillCategoryIcons[category] ?? Icons.workspace_premium;
    final levels = KSkills.skillLevels[category] ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  category,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            ...levels.map((skill) {
              if (skill.isEmpty) return const SizedBox.shrink();
              return _buildSkillCheckbox(skill, category);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillCheckbox(String skill, String category) {
    final isChecked = _selectedSkills.contains(skill);
    final levelLabel = _getSkillLevelLabel(skill, category);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      onTap: () => _toggleSkill(skill, category),
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isChecked
                ? Theme.of(context).colorScheme.primary
                : (isDark ? Colors.white54 : Colors.black45),
            width: 2,
          ),
          color: isChecked
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
        ),
        child: isChecked
            ? Icon(
                Icons.check,
                size: 16,
                color: isDark ? Colors.black : Colors.white,
              )
            : null,
      ),
      title: Text(
        skill,
        style: KTypography.body(
          fontWeight: isChecked
              ? KTypography.fontWeightSemiBold
              : KTypography.fontWeightRegular,
        ),
      ),
      subtitle: (category == 'COD' && levelLabel.isNotEmpty)
          ? Text(
              levelLabel,
              style: KTypography.caption(
                color: Theme.of(context).colorScheme.tertiary,
              ).copyWith(fontStyle: FontStyle.italic),
            )
          : null,
    );
  }

  String _getSkillLevelLabel(String skill, String category) {
    final skillLevel = KSkills.skillColors[skill];
    if (skillLevel == null) return '';

    return KSkills.getLabelForSkillLevel(skillLevel, category);
  }
}
