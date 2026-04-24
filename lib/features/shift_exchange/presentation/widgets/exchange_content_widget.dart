import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/app_empty_state.dart';
import 'package:nexshift_app/core/presentation/widgets/tile_confirm_dialog.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_proposal_model.dart';
import 'package:nexshift_app/core/services/shift_exchange_service.dart';
import 'package:nexshift_app/features/shift_exchange/presentation/widgets/propose_shift_dialog.dart';
import 'package:nexshift_app/features/shift_exchange/presentation/widgets/proposal_selection_dialog.dart';
import 'package:nexshift_app/features/shift_exchange/presentation/widgets/exchange_tile_wrapper.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/replacement_sub_tabs.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/icon_tab_bar.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/unified_request_tile_exports.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/agent_filter_bar.dart';

/// Widget pour afficher le contenu des échanges d'astreinte
/// Utilisé comme onglet dans la page de remplacements
class ExchangeContentWidget extends StatefulWidget {
  const ExchangeContentWidget({super.key});

  @override
  State<ExchangeContentWidget> createState() => _ExchangeContentWidgetState();
}

class _ExchangeContentWidgetState extends State<ExchangeContentWidget>
    with SingleTickerProviderStateMixin {
  final _exchangeService = ShiftExchangeService();
  User? _currentUser;
  late TabController _subTabController;
  String? _stationId;
  DateTime _selectedMonth = DateTime.now();
  User? _selectedAgentExchange;

  // === CACHE DES DONNÉES ===
  bool _isLoading = true;
  bool _hasError = false;

  // Données cachées
  List<ShiftExchangeRequest> _availableRequests = [];
  List<Map<String, dynamic>> _myRequestsWithProposals = [];
  List<Map<String, dynamic>> _proposalsToValidate = [];
  List<Map<String, dynamic>> _allStationExchanges = [];

  // Compteurs calculés
  int _pendingCount = 0;
  int _myRequestsCount = 0;
  int _validationCount = 0;
  int _needingSelectionCount = 0;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 4, vsync: this);
    _initializeData();
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  /// Initialise les données au démarrage
  Future<void> _initializeData() async {
    final user = await UserStorageHelper.loadUser();
    if (!mounted) return;

    setState(() {
      _currentUser = user;
      _stationId = user?.station;
    });

    if (user != null && user.station.isNotEmpty) {
      await _loadAllData();
    }
  }

  /// Charge toutes les données en une seule fois
  Future<void> _loadAllData() async {
    if (_currentUser == null || _stationId == null) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // Charger toutes les données en parallèle
      final results = await Future.wait([
        _exchangeService.getAvailableRequestsForUser(
          userId: _currentUser!.id,
          stationId: _stationId!,
        ),
        _exchangeService.getUserRequestsWithProposals(
          userId: _currentUser!.id,
          stationId: _stationId!,
        ),
        _exchangeService.getProposalsRequiringValidationForLeader(
          userId: _currentUser!.id,
          stationId: _stationId!,
        ),
        _exchangeService.getAllStationExchangesWithProposals(
          stationId: _stationId!,
        ),
      ]);

      if (!mounted) return;

      // Stocker les données
      _availableRequests = results[0] as List<ShiftExchangeRequest>;
      _myRequestsWithProposals = results[1] as List<Map<String, dynamic>>;
      _proposalsToValidate = results[2] as List<Map<String, dynamic>>;
      _allStationExchanges = results[3] as List<Map<String, dynamic>>;

      // Calculer les compteurs avec filtres de date
      _calculateCounts();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ [EXCHANGE_WIDGET] Error loading data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  /// Calcule les compteurs avec les filtres de date appropriés
  void _calculateCounts() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Compteur "En attente" - demandes disponibles avec date future
    _pendingCount = _availableRequests.where((request) {
      final startDate = DateTime(
        request.initiatorStartTime.year,
        request.initiatorStartTime.month,
        request.initiatorStartTime.day,
      );
      return startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
    }).length;

    // Compteur "Mes demandes" - demandes non complétées avec date future
    final filteredMyRequests = _myRequestsWithProposals.where((data) {
      final request = data['request'] as ShiftExchangeRequest;
      if (request.status == ShiftExchangeRequestStatus.accepted) return false;
      final startDate = DateTime(
        request.initiatorStartTime.year,
        request.initiatorStartTime.month,
        request.initiatorStartTime.day,
      );
      return startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
    }).toList();
    _myRequestsCount = filteredMyRequests.length;

    // Compteur "Nécessitant sélection" (badge violet)
    _needingSelectionCount = filteredMyRequests.where((data) {
      final request = data['request'] as ShiftExchangeRequest;
      final proposals = data['proposals'] as List<ShiftExchangeProposal>;
      return request.status == ShiftExchangeRequestStatus.open &&
          proposals.isNotEmpty &&
          request.selectedProposalId == null;
    }).length;

    // Compteur "À valider" - avec filtre date
    final userTeam = _currentUser!.team;
    _validationCount = _proposalsToValidate.where((data) {
      final request = data['request'] as ShiftExchangeRequest;
      final proposal = data['proposal'] as ShiftExchangeProposal;
      final startDate = DateTime(
        request.initiatorStartTime.year,
        request.initiatorStartTime.month,
        request.initiatorStartTime.day,
      );
      final isFuture = startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
      if (!isFuture) return false;
      final hasValidated = proposal.leaderValidations.containsKey(userTeam);
      return !hasValidated;
    }).length;
  }

  /// Rafraîchit toutes les données (pull-to-refresh)
  Future<void> _refreshData() async {
    await _loadAllData();
  }

  @override
  Widget build(BuildContext context) {
    // Afficher le chargement initial
    if (_currentUser == null || _stationId == null || _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Afficher l'erreur si nécessaire
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Erreur de chargement',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Sous-onglets avec icônes et badges (utilise les compteurs cachés)
        ExpandingSubTabBar(
          controller: _subTabController,
          tabs: [
            ExpandingSubTabItem(icon: replacementSubTabs[0].icon, label: replacementSubTabs[0].label, badgeCount: _pendingCount, badgeColor: KColors.appNameColor),
            ExpandingSubTabItem(icon: replacementSubTabs[1].icon, label: replacementSubTabs[1].label, badgeCount: _myRequestsCount + _needingSelectionCount, badgeColor: KColors.appNameColor),
            ExpandingSubTabItem(icon: replacementSubTabs[2].icon, label: replacementSubTabs[2].label, badgeCount: _validationCount, badgeColor: Colors.blue),
            ExpandingSubTabItem(icon: replacementSubTabs[3].icon, label: replacementSubTabs[3].label),
          ],
          selectedColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : KColors.appNameColor,
          unselectedColor: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : KColors.appNameColor.withValues(alpha: 0.7),
        ),
        // Contenu des sous-onglets avec RefreshIndicator
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: replacementSubTabs.map((config) {
              return RefreshIndicator(
                onRefresh: _refreshData,
                child: _buildExchangeSubTab(config.type),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// Construit le contenu d'un sous-onglet d'échange
  Widget _buildExchangeSubTab(ReplacementSubTab subTab) {
    switch (subTab) {
      case ReplacementSubTab.pending:
        return _buildAvailableRequestsTab();
      case ReplacementSubTab.myRequests:
        return _buildMyRequestsTab();
      case ReplacementSubTab.toValidate:
        return _buildToValidateTab();
      case ReplacementSubTab.history:
        return _buildHistoryTab();
    }
  }

  /// Onglet 1: Mes demandes d'échange
  Widget _buildMyRequestsTab() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final requestsWithProposals = _myRequestsWithProposals.where((data) {
      final request = data['request'] as ShiftExchangeRequest;
      if (request.status == ShiftExchangeRequestStatus.accepted) return false;
      final startDate = DateTime(
        request.initiatorStartTime.year,
        request.initiatorStartTime.month,
        request.initiatorStartTime.day,
      );
      return startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
    }).toList();

    requestsWithProposals.sort((a, b) {
      final requestA = a['request'] as ShiftExchangeRequest;
      final requestB = b['request'] as ShiftExchangeRequest;
      return requestA.initiatorStartTime.compareTo(requestB.initiatorStartTime);
    });

    if (requestsWithProposals.isEmpty) {
      return const AppEmptyState(
        icon: Icons.swap_horiz,
        headline: 'Aucune demande d\'échange',
        subtitle: 'Créez une demande pour échanger votre astreinte',
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: requestsWithProposals.length,
      itemBuilder: (context, index) {
        final data = requestsWithProposals[index];
        final request = data['request'] as ShiftExchangeRequest;
        final proposals = data['proposals'] as List<ShiftExchangeProposal>;
        return _buildMyRequestCard(request, proposals);
      },
    );
  }

  /// Onglet 2: Demandes disponibles
  Widget _buildAvailableRequestsTab() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final requests = _availableRequests.where((request) {
      final startDate = DateTime(
        request.initiatorStartTime.year,
        request.initiatorStartTime.month,
        request.initiatorStartTime.day,
      );
      return startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
    }).toList();

    requests.sort((a, b) => a.initiatorStartTime.compareTo(b.initiatorStartTime));

    if (requests.isEmpty) {
      return const AppEmptyState(
        icon: Icons.search,
        headline: 'Aucune demande disponible',
        subtitle: 'Il n\'y a pas de demandes d\'échange compatibles',
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        return ExchangeTileWrapper(
          request: requests[index],
          currentUserId: _currentUser!.id,
          currentUserTeam: _currentUser!.team,
          viewMode: TileViewMode.pending,
          onPropose: () => _showProposeShiftDialog(requests[index]),
          onRefuse: () => _refuseExchangeRequest(requests[index]),
        );
      },
    );
  }

  Widget _buildMyRequestCard(
    ShiftExchangeRequest request,
    List<ShiftExchangeProposal> proposals,
  ) {
    ShiftExchangeProposal? selectedProposal;
    if (request.selectedProposalId != null) {
      selectedProposal = proposals.cast<ShiftExchangeProposal?>().firstWhere(
        (p) => p?.id == request.selectedProposalId,
        orElse: () => null,
      );
    }

    return ExchangeTileWrapper(
      request: request,
      currentUserId: _currentUser!.id,
      currentUserTeam: _currentUser!.team,
      viewMode: TileViewMode.myRequests,
      selectedProposal: selectedProposal,
      proposals: proposals,
      onDelete: () => _deleteExchangeRequest(request),
      onSelectProposal: proposals.isNotEmpty && request.selectedProposalId == null
          ? () => _showProposalSelectionDialog(request, proposals)
          : null,
      onResendNotifications: () => _resendExchangeNotification(request),
    );
  }

  Future<void> _resendExchangeNotification(ShiftExchangeRequest request) async {
    final confirmed = await TileConfirmDialog.show(
      context,
      icon: Icons.notifications_active_rounded,
      iconColor: Colors.orange.shade600,
      title: 'Relancer les notifications',
      message: 'Voulez-vous relancer les notifications pour cette demande d\'échange ?',
      confirmLabel: 'Relancer',
      confirmColor: Colors.orange.shade600,
      confirmIcon: Icons.send_rounded,
    );
    if (confirmed != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notification de relance envoyée'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _showProposalSelectionDialog(
    ShiftExchangeRequest request,
    List<ShiftExchangeProposal> proposals,
  ) async {
    if (_currentUser == null || _stationId == null) return;

    final result = await showProposalSelectionDialog(
      context: context,
      request: request,
      proposals: proposals,
      initiatorId: _currentUser!.id,
      stationId: _stationId!,
    );

    if (result == true && mounted) {
      await _refreshData();
    }
  }

  Future<void> _showProposeShiftDialog(ShiftExchangeRequest request) async {
    if (_currentUser == null || _stationId == null) return;

    final result = await showProposeShiftDialog(
      context: context,
      request: request,
      userId: _currentUser!.id,
      stationId: _stationId!,
    );

    if (result == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      await _refreshData();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Proposition envoyée'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _refuseExchangeRequest(ShiftExchangeRequest request) async {
    final confirmed = await TileConfirmDialog.show(
      context,
      icon: Icons.close_rounded,
      iconColor: Colors.red.shade600,
      title: 'Refuser la demande',
      message: 'Cette action est définitive. Vous ne pourrez plus répondre à cette demande d\'échange.',
      confirmLabel: 'Refuser',
      confirmColor: Colors.red.shade600,
      confirmIcon: Icons.close_rounded,
    );

    if (confirmed == true && mounted) {
      try {
        await _exchangeService.refuseExchangeRequest(
          requestId: request.id,
          userId: _currentUser!.id,
          stationId: _stationId!,
        );

        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          await _refreshData();
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Demande refusée'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur lors du refus: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteExchangeRequest(ShiftExchangeRequest request) async {
    final confirm = await TileConfirmDialog.show(
      context,
      icon: Icons.delete_outline_rounded,
      iconColor: Colors.red,
      title: 'Supprimer la demande',
      message: 'Cette action est irréversible. La demande d\'échange sera définitivement supprimée.',
      confirmLabel: 'Supprimer',
      confirmColor: Colors.red,
      confirmIcon: Icons.delete_rounded,
    );

    if (confirm == true) {
      try {
        if (_stationId == null) throw Exception('Station ID non disponible');

        await _exchangeService.cancelExchangeRequest(
          requestId: request.id,
          stationId: _stationId!,
        );

        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          await _refreshData();
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Demande supprimée'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Onglet 3: À valider
  Widget _buildToValidateTab() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final proposalsToValidate = _proposalsToValidate.where((data) {
      final request = data['request'] as ShiftExchangeRequest;
      final startDate = DateTime(
        request.initiatorStartTime.year,
        request.initiatorStartTime.month,
        request.initiatorStartTime.day,
      );
      return startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
    }).toList();

    if (proposalsToValidate.isEmpty) {
      return const AppEmptyState(
        icon: Icons.check_circle_outline,
        headline: 'Aucune validation requise',
        subtitle: 'Il n\'y a pas de demandes à valider',
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: proposalsToValidate.length,
      itemBuilder: (context, index) {
        final data = proposalsToValidate[index];
        final request = data['request'] as ShiftExchangeRequest;
        final proposal = data['proposal'] as ShiftExchangeProposal;
        return ExchangeTileWrapper(
          request: request,
          currentUserId: _currentUser!.id,
          currentUserTeam: _currentUser!.team,
          viewMode: TileViewMode.toValidate,
          selectedProposal: proposal,
          onValidate: () => _acceptValidation(request, proposal),
          onReject: () => _refuseValidation(request, proposal),
        );
      },
    );
  }

  /// Refuse la validation
  Future<void> _refuseValidation(
    ShiftExchangeRequest request,
    ShiftExchangeProposal proposal,
  ) async {
    final TextEditingController commentController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.close_rounded, size: 20, color: Colors.red.shade600),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Motif du refus', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Veuillez indiquer la raison du refus de cet échange :',
                style: TextStyle(fontSize: 14, color: isDark ? Colors.grey[300] : Colors.grey[700]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentController,
                maxLines: 3,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  hintText: 'Exemple: Contraintes d\'effectif...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (commentController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Le motif est obligatoire'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Confirmer le refus'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _exchangeService.rejectProposal(
        proposalId: proposal.id,
        leaderId: _currentUser!.id,
        teamId: _currentUser!.team,
        comment: commentController.text.trim(),
        stationId: _stationId!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✗ Échange refusé'),
            backgroundColor: Colors.red,
          ),
        );
        await _refreshData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Accepte la validation
  Future<void> _acceptValidation(
    ShiftExchangeRequest request,
    ShiftExchangeProposal proposal,
  ) async {
    final confirmed = await TileConfirmDialog.show(
      context,
      icon: Icons.check_circle_outline_rounded,
      iconColor: Colors.green.shade600,
      title: 'Valider l\'échange',
      message: 'Êtes-vous sûr de vouloir valider cet échange d\'astreinte ?',
      confirmLabel: 'Valider',
      confirmColor: Colors.green.shade600,
      confirmIcon: Icons.check_rounded,
    );

    if (confirmed != true) return;

    try {
      await _exchangeService.validateProposal(
        proposalId: proposal.id,
        leaderId: _currentUser!.id,
        teamId: _currentUser!.team,
        stationId: _stationId!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Validation enregistrée'),
            backgroundColor: Colors.green,
          ),
        );
        await _refreshData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Onglet 4: Historique des échanges
  Widget _buildHistoryTab() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    var historicRequests = _allStationExchanges.where((data) {
      final request = data['request'] as ShiftExchangeRequest;

      if (request.status == ShiftExchangeRequestStatus.accepted ||
          request.status == ShiftExchangeRequestStatus.cancelled) {
        return true;
      }

      final startDate = DateTime(
        request.initiatorStartTime.year,
        request.initiatorStartTime.month,
        request.initiatorStartTime.day,
      );
      return startDate.isBefore(today);
    }).toList();

    final startOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final endOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);

    historicRequests = historicRequests.where((data) {
      final request = data['request'] as ShiftExchangeRequest;
      return request.initiatorStartTime.isAfter(
            startOfMonth.subtract(const Duration(days: 1)),
          ) &&
          request.initiatorStartTime.isBefore(endOfMonth);
    }).toList();

    // Filtre agent
    if (_selectedAgentExchange != null) {
      final agentId = _selectedAgentExchange!.id;
      historicRequests = historicRequests.where((data) {
        final request = data['request'] as ShiftExchangeRequest;
        final proposals = data['proposals'] as List<ShiftExchangeProposal>;
        if (request.initiatorId == agentId) return true;
        if (request.proposedByUserIds.contains(agentId)) return true;
        return proposals.any((p) => p.proposerId == agentId);
      }).toList();
    }

    return Column(
      children: [
        // Navigateur mensuel
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? KColors.appNameColor.withValues(alpha: 0.12)
                : KColors.appNameColor.withValues(alpha: 0.06),
            border: Border(
              bottom: BorderSide(
                color: KColors.appNameColor.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left_rounded, color: KColors.appNameColor),
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month - 1,
                    );
                  });
                },
                tooltip: 'Mois précédent',
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_month_rounded, size: 16, color: KColors.appNameColor),
                    const SizedBox(width: 6),
                    Text(
                      _formatMonthYear(_selectedMonth),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: KColors.appNameColor,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right_rounded, color: KColors.appNameColor),
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month + 1,
                    );
                  });
                },
                tooltip: 'Mois suivant',
              ),
            ],
          ),
        ),
        // Filtre agent
        AgentFilterBar(
          selectedAgent: _selectedAgentExchange,
          stationId: _stationId!,
          onAgentSelected: (a) => setState(() => _selectedAgentExchange = a),
        ),
        // Liste des échanges historiques
        Expanded(
          child: historicRequests.isEmpty
              ? const AppEmptyState(
                  icon: Icons.history,
                  headline: 'Aucun historique',
                  subtitle: 'Il n\'y a pas d\'échanges pour cette période',
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: historicRequests.length,
                  itemBuilder: (context, index) {
                    final data = historicRequests[index];
                    final request = data['request'] as ShiftExchangeRequest;
                    final proposals =
                        data['proposals'] as List<ShiftExchangeProposal>;

                    ShiftExchangeProposal? selectedProposal;
                    if (proposals.isNotEmpty) {
                      try {
                        selectedProposal = proposals.firstWhere(
                          (p) =>
                              p.status == ShiftExchangeProposalStatus.validated &&
                              p.isFinalized,
                        );
                      } catch (_) {
                        selectedProposal = proposals.isNotEmpty ? proposals.first : null;
                      }
                    }

                    return ExchangeTileWrapper(
                      request: request,
                      currentUserId: _currentUser!.id,
                      currentUserTeam: _currentUser!.team,
                      viewMode: TileViewMode.history,
                      selectedProposal: selectedProposal,
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatMonthYear(DateTime date) {
    const months = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}
