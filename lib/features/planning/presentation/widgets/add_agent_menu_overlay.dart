import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/on_call_level_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/features/replacement/presentation/pages/skill_search_page.dart';

/// Widget réutilisable pour afficher le menu d'ajout d'agent avec deux options :
/// - Choix automatique (recherche par compétences → AgentQuery)
/// - Choix manuel (sélection directe depuis la liste d'agents)
///
/// Utilisé dans HomePage au niveau du bouton "Ajouter un agent"
/// dans [OnCallPresenceSection].
class AddAgentMenuOverlay {
  /// Construit le contenu du menu (utilisable dans un Overlay ou BottomSheet).
  static Widget buildMenuContent({
    required BuildContext context,
    required Planning planning,
    required User currentUser,
    required List<OnCallLevel> onCallLevels,
    required VoidCallback onOptionSelected,
    required VoidCallback onManualChoice,
  }) {
    return _AddAgentMenuContent(
      planning: planning,
      currentUser: currentUser,
      onCallLevels: onCallLevels,
      onOptionSelected: onOptionSelected,
      onManualChoice: onManualChoice,
    );
  }

  /// Affiche un BottomSheet avec les options d'ajout d'agent.
  static void showAsBottomSheet({
    required BuildContext context,
    required Planning planning,
    required User currentUser,
    required List<OnCallLevel> onCallLevels,
    required VoidCallback onManualChoice,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddAgentMenuContent(
        planning: planning,
        currentUser: currentUser,
        onCallLevels: onCallLevels,
        onOptionSelected: () => Navigator.pop(ctx),
        onManualChoice: onManualChoice,
      ),
    );
  }
}

class _AddAgentMenuContent extends StatelessWidget {
  final Planning planning;
  final User currentUser;
  final List<OnCallLevel> onCallLevels;
  final VoidCallback onOptionSelected;
  final VoidCallback onManualChoice;

  const _AddAgentMenuContent({
    required this.planning,
    required this.currentUser,
    required this.onCallLevels,
    required this.onOptionSelected,
    required this.onManualChoice,
  });

  @override
  Widget build(BuildContext context) {
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
              onOptionSelected();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SkillSearchPage(
                    planning: planning,
                    currentUser: currentUser,
                    onCallLevels: onCallLevels,
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
              onOptionSelected();
              onManualChoice();
            },
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
