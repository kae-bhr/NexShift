import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/features/replacement/presentation/pages/replacement_page.dart';
import 'package:nexshift_app/features/shift_exchange/presentation/pages/shift_exchange_page.dart';

/// Widget réutilisable pour afficher le menu d'absence avec les trois options :
/// - Recherche automatique
/// - Remplacement manuel
/// - Échange d'astreinte
///
/// Utilisé dans HomePage (via _AbsenceMenuButton) et PlanningPage (via BottomSheet)
class AbsenceMenuOverlay {
  /// Affiche un BottomSheet avec les options d'absence
  static void showAsBottomSheet({
    required BuildContext context,
    required Planning planning,
    required User user,
    Subshift? parentSubshift,
    VoidCallback? onDismiss,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _AbsenceMenuContent(
        planning: planning,
        user: user,
        parentSubshift: parentSubshift,
        onOptionSelected: () {
          Navigator.pop(context);
          onDismiss?.call();
        },
      ),
    );
  }

  /// Construit le contenu du menu (utilisable dans un Overlay ou BottomSheet)
  static Widget buildMenuContent({
    required BuildContext context,
    required Planning planning,
    required User user,
    Subshift? parentSubshift,
    required VoidCallback onOptionSelected,
    double? width,
  }) {
    return _AbsenceMenuContent(
      planning: planning,
      user: user,
      parentSubshift: parentSubshift,
      onOptionSelected: onOptionSelected,
      width: width,
    );
  }
}

class _AbsenceMenuContent extends StatelessWidget {
  final Planning planning;
  final User user;
  final Subshift? parentSubshift;
  final VoidCallback onOptionSelected;
  final double? width;

  const _AbsenceMenuContent({
    required this.planning,
    required this.user,
    required this.onOptionSelected,
    this.parentSubshift,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AbsenceMenuOption(
            icon: Icons.refresh,
            iconColor: Colors.blue,
            title: 'Recherche automatique',
            subtitle: 'Système de vagues progressif',
            onTap: () {
              onOptionSelected();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReplacementPage(
                    planning: planning,
                    currentUser: user,
                    parentSubshift: parentSubshift,
                    isManualMode: false,
                  ),
                ),
              );
            },
          ),
          Divider(height: 1, color: Colors.grey[300]),
          AbsenceMenuOption(
            icon: Icons.person_add,
            iconColor: Colors.green,
            title: 'Remplacement manuel',
            subtitle: 'Proposer directement à quelqu\'un',
            onTap: () {
              onOptionSelected();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReplacementPage(
                    planning: planning,
                    currentUser: user,
                    parentSubshift: parentSubshift,
                    isManualMode: true,
                  ),
                ),
              );
            },
          ),
          Divider(height: 1, color: Colors.grey[300]),
          AbsenceMenuOption(
            icon: Icons.swap_horiz,
            iconColor: Colors.orange,
            title: 'Échange d\'astreinte',
            subtitle: 'Échanger avec un collègue',
            onTap: () {
              onOptionSelected();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShiftExchangePage(
                    planning: planning,
                    currentUser: user,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Widget pour une option du menu d'absence
class AbsenceMenuOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const AbsenceMenuOption({
    super.key,
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
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 12),
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
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
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
