import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/team_event_model.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/services/team_event_service.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Ouvre le dialog de création d'événement d'équipe.
/// Retourne `true` si l'événement a été créé avec succès.
Future<bool?> showCreateTeamEventDialog({
  required BuildContext context,
  required String stationId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _CreateTeamEventDialog(stationId: stationId),
  );
}

/// Icônes disponibles pour les événements (partagées avec team_event_page).
const kEventIcons = <_IconOption>[
  _IconOption(Icons.local_fire_department_rounded, 'Manœuvre'),
  _IconOption(Icons.fitness_center_rounded, 'FMPA'),
  _IconOption(Icons.school_rounded, 'Formation'),
  _IconOption(Icons.groups_rounded, 'Réunion'),
  _IconOption(Icons.engineering_rounded, 'Technique'),
  _IconOption(Icons.health_and_safety_rounded, 'Sécurité'),
  _IconOption(Icons.campaign_rounded, 'Information'),
  _IconOption(Icons.event_rounded, 'Autre'),
];

class _IconOption {
  final IconData icon;
  final String label;
  const _IconOption(this.icon, this.label);
}

// ============================================================================
// DIALOG DE CRÉATION
// ============================================================================

class _CreateTeamEventDialog extends StatefulWidget {
  final String stationId;
  const _CreateTeamEventDialog({required this.stationId});

  @override
  State<_CreateTeamEventDialog> createState() => _CreateTeamEventDialogState();
}

class _CreateTeamEventDialogState extends State<_CreateTeamEventDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();

  TeamEventScope _scope = TeamEventScope.station;
  String? _selectedTeamId;
  List<String> _selectedAgentIds = [];
  int? _selectedIconCodePoint;
  DateTime? _startTime;
  DateTime? _endTime;

  List<Team> _teams = [];
  List<User> _users = [];
  bool _loadingData = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final teams = await TeamRepository().getByStation(widget.stationId);
      final users = await UserRepository().getByStation(widget.stationId);
      if (mounted) {
        setState(() {
          _teams = teams..sort((a, b) => a.order.compareTo(b.order));
          _users = users..sort((a, b) => a.lastName.compareTo(b.lastName));
          _loadingData = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner les horaires.')),
      );
      return;
    }
    if (_endTime!.isBefore(_startTime!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La fin doit être après le début.')),
      );
      return;
    }
    if (_scope == TeamEventScope.team && _selectedTeamId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sélectionnez une équipe.')));
      return;
    }
    if (_scope == TeamEventScope.agents && _selectedAgentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez au moins un agent.')),
      );
      return;
    }

    final creator = await UserStorageHelper.loadUser();
    if (creator == null) return;

    setState(() => _submitting = true);

    try {
      final draft = TeamEvent(
        id: '',
        createdById: creator.id,
        createdByName: '${creator.firstName} ${creator.lastName}',
        title: _titleController.text.trim(),
        iconCodePoint: _selectedIconCodePoint,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        startTime: _startTime!,
        endTime: _endTime!,
        stationId: widget.stationId,
        scope: _scope,
        teamId: _scope == TeamEventScope.team ? _selectedTeamId : null,
        targetAgentIds:
            _scope == TeamEventScope.agents ? _selectedAgentIds : const [],
        status: TeamEventStatus.upcoming,
        createdAt: DateTime.now(),
      );

      await TeamEventService().createEvent(draft: draft, createdBy: creator);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: _loadingData
          ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── En-tête ──────────────────────────────────────
                    Row(
                      children: [
                        const Icon(Icons.event_rounded,
                            color: KColors.appNameColor, size: 22),
                        const SizedBox(width: 8),
                        const Text(
                          'Créer un évènement',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: KColors.appNameColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // ── Corps du formulaire partagé ──────────────────
                    EventFormBody(
                      titleController: _titleController,
                      descriptionController: _descriptionController,
                      locationController: _locationController,
                      selectedIconCodePoint: _selectedIconCodePoint,
                      startTime: _startTime,
                      endTime: _endTime,
                      scope: _scope,
                      selectedTeamId: _selectedTeamId,
                      selectedAgentIds: _selectedAgentIds,
                      teams: _teams,
                      users: _users,
                      onIconSelected: (cp) =>
                          setState(() => _selectedIconCodePoint = cp),
                      onStartTimeChanged: (dt) => setState(() {
                        _startTime = dt;
                        if (_endTime != null && _endTime!.isBefore(dt)) {
                          _endTime = dt.add(const Duration(hours: 2));
                        }
                      }),
                      onEndTimeChanged: (dt) =>
                          setState(() => _endTime = dt),
                      onScopeChanged: (s) => setState(() => _scope = s),
                      onTeamChanged: (t) =>
                          setState(() => _selectedTeamId = t),
                      onAgentsChanged: (ids) =>
                          setState(() => _selectedAgentIds = ids),
                    ),

                    const SizedBox(height: 20),

                    // ── Boutons ───────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _submitting
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text('Annuler'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _submitting ? null : _submit,
                            style: FilledButton.styleFrom(
                                backgroundColor: KColors.appNameColor),
                            child: _submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Créer'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ============================================================================
// CORPS DE FORMULAIRE PARTAGÉ (création + édition)
// ============================================================================

/// Widget réutilisable contenant les champs du formulaire d'événement.
/// Utilisé à la fois dans [_CreateTeamEventDialog] et [_EditEventDialog].
class EventFormBody extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final TextEditingController locationController;
  final int? selectedIconCodePoint;
  final DateTime? startTime;
  final DateTime? endTime;
  final TeamEventScope scope;
  final String? selectedTeamId;
  final List<String> selectedAgentIds;
  final List<Team> teams;
  final List<User> users;

  final ValueChanged<int?> onIconSelected;
  final ValueChanged<DateTime> onStartTimeChanged;
  final ValueChanged<DateTime> onEndTimeChanged;
  final ValueChanged<TeamEventScope> onScopeChanged;
  final ValueChanged<String?> onTeamChanged;
  final ValueChanged<List<String>> onAgentsChanged;

  /// Si null, la section destinataires est affichée (création).
  /// Si non null, elle est masquée (édition — destinataires immuables).
  final bool showScope;

  const EventFormBody({
    super.key,
    required this.titleController,
    required this.descriptionController,
    required this.locationController,
    required this.selectedIconCodePoint,
    required this.startTime,
    required this.endTime,
    required this.scope,
    required this.selectedTeamId,
    required this.selectedAgentIds,
    required this.teams,
    required this.users,
    required this.onIconSelected,
    required this.onStartTimeChanged,
    required this.onEndTimeChanged,
    required this.onScopeChanged,
    required this.onTeamChanged,
    required this.onAgentsChanged,
    this.showScope = true,
  });

  Future<void> _pickDateTime(BuildContext context,
      {required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (startTime ?? now)
        : (endTime ?? startTime ?? now);

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;
    if (!context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final dt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (isStart) {
      onStartTimeChanged(dt);
    } else {
      onEndTimeChanged(dt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Titre ────────────────────────────────────────────
        TextFormField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: 'Titre *',
            hintText: 'ex: Manœuvre générale',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Requis' : null,
        ),
        const SizedBox(height: 14),

        // ── Icône ────────────────────────────────────────────
        _SectionLabel('Icône (optionnel)'),
        const SizedBox(height: 8),
        EventIconPicker(
          selected: selectedIconCodePoint,
          onSelect: onIconSelected,
        ),
        const SizedBox(height: 14),

        // ── Horaires ─────────────────────────────────────────
        _SectionLabel('Horaires *'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _DateTimeButton(
                label: 'Début',
                value: startTime,
                onTap: () => _pickDateTime(context, isStart: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DateTimeButton(
                label: 'Fin',
                value: endTime,
                onTap: () => _pickDateTime(context, isStart: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ── Lieu ─────────────────────────────────────────────
        TextFormField(
          controller: locationController,
          decoration: const InputDecoration(
            labelText: 'Lieu (optionnel)',
            border: OutlineInputBorder(),
            isDense: true,
            prefixIcon: Icon(Icons.location_on_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 10),

        // ── Description ───────────────────────────────────────
        TextFormField(
          controller: descriptionController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Description (optionnel)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),

        // ── Destinataires (création seulement) ───────────────
        if (showScope) ...[
          const SizedBox(height: 14),
          _SectionLabel('Destinataires *'),
          const SizedBox(height: 8),
          _ScopeSelector(
            scope: scope,
            isDark: isDark,
            onChanged: onScopeChanged,
          ),
          const SizedBox(height: 8),
          _ScopeDetail(
            scope: scope,
            isDark: isDark,
            teams: teams,
            users: users,
            selectedTeamId: selectedTeamId,
            selectedAgentIds: selectedAgentIds,
            onTeamChanged: onTeamChanged,
            onAgentsChanged: onAgentsChanged,
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// WIDGETS AUXILIAIRES PARTAGÉS
// ============================================================================

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white54 : Colors.grey.shade600,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _DateTimeButton extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const _DateTimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = DateFormat('dd/MM HH:mm');
    final hasValue = value != null;

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(
        Icons.schedule_rounded,
        size: 16,
        color: hasValue ? KColors.appNameColor : null,
      ),
      label: Text(
        hasValue ? fmt.format(value!) : label,
        style: TextStyle(
          color: hasValue
              ? KColors.appNameColor
              : (isDark ? Colors.white54 : Colors.grey.shade600),
          fontSize: 13,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        side: BorderSide(
          color: hasValue
              ? KColors.appNameColor.withValues(alpha: 0.5)
              : (isDark ? Colors.white24 : Colors.grey.shade400),
        ),
      ),
    );
  }
}

/// Sélecteur d'icône pour les événements — exporté pour réutilisation.
class EventIconPicker extends StatelessWidget {
  final int? selected;
  final ValueChanged<int?> onSelect;

  const EventIconPicker({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Option "aucune icône"
        GestureDetector(
          onTap: () => onSelect(null),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected == null
                    ? KColors.appNameColor
                    : (isDark ? Colors.white24 : Colors.grey.shade300),
                width: selected == null ? 2 : 1,
              ),
              color: selected == null
                  ? KColors.appNameColor.withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            child: Icon(
              Icons.block_rounded,
              size: 20,
              color: isDark ? Colors.white38 : Colors.grey.shade400,
            ),
          ),
        ),
        ...kEventIcons.map((opt) {
          final isSelected = selected == opt.icon.codePoint;
          return GestureDetector(
            onTap: () => onSelect(isSelected ? null : opt.icon.codePoint),
            child: Tooltip(
              message: opt.label,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? KColors.appNameColor
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.grey.shade300),
                    width: isSelected ? 2 : 1,
                  ),
                  color: isSelected
                      ? KColors.appNameColor.withValues(alpha: 0.12)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.grey.shade50),
                ),
                child: Icon(
                  opt.icon,
                  size: 20,
                  color: isSelected
                      ? KColors.appNameColor
                      : (isDark ? Colors.white60 : Colors.grey.shade600),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _ScopeSelector extends StatelessWidget {
  final TeamEventScope scope;
  final bool isDark;
  final ValueChanged<TeamEventScope> onChanged;

  const _ScopeSelector({
    required this.scope,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      (TeamEventScope.station, Icons.apartment_rounded, 'Toute la caserne'),
      (TeamEventScope.team, Icons.group_rounded, 'Une équipe'),
      (TeamEventScope.agents, Icons.person_rounded, 'Agents spécifiques'),
    ];

    return Row(
      children: options.map((opt) {
        final (s, icon, label) = opt;
        final isSelected = scope == s;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(s),
            child: Container(
              margin: EdgeInsets.only(
                  right: s == TeamEventScope.agents ? 0 : 6),
              padding:
                  const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? KColors.appNameColor
                        .withValues(alpha: isDark ? 0.25 : 0.12)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? KColors.appNameColor.withValues(alpha: 0.6)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.grey.shade300),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 20,
                      color: isSelected
                          ? KColors.appNameColor
                          : (isDark ? Colors.white54 : Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected
                          ? KColors.appNameColor
                          : (isDark ? Colors.white54 : Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ScopeDetail extends StatelessWidget {
  final TeamEventScope scope;
  final bool isDark;
  final List<Team> teams;
  final List<User> users;
  final String? selectedTeamId;
  final List<String> selectedAgentIds;
  final ValueChanged<String?> onTeamChanged;
  final ValueChanged<List<String>> onAgentsChanged;

  const _ScopeDetail({
    required this.scope,
    required this.isDark,
    required this.teams,
    required this.users,
    required this.selectedTeamId,
    required this.selectedAgentIds,
    required this.onTeamChanged,
    required this.onAgentsChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (scope == TeamEventScope.team) {
      return DropdownButtonFormField<String>(
        value: selectedTeamId,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          labelText: 'Équipe',
        ),
        hint: const Text('Sélectionner une équipe'),
        items: teams.map((t) {
          return DropdownMenuItem(
            value: t.id,
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration:
                      BoxDecoration(color: t.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(t.name),
              ],
            ),
          );
        }).toList(),
        onChanged: onTeamChanged,
      );
    }

    if (scope == TeamEventScope.agents) {
      final selected = users
          .where((u) => selectedAgentIds.contains(u.id))
          .map((u) => '${u.firstName} ${u.lastName}')
          .join(', ');
      return OutlinedButton.icon(
        onPressed: () async {
          final result = await showDialog<List<String>>(
            context: context,
            builder: (_) => _AgentMultiSelectDialog(
              users: users,
              initialSelected: selectedAgentIds,
            ),
          );
          if (result != null) onAgentsChanged(result);
        },
        icon: const Icon(Icons.people_outline_rounded, size: 18),
        label: Text(
          selectedAgentIds.isEmpty
              ? 'Sélectionner des agents…'
              : '${selectedAgentIds.length} agent(s) : $selected',
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _AgentMultiSelectDialog extends StatefulWidget {
  final List<User> users;
  final List<String> initialSelected;

  const _AgentMultiSelectDialog({
    required this.users,
    required this.initialSelected,
  });

  @override
  State<_AgentMultiSelectDialog> createState() =>
      _AgentMultiSelectDialogState();
}

class _AgentMultiSelectDialogState extends State<_AgentMultiSelectDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSelected);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sélectionner des agents'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.users.length,
          itemBuilder: (_, i) {
            final u = widget.users[i];
            return CheckboxListTile(
              value: _selected.contains(u.id),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(u.id);
                } else {
                  _selected.remove(u.id);
                }
              }),
              title: Text('${u.firstName} ${u.lastName}'),
              subtitle: Text('Équipe ${u.team}'),
              activeColor: KColors.appNameColor,
              dense: true,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
