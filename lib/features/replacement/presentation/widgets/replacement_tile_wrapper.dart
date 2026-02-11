import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/unified_request_tile_exports.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/filtered_requests_view.dart';

/// Widget wrapper pour afficher une demande de remplacement automatique
/// avec le nouveau design unifié
class ReplacementTileWrapper extends StatefulWidget {
  /// La demande de remplacement
  final ReplacementRequest request;

  /// ID de l'utilisateur courant
  final String currentUserId;

  /// ID de la station courante
  final String stationId;

  /// Mode de vue
  final TileViewMode viewMode;

  /// Callback au tap sur la carte
  final VoidCallback? onTap;

  /// Callback pour supprimer
  final VoidCallback? onDelete;

  /// Callback pour accepter
  final VoidCallback? onAccept;

  /// Callback pour refuser
  final VoidCallback? onRefuse;

  /// Callback pour valider (chef)
  final VoidCallback? onValidate;

  /// Callback au tap sur l'indicateur de vague
  final VoidCallback? onWaveTap;

  /// Callback pour marquer comme vu
  final Future<void> Function()? onMarkAsSeen;

  /// Callback DEV pour passer à la vague suivante
  final VoidCallback? onSkipToNextWave;

  /// Callback pour relancer les notifications (vague 5)
  final VoidCallback? onResendNotifications;

  const ReplacementTileWrapper({
    super.key,
    required this.request,
    required this.currentUserId,
    required this.stationId,
    required this.viewMode,
    this.onTap,
    this.onDelete,
    this.onAccept,
    this.onRefuse,
    this.onValidate,
    this.onWaveTap,
    this.onMarkAsSeen,
    this.onSkipToNextWave,
    this.onResendNotifications,
  });

  @override
  State<ReplacementTileWrapper> createState() => _ReplacementTileWrapperState();
}

class _ReplacementTileWrapperState extends State<ReplacementTileWrapper> {
  final _userRepository = UserRepository();
  String _requesterName = 'Chargement...';
  User? _replacer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(ReplacementTileWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.id != widget.request.id ||
        oldWidget.request.replacerId != widget.request.replacerId) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Charger le nom du demandeur
      final requester = await _userRepository.getById(widget.request.requesterId);
      final requesterName = requester != null
          ? requester.displayName
          : 'Inconnu';

      // Charger le remplaçant si accepté
      User? replacer;
      if (widget.request.replacerId != null) {
        replacer = await _userRepository.getById(widget.request.replacerId!);
      }

      if (mounted) {
        setState(() {
          _requesterName = requesterName;
          _replacer = replacer;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _requesterName = 'Erreur';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.blue.shade300,
              ),
            ),
          ),
        ),
      );
    }

    // Convertir la demande en données unifiées
    final tileData = widget.request.toUnifiedTileData(
      requesterName: _requesterName,
      replacer: _replacer,
    );

    // Déterminer si l'utilisateur peut agir
    final isNotified = widget.request.notifiedUserIds.contains(widget.currentUserId);
    final hasDeclined = widget.request.declinedByUserIds.contains(widget.currentUserId);
    final hasPendingAcceptance = widget.request.pendingValidationUserIds.contains(widget.currentUserId);
    final isOwner = widget.request.requesterId == widget.currentUserId;

    bool canAct = false;
    switch (widget.viewMode) {
      case TileViewMode.pending:
        canAct = isNotified && !hasDeclined && !hasPendingAcceptance;
        break;
      case TileViewMode.myRequests:
        canAct = isOwner;
        break;
      case TileViewMode.toValidate:
        // À implémenter selon la logique chef
        canAct = true;
        break;
      case TileViewMode.history:
        canAct = false;
        break;
    }

    // Afficher le bouton DEV uniquement en mode DEV et pour les demandes pending de type replacement
    final showDevButton = EnvironmentConfig.isDev &&
        widget.request.status == ReplacementRequestStatus.pending &&
        widget.request.requestType == RequestType.replacement;

    // onTap uniquement pour le mode "Mes demandes" (ouvre le BottomSheet)
    // Dans les autres modes, l'accès aux dialogs se fait via les boutons
    final effectiveOnTap = widget.viewMode == TileViewMode.myRequests ? widget.onTap : null;

    return UnifiedRequestTile(
      data: tileData,
      viewMode: widget.viewMode,
      currentUserId: widget.currentUserId,
      canAct: canAct,
      onTap: effectiveOnTap,
      onDelete: widget.viewMode == TileViewMode.myRequests ? widget.onDelete : null,
      onAccept: widget.viewMode == TileViewMode.pending ? widget.onAccept : null,
      onRefuse: widget.viewMode == TileViewMode.pending ? widget.onRefuse : null,
      onValidate: widget.viewMode == TileViewMode.toValidate ? widget.onValidate : null,
      onWaveTap: widget.onWaveTap,
      onMarkAsSeen: widget.onMarkAsSeen,
      showDevButton: showDevButton,
      onSkipToNextWave: widget.onSkipToNextWave,
      onResendNotifications: widget.viewMode == TileViewMode.myRequests ? widget.onResendNotifications : null,
      acceptButtonText: 'Accepter',
      refuseButtonText: 'Refuser',
    );
  }
}

/// Widget wrapper pour afficher une proposition de remplacement manuel
/// avec le nouveau design unifié
class ManualProposalTileWrapper extends StatefulWidget {
  /// La proposition manuelle
  final ManualReplacementProposal proposal;

  /// ID de l'utilisateur courant
  final String currentUserId;

  /// Mode de vue
  final TileViewMode viewMode;

  /// Station (optionnel)
  final String? station;

  /// Callback au tap sur la carte
  final VoidCallback? onTap;

  /// Callback pour supprimer
  final VoidCallback? onDelete;

  /// Callback pour accepter
  final VoidCallback? onAccept;

  /// Callback pour refuser
  final VoidCallback? onRefuse;

  /// Callback pour relancer les notifications
  final VoidCallback? onResendNotifications;

  const ManualProposalTileWrapper({
    super.key,
    required this.proposal,
    required this.currentUserId,
    required this.viewMode,
    this.station,
    this.onTap,
    this.onDelete,
    this.onAccept,
    this.onRefuse,
    this.onResendNotifications,
  });

  @override
  State<ManualProposalTileWrapper> createState() => _ManualProposalTileWrapperState();
}

class _ManualProposalTileWrapperState extends State<ManualProposalTileWrapper> {
  final _userRepository = UserRepository();
  String? _replacedTeam;
  String? _replacerTeam;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  @override
  void didUpdateWidget(ManualProposalTileWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.proposal.id != widget.proposal.id ||
        oldWidget.proposal.replacedId != widget.proposal.replacedId ||
        oldWidget.proposal.replacerId != widget.proposal.replacerId) {
      _loadTeams();
    }
  }

  Future<void> _loadTeams() async {
    setState(() => _isLoading = true);

    try {
      // Charger l'équipe du remplacé
      final replacedUser = await _userRepository.getById(widget.proposal.replacedId);
      final replacedTeam = replacedUser?.team;

      // Charger l'équipe du remplaçant
      final replacerUser = await _userRepository.getById(widget.proposal.replacerId);
      final replacerTeam = replacerUser?.team;

      if (mounted) {
        setState(() {
          _replacedTeam = replacedTeam;
          _replacerTeam = replacerTeam;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading teams for manual proposal: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.purple.shade300,
              ),
            ),
          ),
        ),
      );
    }

    // Convertir la proposition en données unifiées avec les équipes chargées
    final tileData = _buildTileData();

    // Déterminer si l'utilisateur peut agir
    final isReplaced = widget.proposal.replacedId == widget.currentUserId;
    final isDesignatedReplacer = widget.proposal.replacerId == widget.currentUserId;

    bool canAct = false;
    switch (widget.viewMode) {
      case TileViewMode.pending:
        canAct = isDesignatedReplacer && widget.proposal.status == 'pending';
        break;
      case TileViewMode.myRequests:
        canAct = isReplaced;
        break;
      case TileViewMode.toValidate:
      case TileViewMode.history:
        canAct = false;
        break;
    }

    // onTap uniquement pour le mode "Mes demandes" (ouvre le BottomSheet)
    final effectiveOnTap = widget.viewMode == TileViewMode.myRequests && isReplaced ? widget.onTap : null;

    return UnifiedRequestTile(
      data: tileData,
      viewMode: widget.viewMode,
      currentUserId: widget.currentUserId,
      canAct: canAct,
      onTap: effectiveOnTap,
      onDelete: widget.viewMode == TileViewMode.myRequests && isReplaced ? widget.onDelete : null,
      onAccept: widget.viewMode == TileViewMode.pending && isDesignatedReplacer ? widget.onAccept : null,
      onRefuse: widget.viewMode == TileViewMode.pending && isDesignatedReplacer ? widget.onRefuse : null,
      onResendNotifications: widget.viewMode == TileViewMode.myRequests && isReplaced ? widget.onResendNotifications : null,
      acceptButtonText: 'Accepter',
      refuseButtonText: 'Refuser',
    );
  }

  /// Construit les données de la tuile avec les équipes chargées
  UnifiedTileData _buildTileData() {
    final proposal = widget.proposal;

    return UnifiedTileData(
      id: proposal.id,
      requestType: UnifiedRequestType.manualReplacement,
      status: _mapStatus(proposal.status),
      createdAt: proposal.createdAt ?? DateTime.now(),
      leftColumn: AgentColumnData(
        agentId: proposal.replacedId,
        agentName: proposal.replacedName,
        team: _replacedTeam ?? proposal.replacedTeam,
        startTime: proposal.startTime,
        endTime: proposal.endTime,
        station: widget.station ?? '',
      ),
      rightColumn: AgentColumnData(
        agentId: proposal.replacerId,
        agentName: proposal.replacerName,
        team: _replacerTeam ?? proposal.replacerTeam,
        startTime: proposal.startTime,
        endTime: proposal.endTime,
        station: widget.station ?? '',
      ),
      extraData: {
        'proposerId': proposal.proposerId,
        'proposerName': proposal.proposerName,
        'planningId': proposal.planningId,
      },
    );
  }

  /// Mappe le statut string vers TileStatus
  TileStatus _mapStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return TileStatus.pending;
      case 'accepted':
        return TileStatus.accepted;
      case 'declined':
        return TileStatus.declined;
      case 'cancelled':
        return TileStatus.cancelled;
      case 'expired':
        return TileStatus.expired;
      default:
        return TileStatus.pending;
    }
  }
}
