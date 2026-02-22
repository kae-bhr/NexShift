import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/on_call_level_model.dart';
import 'package:nexshift_app/core/data/models/planning_agent_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/services/on_call_disposition_service.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/planning/presentation/widgets/add_agent_menu_overlay.dart';
import 'package:nexshift_app/core/presentation/widgets/contextual_menu_button.dart';

/// Section affichant les agents présents dans une garde, groupés par niveau d'astreinte.
/// Lit directement depuis planning.agents — source unique de vérité.
class OnCallPresenceSection extends StatelessWidget {
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
    this.canManage = false,
  });

  User _findUser(String id) {
    return allUsers.firstWhere(
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

  @override
  Widget build(BuildContext context) {
    if (levels.isEmpty) {
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
      planning: planning,
      levels: levels,
      station: station,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sortedLevels = List<OnCallLevel>.from(levels)
      ..sort((a, b) => a.order.compareTo(b.order));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final level in sortedLevels) ...[
          if (disposition[level.id] != null &&
              disposition[level.id]!.isNotEmpty) ...[
            const SizedBox(height: 8),
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
            const SizedBox(height: 4),
            ...disposition[level.id]!.asMap().entries.map((entry) {
              final index = entry.key;
              final slot = entry.value;
              final isFirst = index == 0;
              final isLast = index == disposition[level.id]!.length - 1;
              final agent = _findUser(slot.agentId);
              final replacedAgent = slot.replacedAgentId != null
                  ? _findUser(slot.replacedAgentId!)
                  : null;

              // Trouver le PlanningAgent correspondant pour les callbacks
              final planningAgent = _findPlanningAgent(slot);

              final tile = _OnCallPresenceTile(
                slot: slot,
                level: level,
                agent: agent,
                replacedAgent: replacedAgent,
                isFirst: isFirst,
                isLast: isLast,
                highlight: slot.agentId == currentUser.id ||
                    slot.replacedAgentId == currentUser.id,
                showCheckIcon: canManage,
                onCheckTap: canManage && onToggleCheck != null && planningAgent != null
                    ? () => onToggleCheck!(planningAgent)
                    : null,
                onLongPress: canManage && onEditEntry != null && planningAgent != null
                    ? () => onEditEntry!(planningAgent)
                    : null,
              );

              // Swipe-to-delete unifié
              if (canManage && onRemoveEntry != null && planningAgent != null) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Dismissible(
                    key: ValueKey('agent_${slot.agentId}_${slot.start}_${slot.replacedAgentId}'),
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
                    child: tile,
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: tile,
              );
            }),
          ],
        ],
        if (canManage && onAddAgent != null) ...[
          const SizedBox(height: 12),
          _AddAgentTile(
            planning: planning,
            currentUser: currentUser,
            onCallLevels: levels,
            onManualChoice: onAddAgent!,
          ),
        ],
      ],
    );
  }

  /// Trouve le PlanningAgent correspondant à un AgentPresenceSlot
  PlanningAgent? _findPlanningAgent(AgentPresenceSlot slot) {
    try {
      return planning.agents.firstWhere((a) =>
          a.agentId == slot.agentId &&
          a.start.isAtSameMomentAs(slot.start) &&
          a.end.isAtSameMomentAs(slot.end) &&
          a.replacedAgentId == slot.replacedAgentId);
    } catch (_) {
      return null;
    }
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
            border: Border.all(
              color: level.color,
              width: 2.5,
            ),
          ),
        );
      case PresenceType.regular:
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: level.color,
            shape: BoxShape.circle,
          ),
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
            Icon(Icons.add_circle_outline_rounded, size: 20, color: KColors.appNameColor),
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
