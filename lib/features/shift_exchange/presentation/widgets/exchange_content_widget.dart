import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_proposal_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/services/shift_exchange_service.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/features/shift_exchange/presentation/widgets/propose_shift_dialog.dart';
import 'package:nexshift_app/features/shift_exchange/presentation/widgets/proposal_selection_dialog.dart';
import 'package:nexshift_app/features/shift_exchange/presentation/widgets/exchange_tile_wrapper.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/replacement_sub_tabs.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/icon_tab_bar.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/unified_request_tile_exports.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/presentation/widgets/request_actions_bottom_sheet.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';

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
  final _planningRepository = PlanningRepository();
  final _userRepository = UserRepository();
  User? _currentUser;
  late TabController _subTabController;
  String? _stationId;
  DateTime _selectedMonth = DateTime.now();
  final Map<String, Planning?> _planningCache = {};

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

  String _formatDateTime(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  /// Récupère les détails d'un planning avec cache
  Future<Planning?> _getPlanningDetails(
    String planningId,
    String stationId,
  ) async {
    // Vérifier le cache
    if (_planningCache.containsKey(planningId)) {
      return _planningCache[planningId];
    }

    // Récupérer depuis Firestore
    try {
      final planning = await _planningRepository.getById(
        planningId,
        stationId: stationId,
      );
      _planningCache[planningId] = planning;
      return planning;
    } catch (e) {
      debugPrint('Error fetching planning $planningId: $e');
      return null;
    }
  }

  /// Récupère les chefs d'équipe pour une équipe donnée
  Future<List<User>> _getTeamLeaders(String teamId, String stationId) async {
    try {
      final allUsers = await _userRepository.getByStation(stationId);
      return allUsers
          .where(
            (user) =>
                user.team == teamId &&
                (user.status == KConstants.statusChief ||
                    user.status == KConstants.statusLeader),
          )
          .toList();
    } catch (e) {
      debugPrint('Error fetching team leaders for team $teamId: $e');
      return [];
    }
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
        IconTabBar(
          controller: _subTabController,
          tabs: replacementSubTabs,
          selectedColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : KColors.appNameColor,
          unselectedColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.white70
              : KColors.appNameColor.withValues(alpha: 0.7),
          badgeCounts: {
            ReplacementSubTab.pending: _pendingCount,
            ReplacementSubTab.myRequests: _myRequestsCount,
            ReplacementSubTab.toValidate: _validationCount,
          },
          badgeColors: const {
            ReplacementSubTab.pending: Colors.green,
            ReplacementSubTab.myRequests: Colors.green,
            ReplacementSubTab.toValidate: Colors.blue,
          },
          secondaryBadgeCounts: {
            ReplacementSubTab.myRequests: _needingSelectionCount,
          },
          secondaryBadgeColors: const {
            ReplacementSubTab.myRequests: Colors.purple,
          },
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
        return _buildAvailableRequestsTab(); // Demandes disponibles = demandes en attente
      case ReplacementSubTab.myRequests:
        return _buildMyRequestsTab(); // Mes demandes d'échange
      case ReplacementSubTab.toValidate:
        return _buildToValidateTab(); // Demandes à valider (pour chef)
      case ReplacementSubTab.history:
        return _buildHistoryTab(); // Historique des échanges
    }
  }

  /// Onglet 1: Mes demandes d'échange (utilise les données cachées)
  Widget _buildMyRequestsTab() {
    // Filtrer pour ne garder que les demandes non complétées et dont la date de début n'est pas encore passée
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final requestsWithProposals = _myRequestsWithProposals.where((data) {
      final request = data['request'] as ShiftExchangeRequest;

      // Exclure les demandes acceptées (complétées)
      if (request.status == ShiftExchangeRequestStatus.accepted) {
        return false;
      }

      final startDate = DateTime(
        request.initiatorStartTime.year,
        request.initiatorStartTime.month,
        request.initiatorStartTime.day,
      );
      return startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
    }).toList();

    // Trier par ordre chronologique (date de début)
    requestsWithProposals.sort((a, b) {
      final requestA = a['request'] as ShiftExchangeRequest;
      final requestB = b['request'] as ShiftExchangeRequest;
      return requestA.initiatorStartTime.compareTo(
        requestB.initiatorStartTime,
      );
    });

    if (requestsWithProposals.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_horiz, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Aucune demande d\'échange',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Créez une demande pour échanger votre astreinte',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
        ],
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

  /// Onglet 2: Demandes disponibles (utilise les données cachées)
  Widget _buildAvailableRequestsTab() {
    // Filtrer pour ne garder que les demandes dont la date de début n'est pas encore passée
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

    // Trier par ordre chronologique (date de début)
    requests.sort(
      (a, b) => a.initiatorStartTime.compareTo(b.initiatorStartTime),
    );

    if (requests.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Aucune demande disponible',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Il n\'y a pas de demandes d\'échange compatibles',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        return _buildAvailableRequestCard(requests[index]);
      },
    );
  }

  Widget _buildMyRequestCard(
    ShiftExchangeRequest request,
    List<ShiftExchangeProposal> proposals,
  ) {
    // Trouver la proposition sélectionnée si elle existe
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
      onTap: () => _showExchangeActionsBottomSheet(request),
      onDelete: () => _deleteExchangeRequest(request),
      onSelectProposal: proposals.isNotEmpty && request.selectedProposalId == null
          ? () => _showProposalSelectionDialog(request, proposals)
          : null,
      onResendNotifications: () => _resendExchangeNotification(request),
    );
  }

  /// Affiche le BottomSheet d'actions pour une demande d'échange
  Future<void> _showExchangeActionsBottomSheet(ShiftExchangeRequest request) async {
    // Résoudre le nom de la station
    String stationName = request.station;
    final sdisId = SDISContext().currentSDISId;
    if (sdisId != null && request.station.isNotEmpty) {
      stationName = await StationNameCache().getStationName(sdisId, request.station);
    }

    if (!mounted) return;

    RequestActionsBottomSheet.show(
      context: context,
      requestType: UnifiedRequestType.exchange,
      initiatorName: request.initiatorName,
      team: request.initiatorTeam,
      station: stationName,
      startTime: request.initiatorStartTime,
      endTime: request.initiatorEndTime,
      onResendNotifications: () => _resendExchangeNotification(request),
      onDelete: () => _deleteExchangeRequest(request),
    );
  }

  /// Relance la notification pour une demande d'échange
  Future<void> _resendExchangeNotification(ShiftExchangeRequest request) async {
    // TODO: Implémenter la logique de renotification pour les échanges
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notification de relance envoyée'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Widget _buildMyRequestCardContent(
    ShiftExchangeRequest request,
    List<ShiftExchangeProposal> proposals,
    Color statusColor,
    IconData statusIcon,
    String statusText,
    Planning? planning,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête avec avatar et nom
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.green,
                  radius: 20,
                  child: const Icon(
                    Icons.swap_horiz,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentUser?.displayName ?? 'Utilisateur',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Badge de statut et propositions
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 14, color: statusColor),
                                const SizedBox(width: 4),
                                Text(
                                  statusText,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: proposals.isEmpty
                                  ? Colors.grey.shade100
                                  : Colors.purple.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: proposals.isEmpty
                                    ? Colors.grey.shade300
                                    : Colors.purple.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.people_outline,
                                  size: 14,
                                  color: proposals.isEmpty
                                      ? Colors.grey.shade600
                                      : Colors.purple.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${proposals.length} proposition(s)',
                                  style: TextStyle(
                                    color: proposals.isEmpty
                                        ? Colors.grey.shade600
                                        : Colors.purple.shade700,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Icône de suppression pour les demandes ouvertes
                if (request.status == ShiftExchangeRequestStatus.open) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    onPressed: () => _deleteExchangeRequest(request),
                    tooltip: 'Supprimer la demande',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // Période
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: Colors.blue.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Du ${_formatDateTime(request.initiatorStartTime)}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      Text(
                        'Au ${_formatDateTime(request.initiatorEndTime)}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Station et équipe
            if (request.station.isNotEmpty || planning?.team != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (request.station.isNotEmpty) ...[
                    Icon(
                      Icons.location_on,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      request.station,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  if (planning?.team != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '•',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                    Icon(Icons.group, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      'Équipe ${planning!.team}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            // Bouton pour consulter les propositions si disponibles
            if (proposals.isNotEmpty &&
                request.status == ShiftExchangeRequestStatus.open) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      _showProposalSelectionDialog(request, proposals),
                  icon: const Icon(Icons.people_outline, size: 18),
                  label: Text(
                    'Consulter les ${proposals.length} proposition(s)',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Affiche le dialogue de sélection des propositions
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

  Widget _buildAvailableRequestCard(ShiftExchangeRequest request) {
    return ExchangeTileWrapper(
      request: request,
      currentUserId: _currentUser!.id,
      currentUserTeam: _currentUser!.team,
      viewMode: TileViewMode.pending,
      onTap: () => _showProposeShiftDialog(request),
      onPropose: () => _showProposeShiftDialog(request),
      onRefuse: () => _refuseExchangeRequest(request),
    );
  }

  // Ancienne méthode conservée temporairement
  Widget _buildAvailableRequestCardOld(ShiftExchangeRequest request) {
    return FutureBuilder<Planning?>(
      future: _getPlanningDetails(request.initiatorPlanningId, request.station),
      builder: (context, planningSnapshot) {
        final planning = planningSnapshot.data;

        // Vérifier si l'utilisateur a déjà répondu à cette demande
        return FutureBuilder<List<ShiftExchangeProposal>>(
          future: _exchangeService.getProposalsByRequestId(
            requestId: request.id,
            stationId: request.station,
          ),
          builder: (context, proposalsSnapshot) {
            final hasUserProposed =
                proposalsSnapshot.data?.any(
                  (p) => p.proposerId == _currentUser!.id,
                ) ??
                false;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              child: InkWell(
                onTap: hasUserProposed
                    ? null
                    : () => _showProposeShiftDialog(request),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // En-tête avec avatar et nom
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.green,
                            radius: 20,
                            child: const Icon(
                              Icons.swap_horiz,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  request.initiatorName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: hasUserProposed
                                        ? Colors.green.withValues(alpha: 0.15)
                                        : Colors.blue.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        hasUserProposed
                                            ? Icons.check_circle
                                            : Icons.hourglass_empty,
                                        size: 14,
                                        color: hasUserProposed
                                            ? Colors.green.shade700
                                            : Colors.blue.shade700,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        hasUserProposed
                                            ? 'Propositions envoyées'
                                            : 'En attente',
                                        style: TextStyle(
                                          color: hasUserProposed
                                              ? Colors.green.shade700
                                              : Colors.blue.shade700,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      // Période
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Du ${_formatDateTime(request.initiatorStartTime)}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                Text(
                                  'Au ${_formatDateTime(request.initiatorEndTime)}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Station et équipe
                      if (request.station.isNotEmpty ||
                          planning?.team != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (request.station.isNotEmpty) ...[
                              Icon(
                                Icons.location_on,
                                size: 16,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                request.station,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                            if (planning?.team != null) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  '•',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ),
                              Icon(
                                Icons.group,
                                size: 16,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Équipe ${planning!.team}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (!hasUserProposed) ...[
                        const SizedBox(height: 12),
                        // Boutons d'action
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _refuseExchangeRequest(request),
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text('Refuser'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _showProposeShiftDialog(request),
                                icon: const Icon(Icons.swap_horiz, size: 18),
                                label: const Text('Échanger'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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

  /// Refuse une demande d'échange
  Future<void> _refuseExchangeRequest(ShiftExchangeRequest request) async {
    // Demander confirmation à l'utilisateur
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refuser la demande'),
        content: const Text(
          'Êtes-vous sûr de vouloir refuser cette demande d\'échange ?\n\n'
          'Cette action est définitive et vous ne pourrez plus y répondre.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        // Appeler le service pour enregistrer le refus
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

  /// Supprime une demande d'échange (par l'initiateur)
  Future<void> _deleteExchangeRequest(ShiftExchangeRequest request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer la demande ?"),
        content: const Text(
          "Cette action est irréversible. Voulez-vous vraiment supprimer cette demande d'échange ?",
        ),
        actions: [
          TextButton(
            child: const Text("Annuler"),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Supprimer"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (_stationId == null) {
          throw Exception('Station ID non disponible');
        }

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

  /// Onglet 3: Demandes à valider (pour chef d'équipe)
  /// Onglet 3: À valider (utilise les données cachées)
  Widget _buildToValidateTab() {
    // Filtrer pour n'afficher que les demandes avec date >= aujourd'hui
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
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Aucune demande à valider',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
        ],
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
        final initiatorTeam = data['initiatorTeam'] as String?;
        final proposerTeam = data['proposerTeam'] as String?;
        return _buildValidationCard(
          request,
          proposal,
          initiatorTeam,
          proposerTeam,
        );
      },
    );
  }

  /// Construit une carte de validation pour les chefs d'équipe
  Widget _buildValidationCard(
    ShiftExchangeRequest request,
    ShiftExchangeProposal proposal,
    String? initiatorTeam,
    String? proposerTeam,
  ) {
    // Vérifier si l'utilisateur actuel a déjà validé
    final userTeam = _currentUser!.team;

    // CRITICAL: Vérifier toutes les validations de l'équipe de l'utilisateur
    // La clé est au format "teamId_leaderId" donc on doit chercher les validations qui commencent par le team
    final hasValidated = proposal.leaderValidations.entries.any(
      (entry) =>
          entry.key.startsWith('${userTeam}_') &&
          entry.value.leaderId == _currentUser!.id,
    );

    // CRITICAL: Vérifier si l'utilisateur est un chef d'équipe (chief ou leader)
    final isLeader =
        _currentUser!.status == KConstants.statusChief ||
        _currentUser!.status == KConstants.statusLeader;

    // CRITICAL: L'utilisateur peut agir UNIQUEMENT s'il est un chef ET n'a pas encore validé
    final canAct = isLeader && !hasValidated;

    // Vérifier si l'équipe (pas juste l'utilisateur actuel) a validé pour afficher le bon badge
    final teamValidations = proposal.teamValidationStates;
    final initiatorTeamValidated =
        initiatorTeam != null &&
        (teamValidations[initiatorTeam] ==
                TeamValidationState.validatedTemporarily ||
            teamValidations[initiatorTeam] ==
                TeamValidationState.autoValidated);
    final proposerTeamValidated =
        proposerTeam != null &&
        (teamValidations[proposerTeam] ==
                TeamValidationState.validatedTemporarily ||
            teamValidations[proposerTeam] == TeamValidationState.autoValidated);

    return FutureBuilder<Planning?>(
      future: _getPlanningDetails(request.initiatorPlanningId, request.station),
      builder: (context, initiatorPlanningSnapshot) {
        final initiatorPlanning = initiatorPlanningSnapshot.data;

        // Récupérer le premier planning proposé pour afficher les détails
        return FutureBuilder<Planning?>(
          future: proposal.proposedPlanningIds.isNotEmpty
              ? _getPlanningDetails(
                  proposal.proposedPlanningIds.first,
                  request.station,
                )
              : Future.value(null),
          builder: (context, proposerPlanningSnapshot) {
            final proposerPlanning = proposerPlanningSnapshot.data;

            // Récupérer les chefs des deux équipes pour calculer l'alignement
            return FutureBuilder<List<List<User>>>(
              future: Future.wait([
                _getTeamLeaders(initiatorTeam ?? '?', request.station),
                _getTeamLeaders(proposerTeam ?? '?', request.station),
              ]),
              builder: (context, leadersSnapshot) {
                final initiatorLeadersCount = leadersSnapshot.hasData
                    ? leadersSnapshot.data![0].length
                    : 0;
                final proposerLeadersCount = leadersSnapshot.hasData
                    ? leadersSnapshot.data![1].length
                    : 0;

                // Calculer combien de lignes vides ajouter pour aligner les dividers
                final maxLeaders = [
                  initiatorLeadersCount,
                  proposerLeadersCount,
                ].reduce((a, b) => a > b ? a : b);
                final initiatorEmptyLines = maxLeaders - initiatorLeadersCount;
                final proposerEmptyLines = maxLeaders - proposerLeadersCount;

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Deux colonnes côte à côte
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Colonne 1: Initiateur (gauche)
                            Expanded(
                              child: _buildExchangeColumn(
                                label: initiatorTeam ?? '?',
                                agentName: request.initiatorName,
                                badge: initiatorTeamValidated
                                    ? _buildStatusBadge(
                                        'Validé',
                                        Colors.green,
                                        Icons.check_circle,
                                      )
                                    : _buildStatusBadge(
                                        'En attente',
                                        Colors.blue,
                                        Icons.hourglass_empty,
                                      ),
                                planning: initiatorPlanning,
                                station: request.station,
                                emptyLinesCount: initiatorEmptyLines,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Icône de swap au milieu
                            Padding(
                              padding: const EdgeInsets.only(top: 30),
                              child: Icon(
                                Icons.swap_horiz,
                                color: Colors.green.shade600,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Colonne 2: Proposeur (droite)
                            Expanded(
                              child: _buildExchangeColumn(
                                label: proposerTeam ?? '?',
                                agentName: proposal.proposerName,
                                badge: proposerTeamValidated
                                    ? _buildStatusBadge(
                                        'Validé',
                                        Colors.green,
                                        Icons.check_circle,
                                      )
                                    : _buildStatusBadge(
                                        'En attente',
                                        Colors.blue,
                                        Icons.hourglass_empty,
                                      ),
                                planning: proposerPlanning,
                                station: request.station,
                                emptyLinesCount: proposerEmptyLines,
                              ),
                            ),
                          ],
                        ),
                        // Boutons d'action (uniquement si le chef n'a pas encore validé)
                        if (canAct) ...[
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _refuseValidation(request, proposal),
                                  icon: const Icon(Icons.close, size: 18),
                                  label: const Text('Refuser'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _acceptValidation(request, proposal),
                                  icon: const Icon(Icons.check, size: 18),
                                  label: const Text('Accepter'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Construit une carte d'historique (similaire à validation mais sans boutons)
  Widget _buildHistoryCard(
    ShiftExchangeRequest request,
    ShiftExchangeProposal? selectedProposal,
    String? initiatorTeam,
    String? proposerTeam, {
    String historyStatus = 'accepted',
  }) {
    // Déterminer les couleurs et textes selon le statut
    Color statusColor;
    IconData statusIcon;
    String statusText;
    Color swapIconColor;

    switch (historyStatus) {
      case 'accepted':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Validé';
        swapIconColor = Colors.green.shade600;
        break;
      case 'cancelled':
        statusColor = Colors.orange;
        statusIcon = Icons.cancel;
        statusText = 'Annulé';
        swapIconColor = Colors.orange.shade600;
        break;
      case 'expired':
        statusColor = Colors.grey;
        statusIcon = Icons.schedule;
        statusText = 'Expiré';
        swapIconColor = Colors.grey.shade600;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
        statusText = '?';
        swapIconColor = Colors.grey.shade600;
    }

    return FutureBuilder<Planning?>(
      future: _getPlanningDetails(request.initiatorPlanningId, request.station),
      builder: (context, initiatorPlanningSnapshot) {
        final initiatorPlanning = initiatorPlanningSnapshot.data;

        // Récupérer le premier planning proposé pour afficher les détails
        return FutureBuilder<Planning?>(
          future:
              selectedProposal != null &&
                  selectedProposal.proposedPlanningIds.isNotEmpty
              ? _getPlanningDetails(
                  selectedProposal.proposedPlanningIds.first,
                  request.station,
                )
              : Future.value(null),
          builder: (context, proposerPlanningSnapshot) {
            final proposerPlanning = proposerPlanningSnapshot.data;

            // Récupérer les chefs des deux équipes pour calculer l'alignement
            return FutureBuilder<List<List<User>>>(
              future: Future.wait([
                _getTeamLeaders(initiatorTeam ?? '?', request.station),
                _getTeamLeaders(proposerTeam ?? '?', request.station),
              ]),
              builder: (context, leadersSnapshot) {
                final initiatorLeadersCount = leadersSnapshot.hasData
                    ? leadersSnapshot.data![0].length
                    : 0;
                final proposerLeadersCount = leadersSnapshot.hasData
                    ? leadersSnapshot.data![1].length
                    : 0;

                // Calculer combien de lignes vides ajouter pour aligner les dividers
                final maxLeaders = [
                  initiatorLeadersCount,
                  proposerLeadersCount,
                ].reduce((a, b) => a > b ? a : b);
                final initiatorEmptyLines = maxLeaders - initiatorLeadersCount;
                final proposerEmptyLines = maxLeaders - proposerLeadersCount;

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Deux colonnes côte à côte
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Colonne 1: Initiateur (gauche)
                            Expanded(
                              child: _buildExchangeColumn(
                                label: initiatorTeam ?? '?',
                                agentName: request.initiatorName,
                                badge: _buildStatusBadge(
                                  statusText,
                                  statusColor,
                                  statusIcon,
                                ),
                                planning: initiatorPlanning,
                                station: request.station,
                                emptyLinesCount: initiatorEmptyLines,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Icône de swap au milieu
                            Padding(
                              padding: const EdgeInsets.only(top: 30),
                              child: Icon(
                                historyStatus == 'expired' ? Icons.block : Icons.swap_horiz,
                                color: swapIconColor,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Colonne 2: Proposeur (droite) - afficher seulement si une proposition existe
                            Expanded(
                              child: selectedProposal != null
                                  ? _buildExchangeColumn(
                                      label: proposerTeam ?? '?',
                                      agentName: selectedProposal.proposerName,
                                      badge: _buildStatusBadge(
                                        statusText,
                                        statusColor,
                                        statusIcon,
                                      ),
                                      planning: proposerPlanning,
                                      station: request.station,
                                      emptyLinesCount: proposerEmptyLines,
                                    )
                                  : Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.person_off,
                                            color: Colors.grey.shade400,
                                            size: 40,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Aucune proposition',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Construit une colonne pour afficher les informations d'un agent dans la validation
  Widget _buildExchangeColumn({
    required String label,
    required String agentName,
    required Widget badge,
    Planning? planning,
    required String station,
    int emptyLinesCount = 0, // Nombre de lignes vides à ajouter pour alignement
  }) {
    return FutureBuilder<List<User>>(
      future: _getTeamLeaders(label, station),
      builder: (context, leadersSnapshot) {
        final teamLeaders = leadersSnapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Liste des chefs d'équipe (un par ligne)
            if (teamLeaders.isNotEmpty) ...[
              ...teamLeaders.map(
                (leader) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    leader.displayName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Ajouter des lignes vides pour alignement
              ...List.generate(
                emptyLinesCount,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: SizedBox(height: 16), // Hauteur d'une ligne de texte
                ),
              ),
              const SizedBox(height: 8),
              // Badge de statut aligné à droite
              Align(alignment: Alignment.centerRight, child: badge),
              const SizedBox(height: 8),
            ],
            // Divider au-dessus du nom
            Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            // Nom de l'agent
            Text(
              agentName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            // Dates
            if (planning != null) ...[
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Du ${_formatDateTime(planning.startTime)}',
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Au ${_formatDateTime(planning.endTime)}',
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            // Station et équipe
            if (station.isNotEmpty || planning?.team != null) ...[
              Row(
                children: [
                  if (station.isNotEmpty) ...[
                    Icon(
                      Icons.location_on,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        station,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              if (planning?.team != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.group, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Équipe ${planning!.team}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  /// Construit un badge de statut
  Widget _buildStatusBadge(String text, Color color, IconData icon) {
    // Créer une teinte plus foncée de la couleur
    final darkColor = Color.fromRGBO(
      (color.red * 0.7).round(),
      (color.green * 0.7).round(),
      (color.blue * 0.7).round(),
      1.0,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: darkColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: darkColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Refuse la validation
  Future<void> _refuseValidation(
    ShiftExchangeRequest request,
    ShiftExchangeProposal proposal,
  ) async {
    // Demander le motif du refus (obligatoire)
    final TextEditingController commentController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Motif du refus'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Veuillez indiquer la raison du refus de cet échange :',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: commentController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Exemple: Contraintes d\'effectif...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              if (commentController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Le motif est obligatoire'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.of(context).pop(true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmer le refus'),
          ),
        ],
      ),
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
        await _refreshData(); // Rafraîchir les données cachées
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer la validation'),
        content: const Text(
          'Êtes-vous sûr de vouloir valider cet échange d\'astreinte ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmer'),
          ),
        ],
      ),
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
        await _refreshData(); // Rafraîchir les données cachées
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
  /// Onglet 4: Historique (utilise les données cachées)
  Widget _buildHistoryTab() {
    // Filtrer pour l'historique :
    // - Demandes acceptées ou annulées
    // - OU demandes expirées (date passée et non abouties)
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    var historicRequests = _allStationExchanges.where((data) {
      final request = data['request'] as ShiftExchangeRequest;

      // Toujours inclure les demandes acceptées ou annulées
      if (request.status == ShiftExchangeRequestStatus.accepted ||
          request.status == ShiftExchangeRequestStatus.cancelled) {
        return true;
      }

      // Inclure aussi les demandes expirées (date passée)
      final startDate = DateTime(
        request.initiatorStartTime.year,
        request.initiatorStartTime.month,
        request.initiatorStartTime.day,
      );
      final isExpired = startDate.isBefore(today);
      return isExpired;
    }).toList();

    // Filtrer par mois sélectionné
    final startOfMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month,
      1,
    );
    final endOfMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      1,
    );

    historicRequests = historicRequests.where((data) {
      final request = data['request'] as ShiftExchangeRequest;
      return request.initiatorStartTime.isAfter(
            startOfMonth.subtract(const Duration(days: 1)),
          ) &&
          request.initiatorStartTime.isBefore(endOfMonth);
    }).toList();

    return Column(
      children: [
        // Navigateur mensuel
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey.shade900
              : Colors.grey.shade100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month - 1,
                    );
                  });
                },
              ),
              Text(
                _formatMonthYear(_selectedMonth),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month + 1,
                    );
                  });
                },
              ),
            ],
          ),
        ),
        // Liste des échanges historiques
        Expanded(
          child: historicRequests.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.4,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'Aucun historique pour cette période',
                              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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

                    // Trouver la proposition sélectionnée et finalisée (si elle existe)
                    ShiftExchangeProposal? selectedProposal;
                    if (proposals.isNotEmpty) {
                      try {
                        selectedProposal = proposals.firstWhere(
                          (p) =>
                              p.status == ShiftExchangeProposalStatus.validated &&
                              p.isFinalized,
                        );
                      } catch (_) {
                        // Pas de proposition validée, prendre la première si elle existe
                        selectedProposal = proposals.isNotEmpty ? proposals.first : null;
                      }
                    }

                    // Déterminer le statut historique
                    String historyStatus;
                    if (request.status == ShiftExchangeRequestStatus.accepted) {
                      historyStatus = 'accepted';
                    } else if (request.status == ShiftExchangeRequestStatus.cancelled) {
                      historyStatus = 'cancelled';
                    } else {
                      // Demande expirée (date passée sans aboutissement)
                      historyStatus = 'expired';
                    }

                    // Récupérer les équipes depuis les plannings (utilise le cache)
                    return FutureBuilder<Planning?>(
                      future: _getPlanningDetails(
                        request.initiatorPlanningId,
                        request.station,
                      ),
                      builder: (context, initiatorSnapshot) {
                        final initiatorTeam = initiatorSnapshot.data?.team;

                        return FutureBuilder<Planning?>(
                          future: selectedProposal != null && selectedProposal.proposedPlanningIds.isNotEmpty
                              ? _getPlanningDetails(
                                  selectedProposal.proposedPlanningIds.first,
                                  request.station,
                                )
                              : Future.value(null),
                          builder: (context, proposerSnapshot) {
                            final proposerTeam = proposerSnapshot.data?.team;

                            return _buildHistoryCard(
                              request,
                              selectedProposal,
                              initiatorTeam,
                              proposerTeam,
                              historyStatus: historyStatus,
                            );
                          },
                        );
                      },
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
