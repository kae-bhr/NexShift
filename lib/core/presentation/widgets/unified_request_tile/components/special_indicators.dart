import 'package:flutter/material.dart';
import 'status_badge.dart';

/// Barre d'indicateurs spéciaux (vague, propositions, non notifié)
/// Affichée en bas de la carte selon le contexte
class SpecialIndicatorsBar extends StatelessWidget {
  /// Numéro de vague actuel (remplacement auto)
  final int? currentWave;

  /// Nombre de personnes notifiées (remplacement auto)
  final int? notifiedCount;

  /// Nombre de propositions (échanges)
  final int? proposalCount;

  /// L'utilisateur est-il notifié ?
  final bool isUserNotified;

  /// Est-ce le mode "Mes demandes" ?
  final bool isMyRequestsMode;

  /// Callback au tap sur l'indicateur de vague
  final VoidCallback? onWaveTap;

  /// Callback au tap sur le compteur de notifiés
  final VoidCallback? onNotifiedTap;

  /// Callback au tap sur le compteur de propositions
  final VoidCallback? onProposalsTap;

  /// Callback au tap sur "Non notifié"
  final VoidCallback? onNotNotifiedTap;

  /// Afficher en mode compact
  final bool compact;

  const SpecialIndicatorsBar({
    super.key,
    this.currentWave,
    this.notifiedCount,
    this.proposalCount,
    this.isUserNotified = true,
    this.isMyRequestsMode = false,
    this.onWaveTap,
    this.onNotifiedTap,
    this.onProposalsTap,
    this.onNotNotifiedTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final indicators = <Widget>[];

    // Badge "Non notifié" si l'utilisateur n'est pas notifié
    // SAUF en mode "Mes demandes" (on affiche la vague à la place pour les remplacements auto)
    if (!isUserNotified && !isMyRequestsMode) {
      indicators.add(
        CustomBadge.notNotified(
          onTap: onNotNotifiedTap,
          compact: compact,
        ),
      );
    }

    // Badge de vague (remplacement auto)
    // En mode "Mes demandes", toujours afficher la vague si disponible
    // En mode normal, afficher seulement si l'utilisateur est notifié
    if (currentWave != null && (isUserNotified || isMyRequestsMode)) {
      indicators.add(
        CustomBadge.wave(
          waveNumber: currentWave!,
          onTap: onWaveTap,
          compact: compact,
        ),
      );
    }

    // Badge de personnes notifiées (alternative à vague)
    if (notifiedCount != null && currentWave == null && (isUserNotified || isMyRequestsMode)) {
      indicators.add(
        CustomBadge.notifiedCount(
          count: notifiedCount!,
          onTap: onNotifiedTap,
          compact: compact,
        ),
      );
    }

    // Badge de propositions (échanges)
    if (proposalCount != null) {
      indicators.add(
        CustomBadge.proposalCount(
          count: proposalCount!,
          onTap: onProposalsTap,
          compact: compact,
        ),
      );
    }

    if (indicators.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: indicators,
    );
  }
}

/// Widget d'en-tête avec les chefs de validation
class ValidationHeader extends StatelessWidget {
  /// Noms des chefs avec leur statut de validation
  final List<ValidationChiefDisplay> chiefs;

  /// Afficher le divider en dessous
  final bool showDivider;

  const ValidationHeader({
    super.key,
    required this.chiefs,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    if (chiefs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...chiefs.map(
          (chief) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                _buildStatusIcon(chief.hasValidated),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    chief.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _getTextColor(chief.hasValidated),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (chief.teamLabel != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      chief.teamLabel!,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (showDivider) ...[
          const SizedBox(height: 8),
          Divider(height: 1, color: Colors.grey.shade300),
        ],
      ],
    );
  }

  Widget _buildStatusIcon(bool? hasValidated) {
    if (hasValidated == true) {
      return Icon(Icons.check_circle, size: 16, color: Colors.green.shade600);
    } else if (hasValidated == false) {
      return Icon(Icons.cancel, size: 16, color: Colors.red.shade600);
    } else {
      return Icon(Icons.schedule, size: 16, color: Colors.orange.shade600);
    }
  }

  Color _getTextColor(bool? hasValidated) {
    if (hasValidated == true) return Colors.green.shade700;
    if (hasValidated == false) return Colors.red.shade700;
    return Colors.grey.shade700;
  }
}

/// Données d'affichage pour un chef de validation
class ValidationChiefDisplay {
  /// Nom du chef
  final String name;

  /// A-t-il validé ? (null = pas encore répondu)
  final bool? hasValidated;

  /// Label de l'équipe (optionnel)
  final String? teamLabel;

  const ValidationChiefDisplay({
    required this.name,
    this.hasValidated,
    this.teamLabel,
  });
}
