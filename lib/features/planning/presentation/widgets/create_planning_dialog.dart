import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/planning_agent_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/presentation/widgets/date_time_button.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:uuid/uuid.dart';

/// Ouvre le dialog de création d'une astreinte manuelle.
/// Retourne `true` si le planning a été créé avec succès.
Future<bool?> showCreatePlanningDialog({
  required BuildContext context,
  required String stationId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _PlanningDialog(stationId: stationId),
  );
}

/// Ouvre le dialog d'édition d'une astreinte existante.
/// Retourne `true` si le planning a été modifié avec succès.
Future<bool?> showEditPlanningDialog({
  required BuildContext context,
  required Planning planning,
  required String stationId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _PlanningDialog(stationId: stationId, existing: planning),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

enum _PlanningScope { team, agents }

class _PlanningDialog extends StatefulWidget {
  final String stationId;
  final Planning? existing;

  const _PlanningDialog({required this.stationId, this.existing});

  bool get isEdit => existing != null;

  @override
  State<_PlanningDialog> createState() => _PlanningDialogState();
}

class _PlanningDialogState extends State<_PlanningDialog> {
  DateTime? _startTime;
  DateTime? _endTime;
  _PlanningScope _scope = _PlanningScope.team;
  String? _selectedTeamId;
  List<String> _selectedAgentIds = [];

  List<Team> _teams = [];
  List<User> _users = [];
  bool _loadingData = true;
  bool _submitting = false;

  /// Agents bloqués par un remplacement actif (édition seulement).
  Set<String> _blockedAgentIds = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final teams = await TeamRepository().getByStation(widget.stationId);
      final users = await UserRepository().getByStation(widget.stationId);
      if (!mounted) return;

      // Pré-remplissage si édition
      if (widget.isEdit) {
        final p = widget.existing!;
        final baseAgents = p.agents.where((a) => a.replacedAgentId == null).toList();

        // Agents ciblés par un remplacement (ils ne peuvent pas être retirés)
        final replacedIds = p.agents
            .where((a) => a.replacedAgentId != null)
            .map((a) => a.replacedAgentId!)
            .toSet();

        final baseAgentIds = baseAgents.map((a) => a.agentId).toList();

        // Détecter le scope initial : si tous les agents de base appartiennent
        // à la même équipe et que cette équipe est déclarée sur le planning,
        // on ouvre en mode équipe ; sinon en mode agents.
        _PlanningScope initialScope;
        String? initialTeamId;
        if (p.team.isNotEmpty &&
            baseAgentIds.isNotEmpty &&
            baseAgents.every((a) {
              final user = users.firstWhere(
                (u) => u.id == a.agentId,
                orElse: () => User(
                  id: '',
                  firstName: '',
                  lastName: '',
                  station: '',
                  status: '',
                  team: '',
                  skills: [],
                ),
              );
              return user.team == p.team;
            })) {
          initialScope = _PlanningScope.team;
          initialTeamId = p.team;
        } else {
          initialScope = _PlanningScope.agents;
        }

        setState(() {
          _teams = teams..sort((a, b) => a.order.compareTo(b.order));
          _users = users..sort((a, b) => a.lastName.compareTo(b.lastName));
          _startTime = p.startTime;
          _endTime = p.endTime;
          _scope = initialScope;
          _selectedTeamId = initialTeamId;
          _selectedAgentIds = List.from(baseAgentIds);
          _blockedAgentIds = replacedIds;
          _loadingData = false;
        });
      } else {
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

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? (_startTime ?? now) : (_endTime ?? _startTime ?? now);

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final dt = DateTime.utc(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startTime = dt;
        if (_endTime != null && _endTime!.isBefore(dt)) {
          _endTime = dt.add(const Duration(hours: 12));
        }
      } else {
        _endTime = dt;
      }
    });
  }

  List<PlanningAgent> _buildBaseAgents() {
    final agentIds = _scope == _PlanningScope.team
        ? _users
            .where((u) => u.team == _selectedTeamId)
            .map((u) => u.id)
            .toList()
        : _selectedAgentIds;

    return agentIds
        .map((id) => PlanningAgent(
              agentId: id,
              start: _startTime!,
              end: _endTime!,
              levelId: '',
            ))
        .toList();
  }

  Future<void> _submit() async {
    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner les horaires.')),
      );
      return;
    }
    if (!_endTime!.isAfter(_startTime!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('L\'heure de fin doit être après le début.')),
      );
      return;
    }
    if (_scope == _PlanningScope.team && _selectedTeamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner une équipe.')),
      );
      return;
    }
    if (_scope == _PlanningScope.agents && _selectedAgentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner au moins un agent.')),
      );
      return;
    }

    // Vérifier que les agents bloqués sont toujours inclus (édition mode équipe)
    if (widget.isEdit && _blockedAgentIds.isNotEmpty) {
      if (_scope == _PlanningScope.team) {
        final teamAgentIds = _users
            .where((u) => u.team == _selectedTeamId)
            .map((u) => u.id)
            .toSet();
        final missingBlocked = _blockedAgentIds.where((id) => !teamAgentIds.contains(id));
        if (missingBlocked.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Impossible : des agents avec remplacements actifs ne font pas partie de cette équipe.',
              ),
            ),
          );
          return;
        }
      }
    }

    setState(() => _submitting = true);
    try {
      if (widget.isEdit) {
        final p = widget.existing!;
        // Préserver les entrées de remplacement existantes
        final replacementAgents = p.agents.where((a) => a.replacedAgentId != null).toList();
        final newBaseAgents = _buildBaseAgents();
        final updated = p.copyWith(
          startTime: _startTime,
          endTime: _endTime,
          team: _selectedTeamId ?? p.team,
          agents: [...newBaseAgents, ...replacementAgents],
        );
        await PlanningRepository().save(updated, stationId: widget.stationId);
      } else {
        final planning = Planning(
          id: const Uuid().v4(),
          startTime: _startTime!,
          endTime: _endTime!,
          station: widget.stationId,
          team: _selectedTeamId ?? '',
          agents: _buildBaseAgents(),
          maxAgents: 6,
          isException: true,
        );
        await PlanningRepository().save(planning, stationId: widget.stationId);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEdit = widget.isEdit;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── En-tête ────────────────────────────────────────
            Row(
              children: [
                Icon(
                  Icons.shield_moon_rounded,
                  color: KColors.appNameColor,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  isEdit ? 'Modifier l\'astreinte' : 'Créer une astreinte',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_loadingData)
              const Center(child: CircularProgressIndicator())
            else ...[
              // ── Horaires ───────────────────────────────────────
              _SectionLabel('Horaires *', isDark),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DateTimeButton(
                      label: 'Début',
                      value: _startTime,
                      onTap: () => _pickDateTime(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DateTimeButton(
                      label: 'Fin',
                      value: _endTime,
                      onTap: () => _pickDateTime(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ── Destinataires ──────────────────────────────────
              _SectionLabel('Destinataires *', isDark),
              const SizedBox(height: 8),
              _PlanningRecipientSelector(
                scope: _scope,
                isDark: isDark,
                onChanged: (s) => setState(() {
                  _scope = s;
                  _selectedTeamId = null;
                  _selectedAgentIds = [];
                }),
              ),
              const SizedBox(height: 10),
              _PlanningRecipientDetail(
                scope: _scope,
                isDark: isDark,
                teams: _teams,
                users: _users,
                selectedTeamId: _selectedTeamId,
                selectedAgentIds: _selectedAgentIds,
                blockedAgentIds: _blockedAgentIds,
                onTeamChanged: (id) => setState(() => _selectedTeamId = id),
                onAgentsChanged: (ids) => setState(() => _selectedAgentIds = ids),
              ),

              // ── Avertissement conflits (édition) ───────────────
              if (isEdit && _blockedAgentIds.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.orange.withValues(alpha: 0.15)
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade400),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange.shade700, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_blockedAgentIds.length} agent(s) ont un remplacement actif et ne peuvent pas être retirés.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.orange.shade200
                                : Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // ── Boutons ────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: KColors.appNameColor,
                      ),
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(isEdit ? 'Enregistrer' : 'Créer'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets auxiliaires
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool isDark;

  const _SectionLabel(this.text, this.isDark);

  @override
  Widget build(BuildContext context) {
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

class _PlanningRecipientSelector extends StatelessWidget {
  final _PlanningScope scope;
  final bool isDark;
  final ValueChanged<_PlanningScope> onChanged;

  const _PlanningRecipientSelector({
    required this.scope,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      (_PlanningScope.team, Icons.groups_rounded, 'Une équipe'),
      (_PlanningScope.agents, Icons.person_rounded, 'Agents spécifiques'),
    ];

    return Row(
      children: options.map((opt) {
        final (s, icon, label) = opt;
        final isSelected = scope == s;
        final isLast = s == _PlanningScope.agents;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(s),
            child: Container(
              margin: EdgeInsets.only(right: isLast ? 0 : 6),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? KColors.appNameColor.withValues(alpha: isDark ? 0.25 : 0.12)
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
                  Icon(
                    icon,
                    size: 20,
                    color: isSelected
                        ? KColors.appNameColor
                        : (isDark ? Colors.white54 : Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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

class _PlanningRecipientDetail extends StatelessWidget {
  final _PlanningScope scope;
  final bool isDark;
  final List<Team> teams;
  final List<User> users;
  final String? selectedTeamId;
  final List<String> selectedAgentIds;
  final Set<String> blockedAgentIds;
  final ValueChanged<String?> onTeamChanged;
  final ValueChanged<List<String>> onAgentsChanged;

  const _PlanningRecipientDetail({
    required this.scope,
    required this.isDark,
    required this.teams,
    required this.users,
    required this.selectedTeamId,
    required this.selectedAgentIds,
    required this.blockedAgentIds,
    required this.onTeamChanged,
    required this.onAgentsChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (scope == _PlanningScope.team) {
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
                  decoration: BoxDecoration(color: t.color, shape: BoxShape.circle),
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

    // Mode agents spécifiques
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
            blockedAgentIds: blockedAgentIds,
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
}

class _AgentMultiSelectDialog extends StatefulWidget {
  final List<User> users;
  final List<String> initialSelected;
  final Set<String> blockedAgentIds;

  const _AgentMultiSelectDialog({
    required this.users,
    required this.initialSelected,
    this.blockedAgentIds = const {},
  });

  @override
  State<_AgentMultiSelectDialog> createState() => _AgentMultiSelectDialogState();
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
            final isBlocked = widget.blockedAgentIds.contains(u.id);
            return Tooltip(
              message: isBlocked ? 'Remplacement actif — supprimer le remplacement d\'abord' : '',
              child: CheckboxListTile(
                value: _selected.contains(u.id),
                onChanged: isBlocked
                    ? null
                    : (v) => setState(() {
                          if (v == true) {
                            _selected.add(u.id);
                          } else {
                            _selected.remove(u.id);
                          }
                        }),
                title: Text(
                  '${u.firstName} ${u.lastName}',
                  style: isBlocked
                      ? TextStyle(color: Colors.grey.shade500)
                      : null,
                ),
                subtitle: Text(
                  isBlocked ? 'Remplacement actif' : 'Équipe ${u.team}',
                  style: isBlocked
                      ? TextStyle(color: Colors.orange.shade600, fontSize: 12)
                      : null,
                ),
                activeColor: KColors.appNameColor,
                dense: true,
              ),
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
