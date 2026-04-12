import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/team_event_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/repositories/team_event_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/services/team_event_service.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';
import 'package:nexshift_app/features/team_events/presentation/widgets/create_team_event_dialog.dart';

/// Page dédiée à un événement d'équipe.
class TeamEventPage extends StatefulWidget {
  final TeamEvent event;

  const TeamEventPage({super.key, required this.event});

  @override
  State<TeamEventPage> createState() => _TeamEventPageState();
}

class _TeamEventPageState extends State<TeamEventPage> {
  late TeamEvent _event;
  User? _currentUser;
  List<User> _allUsers = [];
  bool _isLoading = true;
  String? _stationName;

  final _eventService = TeamEventService();
  final _userRepository = UserRepository();
  late final Stream<TeamEvent?> _eventStream;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _eventStream = TeamEventRepository().watchById(
      eventId: _event.id,
      stationId: _event.stationId,
    );
    _loadData();
  }

  Future<void> _loadData() async {
    final user = await UserStorageHelper.loadUser();
    final sdisId = SDISContext().currentSDISId;
    final stationName = await StationNameCache()
        .getStationName(sdisId ?? '', _event.stationId);

    List<User> users = [];
    try {
      users = await _userRepository.getByStation(_event.stationId);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _currentUser = user;
        _allUsers = users;
        _stationName = stationName;
        _isLoading = false;
      });
    }
  }

  bool get _isOrganizer => _currentUser?.id == _event.createdById;

  bool get _canManage =>
      _isOrganizer ||
      (_currentUser?.admin ?? false) ||
      (_currentUser?.status == KConstants.statusLeader);

  bool get _hasAccepted =>
      _currentUser != null && _event.acceptedUserIds.contains(_currentUser!.id);

  bool get _hasDeclined =>
      _currentUser != null && _event.declinedUserIds.contains(_currentUser!.id);

  /// L'agent courant est invité (peut répondre)
  bool get _isInvited =>
      _currentUser != null && _event.invitedUserIds.contains(_currentUser!.id);

  bool get _isPast => _event.endTime.isBefore(DateTime.now());

  String _formatDateRange() {
    final fmt = DateFormat('dd/MM HH:mm');
    return '${fmt.format(_event.startTime)} → ${fmt.format(_event.endTime)}';
  }

  User? _userById(String id) {
    try {
      return _allUsers.firstWhere((u) => u.id == id);
    } catch (_) {
      return null;
    }
  }

  String _displayName(String userId) {
    final u = _userById(userId);
    if (u == null) return userId;
    return '${u.firstName} ${u.lastName}';
  }

  Future<void> _respond(bool accepted) async {
    if (_currentUser == null) return;
    await _eventService.respondToEvent(
      event: _event,
      userId: _currentUser!.id,
      accepted: accepted,
    );
  }

  Future<void> _removeAgent(String agentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer le participant'),
        content: Text(
            'Retirer ${_displayName(agentId)} de l\'événement ? Il ne pourra plus le voir.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _eventService.removeAgent(
      eventId: _event.id,
      stationId: _event.stationId,
      agentId: agentId,
    );
  }

  Future<void> _editEvent() async {
    final updated = await showDialog<TeamEvent>(
      context: context,
      builder: (_) => _EditEventDialog(event: _event),
    );
    if (updated == null) return;
    await TeamEventRepository().update(event: updated, stationId: updated.stationId);
  }

  Future<void> _cancelEvent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler l\'événement'),
        content: const Text(
            'Cette action est irréversible. Confirmer l\'annulation ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Non')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _eventService.cancelEvent(event: _event);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _showAddAgentDialog() async {
    final alreadyIn = {
      ..._event.invitedUserIds,
      ..._event.acceptedUserIds,
      ..._event.declinedUserIds,
    };
    final candidates = _allUsers
        .where((u) => !alreadyIn.contains(u.id))
        .toList()
      ..sort((a, b) => a.lastName.compareTo(b.lastName));

    if (candidates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tous les agents sont déjà invités.')),
        );
      }
      return;
    }

    final selected = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _AddAgentDialog(candidates: candidates),
    );

    if (selected == null || selected.isEmpty) return;
    for (final id in selected) {
      await _eventService.addAgent(
        eventId: _event.id,
        stationId: _event.stationId,
        agentId: id,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TeamEvent?>(
      stream: _eventStream,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          _event = snapshot.data!;
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final isCancelled = _event.status == TeamEventStatus.cancelled;

        return Scaffold(
          appBar: CustomAppBar(
            title: _event.title,
            bottomColor: KColors.appNameColor,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHeader(isDark, isCancelled),
                    const SizedBox(height: 20),
                    if (!isCancelled) _buildRsvpSection(isDark),
                    if (!isCancelled) const SizedBox(height: 20),
                    _buildAgentSection(isDark),
                    const SizedBox(height: 24),
                    if (!isCancelled) ..._buildActions(isDark),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildHeader(bool isDark, bool isCancelled) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? KColors.appNameColor.withValues(alpha: 0.12)
            : KColors.appNameColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: KColors.appNameColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_event.iconCodePoint != null) ...[
                Icon(
                  IconData(_event.iconCodePoint!, fontFamily: 'MaterialIcons'),
                  color: KColors.appNameColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _event.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: KColors.appNameColor,
                  ),
                ),
              ),
              if (_canManage && !_isPast && !isCancelled)
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  color: KColors.appNameColor,
                  tooltip: 'Modifier',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _editEvent,
                ),
              if (isCancelled)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Annulé',
                    style: TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.schedule_rounded,
                  size: 15,
                  color: isDark ? Colors.white60 : Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                _formatDateRange(),
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey.shade700,
                ),
              ),
            ],
          ),
          if (_event.location != null && _event.location!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.location_on_rounded,
                    size: 15,
                    color: isDark ? Colors.white60 : Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _event.location!,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_event.description != null &&
              _event.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _event.description!,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (_stationName != null) ...[
            const SizedBox(height: 8),
            Text(
              _stationName!,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRsvpSection(bool isDark) {
    final total = _event.invitedUserIds.length + 1; // +1 organisateur
    final accepted = _event.acceptedUserIds.length;
    final declined = _event.declinedUserIds.length;
    final pending = (total - accepted - declined).clamp(0, total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Réponses',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white54 : Colors.grey.shade600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        // Jauge segmentée [Vert | Gris | Rouge]
        if (total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                if (accepted > 0)
                  Flexible(
                    flex: accepted,
                    child: Container(height: 6, color: Colors.green),
                  ),
                if (pending > 0)
                  Flexible(
                    flex: pending,
                    child: Container(
                      height: 6,
                      color: isDark ? Colors.white12 : Colors.grey.shade300,
                    ),
                  ),
                if (declined > 0)
                  Flexible(
                    flex: declined,
                    child: Container(height: 6, color: Colors.red.shade400),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            _RsvpChip(
              count: accepted,
              label: 'Accepté',
              color: Colors.green,
              icon: Icons.check_circle_outline_rounded,
            ),
            const SizedBox(width: 8),
            _RsvpChip(
              count: pending,
              label: 'En attente',
              color: Colors.grey,
              icon: Icons.schedule_rounded,
            ),
            const SizedBox(width: 8),
            _RsvpChip(
              count: declined,
              label: 'Refusé',
              color: Colors.red,
              icon: Icons.cancel_outlined,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAgentSection(bool isDark) {
    // Tous les participants connus (union de toutes les listes)
    final allKnownIds = {
      ..._event.acceptedUserIds,
      ..._event.invitedUserIds,
      ..._event.declinedUserIds,
    };

    if (allKnownIds.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Participants',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white54 : Colors.grey.shade600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        // Acceptés
        ..._event.acceptedUserIds
            .map((id) => _buildAgentTile(id, _AgentStatus.accepted, isDark)),
        // En attente (invités non répondus)
        ..._event.invitedUserIds
            .where((id) =>
                !_event.acceptedUserIds.contains(id) &&
                !_event.declinedUserIds.contains(id))
            .map((id) => _buildAgentTile(id, _AgentStatus.pending, isDark)),
        // Refusés
        ..._event.declinedUserIds
            .map((id) => _buildAgentTile(id, _AgentStatus.declined, isDark)),
      ],
    );
  }

  Widget _buildAgentTile(String agentId, _AgentStatus status, bool isDark) {
    final name = _displayName(agentId);
    final isSelf = _currentUser?.id == agentId;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case _AgentStatus.accepted:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_rounded;
        break;
      case _AgentStatus.declined:
        statusColor = Colors.red;
        statusIcon = Icons.cancel_rounded;
        break;
      case _AgentStatus.pending:
        statusColor = Colors.grey;
        statusIcon = Icons.schedule_rounded;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(statusIcon, size: 18, color: statusColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    isSelf ? FontWeight.w600 : FontWeight.w500,
                color: isDark ? Colors.white : Colors.grey.shade800,
              ),
            ),
          ),
          // Bouton retrait (canManage, pas soi-même si organisateur)
          if (_canManage && !(_isOrganizer && isSelf)) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _removeAgent(agentId),
              child: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildActions(bool isDark) {
    final actions = <Widget>[];

    // ─── Boutons RSVP pour l'agent courant (non-organisateur, invité) ───
    if (!_isOrganizer && _currentUser != null && !_isPast) {
      if (_hasAccepted) {
        // A accepté → peut se désister
        actions.add(_rsvpButton(
          label: 'Je ne participe plus',
          icon: Icons.event_busy_rounded,
          color: Colors.orange,
          onPressed: () => _respond(false),
        ));
        actions.add(const SizedBox(height: 10));
      } else if (_hasDeclined) {
        // A refusé → peut finalement accepter
        actions.add(_rsvpButton(
          label: 'Je participe',
          icon: Icons.event_available_rounded,
          color: Colors.green,
          onPressed: () => _respond(true),
        ));
        actions.add(const SizedBox(height: 10));
      } else if (_isInvited) {
        // En attente de réponse
        actions.add(_rsvpButton(
          label: 'Je participe',
          icon: Icons.event_available_rounded,
          color: Colors.green,
          onPressed: () => _respond(true),
        ));
        actions.add(const SizedBox(height: 8));
        actions.add(_rsvpButton(
          label: 'Je ne participe pas',
          icon: Icons.event_busy_rounded,
          color: Colors.orange,
          onPressed: () => _respond(false),
        ));
        actions.add(const SizedBox(height: 10));
      }
    }

    // ─── Ajouter un agent (canManage) ───
    if (_canManage) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showAddAgentDialog,
            icon: const Icon(Icons.person_add_rounded),
            label: const Text('Ajouter un agent'),
          ),
        ),
      );
      actions.add(const SizedBox(height: 10));
    }

    // ─── Annuler l'événement (canManage) ───
    if (_canManage) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _cancelEvent,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Annuler l\'événement'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
          ),
        ),
      );
    }

    return actions;
  }

  Widget _rsvpButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
        ),
      ),
    );
  }
}

// ============================================================================
// WIDGETS AUXILIAIRES
// ============================================================================

enum _AgentStatus { accepted, declined, pending }

class _RsvpChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  final IconData icon;

  const _RsvpChip({
    required this.count,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: color, fontSize: 14),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: 11,
                    color: color.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog d'édition — réutilise [EventFormBody] de create_team_event_dialog.dart.
class _EditEventDialog extends StatefulWidget {
  final TeamEvent event;
  const _EditEventDialog({required this.event});

  @override
  State<_EditEventDialog> createState() => _EditEventDialogState();
}

class _EditEventDialogState extends State<_EditEventDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _descriptionCtrl;
  late DateTime _startTime;
  late DateTime _endTime;
  int? _selectedIconCodePoint;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.event.title);
    _locationCtrl = TextEditingController(text: widget.event.location ?? '');
    _descriptionCtrl = TextEditingController(text: widget.event.description ?? '');
    _startTime = widget.event.startTime;
    _endTime = widget.event.endTime;
    _selectedIconCodePoint = widget.event.iconCodePoint;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier l\'événement'),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: EventFormBody(
              titleController: _titleCtrl,
              descriptionController: _descriptionCtrl,
              locationController: _locationCtrl,
              selectedIconCodePoint: _selectedIconCodePoint,
              startTime: _startTime,
              endTime: _endTime,
              scope: TeamEventScope.station,
              selectedTeamId: null,
              selectedAgentIds: const [],
              teams: const [],
              users: const [],
              onIconSelected: (cp) => setState(() => _selectedIconCodePoint = cp),
              onStartTimeChanged: (dt) => setState(() {
                _startTime = dt;
                if (_endTime.isBefore(_startTime)) {
                  _endTime = _startTime.add(const Duration(hours: 2));
                }
              }),
              onEndTimeChanged: (dt) => setState(() => _endTime = dt),
              onScopeChanged: (_) {},
              onTeamChanged: (_) {},
              onAgentsChanged: (_) {},
              showScope: false,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: KColors.appNameColor),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            if (_endTime.isBefore(_startTime)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('La fin doit être après le début.')),
              );
              return;
            }
            final updated = widget.event.copyWith(
              title: _titleCtrl.text.trim(),
              iconCodePoint: _selectedIconCodePoint,
              clearIconCodePoint: _selectedIconCodePoint == null,
              startTime: _startTime,
              endTime: _endTime,
              location: _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
              clearLocation: _locationCtrl.text.trim().isEmpty,
              description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
              clearDescription: _descriptionCtrl.text.trim().isEmpty,
            );
            Navigator.pop(context, updated);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

/// Dialog de sélection multi-agents.
class _AddAgentDialog extends StatefulWidget {
  final List<User> candidates;

  const _AddAgentDialog({required this.candidates});

  @override
  State<_AddAgentDialog> createState() => _AddAgentDialogState();
}

class _AddAgentDialogState extends State<_AddAgentDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter des agents'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.candidates.length,
          itemBuilder: (_, i) {
            final u = widget.candidates[i];
            final isSelected = _selected.contains(u.id);
            return CheckboxListTile(
              value: isSelected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(u.id);
                  } else {
                    _selected.remove(u.id);
                  }
                });
              },
              title: Text('${u.firstName} ${u.lastName}'),
              subtitle: Text('Équipe ${u.team}'),
              activeColor: KColors.appNameColor,
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
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected.toList()),
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}
