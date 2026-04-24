import 'dart:async';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'unified_tile_data.dart';
import 'unified_tile_enums.dart';
import 'components/status_badge.dart';
import 'components/type_indicator.dart';
import 'components/request_column.dart';
import 'components/tile_actions_footer.dart';
import 'components/special_indicators.dart';

/// Widget principal de tuile unifiée pour les demandes de remplacement et échanges
///
/// Utilise un layout 2 colonnes avec icône centrale :
/// ```
/// ┌─────────────────────────────────────────────────────────────────┐
/// │  [En-tête validation optionnel : Chef A ✓ | Chef B ⏳]         │
/// ├────────────────────┬─────────┬──────────────────────────────────┤
/// │   COLONNE GAUCHE   │  ICÔNE  │      COLONNE DROITE              │
/// │   (demandeur)      │ CENTRALE│      (remplaçant)                │
/// ├────────────────────┴─────────┴──────────────────────────────────┤
/// │  [Indicateurs : 🌊 Vague 2 | 👥 3 propositions]                │
/// ├─────────────────────────────────────────────────────────────────┤
/// │  [Actions : ❌ Refuser | ✅ Accepter]                           │
/// └─────────────────────────────────────────────────────────────────┘
/// ```
class UnifiedRequestTile extends StatefulWidget {
  /// Données de la demande
  final UnifiedTileData data;

  /// Mode de vue (détermine les actions disponibles)
  final TileViewMode viewMode;

  /// ID de l'utilisateur courant (pour déterminer les droits)
  final String currentUserId;

  /// L'utilisateur peut-il agir sur cette demande ?
  final bool canAct;

  /// Callback au tap sur la carte
  final VoidCallback? onTap;

  /// Callback pour suppression
  final VoidCallback? onDelete;

  /// Callback pour accepter
  final VoidCallback? onAccept;

  /// Callback pour refuser
  final VoidCallback? onRefuse;

  /// Callback pour valider (chef)
  final VoidCallback? onValidate;

  /// Callback pour marquer comme vu
  final Future<void> Function()? onMarkAsSeen;

  /// Callback au tap sur l'indicateur de vague
  final VoidCallback? onWaveTap;

  /// Callback au tap sur le compteur de propositions
  final VoidCallback? onProposalsTap;

  /// Callback DEV pour passer à la vague suivante
  final VoidCallback? onSkipToNextWave;

  /// Callback pour relancer les notifications (vague 5)
  final VoidCallback? onResendNotifications;

  /// Callback pour débloquer les compétences-clés (myRequests, vague 5+, chef/admin)
  final VoidCallback? onUnlockKeySkills;

  /// Callback pour voir le détail (navigation vers la page de détail)
  final VoidCallback? onViewDetails;

  /// Callback au tap sur le badge "Historique" (mode history uniquement)
  final VoidCallback? onHistoryTap;

  /// Widget d'en-tête personnalisé (remplace ValidationHeader si fourni)
  final Widget? headerWidget;

  /// Badge personnalisé pour la colonne gauche (remplace le badge calculé automatiquement)
  final Widget? leftBadgeOverride;

  /// Badge personnalisé pour la colonne droite (remplace le badge calculé automatiquement)
  final Widget? rightBadgeOverride;

  /// Afficher le bouton DEV (uniquement en mode dev)
  final bool showDevButton;

  /// Texte personnalisé pour le bouton d'acceptation
  final String? acceptButtonText;

  /// Texte personnalisé pour le bouton de refus
  final String? refuseButtonText;

  /// Délai avant de marquer comme "vu" (en secondes)
  final int seenDelaySeconds;

  const UnifiedRequestTile({
    super.key,
    required this.data,
    required this.viewMode,
    required this.currentUserId,
    this.canAct = true,
    this.onTap,
    this.onDelete,
    this.onAccept,
    this.onRefuse,
    this.onValidate,
    this.onMarkAsSeen,
    this.onWaveTap,
    this.onProposalsTap,
    this.onSkipToNextWave,
    this.onResendNotifications,
    this.onUnlockKeySkills,
    this.onViewDetails,
    this.onHistoryTap,
    this.headerWidget,
    this.leftBadgeOverride,
    this.rightBadgeOverride,
    this.showDevButton = false,
    this.acceptButtonText,
    this.refuseButtonText,
    this.seenDelaySeconds = 2,
  });

  @override
  State<UnifiedRequestTile> createState() => _UnifiedRequestTileState();
}

class _UnifiedRequestTileState extends State<UnifiedRequestTile> {
  Timer? _seenTimer;
  bool _hasBeenMarkedSeen = false;

  @override
  void dispose() {
    _seenTimer?.cancel();
    super.dispose();
  }

  /// Démarre le timer pour marquer comme "vu"
  void _startSeenTimer() {
    if (_hasBeenMarkedSeen) return;
    if (widget.data.hasBeenSeenBy(widget.currentUserId)) return;
    if (widget.onMarkAsSeen == null) return;
    if (widget.viewMode != TileViewMode.pending) return;

    _seenTimer?.cancel();
    _seenTimer = Timer(Duration(seconds: widget.seenDelaySeconds), () {
      _markAsSeen();
    });
  }

  /// Annule le timer
  void _cancelSeenTimer() {
    _seenTimer?.cancel();
  }

  /// Marque la demande comme vue
  Future<void> _markAsSeen() async {
    if (_hasBeenMarkedSeen) return;
    if (widget.onMarkAsSeen == null) return;

    _hasBeenMarkedSeen = true;
    await widget.onMarkAsSeen!();
  }

  @override
  Widget build(BuildContext context) {
    final isUserNotified = widget.data.isUserNotified(widget.currentUserId);
    final hasDeclined = widget.data.hasBeenDeclinedBy(widget.currentUserId);

    // Les remplacements manuels et échanges n'utilisent pas le système de vagues
    // donc pas besoin de vérifier isUserNotified pour ces types
    final usesWaveSystem =
        widget.data.requestType == UnifiedRequestType.automaticReplacement ||
        widget.data.requestType == UnifiedRequestType.sosReplacement;

    // Déterminer si les actions sont possibles
    final canActNow =
        widget.canAct &&
        !hasDeclined &&
        (widget.viewMode != TileViewMode.pending ||
            isUserNotified ||
            !usesWaveSystem);

    // Construire les chefs pour l'en-tête de validation
    final validationChiefs = _buildValidationChiefs();

    // Calculer le footer avant la construction de la carte
    final footer = TileActionsFooter(
      viewMode: widget.viewMode,
      requestType: widget.data.requestType,
      canAct: canActNow,
      currentWave: widget.data.currentWave,
      proposalCount: widget.data.proposalCount,
      usesWaveSystem: usesWaveSystem,
      onAccept: widget.onAccept,
      onRefuse: widget.onRefuse,
      onValidate: widget.onValidate,
      onDelete: widget.onDelete,
      onWaveTap: widget.onWaveTap,
      onHistoryTap: widget.onHistoryTap,
      onProposalsTap: widget.onProposalsTap,
      onResendNotifications: widget.onResendNotifications,
      onUnlockKeySkills: widget.onUnlockKeySkills,
      onViewDetails: widget.onViewDetails,
      acceptButtonText: widget.acceptButtonText,
      refuseButtonText: widget.refuseButtonText,
    );
    // En mode history, le footer est visible s'il y a des boutons (vague ou historique)
    final hasHistoryFooter = widget.viewMode == TileViewMode.history &&
        (widget.onHistoryTap != null ||
            (usesWaveSystem && widget.data.currentWave != null));
    final hasFooter = widget.viewMode != TileViewMode.history || hasHistoryFooter;

    Widget card = Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: widget.data.isSOS
            ? BorderSide(color: Colors.red.shade300, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Corps de la carte (padded)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, hasFooter ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // En-tête personnalisé (priorité) ou en-tête de validation générique
                  if (widget.headerWidget != null) ...[
                    widget.headerWidget!,
                    const SizedBox(height: 12),
                  ] else if (validationChiefs.isNotEmpty) ...[
                    ValidationHeader(
                      chiefs: validationChiefs,
                      showDivider: true,
                      compact: widget.viewMode == TileViewMode.history,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Layout principal : 2 colonnes avec icône centrale
                  Builder(
                    builder: (context) {
                      // Masquer les badges de statut dans les colonnes quand un header
                      // les remplace déjà (headerWidget personnalisé, ou history)
                      final hasValidationHeader =
                          widget.headerWidget != null ||
                          (validationChiefs.isNotEmpty &&
                           widget.viewMode == TileViewMode.history);
                      final badgeVisibility = _calculateBadgeVisibility(
                        hasDeclined,
                        suppressIfValidationHeader: hasValidationHeader,
                      );

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: RequestColumn(
                              data: widget.data.leftColumn,
                              statusBadge: widget.leftBadgeOverride ?? _buildLeftStatusBadge(hasDeclined),
                              showBadge: widget.leftBadgeOverride != null ? true : badgeVisibility.leftBadge,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: TypeIndicator(
                                requestType: widget.data.requestType,
                                status: widget.data.status,
                                size: 28,
                              ),
                            ),
                          ),
                          Expanded(
                            child: widget.data.hasRightColumn
                                ? RequestColumn(
                                    data: widget.data.rightColumn!,
                                    statusBadge: widget.rightBadgeOverride ?? _buildRightStatusBadge(),
                                    showBadge: widget.rightBadgeOverride != null ? true : badgeVisibility.rightBadge,
                                    showDates: widget.data.requestType !=
                                        UnifiedRequestType.agentQuery,
                                    showStation: widget.data.requestType !=
                                        UnifiedRequestType.agentQuery,
                                  )
                                : _buildEmptyColumnWithDelete(),
                          ),
                        ],
                      );
                    },
                  ),

                  // Indicateurs spéciaux — uniquement pour les modes non-history
                  // (en mode history, vague et historique sont dans le footer)
                  if (_hasSpecialIndicators(isUserNotified) &&
                      widget.viewMode != TileViewMode.history) ...[
                    const SizedBox(height: 12),
                    SpecialIndicatorsBar(
                      currentWave: widget.data.currentWave,
                      notifiedCount:
                          widget.data.requestType == UnifiedRequestType.exchange
                          ? null
                          : widget.data.notifiedUserIds.length,
                      proposalCount: widget.data.proposalCount,
                      isUserNotified: isUserNotified,
                      isMyRequestsMode: widget.viewMode == TileViewMode.myRequests,
                      onWaveTap: widget.onWaveTap,
                      onNotifiedTap: widget.onWaveTap,
                      onProposalsTap: widget.onProposalsTap,
                      onNotNotifiedTap: widget.onWaveTap,
                      onHistoryTap: widget.onHistoryTap,
                    ),
                  ],
                ],
              ),
            ),

            // Footer collé au bas, hors padding, avec fond teinté
            if (hasFooter) footer,
          ],
        ),
      ),
    );

    // Wrapper avec VisibilityDetector pour l'état "Vu"
    if (widget.viewMode == TileViewMode.pending &&
        widget.onMarkAsSeen != null &&
        !widget.data.hasBeenSeenBy(widget.currentUserId)) {
      return VisibilityDetector(
        key: Key('unified_tile_${widget.data.id}'),
        onVisibilityChanged: (info) {
          if (info.visibleFraction > 0.5) {
            _startSeenTimer();
          } else {
            _cancelSeenTimer();
          }
        },
        child: card,
      );
    }

    return card;
  }

  /// Construit le badge de statut pour la colonne gauche
  ///
  /// Les badges de validation (En attente, Refusé, Accepté) ne sont affichés que pour :
  /// - Les demandes d'échange (toujours)
  /// - Les remplacements automatiques avec agent sous-qualifié nécessitant validation chef
  /// - Le badge "Refusé par vous" est toujours affiché si l'utilisateur a décliné
  /// - Le badge "Expiré" est toujours affiché pour les demandes expirées
  Widget _buildLeftStatusBadge(bool hasDeclined) {
    // Afficher "Refusé par vous" si l'utilisateur a décliné — sauf en mode historique
    // (en historique, le statut final de la demande est plus pertinent)
    if (hasDeclined && widget.viewMode != TileViewMode.history) {
      return const StatusBadge(
        status: TileStatus.declined,
        customText: 'Refusé par vous',
        compact: true,
      );
    }

    // Toujours afficher le badge "Expiré" si la demande est expirée
    if (widget.data.status == TileStatus.expired) {
      return const StatusBadge(status: TileStatus.expired, compact: true);
    }

    // Pour "En attente de validation", afficher uniquement si vraiment en attente de validation chef
    final hasPendingAcceptance =
        widget.data.extraData['hasPendingAcceptance'] == true;
    if (hasPendingAcceptance) {
      return const StatusBadge(
        status: TileStatus.pendingValidation,
        compact: true,
      );
    }

    // Les badges de validation ne s'affichent que pour :
    // - Les échanges
    // - Les remplacements nécessitant validation chef (validationChiefs non vide)
    final requiresChiefValidation =
        widget.data.requiresChiefValidation ||
        widget.data.requestType == UnifiedRequestType.exchange;

    // Pour les vues "A valider" et "Historique", afficher le statut de validation si applicable
    if (requiresChiefValidation &&
        (widget.viewMode == TileViewMode.toValidate ||
            widget.viewMode == TileViewMode.history)) {
      return StatusBadge(status: widget.data.status, compact: true);
    }

    // Pour les autres cas (remplacements normaux sans validation chef), pas de badge
    return const SizedBox.shrink();
  }

  /// Construit le badge de statut pour la colonne droite
  Widget _buildRightStatusBadge() {
    // Même logique que pour la colonne gauche pour la cohérence
    // Les badges de validation ne s'affichent que pour les cas nécessitant validation chef

    // Toujours afficher le badge "Expiré" si la demande est expirée
    if (widget.data.status == TileStatus.expired) {
      return const StatusBadge(status: TileStatus.expired, compact: true);
    }

    // Les badges de validation ne s'affichent que pour :
    // - Les échanges
    // - Les remplacements nécessitant validation chef (validationChiefs non vide)
    final requiresChiefValidation =
        widget.data.requiresChiefValidation ||
        widget.data.requestType == UnifiedRequestType.exchange;

    // Pour les vues "A valider" et "Historique", afficher le statut de validation si applicable
    if (requiresChiefValidation &&
        (widget.viewMode == TileViewMode.toValidate ||
            widget.viewMode == TileViewMode.history)) {
      return StatusBadge(status: widget.data.status, compact: true);
    }

    // Pour les autres cas, pas de badge
    return const SizedBox.shrink();
  }

  /// Calcule la visibilité des badges pour les deux colonnes
  ///
  /// Retourne un record avec :
  /// - leftBadge: true (afficher), false (placeholder), null (masquer avec divider)
  /// - rightBadge: true (afficher), false (placeholder), null (masquer avec divider)
  ({bool? leftBadge, bool? rightBadge}) _calculateBadgeVisibility(
    bool hasDeclined, {
    bool suppressIfValidationHeader = false,
  }) {
    // Si un header de validation pleine largeur est affiché, masquer tous les badges
    // de statut dans les colonnes (ils seraient redondants et créeraient un décalage)
    if (suppressIfValidationHeader) {
      return (leftBadge: null, rightBadge: null);
    }

    // Déterminer si chaque colonne a un badge à afficher
    final leftHasBadge = _shouldShowLeftBadge(hasDeclined);
    final rightHasBadge = _shouldShowRightBadge();

    // Si aucune colonne n'a de badge, masquer tout (null)
    if (!leftHasBadge && !rightHasBadge) {
      return (leftBadge: null, rightBadge: null);
    }

    // Si les deux ont un badge, les afficher
    if (leftHasBadge && rightHasBadge) {
      return (leftBadge: true, rightBadge: true);
    }

    // Si une seule a un badge, afficher le badge et un placeholder pour l'autre
    if (leftHasBadge) {
      return (leftBadge: true, rightBadge: false);
    } else {
      return (leftBadge: false, rightBadge: true);
    }
  }

  /// Vérifie si la colonne gauche doit afficher un badge
  bool _shouldShowLeftBadge(bool hasDeclined) {
    // "Refusé par vous" affiché sauf en mode historique
    if (hasDeclined && widget.viewMode != TileViewMode.history) return true;

    // "Expiré" est toujours affiché
    if (widget.data.status == TileStatus.expired) return true;

    // "En attente de validation" si applicable
    final hasPendingAcceptance =
        widget.data.extraData['hasPendingAcceptance'] == true;
    if (hasPendingAcceptance) return true;

    // Badge de validation pour échanges ou remplacements sous-qualifiés
    final requiresChiefValidation =
        widget.data.requiresChiefValidation ||
        widget.data.requestType == UnifiedRequestType.exchange;

    if (requiresChiefValidation &&
        (widget.viewMode == TileViewMode.toValidate ||
            widget.viewMode == TileViewMode.history)) {
      return true;
    }

    return false;
  }

  /// Vérifie si la colonne droite doit afficher un badge
  bool _shouldShowRightBadge() {
    // "Expiré" est toujours affiché
    if (widget.data.status == TileStatus.expired) return true;

    // Badge de validation pour échanges ou remplacements sous-qualifiés
    final requiresChiefValidation =
        widget.data.requiresChiefValidation ||
        widget.data.requestType == UnifiedRequestType.exchange;

    if (requiresChiefValidation &&
        (widget.viewMode == TileViewMode.toValidate ||
            widget.viewMode == TileViewMode.history)) {
      return true;
    }

    return false;
  }

  /// Construit la colonne droite vide (pour les demandes sans remplaçant désigné)
  Widget _buildEmptyColumnWithDelete() {
    // Les actions (relance/suppression) sont gérées via le BottomSheet (onTap)
    return const EmptyColumn();
  }

  /// Construit la liste des chefs pour l'en-tête de validation
  List<ValidationChiefDisplay> _buildValidationChiefs() {
    if (widget.data.validationChiefs == null ||
        widget.data.validationChiefs!.isEmpty) {
      return [];
    }

    // Dans l'historique, n'afficher que les chefs ayant validé
    if (widget.viewMode == TileViewMode.history) {
      return widget.data.validationChiefs!
          .where((chief) => chief.hasValidated == true)
          .map(
            (chief) => ValidationChiefDisplay(
              name: chief.chiefName,
              hasValidated: chief.hasValidated,
              teamLabel: chief.team,
            ),
          )
          .toList();
    }

    // Dans les autres vues, afficher tous les chefs avec leur statut
    return widget.data.validationChiefs!
        .map(
          (chief) => ValidationChiefDisplay(
            name: chief.chiefName,
            hasValidated: chief.hasValidated,
            teamLabel: chief.team,
            teamStatuses: chief.teamStatuses,
          ),
        )
        .toList();
  }

  /// Vérifie si des indicateurs spéciaux doivent être affichés
  bool _hasSpecialIndicators(bool isUserNotified) {
    // Les remplacements manuels et échanges n'utilisent pas le système de vagues
    final usesWaveSystem =
        widget.data.requestType == UnifiedRequestType.automaticReplacement ||
        widget.data.requestType == UnifiedRequestType.sosReplacement;

    // Badge vague ou notifiés pour remplacement auto uniquement
    if (widget.data.currentWave != null && usesWaveSystem) {
      return true;
    }

    // Badge "Non notifié" uniquement pour les demandes avec système de vagues
    // MAIS pas en mode "Mes demandes" (on affiche la vague à la place)
    if (!isUserNotified &&
        widget.viewMode == TileViewMode.pending &&
        usesWaveSystem) {
      return true;
    }

    // En mode "Mes demandes" pour les remplacements auto, afficher la vague
    if (widget.viewMode == TileViewMode.myRequests &&
        usesWaveSystem &&
        widget.data.currentWave != null) {
      return true;
    }

    // Badge propositions pour échanges
    if (widget.data.proposalCount != null &&
        widget.viewMode == TileViewMode.myRequests) {
      return true;
    }

    // Badge agents notifiés pour les recherches (agentQuery) en mode "Mes demandes" et "Historique"
    if (widget.data.requestType == UnifiedRequestType.agentQuery &&
        widget.data.notifiedUserIds.isNotEmpty &&
        (widget.viewMode == TileViewMode.myRequests ||
            widget.viewMode == TileViewMode.history)) {
      return true;
    }

    // Badge "Historique" si onHistoryTap fourni (mode history uniquement)
    if (widget.viewMode == TileViewMode.history && widget.onHistoryTap != null) {
      return true;
    }

    return false;
  }
}
