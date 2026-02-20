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
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';

class EditSkillsPage extends StatefulWidget {
  final User user;

  const EditSkillsPage({super.key, required this.user});

  @override
  State<EditSkillsPage> createState() => _EditSkillsPageState();
}

class _EditSkillsPageState extends State<EditSkillsPage> {
  final LocalRepository _repository = LocalRepository();
  late Set<String> _selectedSkills;
  late Set<String> _selectedKeySkills; // Compétences-clés
  bool _isSaving = false;
  final Map<String, String> _warnings = {};

  @override
  void initState() {
    super.initState();
    _selectedSkills = Set.from(widget.user.skills);
    _selectedKeySkills = Set.from(widget.user.keySkills);
  }

  Future<void> _saveSkills() async {
    // Vérifier les avertissements
    _checkSkillProgression();
    if (_warnings.isNotEmpty) {
      final proceed = await _showWarningDialog();
      if (!proceed) return;
    }

    // Afficher le dialogue de confirmation avec les modifications
    final confirmed = await _showConfirmationDialog();
    if (!confirmed) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _isSaving = true;
    });

    try {
      final updatedUser = widget.user.copyWith(
        skills: _selectedSkills.toList(),
        keySkills: _selectedKeySkills.toList(),
      );

      await _repository.updateUserProfile(updatedUser);

      // Synchroniser les compétences sur toutes les stations de l'utilisateur
      await _syncSkillsAcrossStations(updatedUser);

      // Si c'est l'utilisateur actuel, mettre à jour le notifier + stockage local
      if (userNotifier.value?.id == updatedUser.id) {
        userNotifier.value = updatedUser;
        await UserStorageHelper.saveUser(updatedUser);
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
            // Mettre à jour les compétences ET les compétences-clés
            final updatedUserInStation = userInStation.copyWith(
              skills: user.skills,
              keySkills: user.keySkills,
            );

            await userRepo.upsert(updatedUserInStation);
            debugPrint('✅ Skills and keySkills synced for station $stationId');
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

  Future<bool> _showConfirmationDialog() async {
    final initialSkills = widget.user.skills.toSet();
    final initialKeySkills = widget.user.keySkills.toSet();

    // Calculer les modifications
    final addedSkills = _selectedSkills.difference(initialSkills).toList()..sort();
    final removedSkills = initialSkills.difference(_selectedSkills).toList()..sort();
    final addedKeySkills = _selectedKeySkills.difference(initialKeySkills).toList()..sort();
    final removedKeySkills = initialKeySkills.difference(_selectedKeySkills).toList()..sort();

    // Debug
    debugPrint('📊 Confirmation Dialog - Changes detected:');
    debugPrint('  Added skills: $addedSkills');
    debugPrint('  Removed skills: $removedSkills');
    debugPrint('  Added keySkills: $addedKeySkills');
    debugPrint('  Removed keySkills: $removedKeySkills');

    // S'il n'y a aucune modification, ne pas afficher le dialogue
    if (addedSkills.isEmpty && removedSkills.isEmpty &&
        addedKeySkills.isEmpty && removedKeySkills.isEmpty) {
      debugPrint('  ⚠️ No changes detected, skipping dialog');
      return true;
    }

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: KBorderRadius.circularL,
            ),
            title: Row(
              children: [
                Icon(
                  Icons.edit_note,
                  color: KColors.appNameColor,
                  size: KIconSize.l,
                ),
                SizedBox(width: KSpacing.m),
                const Expanded(
                  child: Text('Confirmer les modifications'),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Compétences ajoutées
                    if (addedSkills.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.add_circle, color: Colors.green, size: 20),
                          SizedBox(width: KSpacing.s),
                          Text(
                            'Compétences ajoutées :',
                            style: KTypography.body(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      SizedBox(height: KSpacing.s),
                      ...addedSkills.map(
                        (skill) => Padding(
                          padding: EdgeInsets.only(left: KSpacing.l, bottom: KSpacing.xs),
                          child: Text('• $skill', style: KTypography.body()),
                        ),
                      ),
                      SizedBox(height: KSpacing.m),
                    ],
                    // Compétences retirées
                    if (removedSkills.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                          SizedBox(width: KSpacing.s),
                          Text(
                            'Compétences retirées :',
                            style: KTypography.body(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      SizedBox(height: KSpacing.s),
                      ...removedSkills.map(
                        (skill) => Padding(
                          padding: EdgeInsets.only(left: KSpacing.l, bottom: KSpacing.xs),
                          child: Text('• $skill', style: KTypography.body()),
                        ),
                      ),
                      SizedBox(height: KSpacing.m),
                    ],
                    // Compétences-clés ajoutées
                    if (addedKeySkills.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 20),
                          SizedBox(width: KSpacing.s),
                          Text(
                            'Compétences-clés ajoutées :',
                            style: KTypography.body(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      SizedBox(height: KSpacing.s),
                      ...addedKeySkills.map(
                        (skill) => Padding(
                          padding: EdgeInsets.only(left: KSpacing.l, bottom: KSpacing.xs),
                          child: Text('• $skill', style: KTypography.body()),
                        ),
                      ),
                      SizedBox(height: KSpacing.m),
                    ],
                    // Compétences-clés retirées
                    if (removedKeySkills.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.star_border, color: Colors.grey, size: 20),
                          SizedBox(width: KSpacing.s),
                          Text(
                            'Compétences-clés retirées :',
                            style: KTypography.body(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      SizedBox(height: KSpacing.s),
                      ...removedKeySkills.map(
                        (skill) => Padding(
                          padding: EdgeInsets.only(left: KSpacing.l, bottom: KSpacing.xs),
                          child: Text('• $skill', style: KTypography.body()),
                        ),
                      ),
                    ],
                ],
              ),
            ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KColors.appNameColor,
                ),
                child: const Text('Confirmer'),
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
        // Si on désélectionne une compétence, retirer aussi des keySkills
        _selectedKeySkills.remove(skill);
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

  void _toggleKeySkill(String skill) {
    // Ne peut être une keySkill que si elle est déjà sélectionnée
    if (!_selectedSkills.contains(skill)) return;

    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedKeySkills.contains(skill)) {
        _selectedKeySkills.remove(skill);
      } else {
        _selectedKeySkills.add(skill);
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
    final initialSkills = widget.user.skills.toSet();
    final initialKeySkills = widget.user.keySkills.toSet();

    // Vérifier les changements de skills
    final skillsChanged = !_selectedSkills.containsAll(initialSkills) ||
        !initialSkills.containsAll(_selectedSkills);

    // Vérifier les changements de keySkills
    final keySkillsChanged = !_selectedKeySkills.containsAll(initialKeySkills) ||
        !initialKeySkills.containsAll(_selectedKeySkills);

    return skillsChanged || keySkillsChanged;
  }

  Future<bool> _showDiscardChangesDialog() async {
    // Calculer les modifications pour skills
    final initialSkills = widget.user.skills.toSet();
    final addedSkills = _selectedSkills.difference(initialSkills).toList()..sort();
    final removedSkills = initialSkills.difference(_selectedSkills).toList()..sort();

    // Calculer les modifications pour keySkills
    final initialKeySkills = widget.user.keySkills.toSet();
    final addedKeySkills = _selectedKeySkills.difference(initialKeySkills).toList()..sort();
    final removedKeySkills = initialKeySkills.difference(_selectedKeySkills).toList()..sort();

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
                  if (addedSkills.isNotEmpty) ...[
                    Text(
                      'Compétences ajoutées (${addedSkills.length})',
                      style: KTypography.body(
                        fontWeight: KTypography.fontWeightSemiBold,
                      ),
                    ),
                    SizedBox(height: KSpacing.xs),
                    ...addedSkills.map(
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
                  if (removedSkills.isNotEmpty) ...[
                    Text(
                      'Compétences retirées (${removedSkills.length})',
                      style: KTypography.body(
                        fontWeight: KTypography.fontWeightSemiBold,
                      ),
                    ),
                    SizedBox(height: KSpacing.xs),
                    ...removedSkills.map(
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
                    SizedBox(height: KSpacing.s),
                  ],
                  if (addedKeySkills.isNotEmpty) ...[
                    Text(
                      'Compétences-clés ajoutées (${addedKeySkills.length})',
                      style: KTypography.body(
                        fontWeight: KTypography.fontWeightSemiBold,
                      ),
                    ),
                    SizedBox(height: KSpacing.xs),
                    ...addedKeySkills.map(
                      (s) => Padding(
                        padding: EdgeInsets.only(bottom: KSpacing.xs),
                        child: Row(
                          children: [
                            Icon(Icons.star, size: 16, color: Colors.amber),
                            SizedBox(width: KSpacing.s),
                            Expanded(child: Text(s, style: KTypography.body())),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: KSpacing.s),
                  ],
                  if (removedKeySkills.isNotEmpty) ...[
                    Text(
                      'Compétences-clés retirées (${removedKeySkills.length})',
                      style: KTypography.body(
                        fontWeight: KTypography.fontWeightSemiBold,
                      ),
                    ),
                    SizedBox(height: KSpacing.xs),
                    ...removedKeySkills.map(
                      (s) => Padding(
                        padding: EdgeInsets.only(bottom: KSpacing.xs),
                        child: Row(
                          children: [
                            Icon(Icons.star_border, size: 16, color: Colors.grey),
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
        widget.user.displayName;

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
                  await _saveSkills();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = KColors.appNameColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: primary.withValues(alpha: isDark ? 0.28 : 0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: primary, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cochez les compétences acquises par l\'agent',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(String category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final icon = KSkills.skillCategoryIcons[category] ?? Icons.workspace_premium;
    final levels = KSkills.skillLevels[category] ?? [];

    // Vérifier si la catégorie a au moins une compétence sélectionnée
    final hasAcquired = levels.any((s) => s.isNotEmpty && _selectedSkills.contains(s));
    final accentColor = hasAcquired
        ? KColors.appNameColor
        : (isDark ? Colors.grey.shade600 : Colors.grey.shade400);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: hasAcquired
            ? KColors.appNameColor.withValues(alpha: isDark ? 0.08 : 0.05)
            : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasAcquired
              ? KColors.appNameColor.withValues(alpha: isDark ? 0.28 : 0.18)
              : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête catégorie
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: hasAcquired ? 0.14 : 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: accentColor, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  category,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: hasAcquired
                ? KColors.appNameColor.withValues(alpha: isDark ? 0.15 : 0.10)
                : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200),
            indent: 14,
            endIndent: 14,
          ),
          ...levels.map((skill) {
            if (skill.isEmpty) return const SizedBox.shrink();
            return _buildSkillCheckbox(skill, category);
          }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildSkillCheckbox(String skill, String category) {
    final isChecked = _selectedSkills.contains(skill);
    final isKeySkill = _selectedKeySkills.contains(skill);
    final levelLabel = _getSkillLevelLabel(skill, category);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Couleur du niveau de compétence
    final skillLevelColor = KSkills.skillColors[skill];
    final skillColor = skillLevelColor != null
        ? KSkills.getColorForSkillLevel(skillLevelColor, context)
        : (isDark ? Colors.grey.shade400 : Colors.grey.shade500);

    return InkWell(
      onTap: () => _toggleSkill(skill, category),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Barre colorée verticale (visible si acquis)
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 3,
              height: 32,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isChecked
                    ? skillColor.withValues(alpha: 0.8)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Checkbox rond
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isChecked ? skillColor : Colors.transparent,
                border: Border.all(
                  color: isChecked
                      ? skillColor
                      : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                  width: 2,
                ),
              ),
              child: isChecked
                  ? Icon(Icons.check_rounded,
                      size: 13,
                      color: isDark ? Colors.black87 : Colors.white)
                  : null,
            ),
            // Texte
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    skill,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isChecked
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isChecked
                          ? (isDark ? Colors.grey.shade200 : Colors.grey.shade800)
                          : (isDark ? Colors.grey.shade500 : Colors.grey.shade500),
                    ),
                  ),
                  if (levelLabel.isNotEmpty)
                    Text(
                      levelLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: isChecked
                            ? skillColor
                            : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                      ),
                    ),
                ],
              ),
            ),
            // Étoile (compétence-clé) — visible uniquement si acquise
            if (isChecked)
              GestureDetector(
                onTap: () => _toggleKeySkill(skill),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    isKeySkill ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isKeySkill ? Colors.amber.shade600 : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getSkillLevelLabel(String skill, String category) {
    final skillLevel = KSkills.skillColors[skill];
    if (skillLevel == null) return '';

    return KSkills.getLabelForSkillLevel(skillLevel, category);
  }
}
