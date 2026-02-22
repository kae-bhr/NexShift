import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/on_call_level_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/services/agent_query_service.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/features/replacement/services/replacement_search_service.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/planning_tile.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/presentation/widgets/planning_form_widgets.dart';

class SkillSearchPage extends StatefulWidget {
  final Planning planning;
  final List<String> preselectedSkills;

  /// Paramètres pour le mode "Choix automatique" (AgentQuery)
  final User? currentUser;
  final List<OnCallLevel> onCallLevels;

  /// Si true, le bouton principal crée une [AgentQuery] au lieu d'une
  /// [ReplacementRequest] de type availability.
  final bool launchAsAgentQuery;

  const SkillSearchPage({
    super.key,
    required this.planning,
    this.preselectedSkills = const [],
    this.currentUser,
    this.onCallLevels = const [],
    this.launchAsAgentQuery = false,
  });

  @override
  State<SkillSearchPage> createState() => _SkillSearchPageState();
}

class _SkillSearchPageState extends State<SkillSearchPage> {
  // Data
  final LocalRepository _localRepository = LocalRepository();
  final UserRepository _userRepository = UserRepository();
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
  String? selectedOnCallLevelId; // Mode AgentQuery uniquement
  bool isLoading = true;

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
      // Charger les agents de la station courante (via currentUser ou fallback)
      final stationId = widget.currentUser?.station ?? widget.planning.station;
      final List<User> users = stationId.isNotEmpty
          ? await _userRepository.getByStation(stationId)
          : await _localRepository.getAllUsers();
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
        // Exclure les agents suspendus ou en arrêt maladie
        if (!user.isActiveForReplacement) return false;
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

  void _toggleSkill(String skill) {
    setState(() {
      if (selectedSkills.contains(skill)) {
        selectedSkills.remove(skill);
      } else {
        selectedSkills.add(skill);
      }
    });
    _filterUsers();
  }

  String _skillShortLabel(String category, String skill) {
    final levelColor = KSkills.skillColors[skill];
    if (levelColor == null) return skill;
    return KSkills.getLabelForSkillLevel(levelColor, category);
  }

  bool _hasCategorySelection(String category) {
    final levels = KSkills.skillLevels[category] ?? const <String>[];
    return selectedSkills.any((s) => levels.contains(s) && s.isNotEmpty);
  }

  Future<void> _createAgentQuery() async {
    final createdBy = widget.currentUser;
    if (createdBy == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Utilisateur non trouvé')));
      return;
    }

    // Vérifier qu'un niveau d'astreinte est sélectionné
    final levelId = selectedOnCallLevelId;
    if (levelId == null || levelId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un niveau d\'astreinte'),
        ),
      );
      return;
    }

    final level = widget.onCallLevels.firstWhere(
      (l) => l.id == levelId,
      orElse: () => widget.onCallLevels.first,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lancer la recherche automatique'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Niveau : ${level.name}'),
            const SizedBox(height: 4),
            Text(
              'Compétences : ${selectedSkills.isEmpty ? 'Toutes' : selectedSkills.join(', ')}',
            ),
            const SizedBox(height: 4),
            if (startDateTime != null && endDateTime != null)
              Text(
                'Période : ${DateFormat('dd/MM HH:mm').format(startDateTime!)} → ${DateFormat('dd/MM HH:mm').format(endDateTime!)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 12),
            const Text(
              'Les agents éligibles seront notifiés. Le premier à accepter sera ajouté à l\'astreinte.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lancer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await AgentQueryService().createQuery(
        planning: widget.planning,
        onCallLevelId: level.id,
        onCallLevelName: level.name,
        requiredSkills: selectedSkills,
        createdBy: createdBy,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recherche lancée — les agents éligibles ont été notifiés',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
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
        .collection(EnvironmentConfig.getCollectionPath(
            'replacements/automatic/replacementRequests', currentUser.station))
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

  bool get _isButtonEnabled {
    if (widget.launchAsAgentQuery) {
      return selectedOnCallLevelId != null && selectedOnCallLevelId!.isNotEmpty;
    }
    return startDateTime != null && endDateTime != null && dateError == null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Recherche par compétences',
        bottomColor: KColors.appNameColor,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _isButtonEnabled
                ? (widget.launchAsAgentQuery
                      ? _createAgentQuery
                      : _searchForAvailableAgent)
                : null,
            icon: Icon(
              widget.launchAsAgentQuery
                  ? Icons.manage_search_rounded
                  : Icons.person_search,
            ),
            label: Text(
              widget.launchAsAgentQuery
                  ? 'Lancer la recherche'
                  : 'Rechercher un agent',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: KColors.appNameColor,
            ),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                // ── Section Astreinte ──────────────────────────────────────
                _SectionHeader(icon: Icons.event_rounded, label: 'Astreinte'),
                const SizedBox(height: 8),
                SharedPlanningDetailCard(planning: widget.planning),
                const SizedBox(height: 20),

                // ── Section Période de remplacement ───────────────────────
                _SectionHeader(
                  icon: Icons.schedule_rounded,
                  label: 'Période de remplacement',
                ),
                const SizedBox(height: 8),
                SharedReplacementPeriodCard(
                  startDateTime: startDateTime,
                  endDateTime: endDateTime,
                  errorMessage: dateError,
                  uncoveredPeriods: const [],
                  onPickStart: () => _pickDateTime(true),
                  onPickEnd: () => _pickDateTime(false),
                ),
                const SizedBox(height: 20),

                // ── Section Niveau d'astreinte (AgentQuery uniquement) ────
                if (widget.launchAsAgentQuery &&
                    widget.onCallLevels.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.layers_rounded,
                    label: 'Niveau d\'astreinte',
                  ),
                  const SizedBox(height: 8),
                  _buildOnCallLevelTiles(isDark),
                  const SizedBox(height: 12),
                ],

                // ── Section Compétences ────────────────────────────────────
                Row(
                  children: [
                    _SectionHeader(
                      icon: Icons.workspace_premium_rounded,
                      label: 'Compétences requises',
                    ),
                    const Spacer(),
                    Opacity(
                      opacity: selectedSkills.isNotEmpty ? 1.0 : 0.0,
                      child: IgnorePointer(
                        ignoring: selectedSkills.isEmpty,
                        child: TextButton(
                          onPressed: () {
                            setState(() => selectedSkills.clear());
                            _filterUsers();
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Effacer tout'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _buildSkillsSection(context, isDark),
              ],
            ),
    );
  }

  // ── Niveaux d'astreinte radio-style ─────────────────────────────────────

  Widget _buildOnCallLevelTiles(bool isDark) {
    return Column(
      children: widget.onCallLevels.map((level) {
        final isSelected = selectedOnCallLevelId == level.id;
        final levelColor = level.color;
        return GestureDetector(
          onTap: () => setState(() => selectedOnCallLevelId = level.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? levelColor.withValues(alpha: isDark ? 0.18 : 0.1)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.grey.shade50),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? levelColor
                    : (isDark ? Colors.white12 : Colors.grey.shade300),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: levelColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.layers_rounded,
                    color: levelColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    level.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? levelColor : null,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, color: levelColor, size: 20)
                else
                  Icon(
                    Icons.radio_button_unchecked,
                    color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                    size: 20,
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Compétences par catégorie (ExpansionTile) ────────────────────────────

  Widget _buildSkillsSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...KSkills.skillCategoryOrder.map((category) {
          final categorySkills = (KSkills.skillLevels[category] ?? [])
              .where((s) => s.isNotEmpty)
              .toList();
          if (categorySkills.isEmpty) return const SizedBox.shrink();

          final hasCatSelection = _hasCategorySelection(category);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasCatSelection
                    ? KColors.appNameColor.withValues(alpha: 0.4)
                    : (isDark ? Colors.white12 : Colors.grey.shade300),
              ),
            ),
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              leading: Icon(
                KSkills.skillCategoryIcons[category] ?? Icons.workspace_premium,
                size: 20,
                color: hasCatSelection ? KColors.appNameColor : null,
              ),
              title: Text(
                category,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: hasCatSelection ? KColors.appNameColor : null,
                ),
              ),
              trailing: hasCatSelection
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: KColors.appNameColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${categorySkills.where((s) => selectedSkills.contains(s)).length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: KColors.appNameColor,
                        ),
                      ),
                    )
                  : null,
              initiallyExpanded: hasCatSelection,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categorySkills.map((skill) {
                      final isSelected = selectedSkills.contains(skill);
                      final levelColor = KSkills.skillColors[skill];
                      final chipColor = levelColor != null
                          ? KSkills.getColorForSkillLevel(levelColor, context)
                          : KColors.appNameColor;
                      final shortLabel = _skillShortLabel(category, skill);
                      return GestureDetector(
                        onTap: () => _toggleSkill(skill),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? chipColor.withValues(
                                    alpha: isDark ? 0.18 : 0.10,
                                  )
                                : (isDark
                                      ? Colors.white.withValues(alpha: 0.04)
                                      : Colors.grey.shade50),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? chipColor.withValues(alpha: 0.7)
                                  : (isDark
                                        ? Colors.white24
                                        : Colors.grey.shade300),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Barre colorée verticale (style skills_page)
                              Container(
                                width: 3,
                                height: 32,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: chipColor.withValues(
                                    alpha: isSelected ? 0.9 : 0.4,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Nom du skill
                                  Text(
                                    skill,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? chipColor
                                          : (isDark
                                                ? Colors.grey.shade300
                                                : Colors.grey.shade700),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  // Label de niveau (ex: "COD 0", "INC")
                                  Text(
                                    shortLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: isSelected
                                          ? chipColor
                                          : (isDark
                                                ? Colors.grey.shade500
                                                : Colors.grey.shade500),
                                    ),
                                  ),
                                ],
                              ),
                              // Espace fixe pour éviter le redimensionnement au clic
                              const SizedBox(width: 6),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}

// ── Widgets locaux ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(
          icon,
          size: 15,
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
