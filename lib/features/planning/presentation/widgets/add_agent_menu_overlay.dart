import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/on_call_level_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/features/replacement/presentation/pages/skill_search_page.dart';

/// Widget réutilisable pour afficher le menu d'ajout d'agent avec trois options :
/// - Choix automatique (recherche par compétences → AgentQuery)
/// - Choix manuel (sélection directe depuis la liste d'agents)
/// - Ajouter en disponibilité (formulaire inline chef/admin)
class AddAgentMenuOverlay {
  /// Construit le contenu du menu (utilisable dans un Overlay ou BottomSheet).
  static Widget buildMenuContent({
    required BuildContext context,
    required Planning planning,
    required User currentUser,
    required List<OnCallLevel> onCallLevels,
    required VoidCallback onOptionSelected,
    required VoidCallback onManualChoice,
    List<User> allUsers = const [],
    Future<void> Function(String agentId, String levelId, DateTime start, DateTime end)? onAddAvailability,
  }) {
    return _AddAgentMenuContent(
      planning: planning,
      currentUser: currentUser,
      onCallLevels: onCallLevels,
      onOptionSelected: onOptionSelected,
      onManualChoice: onManualChoice,
      allUsers: allUsers,
      onAddAvailability: onAddAvailability,
    );
  }

  /// Affiche un BottomSheet avec les options d'ajout d'agent.
  static void showAsBottomSheet({
    required BuildContext context,
    required Planning planning,
    required User currentUser,
    required List<OnCallLevel> onCallLevels,
    required VoidCallback onManualChoice,
    List<User> allUsers = const [],
    Future<void> Function(String agentId, String levelId, DateTime start, DateTime end)? onAddAvailability,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => _AddAgentMenuContent(
        planning: planning,
        currentUser: currentUser,
        onCallLevels: onCallLevels,
        onOptionSelected: () => Navigator.pop(ctx),
        onManualChoice: onManualChoice,
        allUsers: allUsers,
        onAddAvailability: onAddAvailability,
      ),
    );
  }
}

class _AddAgentMenuContent extends StatefulWidget {
  final Planning planning;
  final User currentUser;
  final List<OnCallLevel> onCallLevels;
  final VoidCallback onOptionSelected;
  final VoidCallback onManualChoice;
  final List<User> allUsers;
  final Future<void> Function(String agentId, String levelId, DateTime start, DateTime end)? onAddAvailability;

  const _AddAgentMenuContent({
    required this.planning,
    required this.currentUser,
    required this.onCallLevels,
    required this.onOptionSelected,
    required this.onManualChoice,
    required this.allUsers,
    this.onAddAvailability,
  });

  @override
  State<_AddAgentMenuContent> createState() => _AddAgentMenuContentState();
}

class _AddAgentMenuContentState extends State<_AddAgentMenuContent> {
  bool _showAvailabilityForm = false;

  List<OnCallLevel> get _availabilityLevels =>
      widget.onCallLevels.where((l) => l.isAvailability).toList();

  @override
  Widget build(BuildContext context) {
    if (_showAvailabilityForm) {
      return _AddAvailabilityInlineForm(
        planning: widget.planning,
        allUsers: widget.allUsers,
        availabilityLevels: _availabilityLevels,
        onConfirm: (agentId, levelId, start, end) async {
          if (widget.onAddAvailability != null) {
            await widget.onAddAvailability!(agentId, levelId, start, end);
          }
          widget.onOptionSelected();
        },
        onBack: () => setState(() => _showAvailabilityForm = false),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Choix automatique
          _AddAgentOption(
            icon: Icons.manage_search_rounded,
            iconColor: Colors.teal,
            title: 'Choix automatique',
            subtitle: 'Recherche par compétences',
            onTap: () {
              widget.onOptionSelected();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SkillSearchPage(
                    planning: widget.planning,
                    currentUser: widget.currentUser,
                    onCallLevels: widget.onCallLevels,
                    launchAsAgentQuery: true,
                  ),
                ),
              );
            },
          ),
          Divider(height: 1, color: Colors.grey[300]),
          // Choix manuel
          _AddAgentOption(
            icon: Icons.person_add_rounded,
            iconColor: Colors.blue,
            title: 'Choix manuel',
            subtitle: 'Sélectionner directement un agent',
            onTap: () {
              widget.onOptionSelected();
              widget.onManualChoice();
            },
          ),
          // Option disponibilité (uniquement si des niveaux dispo existent)
          if (_availabilityLevels.isNotEmpty && widget.onAddAvailability != null) ...[
            Divider(height: 1, color: Colors.grey[300]),
            _AddAgentOption(
              icon: Icons.volunteer_activism_rounded,
              iconColor: Colors.orange,
              title: 'Ajouter en disponibilité',
              subtitle: 'Déclarer un agent disponible sur ce planning',
              onTap: () => setState(() => _showAvailabilityForm = true),
            ),
          ],
        ],
      ),
    );
  }
}

/// Formulaire inline pour ajouter un agent en disponibilité (chef/admin).
class _AddAvailabilityInlineForm extends StatefulWidget {
  final Planning planning;
  final List<User> allUsers;
  final List<OnCallLevel> availabilityLevels;
  final Future<void> Function(String agentId, String levelId, DateTime start, DateTime end) onConfirm;
  final VoidCallback onBack;

  const _AddAvailabilityInlineForm({
    required this.planning,
    required this.allUsers,
    required this.availabilityLevels,
    required this.onConfirm,
    required this.onBack,
  });

  @override
  State<_AddAvailabilityInlineForm> createState() =>
      _AddAvailabilityInlineFormState();
}

class _AddAvailabilityInlineFormState
    extends State<_AddAvailabilityInlineForm> {
  User? _selectedAgent;
  OnCallLevel? _selectedLevel;
  late DateTime _start;
  late DateTime _end;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _start = widget.planning.startTime;
    _end = widget.planning.endTime;
    if (widget.availabilityLevels.length == 1) {
      _selectedLevel = widget.availabilityLevels.first;
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = (isStart ? _start : _end).toUtc();
    final firstDate = isStart ? DateTime.now() : _start.toUtc();

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: initial.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (time == null || !mounted) return;

    final picked = DateTime.utc(
        date.year, date.month, date.day, time.hour, time.minute);

    setState(() {
      if (isStart) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
      } else {
        if (picked.isAfter(_start)) _end = picked;
      }
    });
  }

  Future<void> _confirm() async {
    if (_selectedAgent == null || _selectedLevel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un agent et un niveau'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await widget.onConfirm(
          _selectedAgent!.id, _selectedLevel!.id, _start, _end);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM HH:mm');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header avec bouton retour
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: widget.onBack,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              const Text(
                'Ajouter en disponibilité',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Sélection agent
          DropdownButtonFormField<User>(
            decoration: InputDecoration(
              labelText: 'Agent',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            value: _selectedAgent,
            items: widget.allUsers
                .map((u) => DropdownMenuItem(
                      value: u,
                      child: Text(u.displayName,
                          style: const TextStyle(fontSize: 14)),
                    ))
                .toList(),
            onChanged: (u) => setState(() => _selectedAgent = u),
          ),
          const SizedBox(height: 10),

          // Sélection niveau
          if (widget.availabilityLevels.length == 1)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _selectedLevel?.color ?? Colors.grey,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _selectedLevel?.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedLevel?.name ?? '',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _selectedLevel?.color),
                  ),
                ],
              ),
            )
          else
            DropdownButtonFormField<OnCallLevel>(
              decoration: InputDecoration(
                labelText: 'Niveau de disponibilité',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              value: _selectedLevel,
              items: widget.availabilityLevels
                  .map((l) => DropdownMenuItem(
                        value: l,
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: l.color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Text(l.name,
                                style: const TextStyle(fontSize: 14)),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (l) => setState(() => _selectedLevel = l),
            ),
          const SizedBox(height: 10),

          // Horaires
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickTime(true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Début',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                        const SizedBox(height: 2),
                        Text(fmt.format(_start.toUtc()),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 16),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickTime(false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Fin',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                        const SizedBox(height: 2),
                        Text(fmt.format(_end.toUtc()),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Bouton confirmer
          FilledButton.icon(
            onPressed: _isLoading ? null : _confirm,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check, size: 18),
            label: const Text('Confirmer'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddAgentOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AddAgentOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
