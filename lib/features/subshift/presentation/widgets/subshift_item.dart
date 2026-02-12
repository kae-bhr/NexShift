import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';

/// Widget représentant un élément visuel d'un remplacement (SubShift)
/// Purement UI : ne gère aucune donnée métier ni persistence.
class SubShiftItem extends StatelessWidget {
  final Subshift subShift;
  final Planning planning;
  final List<User> allUsers;
  final User noneUser;
  final bool isFirst;
  final bool isLast;
  final bool highlight;

  /// Si true, affiche l'icône check à droite
  final bool showCheckIcon;

  /// Callback appelé lors du clic sur l'icône check
  final VoidCallback? onCheckTap;

  const SubShiftItem({
    super.key,
    required this.subShift,
    required this.planning,
    required this.allUsers,
    required this.noneUser,
    this.isFirst = false,
    this.isLast = false,
    this.highlight = false,
    this.showCheckIcon = false,
    this.onCheckTap,
  });

  @override
  Widget build(BuildContext context) {
    final replaced = allUsers.firstWhere(
      (u) => u.id == subShift.replacedId,
      orElse: () => noneUser,
    );
    final replacer = allUsers.firstWhere(
      (u) => u.id == subShift.replacerId,
      orElse: () => noneUser,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.grey.shade200;
    final dotColor = Theme.of(context).colorScheme.primary;
    final isExchange = subShift.isExchange;
    final bg = highlight
        ? (isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.04))
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
            // Vertical timeline
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
                  isExchange
                      ? Container(
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
                        )
                      : Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: dotColor.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: dotColor,
                              width: 2.5,
                            ),
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
            const SizedBox(width: 10),

            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    textAlign: TextAlign.start,
                    text: TextSpan(
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.tertiary,
                        fontSize: 13,
                      ),
                      children: [
                        TextSpan(
                          text: replacer.displayName,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: "  \u2190  ",
                          style: TextStyle(
                            color: isDark
                                ? Colors.grey.shade500
                                : Colors.grey.shade400,
                            fontSize: 12,
                          ),
                        ),
                        TextSpan(
                          text: replaced.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.grey.shade300
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "${DateFormat('dd/MM HH:mm').format(subShift.start)} \u2192 ${DateFormat('dd/MM HH:mm').format(subShift.end)}",
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

            // Check icon
            if (showCheckIcon) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onCheckTap,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      subShift.checkedByChief
                          ? Icons.check_circle_rounded
                          : Icons.check_circle_outline_rounded,
                      key: ValueKey(subShift.checkedByChief),
                      color: subShift.checkedByChief
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
    );
  }
}
