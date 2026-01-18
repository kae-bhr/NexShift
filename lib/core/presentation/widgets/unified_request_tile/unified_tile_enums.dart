/// Enums et types pour les tuiles de demande unifiées
library;

/// Type de demande pour l'affichage
enum UnifiedRequestType {
  /// Remplacement automatique (système de vagues)
  automaticReplacement,

  /// Remplacement SOS urgent
  sosReplacement,

  /// Remplacement manuel (proposition directe)
  manualReplacement,

  /// Échange de garde
  exchange,
}

/// Mode de vue déterminant les actions disponibles
enum TileViewMode {
  /// Historique : lecture seule, aucune action
  history,

  /// Mes demandes : action de suppression possible
  myRequests,

  /// En attente : action de réponse (accepter/refuser)
  pending,

  /// À valider : action de validation chef
  toValidate,
}

/// Statut de la demande pour l'affichage du badge
enum TileStatus {
  /// En attente de réponse
  pending,

  /// Accepté
  accepted,

  /// Refusé
  declined,

  /// Expiré (délai dépassé)
  expired,

  /// Annulé par le demandeur
  cancelled,

  /// En attente de validation par le chef
  pendingValidation,

  /// Validé par le chef
  validated,

  /// Auto-validé (pas de validation chef requise)
  autoValidated,
}

/// Extension pour obtenir les propriétés d'affichage du statut
extension TileStatusDisplay on TileStatus {
  /// Texte d'affichage du statut
  String get displayText {
    switch (this) {
      case TileStatus.pending:
        return 'En attente';
      case TileStatus.accepted:
        return 'Accepté';
      case TileStatus.declined:
        return 'Refusé';
      case TileStatus.expired:
        return 'Expiré';
      case TileStatus.cancelled:
        return 'Annulé';
      case TileStatus.pendingValidation:
        return 'En attente de validation';
      case TileStatus.validated:
        return 'Validé';
      case TileStatus.autoValidated:
        return 'Auto-validé';
    }
  }

  /// Indique si ce statut représente un état "final" (historique)
  bool get isFinal {
    switch (this) {
      case TileStatus.accepted:
      case TileStatus.declined:
      case TileStatus.expired:
      case TileStatus.cancelled:
      case TileStatus.validated:
      case TileStatus.autoValidated:
        return true;
      case TileStatus.pending:
      case TileStatus.pendingValidation:
        return false;
    }
  }
}

/// Extension pour obtenir les propriétés d'affichage du type de demande
extension UnifiedRequestTypeDisplay on UnifiedRequestType {
  /// Texte d'affichage du type
  String get displayText {
    switch (this) {
      case UnifiedRequestType.automaticReplacement:
        return 'Remplacement';
      case UnifiedRequestType.sosReplacement:
        return 'SOS';
      case UnifiedRequestType.manualReplacement:
        return 'Remplacement manuel';
      case UnifiedRequestType.exchange:
        return 'Échange';
    }
  }
}
