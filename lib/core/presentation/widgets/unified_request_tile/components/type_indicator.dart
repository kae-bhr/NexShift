import 'package:flutter/material.dart';
import '../unified_tile_enums.dart';

/// Indicateur central du type de demande
/// Affiche une icône représentant le type (auto, SOS, manuel, échange)
/// ou l'état final (expiré, annulé) dans l'historique
class TypeIndicator extends StatelessWidget {
  /// Type de demande
  final UnifiedRequestType requestType;

  /// Statut de la demande (pour afficher l'icône d'état final)
  final TileStatus status;

  /// Taille de l'icône
  final double size;

  /// Afficher le conteneur décoratif (cercle coloré)
  final bool showContainer;

  const TypeIndicator({
    super.key,
    required this.requestType,
    required this.status,
    this.size = 32,
    this.showContainer = false,
  });

  @override
  Widget build(BuildContext context) {
    // Pour les états finaux négatifs, afficher l'icône correspondante
    if (status == TileStatus.expired) {
      return _buildIcon(
        Icons.block,
        Colors.grey.shade500,
        showContainer: showContainer,
        containerColor: Colors.grey.shade100,
        containerBorderColor: Colors.grey.shade300,
      );
    }

    if (status == TileStatus.cancelled) {
      return _buildIcon(
        Icons.cancel_outlined,
        Colors.orange.shade600,
        showContainer: showContainer,
        containerColor: Colors.orange.shade50,
        containerBorderColor: Colors.orange.shade200,
      );
    }

    // Pour les états validés/acceptés, montrer un check avec l'icône du type
    if (status == TileStatus.validated ||
        status == TileStatus.accepted ||
        status == TileStatus.autoValidated) {
      return _buildIcon(
        _getTypeIcon(),
        Colors.green.shade600,
        showContainer: showContainer,
        containerColor: Colors.green.shade50,
        containerBorderColor: Colors.green.shade200,
      );
    }

    // Pour les états en cours, montrer l'icône du type
    return _buildIcon(
      _getTypeIcon(),
      _getTypeColor(),
      showContainer: showContainer,
      containerColor: _getTypeColor().withValues(alpha: 0.1),
      containerBorderColor: _getTypeColor().withValues(alpha: 0.3),
    );
  }

  Widget _buildIcon(
    IconData icon,
    Color color, {
    bool showContainer = false,
    Color? containerColor,
    Color? containerBorderColor,
  }) {
    final iconWidget = Icon(icon, color: color, size: size);

    if (!showContainer) {
      return iconWidget;
    }

    return Container(
      padding: EdgeInsets.all(size * 0.25),
      decoration: BoxDecoration(
        color: containerColor,
        shape: BoxShape.circle,
        border: containerBorderColor != null
            ? Border.all(color: containerBorderColor, width: 2)
            : null,
      ),
      child: iconWidget,
    );
  }

  /// Retourne l'icône correspondant au type de demande
  IconData _getTypeIcon() {
    switch (requestType) {
      case UnifiedRequestType.automaticReplacement:
        return Icons.autorenew;
      case UnifiedRequestType.sosReplacement:
        return Icons.warning_rounded;
      case UnifiedRequestType.manualReplacement:
        return Icons.person_pin;
      case UnifiedRequestType.exchange:
        return Icons.swap_horiz;
    }
  }

  /// Retourne la couleur correspondant au type de demande
  Color _getTypeColor() {
    switch (requestType) {
      case UnifiedRequestType.automaticReplacement:
        return Colors.blue.shade600;
      case UnifiedRequestType.sosReplacement:
        return Colors.red.shade600;
      case UnifiedRequestType.manualReplacement:
        return Colors.purple.shade600;
      case UnifiedRequestType.exchange:
        return Colors.green.shade600;
    }
  }
}

/// Version simplifiée pour afficher juste l'icône du type sans état
class SimpleTypeIcon extends StatelessWidget {
  /// Type de demande
  final UnifiedRequestType requestType;

  /// Taille de l'icône
  final double size;

  const SimpleTypeIcon({
    super.key,
    required this.requestType,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      _getIcon(),
      color: _getColor(),
      size: size,
    );
  }

  IconData _getIcon() {
    switch (requestType) {
      case UnifiedRequestType.automaticReplacement:
        return Icons.autorenew;
      case UnifiedRequestType.sosReplacement:
        return Icons.warning_rounded;
      case UnifiedRequestType.manualReplacement:
        return Icons.person_pin;
      case UnifiedRequestType.exchange:
        return Icons.swap_horiz;
    }
  }

  Color _getColor() {
    switch (requestType) {
      case UnifiedRequestType.automaticReplacement:
        return Colors.blue.shade600;
      case UnifiedRequestType.sosReplacement:
        return Colors.red.shade600;
      case UnifiedRequestType.manualReplacement:
        return Colors.purple.shade600;
      case UnifiedRequestType.exchange:
        return Colors.green.shade600;
    }
  }
}
