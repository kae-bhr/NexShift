import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/unified_request_tile_exports.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_proposal_model.dart' hide TeamValidationState;
import 'package:nexshift_app/core/data/models/shift_exchange_proposal_model.dart' as proposal_model show TeamValidationState;
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';

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
  final _userRepository = UserRepository();

  Planning? _initiatorPlanning;
  Planning? _proposerPlanning;
  String? _initiatorTeam;
  String? _proposerTeam;
  String? _initiatorName;
  String? _proposerName;
  String _stationName = '';
  bool _isLoading = true;

  // Données chargées en mode history pour la validation chef
  DateTime? _leaderValidatedAt;
  String? _leaderValidatorName;

  /// Nom du chef validateur par équipe (teamId → displayName du chef)
  final Map<String, String> _validatorNameByTeam = {};

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
      // Priorité : selectedPlanningId (nouveau format) → proposerPlanningId (legacy)
      if (widget.selectedProposal != null) {
        final planningId = widget.selectedProposal!.selectedPlanningId
            ?? (widget.selectedProposal!.proposedPlanningIds.isNotEmpty
                ? widget.selectedProposal!.proposedPlanningIds.first
                : widget.selectedProposal!.proposerPlanningId);
        if (planningId != null) {
          _proposerPlanning = await _planningRepository.getById(
            planningId,
            stationId: widget.request.station,
          );
          _proposerTeam = _proposerPlanning?.team;
        }
      }

      // Résoudre les noms des agents depuis le cache déchiffré
      final initiator = await _userRepository.getById(
        widget.request.initiatorId,
        stationId: widget.request.station,
      );
      // Si trouvé → displayName (gère le fallback 'Agent $id' si pas de prénom/nom)
      // Si non trouvé → nom stocké en base s'il est non vide, sinon 'Agent $id'
      if (initiator != null) {
        _initiatorName = initiator.displayName;
      } else {
        _initiatorName = widget.request.initiatorName.trim().isNotEmpty
            ? widget.request.initiatorName
            : 'Agent ${widget.request.initiatorId}';
      }

      if (widget.selectedProposal != null) {
        final proposer = await _userRepository.getById(
          widget.selectedProposal!.proposerId,
          stationId: widget.request.station,
        );
        if (proposer != null) {
          _proposerName = proposer.displayName;
        } else {
          _proposerName = widget.selectedProposal!.proposerName.trim().isNotEmpty
              ? widget.selectedProposal!.proposerName
              : 'Agent ${widget.selectedProposal!.proposerId}';
        }
      }

      // Charger les noms des chefs validateurs par équipe (toValidate + history)
      // Clé leaderValidations : "${teamId}_${leaderId}"
      _validatorNameByTeam.clear();
      if (widget.selectedProposal?.leaderValidations.isNotEmpty == true) {
        // Pour le badge "Historique" en mode history : premier chef approuvant
        LeaderValidation? firstApproval;
        for (final entry in widget.selectedProposal!.leaderValidations.entries) {
          final v = entry.value;
          if (!v.approved) continue;
          final teamId = entry.key.split('_').first;
          if (!_validatorNameByTeam.containsKey(teamId)) {
            final leader = await _userRepository.getById(
              v.leaderId,
              stationId: widget.request.station,
            );
            if (leader != null) {
              _validatorNameByTeam[teamId] = leader.displayName;
            }
          }
          firstApproval ??= v;
        }
        // Données pour le dialog Historique (inchangé)
        if (widget.viewMode == TileViewMode.history && firstApproval != null) {
          _leaderValidatedAt = firstApproval.validatedAt;
          final teamId = widget.selectedProposal!.leaderValidations.entries
              .firstWhere((e) => e.value == firstApproval)
              .key
              .split('_')
              .first;
          _leaderValidatorName = _validatorNameByTeam[teamId];
        }
      }

      // Résoudre le nom de la station
      // Priorité : SDISContext → UserStorageHelper (fallback si contexte pas encore initialisé)
      String? sdisId = SDISContext().currentSDISId;
      if ((sdisId == null || sdisId.isEmpty) && widget.request.station.isNotEmpty) {
        sdisId = await UserStorageHelper.loadSdisId();
      }
      if (sdisId != null && sdisId.isNotEmpty && widget.request.station.isNotEmpty) {
        _stationName = await StationNameCache().getStationName(sdisId, widget.request.station);
      } else {
        _stationName = widget.request.station;
      }
    } catch (e) {
      debugPrint('Error loading exchange data: $e');
      _stationName = widget.request.station;
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

    // Badges de colonnes pour échanges (toValidate et history)
    Widget? leftBadge;
    Widget? rightBadge;
    if (widget.selectedProposal != null &&
        (widget.viewMode == TileViewMode.toValidate ||
         widget.viewMode == TileViewMode.history)) {
      final badges = _buildColumnBadges(widget.selectedProposal!);
      leftBadge = badges.$1;
      rightBadge = badges.$2;
    }

    // Convertir en UnifiedTileData (avec nom de station et noms d'agents résolus)
    var tileData = widget.request.toUnifiedTileData(
      selectedProposal: widget.selectedProposal,
      proposerPlanning: _proposerPlanning,
      initiatorTeam: _initiatorTeam,
      proposerTeam: _proposerTeam,
      validationChiefs: null,
    ).withStationName(_stationName);

    // Remplacer les noms d'agents par les noms déchiffrés si disponibles
    if (_initiatorName != null && _initiatorName!.isNotEmpty) {
      tileData = tileData.copyWith(
        leftColumn: tileData.leftColumn.withAgentName(_initiatorName!),
      );
    }
    if (_proposerName != null && _proposerName!.isNotEmpty && tileData.rightColumn != null) {
      tileData = tileData.copyWith(
        rightColumn: tileData.rightColumn!.withAgentName(_proposerName!),
      );
    }

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
    VoidCallback? onValidateCallback;

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
        onValidateCallback = widget.onValidate;
        onRefuse = widget.onReject;
        break;
      case TileViewMode.history:
        break;
    }

    final isInitiator = widget.request.initiatorId == widget.currentUserId;

    // Badge "Historique" en mode history
    VoidCallback? onHistoryTap;
    if (widget.viewMode == TileViewMode.history) {
      // Construire une entrée par équipe ayant validé, triées par date croissante
      List<TeamValidationEntry>? teamValidations;
      if (widget.selectedProposal != null) {
        final entries = <TeamValidationEntry>[];
        for (final entry in widget.selectedProposal!.leaderValidations.entries) {
          final v = entry.value;
          if (!v.approved) continue;
          final teamId = entry.key.split('_').first;
          if (entries.any((e) => e.teamId == teamId)) continue;
          entries.add(TeamValidationEntry(
            teamId: teamId,
            validatorName: _validatorNameByTeam[teamId],
            validatedAt: v.validatedAt,
          ));
        }
        entries.sort((a, b) => a.validatedAt.compareTo(b.validatedAt));
        if (entries.isNotEmpty) teamValidations = entries;
      }

      onHistoryTap = () => showHistoryDialog(
        context,
        HistoryDialogData(
          createdAt: widget.request.createdAt,
          acceptedAt: widget.selectedProposal?.acceptedAt ?? widget.request.completedAt,
          teamValidations: teamValidations,
          // Fallback mono-validation si aucune entrée par équipe
          validatedAt: teamValidations == null ? _leaderValidatedAt : null,
          validatorName: teamValidations == null ? _leaderValidatorName : null,
          requestTypeLabel: 'Échange de garde',
        ),
      );
    }

    return UnifiedRequestTile(
      data: tileData,
      viewMode: widget.viewMode,
      currentUserId: widget.currentUserId,
      canAct: canAct,
      onDelete: widget.viewMode == TileViewMode.myRequests ? widget.onDelete : null,
      onAccept: onAccept,
      onRefuse: onRefuse,
      onValidate: onValidateCallback,
      onProposalsTap: widget.onSelectProposal,
      onResendNotifications: widget.viewMode == TileViewMode.myRequests && isInitiator ? widget.onResendNotifications : null,
      onHistoryTap: onHistoryTap,
      leftBadgeOverride: leftBadge,
      rightBadgeOverride: rightBadge,
      acceptButtonText: 'Accepter',
      refuseButtonText: 'Refuser',
    );
  }

  /// Construit les badges de colonnes pour le mode toValidate.
  ///
  /// Colonne gauche (initiateur) : badge statut équipe initiateur
  /// Colonne droite (proposeur)  : badge statut équipe proposeur + nom du validateur si validé
  (Widget?, Widget?) _buildColumnBadges(ShiftExchangeProposal proposal) {
    final states = proposal.teamValidationStates;

    Widget? left;
    if (_initiatorTeam != null) {
      final badge = _buildTeamStatusBadge(_initiatorTeam!, states[_initiatorTeam]);
      final validatorName = _resolveValidatorName(_initiatorTeam!, proposal);
      if (validatorName != null) {
        left = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                validatorName,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            badge,
          ],
        );
      } else {
        left = badge;
      }
    }

    Widget? right;
    if (_proposerTeam != null) {
      final state = states[_proposerTeam];
      final badge = _buildTeamStatusBadge(_proposerTeam!, state);
      // Si validé, afficher le nom du validateur à côté du badge
      final validatorName = _resolveValidatorName(_proposerTeam!, proposal);
      if (validatorName != null) {
        right = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                validatorName,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            badge,
          ],
        );
      } else {
        right = badge;
      }
    }

    return (left, right);
  }

  /// Retourne le nom du chef ayant validé pour une équipe donnée, ou null si pas encore validé.
  String? _resolveValidatorName(String teamId, ShiftExchangeProposal proposal) {
    return _validatorNameByTeam[teamId];
  }

  Widget _buildTeamStatusBadge(String teamId, proposal_model.TeamValidationState? state) {
    final IconData icon;
    final String label;
    final Color bg;
    final Color fg;

    switch (state) {
      case proposal_model.TeamValidationState.validatedTemporarily:
      case proposal_model.TeamValidationState.autoValidated:
        icon = Icons.check_circle_rounded;
        label = 'Validé';
        bg = Colors.green.shade50;
        fg = Colors.green.shade700;
        break;
      case proposal_model.TeamValidationState.rejected:
        icon = Icons.cancel_rounded;
        label = 'Refusé';
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        break;
      case proposal_model.TeamValidationState.pending:
      case null:
        icon = Icons.schedule_rounded;
        label = 'En attente';
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade700;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }

}
