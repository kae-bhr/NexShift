import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/availability_model.dart';
import 'package:nexshift_app/core/data/models/on_call_level_model.dart';
import 'package:nexshift_app/core/data/models/planning_agent_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/presentation/widgets/diagonal_stripe_painter.dart';
import 'package:nexshift_app/core/services/on_call_disposition_service.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/planning/presentation/widgets/add_agent_menu_overlay.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/presentation/widgets/contextual_menu_button.dart';
import 'package:nexshift_app/core/services/preferences_service.dart';

class _PersonalSlot {
  final AgentPresenceSlot slot;
  final OnCallLevel level;
  final bool isAvailability;
  final String? replacedAgentName;
  const _PersonalSlot({
    required this.slot,
    required this.level,
    required this.isAvailability,
    this.replacedAgentName,
  });
}

/// Section affichant les agents présents dans une garde, groupés par niveau d'astreinte.
/// Lit directement depuis planning.agents — source unique de vérité.
class OnCallPresenceSection extends StatefulWidget {
  final Planning planning;
  final List<OnCallLevel> levels;
  final Station station;
  final List<User> allUsers;
  final User currentUser;

  /// Callbacks unifiés
  final Future<void> Function(PlanningAgent entry)? onToggleCheck;
  final Future<void> Function(PlanningAgent entry)? onRemoveEntry;
  final Future<void> Function(PlanningAgent entry)? onEditEntry;
  final VoidCallback? onAddAgent;

  /// Disponibilités à afficher sous les niveaux isAvailability
  final List<Availability> availabilities;

  /// Callback pour supprimer une disponibilité (chef/admin)
  final Future<void> Function(Availability availability)? onRemoveAvailability;

  /// Callback pour ajouter un agent en disponibilité (chef/admin)
  final Future<void> Function(
    String agentId,
    String levelId,
    DateTime start,
    DateTime end,
  )?
  onAddAvailability;

  /// Permissions
  final bool canManage;

  const OnCallPresenceSection({
    super.key,
    required this.planning,
    required this.levels,
    required this.station,
    required this.allUsers,
    required this.currentUser,
    this.onToggleCheck,
    this.onRemoveEntry,
    this.onEditEntry,
    this.onAddAgent,
    this.availabilities = const [],
    this.onRemoveAvailability,
    this.onAddAvailability,
    this.canManage = false,
  });

  @override
  State<OnCallPresenceSection> createState() => _OnCallPresenceSectionState();
}

class _OnCallPresenceSectionState extends State<OnCallPresenceSection> {
  @override
  void initState() {
    super.initState();
    presenceViewModeNotifier.addListener(_onViewModeChanged);
  }

  @override
  void dispose() {
    presenceViewModeNotifier.removeListener(_onViewModeChanged);
    super.dispose();
  }

  void _onViewModeChanged() => setState(() {});

  User _findUser(String id) {
    return widget.allUsers.firstWhere(
      (u) => u.id == id,
      orElse: () => User(
        id: id,
        firstName: 'Inconnu',
        lastName: '',
        station: '',
        status: '',
        team: '',
        skills: [],
      ),
    );
  }

  /// Trouve le PlanningAgent correspondant à un AgentPresenceSlot
  PlanningAgent? _findPlanningAgent(AgentPresenceSlot slot) {
    try {
      return widget.planning.agents.firstWhere(
        (a) =>
            a.agentId == slot.agentId &&
            a.start.isAtSameMomentAs(slot.start) &&
            a.end.isAtSameMomentAs(slot.end) &&
            a.replacedAgentId == slot.replacedAgentId,
      );
    } catch (_) {
      return null;
    }
  }

  List<Widget> _buildPersonalView(BuildContext context, bool isDark) {
    final disposition = OnCallDispositionService.computeDisposition(
      planning: widget.planning,
      levels: widget.levels,
      station: widget.station,
    );
    final sortedLevels = List<OnCallLevel>.from(widget.levels)
      ..sort((a, b) => a.order.compareTo(b.order));

    final byAgent = <String, List<_PersonalSlot>>{};

    for (final level in sortedLevels) {
      if (level.isAvailability) {
        final levelAvails =
            widget.availabilities
                .where(
                  (a) =>
                      a.levelId == level.id &&
                      a.start.isBefore(widget.planning.endTime) &&
                      a.end.isAfter(widget.planning.startTime),
                )
                .toList()
              ..sort((a, b) => a.start.compareTo(b.start));

        final levelAvailAgentIds = levelAvails.map((a) => a.agentId).toSet();
        final extraAgents = widget.planning.agents
            .where(
              (a) =>
                  a.levelId == level.id &&
                  !levelAvailAgentIds.contains(a.agentId),
            )
            .toList();

        for (final avail in levelAvails) {
          final ps = _PersonalSlot(
            slot: AgentPresenceSlot(
              agentId: avail.agentId,
              start: avail.start,
              end: avail.end,
              levelId: level.id,
              type: PresenceType.regular,
            ),
            level: level,
            isAvailability: true,
          );
          byAgent.putIfAbsent(avail.agentId, () => []).add(ps);
        }
        for (final pa in extraAgents) {
          final ps = _PersonalSlot(
            slot: AgentPresenceSlot(
              agentId: pa.agentId,
              start: pa.start,
              end: pa.end,
              levelId: level.id,
              type: PresenceType.regular,
              replacedAgentId: pa.replacedAgentId,
            ),
            level: level,
            isAvailability: true,
            replacedAgentName: pa.replacedAgentId != null
                ? _findUser(pa.replacedAgentId!).displayName
                : null,
          );
          byAgent.putIfAbsent(pa.agentId, () => []).add(ps);
        }
      } else {
        final slots = disposition[level.id];
        if (slots == null) continue;
        for (final slot in slots) {
          final ps = _PersonalSlot(
            slot: slot,
            level: level,
            isAvailability: false,
            replacedAgentName: slot.replacedAgentId != null
                ? _findUser(slot.replacedAgentId!).displayName
                : null,
          );
          byAgent.putIfAbsent(slot.agentId, () => []).add(ps);
        }
      }
    }

    // Sort agents alphabetically
    final sortedAgentIds = byAgent.keys.toList()
      ..sort(
        (a, b) => _findUser(a).displayName.toLowerCase().compareTo(
          _findUser(b).displayName.toLowerCase(),
        ),
      );

    // Sort slots within each agent chronologically
    for (final slots in byAgent.values) {
      slots.sort((a, b) => a.slot.start.compareTo(b.slot.start));
    }

    final widgets = <Widget>[];
    for (int gi = 0; gi < sortedAgentIds.length; gi++) {
      final agentId = sortedAgentIds[gi];
      final slots = byAgent[agentId]!;
      final agent = _findUser(agentId);
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: _PersonalViewAgentGroup(
            agent: agent,
            slots: slots,
            isFirstGroup: gi == 0,
            isLastGroup: gi == sortedAgentIds.length - 1,
            highlight: agentId == widget.currentUser.id,
            canManage: widget.canManage,
            findPlanningAgent: (ps) => _findPlanningAgent(ps.slot),
            onToggleCheck: widget.onToggleCheck,
            onRemoveEntry: widget.onRemoveEntry,
            onRemoveAvailability: widget.onRemoveAvailability,
            onEditEntry: widget.onEditEntry,
          ),
        ),
      );
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.levels.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Aucun niveau d\'astreinte configuré.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    final disposition = OnCallDispositionService.computeDisposition(
      planning: widget.planning,
      levels: widget.levels,
      station: widget.station,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sortedLevels = List<OnCallLevel>.from(widget.levels)
      ..sort((a, b) => a.order.compareTo(b.order));

    final levelWidgets = <Widget>[];

    for (final level in sortedLevels) {
      if (level.isAvailability) {
        // Niveau de disponibilité : afficher les Availability correspondantes
        // ET les PlanningAgent dont le levelId pointe vers ce niveau isAvailability
        final levelAvails =
            widget.availabilities
                .where(
                  (a) =>
                      a.levelId == level.id &&
                      a.start.isBefore(widget.planning.endTime) &&
                      a.end.isAfter(widget.planning.startTime),
                )
                .toList()
              ..sort((a, b) => a.start.compareTo(b.start));

        // Agents en planning.agents avec ce niveau isAvailability
        final planningAgentsForLevel = widget.planning.agents
            .where((a) => a.levelId == level.id)
            .toList();

        // Éviter les doublons : ignorer ceux déjà dans levelAvails
        final levelAvailAgentIds = levelAvails.map((a) => a.agentId).toSet();
        final extraAgents = planningAgentsForLevel
            .where((a) => !levelAvailAgentIds.contains(a.agentId))
            .toList();

        if (levelAvails.isEmpty && extraAgents.isEmpty) continue;

        levelWidgets.add(const SizedBox(height: 8));
        levelWidgets.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              level.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
              ),
            ),
          ),
        );
        levelWidgets.add(const SizedBox(height: 4));

        for (int i = 0; i < levelAvails.length; i++) {
          final avail = levelAvails[i];
          final agent = _findUser(avail.agentId);
          final tile = _AvailabilityPresenceTile(
            availability: avail,
            level: level,
            agent: agent,
            isFirst: i == 0,
            isLast: i == levelAvails.length - 1,
            highlight: avail.agentId == widget.currentUser.id,
          );

          if (widget.canManage && widget.onRemoveAvailability != null) {
            levelWidgets.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Dismissible(
                  key: ValueKey('avail_${avail.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.red.shade400,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white,
                    ),
                  ),
                  confirmDismiss: (_) async {
                    await widget.onRemoveAvailability!(avail);
                    return false;
                  },
                  child: tile,
                ),
              ),
            );
          } else {
            levelWidgets.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: tile,
              ),
            );
          }
        }

        // Afficher les PlanningAgents avec ce niveau isAvailability
        final totalCount = levelAvails.length + extraAgents.length;
        for (int i = 0; i < extraAgents.length; i++) {
          final pa = extraAgents[i];
          final agent = _findUser(pa.agentId);
          final globalIdx = levelAvails.length + i;
          final avail = Availability(
            id: pa.agentId,
            agentId: pa.agentId,
            start: pa.start,
            end: pa.end,
            planningId: widget.planning.id,
            levelId: level.id,
          );
          final tile = _AvailabilityPresenceTile(
            availability: avail,
            level: level,
            agent: agent,
            isFirst: globalIdx == 0,
            isLast: globalIdx == totalCount - 1,
            highlight: pa.agentId == widget.currentUser.id,
          );

          if (widget.canManage && widget.onRemoveEntry != null) {
            final planningAgent = _findPlanningAgent(
              AgentPresenceSlot(
                agentId: pa.agentId,
                start: pa.start,
                end: pa.end,
                levelId: level.id,
                type: PresenceType.regular,
                replacedAgentId: pa.replacedAgentId,
              ),
            );
            if (planningAgent != null) {
              levelWidgets.add(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Dismissible(
                    key: ValueKey('pa_avail_${pa.agentId}_${pa.start}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.red.shade400,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.white,
                      ),
                    ),
                    confirmDismiss: (_) async {
                      await widget.onRemoveEntry!(planningAgent);
                      return false;
                    },
                    child: tile,
                  ),
                ),
              );
              continue;
            }
          }
          levelWidgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: tile,
            ),
          );
        }
      } else {
        // Niveau d'astreinte standard
        final slots = disposition[level.id];
        if (slots == null || slots.isEmpty) continue;

        // Tri chronologique + alphabétique en tiebreak
        slots.sort((a, b) {
          final t = a.start.compareTo(b.start);
          if (t != 0) return t;
          return _findUser(a.agentId).displayName.toLowerCase().compareTo(
            _findUser(b.agentId).displayName.toLowerCase(),
          );
        });

        levelWidgets.add(const SizedBox(height: 8));
        levelWidgets.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              level.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
              ),
            ),
          ),
        );
        levelWidgets.add(const SizedBox(height: 4));

        for (int i = 0; i < slots.length; i++) {
          final slot = slots[i];
          final agent = _findUser(slot.agentId);
          final replacedAgent = slot.replacedAgentId != null
              ? _findUser(slot.replacedAgentId!)
              : null;
          final planningAgent = _findPlanningAgent(slot);

          final tile = _OnCallPresenceTile(
            slot: slot,
            level: level,
            agent: agent,
            replacedAgent: replacedAgent,
            isFirst: i == 0,
            isLast: i == slots.length - 1,
            highlight:
                slot.agentId == widget.currentUser.id ||
                slot.replacedAgentId == widget.currentUser.id,
            showCheckIcon: widget.canManage,
            onCheckTap:
                widget.canManage &&
                    widget.onToggleCheck != null &&
                    planningAgent != null
                ? () => widget.onToggleCheck!(planningAgent)
                : null,
            onLongPress:
                widget.canManage &&
                    widget.onEditEntry != null &&
                    planningAgent != null
                ? () => widget.onEditEntry!(planningAgent)
                : null,
          );

          if (widget.canManage &&
              widget.onRemoveEntry != null &&
              planningAgent != null) {
            levelWidgets.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Dismissible(
                  key: ValueKey(
                    'agent_${slot.agentId}_${slot.start}_${slot.replacedAgentId}',
                  ),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.red.shade400,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white,
                    ),
                  ),
                  confirmDismiss: (_) async {
                    await widget.onRemoveEntry!(planningAgent);
                    return false;
                  },
                  child: tile,
                ),
              ),
            );
          } else {
            levelWidgets.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: tile,
              ),
            );
          }
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _ViewToggleButton(
            currentMode: presenceViewModeNotifier.value,
            onModeChanged: (mode) {
              presenceViewModeNotifier.value = mode;
              PreferencesService().savePresenceViewMode(mode);
            },
          ),
        ),
        const SizedBox(height: 4),
        if (presenceViewModeNotifier.value == PresenceViewMode.chronological)
          ...levelWidgets
        else
          ..._buildPersonalView(context, isDark),
        if (widget.canManage && widget.onAddAgent != null) ...[
          const SizedBox(height: 12),
          _AddAgentTile(
            planning: widget.planning,
            currentUser: widget.currentUser,
            onCallLevels: widget.levels,
            onManualChoice: widget.onAddAgent!,
          ),
        ],
      ],
    );
  }
}

/// Tuile individuelle pour un agent dans la liste de présence.
class _OnCallPresenceTile extends StatelessWidget {
  final AgentPresenceSlot slot;
  final OnCallLevel level;
  final User agent;
  final User? replacedAgent;
  final bool isFirst;
  final bool isLast;
  final bool highlight;
  final bool showCheckIcon;
  final VoidCallback? onCheckTap;
  final VoidCallback? onLongPress;

  const _OnCallPresenceTile({
    required this.slot,
    required this.level,
    required this.agent,
    this.replacedAgent,
    this.isFirst = false,
    this.isLast = false,
    this.highlight = false,
    this.showCheckIcon = false,
    this.onCheckTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.grey.shade200;
    final bg = highlight
        ? (isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.04))
        : Colors.transparent;

    return GestureDetector(
      onLongPress: onLongPress,
      child: IntrinsicHeight(
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Container(
                        width: 1.5,
                        color: isFirst ? Colors.transparent : lineColor,
                        margin: const EdgeInsets.only(bottom: 4),
                      ),
                    ),
                    _buildDotIcon(isDark),
                    Expanded(
                      child: Container(
                        width: 1.5,
                        color: isLast ? Colors.transparent : lineColor,
                        margin: const EdgeInsets.only(top: 4),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 4,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: level.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildNameRow(context, isDark),
                    const SizedBox(height: 3),
                    Text(
                      "${DateFormat('dd/MM HH:mm').format(slot.start)} \u2192 ${DateFormat('dd/MM HH:mm').format(slot.end)}",
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              if (showCheckIcon) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onCheckTap,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        slot.checkedByChief
                            ? Icons.check_circle_rounded
                            : Icons.check_circle_outline_rounded,
                        key: ValueKey(slot.checkedByChief),
                        color: slot.checkedByChief
                            ? Colors.green.shade400
                            : (isDark
                                  ? Colors.grey.shade600
                                  : Colors.grey.shade300),
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDotIcon(bool isDark) {
    switch (slot.type) {
      case PresenceType.exchange:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: isDark ? 0.2 : 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.swap_horiz_rounded,
            size: 16,
            color: Colors.green.shade400,
          ),
        );
      case PresenceType.replacement:
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: level.color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(color: level.color, width: 2.5),
          ),
        );
      case PresenceType.regular:
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: level.color, shape: BoxShape.circle),
        );
    }
  }

  Widget _buildNameRow(BuildContext context, bool isDark) {
    if (replacedAgent != null) {
      return RichText(
        textAlign: TextAlign.start,
        text: TextSpan(
          style: TextStyle(
            color: Theme.of(context).colorScheme.tertiary,
            fontSize: 13,
          ),
          children: [
            TextSpan(
              text: agent.displayName,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: "  \u2190  ",
              style: TextStyle(
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                fontSize: 12,
              ),
            ),
            TextSpan(
              text: replacedAgent!.displayName,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey.shade300 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return Text(
      agent.displayName,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// Tuile "+" pour ajouter un agent — affiche un overlay animé (comme "Je souhaite m'absenter")
class _AddAgentTile extends StatelessWidget {
  final Planning planning;
  final User currentUser;
  final List<OnCallLevel> onCallLevels;
  final VoidCallback onManualChoice;

  const _AddAgentTile({
    required this.planning,
    required this.currentUser,
    required this.onCallLevels,
    required this.onManualChoice,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ContextualMenuButton(
      menuBorderRadius: 16,
      estimatedMenuHeight: 260,
      menuContent: (onClose) => AddAgentMenuOverlay.buildMenuContent(
        context: context,
        planning: planning,
        currentUser: currentUser,
        onCallLevels: onCallLevels,
        onOptionSelected: onClose,
        onManualChoice: onManualChoice,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_circle_outline_rounded,
              size: 20,
              color: KColors.appNameColor,
            ),
            const SizedBox(width: 8),
            Text(
              'Ajouter un agent',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: KColors.appNameColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tuile pour un agent en disponibilité (hachuré, non checkable).
class _AvailabilityPresenceTile extends StatelessWidget {
  final Availability availability;
  final OnCallLevel level;
  final User agent;
  final bool isFirst;
  final bool isLast;
  final bool highlight;

  const _AvailabilityPresenceTile({
    required this.availability,
    required this.level,
    required this.agent,
    this.isFirst = false,
    this.isLast = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.grey.shade200;
    final bg = highlight
        ? (isDark
              ? Colors.white.withValues(alpha: 0.04)
              : level.color.withValues(alpha: 0.04))
        : Colors.transparent;

    return IntrinsicHeight(
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Colonne connecteur vertical + dot
            SizedBox(
              width: 28,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: isFirst ? Colors.transparent : lineColor,
                      margin: const EdgeInsets.only(bottom: 4),
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: level.color.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: level.color, width: 2),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: isLast ? Colors.transparent : lineColor,
                      margin: const EdgeInsets.only(top: 4),
                    ),
                  ),
                ],
              ),
            ),
            // Barre couleur hachuré (gauche)
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                width: 4,
                child: CustomPaint(
                  painter: DiagonalStripePainter(
                    color1: level.color.withValues(alpha: 0.6),
                    color2: isDark ? Colors.grey.shade800 : Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Nom + horaire
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent.displayName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: level.color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "${DateFormat('dd/MM HH:mm').format(availability.start)} \u2192 ${DateFormat('dd/MM HH:mm').format(availability.end)}",
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vue personnelle — bouton toggle
// ─────────────────────────────────────────────────────────────────────────────

class _ViewToggleButton extends StatefulWidget {
  final PresenceViewMode currentMode;
  final ValueChanged<PresenceViewMode> onModeChanged;

  const _ViewToggleButton({
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  State<_ViewToggleButton> createState() => _ViewToggleButtonState();
}

class _ViewToggleButtonState extends State<_ViewToggleButton>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  late AnimationController _animationController;
  late Animation<double> _animation;

  static const double _menuWidth = 220;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _animationController.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _animationController.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  void _toggleMenu() {
    if (_overlayEntry != null) {
      _removeOverlay();
    } else {
      _showMenu();
    }
  }

  void _showMenu() {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Aligner le bord droit du menu avec le bord droit du bouton
    final rightEdge = screenWidth - (offset.dx + size.width);
    const menuHeight = 110.0;
    final fitsBelow = offset.dy + size.height + 8 + menuHeight <= screenHeight;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => GestureDetector(
        onTap: _removeOverlay,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            Positioned(
              right: rightEdge,
              top: fitsBelow ? offset.dy + size.height + 6 : null,
              bottom: fitsBelow ? null : screenHeight - offset.dy + 6,
              width: _menuWidth,
              child: FadeTransition(
                opacity: _animation,
                child: ScaleTransition(
                  scale: _animation,
                  alignment: fitsBelow
                      ? Alignment.topRight
                      : Alignment.bottomRight,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    child: _buildMenu(ctx),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
    _animationController.forward();
  }

  Widget _buildMenu(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildOption(
          ctx,
          icon: Icons.shield_rounded,
          label: 'Classer par astreinte',
          mode: PresenceViewMode.chronological,
        ),
        Divider(
          height: 1,
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
        _buildOption(
          ctx,
          icon: Icons.group_rounded,
          label: 'Classer par agent',
          mode: PresenceViewMode.personal,
        ),
      ],
    );
  }

  Widget _buildOption(
    BuildContext ctx, {
    required IconData icon,
    required String label,
    required PresenceViewMode mode,
  }) {
    final isActive = widget.currentMode == mode;
    final color = isActive
        ? Theme.of(ctx).colorScheme.primary
        : Theme.of(ctx).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        widget.onModeChanged(mode);
        _removeOverlay();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
            ),
            if (isActive) Icon(Icons.check_rounded, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: _toggleMenu,
      child: Padding(
        padding: const EdgeInsets.only(right: 4, top: 2, bottom: 2),
        child: Icon(
          Icons.tune_rounded,
          size: 18,
          color: widget.currentMode == PresenceViewMode.personal
              ? Theme.of(context).colorScheme.primary
              : (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vue personnelle — groupe par agent
// ─────────────────────────────────────────────────────────────────────────────

class _PersonalViewAgentGroup extends StatelessWidget {
  final User agent;
  final List<_PersonalSlot> slots;
  final bool isFirstGroup;
  final bool isLastGroup;
  final bool highlight;
  final bool canManage;
  final PlanningAgent? Function(_PersonalSlot) findPlanningAgent;
  final Future<void> Function(PlanningAgent)? onToggleCheck;
  final Future<void> Function(PlanningAgent)? onRemoveEntry;
  final Future<void> Function(Availability)? onRemoveAvailability;
  final Future<void> Function(PlanningAgent)? onEditEntry;

  const _PersonalViewAgentGroup({
    required this.agent,
    required this.slots,
    required this.isFirstGroup,
    required this.isLastGroup,
    required this.highlight,
    required this.canManage,
    required this.findPlanningAgent,
    this.onToggleCheck,
    this.onRemoveEntry,
    this.onRemoveAvailability,
    this.onEditEntry,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.grey.shade200;
    final nameColor = highlight
        ? Theme.of(context).colorScheme.primary
        : (isDark ? Colors.grey.shade200 : Colors.grey.shade800);

    final children = <Widget>[
      // En-tête agent (nom)
      SizedBox(
        height: 36,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: isFirstGroup ? Colors.transparent : lineColor,
                      margin: const EdgeInsets.only(bottom: 4),
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: lineColor,
                      margin: const EdgeInsets.only(top: 4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  agent.displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: nameColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];

    // Slots de l'agent
    for (int i = 0; i < slots.length; i++) {
      final ps = slots[i];
      final isLast = isLastGroup && i == slots.length - 1;
      final planningAgent = findPlanningAgent(ps);

      final slotRow = _PersonalViewSlotRow(
        ps: ps,
        isLast: isLast,
        showCheckIcon: canManage && !ps.isAvailability,
        onCheckTap:
            canManage &&
                !ps.isAvailability &&
                onToggleCheck != null &&
                planningAgent != null
            ? () => onToggleCheck!(planningAgent)
            : null,
        onLongPress:
            canManage &&
                !ps.isAvailability &&
                onEditEntry != null &&
                planningAgent != null
            ? () => onEditEntry!(planningAgent)
            : null,
      );

      if (canManage &&
          !ps.isAvailability &&
          onRemoveEntry != null &&
          planningAgent != null) {
        children.add(
          Dismissible(
            key: ValueKey(
              'personal_${ps.slot.agentId}_${ps.level.id}_${ps.slot.start}',
            ),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.white,
              ),
            ),
            confirmDismiss: (_) async {
              await onRemoveEntry!(planningAgent);
              return false;
            },
            child: slotRow,
          ),
        );
      } else if (canManage &&
          ps.isAvailability &&
          onRemoveAvailability != null) {
        final avail = Availability(
          id: '${ps.slot.agentId}_${ps.slot.start}',
          agentId: ps.slot.agentId,
          start: ps.slot.start,
          end: ps.slot.end,
          planningId: '',
          levelId: ps.level.id,
        );
        children.add(
          Dismissible(
            key: ValueKey(
              'personal_avail_${ps.slot.agentId}_${ps.level.id}_${ps.slot.start}',
            ),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.white,
              ),
            ),
            confirmDismiss: (_) async {
              await onRemoveAvailability!(avail);
              return false;
            },
            child: slotRow,
          ),
        );
      } else {
        children.add(slotRow);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vue personnelle — ligne de slot
// ─────────────────────────────────────────────────────────────────────────────

class _PersonalViewSlotRow extends StatelessWidget {
  final _PersonalSlot ps;
  final bool isLast;
  final bool showCheckIcon;
  final VoidCallback? onCheckTap;
  final VoidCallback? onLongPress;

  const _PersonalViewSlotRow({
    required this.ps,
    required this.isLast,
    this.showCheckIcon = false,
    this.onCheckTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.grey.shade200;
    final level = ps.level;
    final slot = ps.slot;

    return GestureDetector(
      onLongPress: onLongPress,
      child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Connecteur vertical (pas de dot — la ligne continue depuis le header)
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: lineColor,
                    margin: const EdgeInsets.only(bottom: 4),
                  ),
                ),
                const SizedBox(height: 10), // espace symétrique au dot
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: isLast ? Colors.transparent : lineColor,
                    margin: const EdgeInsets.only(top: 4),
                  ),
                ),
              ],
            ),
          ),
          // Barre couleur gauche
          ps.isAvailability
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    width: 4,
                    child: CustomPaint(
                      painter: DiagonalStripePainter(
                        color1: level.color.withValues(alpha: 0.6),
                        color2: isDark ? Colors.grey.shade800 : Colors.white,
                      ),
                    ),
                  ),
                )
              : Container(
                  width: 4,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: level.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
          const SizedBox(width: 8),
          // Contenu : date + badge + check
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "${DateFormat('dd/MM HH:mm').format(slot.start)} \u2192 ${DateFormat('dd/MM HH:mm').format(slot.end)}",
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.grey.shade500
                                : Colors.grey.shade400,
                          ),
                        ),
                        if (ps.replacedAgentName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '\u2190 ${ps.replacedAgentName}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.grey.shade600
                                  : Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Badge niveau
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: level.color.withValues(
                        alpha: ps.isAvailability ? 0.10 : 0.15,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      border: ps.isAvailability
                          ? Border.all(
                              color: level.color.withValues(alpha: 0.5),
                              width: 0.8,
                            )
                          : null,
                    ),
                    child: Text(
                      level.name,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: level.color,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  if (showCheckIcon) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: onCheckTap,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            slot.checkedByChief
                                ? Icons.check_circle_rounded
                                : Icons.check_circle_outline_rounded,
                            key: ValueKey(slot.checkedByChief),
                            color: slot.checkedByChief
                                ? Colors.green.shade400
                                : (isDark
                                      ? Colors.grey.shade600
                                      : Colors.grey.shade300),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }
}
