import 'package:flutter/material.dart';
import '../unified_tile_enums.dart';

/// Barre d'actions conditionnelle pour les tuiles de demande
/// Affiche les boutons appropriés selon le mode de vue
/// Convention : [ Refuser (gauche) ]  [ Accepter (droite) ]
class TileActionBar extends StatelessWidget {
  /// Mode de vue déterminant les actions disponibles
  final TileViewMode viewMode;

  /// L'utilisateur peut-il agir sur cette demande ?
  final bool canAct;

  /// Callback pour suppression (myRequests)
  final VoidCallback? onDelete;

  /// Callback pour accepter/répondre (pending)
  final VoidCallback? onAccept;

  /// Callback pour refuser (pending, toValidate)
  final VoidCallback? onRefuse;

  /// Callback pour valider (toValidate)
  final VoidCallback? onValidate;

  /// Texte personnalisé pour le bouton d'acceptation
  final String? acceptButtonText;

  /// Texte personnalisé pour le bouton de refus
  final String? refuseButtonText;

  /// Afficher en mode compact (icônes seulement)
  final bool compact;

  const TileActionBar({
    super.key,
    required this.viewMode,
    this.canAct = true,
    this.onDelete,
    this.onAccept,
    this.onRefuse,
    this.onValidate,
    this.acceptButtonText,
    this.refuseButtonText,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // Historique : aucune action
    if (viewMode == TileViewMode.history) {
      return const SizedBox.shrink();
    }

    // Si l'utilisateur ne peut pas agir, ne rien afficher
    if (!canAct) {
      return const SizedBox.shrink();
    }

    switch (viewMode) {
      case TileViewMode.history:
        return const SizedBox.shrink();

      case TileViewMode.myRequests:
        return _buildMyRequestsActions();

      case TileViewMode.pending:
        return _buildPendingActions();

      case TileViewMode.toValidate:
        return _buildValidationActions();
    }
  }

  /// Actions pour "Mes demandes" : bouton supprimer
  Widget _buildMyRequestsActions() {
    if (onDelete == null) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        tooltip: 'Supprimer la demande',
        style: IconButton.styleFrom(
          backgroundColor: Colors.red.shade50,
        ),
      ),
    );
  }

  /// Actions pour "En attente" : Refuser (gauche) | Accepter (droite)
  Widget _buildPendingActions() {
    if (onAccept == null && onRefuse == null) return const SizedBox.shrink();

    return Row(
      children: [
        // Bouton Refuser (gauche)
        if (onRefuse != null)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onRefuse,
              icon: Icon(Icons.close, size: compact ? 16 : 18),
              label: compact
                  ? const SizedBox.shrink()
                  : Text(refuseButtonText ?? 'Refuser'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: EdgeInsets.symmetric(
                  vertical: compact ? 8 : 12,
                  horizontal: compact ? 8 : 16,
                ),
              ),
            ),
          ),

        if (onRefuse != null && onAccept != null) const SizedBox(width: 12),

        // Bouton Accepter (droite)
        if (onAccept != null)
          Expanded(
            child: FilledButton.icon(
              onPressed: onAccept,
              icon: Icon(Icons.check, size: compact ? 16 : 18),
              label: compact
                  ? const SizedBox.shrink()
                  : Text(acceptButtonText ?? 'Accepter'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  vertical: compact ? 8 : 12,
                  horizontal: compact ? 8 : 16,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Actions pour "À valider" : Refuser (gauche) | Valider (droite)
  Widget _buildValidationActions() {
    if (onValidate == null && onRefuse == null) return const SizedBox.shrink();

    return Row(
      children: [
        // Bouton Refuser (gauche)
        if (onRefuse != null)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onRefuse,
              icon: Icon(Icons.close, size: compact ? 16 : 18),
              label: compact
                  ? const SizedBox.shrink()
                  : Text(refuseButtonText ?? 'Refuser'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: EdgeInsets.symmetric(
                  vertical: compact ? 8 : 12,
                  horizontal: compact ? 8 : 16,
                ),
              ),
            ),
          ),

        if (onRefuse != null && onValidate != null) const SizedBox(width: 12),

        // Bouton Valider (droite)
        if (onValidate != null)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onValidate,
              icon: Icon(Icons.check, size: compact ? 16 : 18),
              label: compact
                  ? const SizedBox.shrink()
                  : const Text('Valider'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  vertical: compact ? 8 : 12,
                  horizontal: compact ? 8 : 16,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Bouton de suppression isolé (pour placer dans l'en-tête de la carte)
class DeleteButton extends StatelessWidget {
  /// Callback de suppression
  final VoidCallback onDelete;

  /// Taille de l'icône
  final double size;

  const DeleteButton({
    super.key,
    required this.onDelete,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onDelete,
      icon: Icon(Icons.delete_outline, color: Colors.red, size: size),
      tooltip: 'Supprimer',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
    );
  }
}
