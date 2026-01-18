import 'package:flutter/material.dart';
import '../unified_tile_enums.dart';

/// Badge de statut réutilisable pour les tuiles de demande
class StatusBadge extends StatelessWidget {
  /// Statut à afficher
  final TileStatus status;

  /// Texte personnalisé (surcharge le texte par défaut)
  final String? customText;

  /// Icône personnalisée (surcharge l'icône par défaut)
  final IconData? customIcon;

  /// Taille compacte (pour les espaces réduits)
  final bool compact;

  const StatusBadge({
    super.key,
    required this.status,
    this.customText,
    this.customIcon,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            customIcon ?? _icon,
            size: compact ? 12 : 14,
            color: _foregroundColor,
          ),
          SizedBox(width: compact ? 3 : 4),
          Text(
            customText ?? status.displayText,
            style: TextStyle(
              color: _foregroundColor,
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Couleur de fond selon le statut
  Color get _backgroundColor {
    switch (status) {
      case TileStatus.pending:
        return Colors.orange.shade100;
      case TileStatus.accepted:
      case TileStatus.validated:
      case TileStatus.autoValidated:
        return Colors.green.shade100;
      case TileStatus.declined:
      case TileStatus.cancelled:
        return Colors.red.shade100;
      case TileStatus.expired:
        return Colors.grey.shade200;
      case TileStatus.pendingValidation:
        return Colors.blue.shade100;
    }
  }

  /// Couleur du texte et de l'icône selon le statut
  Color get _foregroundColor {
    switch (status) {
      case TileStatus.pending:
        return Colors.orange.shade700;
      case TileStatus.accepted:
      case TileStatus.validated:
      case TileStatus.autoValidated:
        return Colors.green.shade700;
      case TileStatus.declined:
      case TileStatus.cancelled:
        return Colors.red.shade700;
      case TileStatus.expired:
        return Colors.grey.shade600;
      case TileStatus.pendingValidation:
        return Colors.blue.shade700;
    }
  }

  /// Icône selon le statut
  IconData get _icon {
    switch (status) {
      case TileStatus.pending:
        return Icons.access_time;
      case TileStatus.accepted:
      case TileStatus.validated:
      case TileStatus.autoValidated:
        return Icons.check_circle;
      case TileStatus.declined:
      case TileStatus.cancelled:
        return Icons.cancel;
      case TileStatus.expired:
        return Icons.block;
      case TileStatus.pendingValidation:
        return Icons.schedule;
    }
  }
}

/// Badge personnalisé pour les états spéciaux (non notifié, etc.)
class CustomBadge extends StatelessWidget {
  /// Texte du badge
  final String text;

  /// Couleur de fond
  final Color backgroundColor;

  /// Couleur du texte et de l'icône
  final Color foregroundColor;

  /// Icône à afficher
  final IconData icon;

  /// Callback au tap (optionnel, rend le badge cliquable)
  final VoidCallback? onTap;

  /// Afficher une icône info à droite (pour les badges cliquables)
  final bool showInfoIcon;

  /// Taille compacte
  final bool compact;

  const CustomBadge({
    super.key,
    required this.text,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    this.onTap,
    this.showInfoIcon = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: onTap != null
            ? Border.all(color: foregroundColor.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: compact ? 12 : 14,
            color: foregroundColor,
          ),
          SizedBox(width: compact ? 3 : 4),
          Text(
            text,
            style: TextStyle(
              color: foregroundColor,
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (showInfoIcon) ...[
            SizedBox(width: compact ? 2 : 3),
            Icon(
              Icons.info_outline,
              size: compact ? 12 : 14,
              color: foregroundColor,
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }

  /// Factory pour créer un badge "Non notifié"
  factory CustomBadge.notNotified({VoidCallback? onTap, bool compact = false}) {
    return CustomBadge(
      text: 'Non notifié',
      backgroundColor: Colors.grey.shade100,
      foregroundColor: Colors.grey.shade600,
      icon: Icons.visibility_off,
      onTap: onTap,
      showInfoIcon: onTap != null,
      compact: compact,
    );
  }

  /// Factory pour créer un badge de vague
  factory CustomBadge.wave({
    required int waveNumber,
    VoidCallback? onTap,
    bool compact = false,
  }) {
    return CustomBadge(
      text: 'Vague $waveNumber',
      backgroundColor: Colors.blue.shade100,
      foregroundColor: Colors.blue.shade700,
      icon: Icons.waves,
      onTap: onTap,
      showInfoIcon: onTap != null,
      compact: compact,
    );
  }

  /// Factory pour créer un badge de personnes notifiées
  factory CustomBadge.notifiedCount({
    required int count,
    VoidCallback? onTap,
    bool compact = false,
  }) {
    return CustomBadge(
      text: '$count notifiés',
      backgroundColor: Colors.purple.shade100,
      foregroundColor: Colors.purple.shade700,
      icon: Icons.people_outline,
      onTap: onTap,
      showInfoIcon: onTap != null,
      compact: compact,
    );
  }

  /// Factory pour créer un badge de propositions
  factory CustomBadge.proposalCount({
    required int count,
    VoidCallback? onTap,
    bool compact = false,
  }) {
    return CustomBadge(
      text: '$count proposition${count > 1 ? 's' : ''}',
      backgroundColor:
          count > 0 ? Colors.purple.shade100 : Colors.grey.shade100,
      foregroundColor:
          count > 0 ? Colors.purple.shade700 : Colors.grey.shade600,
      icon: Icons.people_outline,
      onTap: count > 0 ? onTap : null,
      showInfoIcon: count > 0 && onTap != null,
      compact: compact,
    );
  }
}
