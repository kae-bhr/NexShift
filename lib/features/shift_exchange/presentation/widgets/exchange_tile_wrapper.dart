import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/unified_request_tile_exports.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_proposal_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';

/// Widget wrapper pour afficher une demande d'échange
/// avec le nouveau design unifié
class ExchangeTileWrapper extends StatefulWidget {
  /// La demande d'échange
  final ShiftExchangeRequest request;

  /// ID de l'utilisateur courant
  final String currentUserId;

  /// Équipe de l'utilisateur courant
  final String? currentUserTeam;

  /// Mode de vue
  final TileViewMode viewMode;

  /// Proposition sélectionnée (si existante)
  final ShiftExchangeProposal? selectedProposal;

  /// Liste des propositions (pour "Mes demandes")
  final List<ShiftExchangeProposal>? proposals;

  /// Callback au tap sur la carte
  final VoidCallback? onTap;

  /// Callback pour supprimer/annuler
  final VoidCallback? onDelete;

  /// Callback pour proposer un échange
  final VoidCallback? onPropose;

  /// Callback pour refuser
  final VoidCallback? onRefuse;

  /// Callback pour valider (chef)
  final VoidCallback? onValidate;

  /// Callback pour rejeter (chef)
  final VoidCallback? onReject;

  /// Callback pour sélectionner une proposition
  final VoidCallback? onSelectProposal;

  /// Callback pour relancer les notifications
  final VoidCallback? onResendNotifications;

  const ExchangeTileWrapper({
    super.key,
    required this.request,
    required this.currentUserId,
    this.currentUserTeam,
    required this.viewMode,
    this.selectedProposal,
    this.proposals,
    this.onTap,
    this.onDelete,
    this.onPropose,
    this.onRefuse,
    this.onValidate,
    this.onReject,
    this.onSelectProposal,
    this.onResendNotifications,
  });

  @override
  State<ExchangeTileWrapper> createState() => _ExchangeTileWrapperState();
}

class _ExchangeTileWrapperState extends State<ExchangeTileWrapper> {
  final _planningRepository = PlanningRepository();

  Planning? _initiatorPlanning;
  Planning? _proposerPlanning;
  String? _initiatorTeam;
  String? _proposerTeam;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(ExchangeTileWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.id != widget.request.id ||
        oldWidget.selectedProposal?.id != widget.selectedProposal?.id) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Charger le planning de l'initiateur
      _initiatorPlanning = await _planningRepository.getById(
        widget.request.initiatorPlanningId,
        stationId: widget.request.station,
      );
      _initiatorTeam = _initiatorPlanning?.team;

      // Charger le planning du proposeur si une proposition est sélectionnée
      if (widget.selectedProposal != null &&
          widget.selectedProposal!.proposerPlanningId != null) {
        _proposerPlanning = await _planningRepository.getById(
          widget.selectedProposal!.proposerPlanningId!,
          stationId: widget.request.station,
        );
        _proposerTeam = _proposerPlanning?.team;
      }
    } catch (e) {
      debugPrint('Error loading exchange data: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Construire les données de validation des chefs
    List<ChiefValidationData>? validationChiefs;
    if (widget.selectedProposal != null) {
      validationChiefs = _buildValidationChiefs(widget.selectedProposal!);
    }

    // Convertir en UnifiedTileData
    final tileData = widget.request.toUnifiedTileData(
      selectedProposal: widget.selectedProposal,
      proposerPlanning: _proposerPlanning,
      initiatorTeam: _initiatorTeam,
      proposerTeam: _proposerTeam,
      validationChiefs: validationChiefs,
    );

    // Déterminer si l'utilisateur peut agir
    bool canAct = true;
    switch (widget.viewMode) {
      case TileViewMode.pending:
        // Peut proposer s'il n'a pas déjà proposé et n'a pas refusé
        canAct = !widget.request.refusedByUserIds.contains(widget.currentUserId);
        break;
      case TileViewMode.myRequests:
        // Peut supprimer ou sélectionner une proposition
        canAct = widget.request.status == ShiftExchangeRequestStatus.open;
        break;
      case TileViewMode.toValidate:
        canAct = true;
        break;
      case TileViewMode.history:
        canAct = false;
        break;
    }

    // Déterminer les actions disponibles selon le mode
    VoidCallback? onAccept;
    VoidCallback? onRefuse;

    switch (widget.viewMode) {
      case TileViewMode.pending:
        onAccept = widget.onPropose;
        onRefuse = widget.onRefuse;
        break;
      case TileViewMode.myRequests:
        // Pas d'actions Accepter/Refuser dans Mes demandes
        // Le bouton "Sélectionner proposition" est géré séparément
        break;
      case TileViewMode.toValidate:
        onAccept = widget.onValidate;
        onRefuse = widget.onReject;
        break;
      case TileViewMode.history:
        break;
    }

    // onTap uniquement pour le mode "Mes demandes" (ouvre le BottomSheet)
    final isInitiator = widget.request.initiatorId == widget.currentUserId;
    final effectiveOnTap = widget.viewMode == TileViewMode.myRequests && isInitiator ? widget.onTap : null;

    return UnifiedRequestTile(
      data: tileData,
      viewMode: widget.viewMode,
      currentUserId: widget.currentUserId,
      canAct: canAct,
      onTap: effectiveOnTap,
      onDelete: widget.viewMode == TileViewMode.myRequests ? widget.onDelete : null,
      onAccept: onAccept,
      onRefuse: onRefuse,
      onProposalsTap: widget.onSelectProposal,
      onResendNotifications: widget.viewMode == TileViewMode.myRequests && isInitiator ? widget.onResendNotifications : null,
      acceptButtonText: widget.viewMode == TileViewMode.pending ? 'Proposer' : 'Valider',
      refuseButtonText: 'Refuser',
    );
  }

  /// Construit les données de validation des chefs
  List<ChiefValidationData> _buildValidationChiefs(ShiftExchangeProposal proposal) {
    final chiefs = <ChiefValidationData>[];

    for (final entry in proposal.leaderValidations.entries) {
      final teamId = entry.key;
      final validation = entry.value;

      chiefs.add(ChiefValidationData(
        chiefId: validation.leaderId,
        chiefName: 'Chef équipe $teamId',
        team: teamId,
        hasValidated: validation.approved,
      ));
    }

    return chiefs;
  }
}
