import 'package:flutter/material.dart';
import 'status_badge.dart';
import '../unified_tile_data.dart' show ChiefTeamStatus;

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

  /// Callback au tap sur le badge "Historique" (mode history uniquement)
  final VoidCallback? onHistoryTap;

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
    this.onHistoryTap,
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

    // Badge "Historique" (mode history uniquement, affiché en dernier)
    if (onHistoryTap != null) {
      indicators.add(
        CustomBadge.history(onTap: onHistoryTap!, compact: compact),
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

  /// Mode compact : nom à gauche, badge statut à droite sur une seule ligne
  /// (utilisé en mode history pour ne pas décaler les colonnes)
  final bool compact;

  const ValidationHeader({
    super.key,
    required this.chiefs,
    this.showDivider = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (chiefs.isEmpty) return const SizedBox.shrink();

    // Layout échange : une seule ligne avec nom+équipe à gauche, badges statuts à droite
    if (chiefs.first.teamStatuses != null) {
      return _buildExchangeLayout(context, chiefs.first);
    }

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...chiefs.map(
            (chief) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      chief.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildCompactStatusBadge(chief.hasValidated),
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

  /// Layout spécifique échange :
  /// [✓] Prénom Nom  [éq]          [Validé]  [En attente]
  Widget _buildExchangeLayout(BuildContext context, ValidationChiefDisplay chief) {
    final statuses = chief.teamStatuses!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Icône statut du chef courant
            _buildStatusIcon(chief.hasValidated),
            const SizedBox(width: 6),
            // Nom du chef
            Flexible(
              child: Text(
                chief.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _getTextColor(chief.hasValidated),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Badge équipe du chef
            if (chief.teamLabel != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'éq. ${chief.teamLabel}',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ),
            ],
            const Spacer(),
            // Badges statut par équipe
            ...statuses.entries.map((e) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _buildTeamStatusBadge(e.key, e.value),
            )),
          ],
        ),
        if (showDivider) ...[
          const SizedBox(height: 8),
          Divider(height: 1, color: Colors.grey.shade300),
        ],
      ],
    );
  }

  /// Badge [éqX · Validé / En attente / Refusé]
  Widget _buildTeamStatusBadge(String teamId, ChiefTeamStatus status) {
    final IconData icon;
    final String label;
    final Color bg;
    final Color fg;

    switch (status) {
      case ChiefTeamStatus.validated:
        icon = Icons.check_circle_rounded;
        label = 'Validé';
        bg = Colors.green.shade50;
        fg = Colors.green.shade700;
        break;
      case ChiefTeamStatus.rejected:
        icon = Icons.cancel_rounded;
        label = 'Refusé';
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        break;
      case ChiefTeamStatus.pending:
        icon = Icons.schedule_rounded;
        label = 'En attente';
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade700;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }

  /// Badge compact [icône + label] pour le mode history
  Widget _buildCompactStatusBadge(bool? hasValidated) {
    final IconData icon;
    final String label;
    final Color bg;
    final Color fg;

    if (hasValidated == true) {
      icon = Icons.check_circle_rounded;
      label = 'Validé';
      bg = Colors.green.shade50;
      fg = Colors.green.shade700;
    } else if (hasValidated == false) {
      icon = Icons.cancel_rounded;
      label = 'Refusé';
      bg = Colors.red.shade50;
      fg = Colors.red.shade700;
    } else {
      icon = Icons.schedule_rounded;
      label = 'En attente';
      bg = Colors.orange.shade50;
      fg = Colors.orange.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
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

  /// Statuts par équipe (layout échange : une ligne, badges à droite)
  final Map<String, ChiefTeamStatus>? teamStatuses;

  const ValidationChiefDisplay({
    required this.name,
    this.hasValidated,
    this.teamLabel,
    this.teamStatuses,
  });
}
