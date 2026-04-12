import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/unified_request_tile_exports.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';
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

  /// Utilisateur courant (pour détecter le rôle observateur-privilégié)
  final User? currentUser;

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

  /// Callback pour débloquer les compétences-clés (myRequests, vague 5+, chef/admin)
  final VoidCallback? onUnlockKeySkills;

  const ReplacementTileWrapper({
    super.key,
    required this.request,
    required this.currentUserId,
    required this.stationId,
    required this.viewMode,
    this.currentUser,
    this.onTap,
    this.onDelete,
    this.onAccept,
    this.onRefuse,
    this.onValidate,
    this.onWaveTap,
    this.onMarkAsSeen,
    this.onSkipToNextWave,
    this.onResendNotifications,
    this.onUnlockKeySkills,
  });

  @override
  State<ReplacementTileWrapper> createState() => _ReplacementTileWrapperState();
}

class _ReplacementTileWrapperState extends State<ReplacementTileWrapper> {
  final _userRepository = UserRepository();
  String _requesterName = 'Chargement...';
  String _stationName = '';
  User? _replacer;
  DateTime? _pendingAcceptanceStartTime;
  DateTime? _pendingAcceptanceEndTime;
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
        oldWidget.request.replacerId != widget.request.replacerId ||
        !listEquals(oldWidget.request.pendingValidationUserIds,
            widget.request.pendingValidationUserIds)) {
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
          : 'Agent ${widget.request.requesterId}';

      // Charger le remplaçant si accepté (replacerId renseigné = remplacement validé)
      User? replacer;
      DateTime? pendingStart;
      DateTime? pendingEnd;
      if (widget.request.replacerId != null) {
        replacer = await _userRepository.getById(widget.request.replacerId!);
      } else if (widget.request.pendingValidationUserIds.isNotEmpty) {
        // En attente de validation chef : requête Firestore ciblée (évite fromJson
        // qui échoue si userName n'est pas persisté dans le document)
        final acceptancesPath = EnvironmentConfig.getCollectionPath(
          'replacements/automatic/replacementAcceptances',
          widget.request.station,
        );
        final snap = await FirebaseFirestore.instance
            .collection(acceptancesPath)
            .where('requestId', isEqualTo: widget.request.id)
            .where('status', isEqualTo: 'pendingValidation')
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final data = snap.docs.first.data();
          final userId = data['userId'] as String?;
          final rawStart = data['acceptedStartTime'];
          final rawEnd = data['acceptedEndTime'];
          if (userId != null) {
            replacer = await _userRepository.getById(userId);
            pendingStart = rawStart != null ? (rawStart as Timestamp).toDate() : null;
            pendingEnd = rawEnd != null ? (rawEnd as Timestamp).toDate() : null;
          }
        }
      }

      // Résoudre le nom de la station
      String stationName = widget.request.station;
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && widget.request.station.isNotEmpty) {
        stationName = await StationNameCache().getStationName(sdisId, widget.request.station);
      }

      if (mounted) {
        setState(() {
          _requesterName = requesterName;
          _replacer = replacer;
          _pendingAcceptanceStartTime = pendingStart;
          _pendingAcceptanceEndTime = pendingEnd;
          _stationName = stationName;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _requesterName = 'Erreur';
          _stationName = widget.request.station;
          _isLoading = false;
        });
      }
    }
  }

  /// Vrai si l'utilisateur est chef/leader/admin sur le périmètre de cette demande.
  /// Ces utilisateurs voient la tuile en mode suivi. S'ils ne sont pas notifiés,
  /// canAct=false et les boutons Refuser/Accepter sont masqués.
  bool _isPrivilegedObserver(ReplacementRequest request) {
    final user = widget.currentUser;
    if (user == null) return false;
    if (user.admin || user.status == 'leader') return true;
    if (user.status == 'chief' &&
        request.team != null &&
        request.team == user.team) {
      return true;
    }
    return false;
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

    // Convertir la demande en données unifiées (avec nom de station résolu)
    var tileData = widget.request.toUnifiedTileData(
      requesterName: _requesterName,
      replacer: _replacer,
    ).withStationName(_stationName);

    // Si les horaires viennent d'une acceptance en attente (pas encore sur la demande),
    // remplacer les horaires de la colonne droite.
    if (_replacer != null &&
        _pendingAcceptanceStartTime != null &&
        _pendingAcceptanceEndTime != null) {
      tileData = tileData.copyWith(
        rightColumn: AgentColumnData(
          agentId: _replacer!.id,
          agentName: _replacer!.displayName,
          team: _replacer!.team,
          startTime: _pendingAcceptanceStartTime!,
          endTime: _pendingAcceptanceEndTime!,
          station: _stationName,
        ),
      );
    }

    // Déterminer si l'utilisateur peut agir
    final isNotified = widget.request.notifiedUserIds.contains(widget.currentUserId);
    final hasDeclined = widget.request.declinedByUserIds.contains(widget.currentUserId);
    final hasPendingAcceptance = widget.request.pendingValidationUserIds.contains(widget.currentUserId);
    final isOwner = widget.request.requesterId == widget.currentUserId;

    // Vrai si l'utilisateur est un observateur-privilégié (admin/leader/chef sur vague 5)
    // mais n'a pas été réellement assigné à répondre à cette demande.
    // Dans ce cas il ne doit pas pouvoir Refuser/Accepter.
    final isPrivilegedObserver = _isPrivilegedObserver(widget.request);

    bool canAct = false;
    switch (widget.viewMode) {
      case TileViewMode.pending:
        // Un observateur-privilégié peut quand même agir s'il est réellement notifié
        // (ex: chef notifié en vague 1 car même équipe que l'astreinte).
        final isObserverOnly = isPrivilegedObserver && !isNotified;
        canAct = !isObserverOnly && isNotified && !hasDeclined && !hasPendingAcceptance;
        break;
      case TileViewMode.myRequests:
        canAct = isOwner;
        break;
      case TileViewMode.toValidate:
        final user = widget.currentUser;
        canAct = user != null &&
            (user.admin ||
                user.status == 'leader' ||
                (user.status == 'chief' &&
                    widget.request.team != null &&
                    widget.request.team == user.team));
        break;
      case TileViewMode.history:
        canAct = false;
        break;
    }

    // Afficher le bouton DEV uniquement en mode DEV et pour les demandes pending de type replacement
    final showDevButton = kDebugMode &&
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
      onRefuse: (widget.viewMode == TileViewMode.pending ||
              widget.viewMode == TileViewMode.toValidate)
          ? widget.onRefuse
          : null,
      onValidate: widget.viewMode == TileViewMode.toValidate ? widget.onValidate : null,
      onWaveTap: widget.onWaveTap,
      onMarkAsSeen: widget.onMarkAsSeen,
      showDevButton: showDevButton,
      onSkipToNextWave: widget.onSkipToNextWave,
      onResendNotifications: widget.viewMode == TileViewMode.myRequests ? widget.onResendNotifications : null,
      onUnlockKeySkills: (widget.viewMode == TileViewMode.myRequests ||
                          widget.viewMode == TileViewMode.pending)
          ? widget.onUnlockKeySkills
          : null,
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
  String _stationName = '';
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

      // Résoudre le nom de la station
      String stationName = widget.station ?? '';
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && widget.station != null && widget.station!.isNotEmpty) {
        stationName = await StationNameCache().getStationName(sdisId, widget.station!);
      }

      if (mounted) {
        setState(() {
          _replacedTeam = replacedTeam;
          _replacerTeam = replacerTeam;
          _stationName = stationName;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading teams for manual proposal: $e');
      if (mounted) {
        setState(() {
          _stationName = widget.station ?? '';
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

    // Fallback "Agent <matricule>" si prénom/nom absent (agent créé mais non enregistré)
    final replacedName = proposal.replacedName.trim().isNotEmpty
        ? proposal.replacedName
        : 'Agent ${proposal.replacedId}';
    final replacerName = proposal.replacerName.trim().isNotEmpty
        ? proposal.replacerName
        : 'Agent ${proposal.replacerId}';

    return UnifiedTileData(
      id: proposal.id,
      requestType: UnifiedRequestType.manualReplacement,
      status: _mapStatus(proposal.status),
      createdAt: proposal.createdAt ?? DateTime.now(),
      leftColumn: AgentColumnData(
        agentId: proposal.replacedId,
        agentName: replacedName,
        team: _replacedTeam ?? proposal.replacedTeam,
        startTime: proposal.startTime,
        endTime: proposal.endTime,
        station: _stationName,
      ),
      rightColumn: AgentColumnData(
        agentId: proposal.replacerId,
        agentName: replacerName,
        team: _replacerTeam ?? proposal.replacerTeam,
        startTime: proposal.startTime,
        endTime: proposal.endTime,
        station: _stationName,
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
