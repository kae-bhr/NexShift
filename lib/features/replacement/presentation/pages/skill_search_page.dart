import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/planning_tile.dart';
import 'package:nexshift_app/features/replacement/services/replacement_search_service.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';

class SkillSearchPage extends StatefulWidget {
  final Planning planning;
  final List<String> preselectedSkills;

  const SkillSearchPage({
    super.key,
    required this.planning,
    this.preselectedSkills = const [],
  });

  @override
  State<SkillSearchPage> createState() => _SkillSearchPageState();
}

class _SkillSearchPageState extends State<SkillSearchPage> {
  // Data
  final LocalRepository _localRepository = LocalRepository();
  final ReplacementNotificationService _notificationService =
      ReplacementNotificationService();
  late final SubshiftRepository _subshiftRepository = SubshiftRepository();

  List<User> allUsers = [];
  List<User> filteredUsers = [];
  List<Subshift> existingSubshifts = [];

  // UI State
  List<String> selectedSkills = [];
  DateTime? startDateTime;
  DateTime? endDateTime;
  String? dateError;
  bool isLoading = true;
  bool showSkills = true;
  final Map<int, bool> _categoryExpanded = {
    0: true, // Disponibles
    1: true, // Remplacement partiel
    2: true, // Remplacement total
    3: true, // Astreinte
    4: true, // Autres
  };

  @override
  void initState() {
    super.initState();
    selectedSkills = [...widget.preselectedSkills];
    // Initialize with full planning window to enable validation and ordering
    startDateTime = widget.planning.startTime;
    endDateTime = widget.planning.endTime;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final users = await _localRepository.getAllUsers();
      final subs = await _subshiftRepository.getByPlanningId(
        widget.planning.id,
      );
      setState(() {
        allUsers = users;
        existingSubshifts = subs;
      });
      _filterUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur de chargement: $e')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _filterUsers() {
    if (selectedSkills.isEmpty) {
      setState(() => filteredUsers = []);
      return;
    }
    setState(() {
      filteredUsers = allUsers.where((user) {
        return selectedSkills.every((skill) => user.skills.contains(skill));
      }).toList();
      _sortFilteredUsers();
    });
  }

  void _sortFilteredUsers() {
    if (startDateTime == null || endDateTime == null) {
      filteredUsers.sort(ReplacementSearchService.sortByLastName);
      return;
    }

    final disponibles = <User>[];
    final rempPartiel = <User>[];
    final rempTotal = <User>[];
    final astreinte = <User>[];
    final autres = <User>[];

    for (final u in filteredUsers) {
      switch (_userCategory(u)) {
        case 0:
          disponibles.add(u);
          break;
        case 1:
          rempPartiel.add(u);
          break;
        case 2:
          rempTotal.add(u);
          break;
        case 3:
          astreinte.add(u);
          break;
        default:
          autres.add(u);
      }
    }

    disponibles.sort(ReplacementSearchService.sortByLastName);
    rempPartiel.sort(ReplacementSearchService.sortByLastName);
    rempTotal.sort(ReplacementSearchService.sortByLastName);
    astreinte.sort(ReplacementSearchService.sortByLastName);
    autres.sort(ReplacementSearchService.sortByLastName);

    filteredUsers = [
      ...disponibles,
      ...rempPartiel,
      ...rempTotal,
      ...astreinte,
      ...autres,
    ];
  }

  // --- Helpers to compute per-user status against selected window ---
  bool _overlaps(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    return aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
  }

  Duration _overlapDuration(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    if (!_overlaps(aStart, aEnd, bStart, bEnd)) return Duration.zero;
    final start = aStart.isAfter(bStart) ? aStart : bStart;
    final end = aEnd.isBefore(bEnd) ? aEnd : bEnd;
    return end.difference(start);
  }

  /// Catégorie: 0=Disponible (inclut totalement remplacé), 1=Partiel (remplaçant OU remplacé partiel),
  /// 2=Remplacement total (remplaçant total), 3=Astreinte (présent non remplacé), 4=Autres
  int _userCategory(User user) {
    if (startDateTime == null || endDateTime == null) return 4;
    final selStart = startDateTime!;
    final selEnd = endDateTime!;
    final selDur = selEnd.difference(selStart);
    final tolerance = const Duration(minutes: 1);

    final isPlanned = widget.planning.agentsId.contains(user.id);

    final replacedOverlaps = existingSubshifts
        .where(
          (s) => s.planningId == widget.planning.id && s.replacedId == user.id,
        )
        .map((s) => _overlapDuration(s.start, s.end, selStart, selEnd))
        .fold(Duration.zero, (a, b) => a + b);

    final replacerOverlaps = existingSubshifts
        .where(
          (s) => s.planningId == widget.planning.id && s.replacerId == user.id,
        )
        .map((s) => _overlapDuration(s.start, s.end, selStart, selEnd))
        .fold(Duration.zero, (a, b) => a + b);

    final fullyReplaced = replacedOverlaps >= selDur - tolerance;
    final partiallyReplaced =
        replacedOverlaps > Duration.zero &&
        replacedOverlaps < selDur - tolerance;
    final replacerFull = replacerOverlaps >= selDur - tolerance;
    final replacerPartial =
        replacerOverlaps > Duration.zero &&
        replacerOverlaps < selDur - tolerance;
    final astreinteActive = isPlanned && replacedOverlaps == Duration.zero;

    final disponible =
        !astreinteActive &&
        replacerOverlaps == Duration.zero &&
        (!isPlanned || fullyReplaced);

    if (disponible) return 0;
    if (replacerPartial || partiallyReplaced) return 1;
    if (replacerFull) return 2;
    if (astreinteActive) return 3;
    return 4;
  }

  Color _categoryBorderColor(int category, BuildContext context) {
    switch (category) {
      case 0:
        return Colors.green.shade400; // Disponible/Totalement remplacé
      case 1:
        return Colors.orange.shade400; // Partiel (rempl./remplacé)
      case 2:
      case 3:
        return Colors.red.shade400; // Rempl. total ou Astreinte
      default:
        return Theme.of(context).dividerColor;
    }
  }

  Widget _buildCategoryHeader(BuildContext context, int category) {
    String label;
    switch (category) {
      case 0:
        label = 'Disponibles';
        break;
      case 1:
        label = 'Remplacement partiel';
        break;
      case 2:
        label = 'Remplacement total';
        break;
      case 3:
        label = 'Astreinte';
        break;
      default:
        label = 'Autres';
    }

    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
    );

    final isExpanded = _categoryExpanded[category] ?? true;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Text(label, style: textStyle),
          const SizedBox(width: 8),
          const Expanded(child: Divider(height: 1)),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => setState(() {
              _categoryExpanded[category] =
                  !(_categoryExpanded[category] ?? true);
            }),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _toggleSkill(String skill) {
    final wasSelected = selectedSkills.contains(skill);
    setState(() {
      if (wasSelected) {
        selectedSkills.remove(skill);
      } else {
        selectedSkills.add(skill);
        // Auto-sélectionner les niveaux inférieurs et logique mutuellement exclusive
        _handleSkillSelectionLogic(skill);
      }
    });
    _filterUsers();
    // Retourne true si on vient d'ajouter une compétence (pour fermer la popup)
    return !wasSelected;
  }

  String _skillShortLabel(String category, String skill) {
    final levelColor = KSkills.skillColors[skill];
    if (levelColor == null) return skill;
    return KSkills.getLabelForSkillLevel(levelColor, category);
  }

  // Sélections actuelles d'une catégorie
  List<String> _selectedInCategory(String category) {
    final levels = KSkills.skillLevels[category] ?? const <String>[];
    return selectedSkills
        .where((s) => levels.contains(s) && s.isNotEmpty)
        .toList();
  }

  // Ouvre une feuille légère pour choisir les niveaux d'une catégorie
  Future<void> _showCategoryPicker(String category) async {
    final levels = (KSkills.skillLevels[category] ?? const <String>[])
        .where((s) => s.isNotEmpty)
        .toList();
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Icon(
                          KSkills.skillCategoryIcons[category] ??
                              Icons.workspace_premium,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          category,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        if (_selectedInCategory(category).isNotEmpty)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                final toRemove = _selectedInCategory(category);
                                selectedSkills.removeWhere(
                                  (s) => toRemove.contains(s),
                                );
                              });
                              _filterUsers();
                              Navigator.pop(context);
                            },
                            child: const Text('Effacer'),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ...levels.map((skill) {
                    final isSelected = selectedSkills.contains(skill);
                    return ListTile(
                      onTap: () {
                        final shouldClose = _toggleSkill(skill);
                        setModalState(() {}); // Mettre à jour l'UI de la popup
                        // Fermer la popup uniquement si on vient d'ajouter une compétence
                        if (shouldClose) {
                          Navigator.pop(context);
                        }
                      },
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).iconTheme.color,
                        size: 20,
                      ),
                      title: Text(_skillShortLabel(category, skill)),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Gère la logique de sélection des compétences :
  /// - Auto-sélectionne les niveaux inférieurs (chef d'agrès -> équipier)
  /// - Gère la logique mutuellement exclusive entre apprenant et autres niveaux
  void _handleSkillSelectionLogic(String skill) {
    final skillLevel = KSkills.skillColors[skill];
    if (skillLevel == null) return;

    // Auto-sélectionner les niveaux inférieurs pour chef d'agrès et chef d'équipe
    if (skillLevel == SkillLevelColor.chiefOfficer) {
      _autoSelectLowerLevels(skill, includingTeamLeader: true);
    } else if (skillLevel == SkillLevelColor.teamLeader) {
      _autoSelectLowerLevels(skill, includingTeamLeader: false);
    }

    // Logique mutuellement exclusive pour apprenant
    _handleMutualExclusiveSkills(skill);
  }

  /// Auto-sélectionne les niveaux inférieurs (équipier et optionnellement chef d'équipe)
  void _autoSelectLowerLevels(
    String skill, {
    required bool includingTeamLeader,
  }) {
    // Déterminer la catégorie de la compétence
    String? category;
    for (final cat in KSkills.skillCategoryOrder) {
      final levels = KSkills.skillLevels[cat] ?? [];
      if (levels.contains(skill)) {
        category = cat;
        break;
      }
    }

    if (category == null) return;
    final levels = KSkills.skillLevels[category] ?? [];

    // Auto-sélectionner équipier
    for (final lvl in levels) {
      if (lvl.isNotEmpty &&
          KSkills.skillColors[lvl] == SkillLevelColor.equipier &&
          !selectedSkills.contains(lvl)) {
        selectedSkills.add(lvl);
      }
    }

    // Auto-sélectionner chef d'équipe si demandé (pour INC uniquement)
    if (includingTeamLeader) {
      for (final lvl in levels) {
        if (lvl.isNotEmpty &&
            KSkills.skillColors[lvl] == SkillLevelColor.teamLeader &&
            !selectedSkills.contains(lvl)) {
          selectedSkills.add(lvl);
        }
      }
    }
  }

  /// Gère la logique mutuellement exclusive entre apprenant et équipier/chef
  /// Pour SUAP/PPBE/INC uniquement :
  /// - Cocher apprenant décoche équipier et chef d'agrès
  /// - Cocher équipier ou chef décoche apprenant
  void _handleMutualExclusiveSkills(String skill) {
    // SUAP
    if (skill == KSkills.suapA) {
      selectedSkills.remove(KSkills.suap);
      selectedSkills.remove(KSkills.suapCA);
    } else if (skill == KSkills.suap || skill == KSkills.suapCA) {
      selectedSkills.remove(KSkills.suapA);
    }
    // PPBE
    else if (skill == KSkills.ppbeA) {
      selectedSkills.remove(KSkills.ppbe);
      selectedSkills.remove(KSkills.ppbeCA);
    } else if (skill == KSkills.ppbe || skill == KSkills.ppbeCA) {
      selectedSkills.remove(KSkills.ppbeA);
    }
    // INC
    else if (skill == KSkills.incA) {
      selectedSkills.remove(KSkills.inc);
      selectedSkills.remove(KSkills.incCE);
      selectedSkills.remove(KSkills.incCA);
    } else if (skill == KSkills.inc ||
        skill == KSkills.incCE ||
        skill == KSkills.incCA) {
      selectedSkills.remove(KSkills.incA);
    }
  }

  Future<void> _searchForAvailableAgent() async {
    // Validate dates first
    _validateDates();
    if (dateError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(dateError!)));
      return;
    }

    // Get current user from notifier
    final currentUser = userNotifier.value;
    if (currentUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Utilisateur non trouvé")));
      return;
    }

    // Afficher une boîte de dialogue de confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechercher un agent disponible'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cette action enverra une notification aux agents disponibles ou en remplacement partiel pour la période sélectionnée.',
            ),
            const SizedBox(height: 16),
            Text(
              'Période : ${DateFormat('dd/MM/yyyy HH:mm').format(startDateTime!)} - ${DateFormat('dd/MM/yyyy HH:mm').format(endDateTime!)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
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
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Créer la demande de disponibilité via le service de notification
      await _notificationService.createReplacementRequest(
        requesterId: currentUser.id,
        planningId: widget.planning.id,
        startTime: startDateTime!,
        endTime: endDateTime!,
        station: currentUser.station,
        team: currentUser.team,
        requestType: RequestType.availability,
        requiredSkills: selectedSkills.isNotEmpty ? selectedSkills : null,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Demande de disponibilité envoyée aux agents disponibles',
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Retourner à la page précédente
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de l\'envoi de la demande: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _validateDates() async {
    // Récupérer les demandes existantes de l'utilisateur courant
    final currentUser = await UserStorageHelper.loadUser();
    if (currentUser == null) {
      setState(() {
        dateError = null;
      });
      return;
    }

    // Récupérer toutes les demandes de remplacement de l'utilisateur
    final existingRequestsSnapshot = await _notificationService.firestore
        .collection('replacementRequests')
        .where('requesterId', isEqualTo: currentUser.id)
        .where('status', isEqualTo: 'pending')
        .get();

    final existingRequests = existingRequestsSnapshot.docs
        .map((doc) => doc.data())
        .toList();

    setState(() {
      dateError = DateTimePickerService.validateReplacementDates(
        startDateTime: startDateTime,
        endDateTime: endDateTime,
        planning: widget.planning,
        existingRequests: existingRequests,
      );
    });
  }

  Future<bool> _pickDateTime(bool isStart) async {
    final initialDate = isStart
        ? (startDateTime ?? widget.planning.startTime)
        : (endDateTime ?? widget.planning.endTime);

    final result = await DateTimePickerService.pickDateTime(
      context: context,
      initialDate: initialDate,
      firstDate: widget.planning.startTime.subtract(const Duration(days: 30)),
      lastDate: widget.planning.endTime.add(const Duration(days: 30)),
    );

    if (result != null) {
      setState(() {
        if (isStart) {
          startDateTime = result;
        } else {
          endDateTime = result;
        }
        _validateDates();
        _sortFilteredUsers();
      });
      return true;
    }
    return false;
  }

  void _showDateTimePickerDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Modifier les horaires'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Début'),
                subtitle: Text(
                  startDateTime != null
                      ? DateFormat('dd/MM/yyyy HH:mm').format(startDateTime!)
                      : 'Non défini',
                ),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final result = await _pickDateTime(true);
                  if (result) {
                    setDialogState(() {});
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Fin'),
                subtitle: Text(
                  endDateTime != null
                      ? DateFormat('dd/MM/yyyy HH:mm').format(endDateTime!)
                      : 'Non défini',
                ),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final result = await _pickDateTime(false);
                  if (result) {
                    setDialogState(() {});
                  }
                },
              ),
            ],
          ),
          actions: [
            if (startDateTime != null && endDateTime != null)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Valider'),
              )
            else
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Recherche par compétences',
        bottomColor: KColors.appNameColor,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Tuile d'astreinte cliquable
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: PlanningTile(
                    planning: widget.planning,
                    startDateTime: startDateTime,
                    endDateTime: endDateTime,
                    errorMessage: dateError,
                    onTap: _showDateTimePickerDialog,
                  ),
                ),

                // Section des compétences (repliable)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Compétences recherchées :',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (selectedSkills.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  selectedSkills.clear();
                                });
                                _filterUsers();
                              },
                              child: const Text('Effacer tout'),
                            ),
                          GestureDetector(
                            onTap: () =>
                                setState(() => showSkills = !showSkills),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                              child: Icon(
                                showSkills
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 20,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (showSkills) ...[
                        const SizedBox(height: 6),
                        // Version compacte: 5 chips de catégories ouvrant un sélecteur léger
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: KSkills.skillCategoryOrder.map((category) {
                            final hasAny = _selectedInCategory(
                              category,
                            ).isNotEmpty;
                            return FilterChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    KSkills.skillCategoryIcons[category] ??
                                        Icons.workspace_premium,
                                    size: 16,
                                    color: hasAny
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onPrimary
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(category),
                                ],
                              ),
                              selected: hasAny,
                              onSelected: (_) => _showCategoryPicker(category),
                              selectedColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                              showCheckmark: false,
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                ElevatedButton.icon(
                  onPressed: _searchForAvailableAgent,
                  icon: const Icon(Icons.person_search),
                  label: const Text('Rechercher un agent'),
                ),

                const Divider(),

                // Résultats
                Expanded(
                  child: selectedSkills.isEmpty
                      ? Center(
                          child: Text(
                            'Sélectionnez des compétences pour voir les agents disponibles',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : filteredUsers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_off,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Aucun agent trouvé avec ces compétences',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : Builder(
                          builder: (context) {
                            final List<Widget> items = [];
                            int? lastCategory;
                            for (final user in filteredUsers) {
                              final cat = _userCategory(user);
                              if (lastCategory == null || cat != lastCategory) {
                                items.add(_buildCategoryHeader(context, cat));
                                lastCategory = cat;
                              }
                              if (_categoryExpanded[cat] ?? true) {
                                items.add(
                                  Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: _categoryBorderColor(
                                          cat,
                                          context,
                                        ),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: ListTile(
                                      title: Text(
                                        '${user.firstName} ${user.lastName}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text('Équipe ${user.team}'),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }
                            }
                            return ListView(
                              padding: const EdgeInsets.all(16),
                              children: items,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
