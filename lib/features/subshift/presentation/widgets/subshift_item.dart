import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';

/// Widget représentant un élément visuel d’un remplacement (SubShift)
/// Purement UI : ne gère aucune donnée métier ni persistence.
class SubShiftItem extends StatelessWidget {
  final Subshift subShift;
  final Planning planning;
  final List<User> allUsers;
  final User noneUser;
  final bool isFirst;
  final bool isLast;
  final bool highlight;

  const SubShiftItem({
    super.key,
    required this.subShift,
    required this.planning,
    required this.allUsers,
    required this.noneUser,
    this.isFirst = false,
    this.isLast = false,
    this.highlight = false,
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

    final lineColor = Theme.of(context).colorScheme.primary.withOpacity(0.5);
    final dotColor = Theme.of(context).colorScheme.primary;
    final bg = highlight
        ? Theme.of(context).colorScheme.primary.withOpacity(0.06)
        : Colors.transparent;

    return IntrinsicHeight(
      child: Container(
        color: bg,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ligne verticale + point central
            SizedBox(
              width: 28,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isFirst ? Colors.transparent : lineColor,
                      margin: const EdgeInsets.only(bottom: 6),
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isLast ? Colors.transparent : lineColor,
                      margin: const EdgeInsets.only(top: 6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Bloc de texte (remplaçant ← remplacé + horaires)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  // TODO : ouvrir un détail ou déclencher une action
                },
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
                            text: "${replacer.firstName} ${replacer.lastName}",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const TextSpan(text: " ← "),
                          TextSpan(
                            text: "${replaced.firstName} ${replaced.lastName}",
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${DateFormat('dd/MM HH:mm').format(subShift.start)} → ${DateFormat('dd/MM HH:mm').format(subShift.end)}",
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
