import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:nexshift_app/core/services/wave_calculation_service.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/features/replacement/presentation/pages/replacement_request_dialog.dart';
import 'package:nexshift_app/core/data/models/agent_query_model.dart';
import 'package:nexshift_app/core/repositories/agent_query_repository.dart';
import 'package:nexshift_app/core/services/agent_query_service.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/replacement_sub_tabs.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/icon_tab_bar.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/filtered_requests_view.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/replacement_tile_wrapper.dart';
import 'package:nexshift_app/features/replacement/presentation/widgets/agent_query_tile_wrapper.dart';
import 'package:nexshift_app/features/shift_exchange/presentation/widgets/exchange_content_widget.dart';
import 'package:nexshift_app/core/presentation/widgets/app_empty_state.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/presentation/widgets/unified_request_tile/unified_request_tile_exports.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/services/shift_exchange_service.dart';
import 'package:nexshift_app/core/services/badge_count_service.dart';
import 'package:nexshift_app/core/presentation/widgets/request_actions_bottom_sheet.dart';
import 'package:nexshift_app/core/presentation/widgets/notified_agents_sheet.dart';
import 'package:nexshift_app/core/presentation/widgets/availability_picker_section.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';

// ManualReplacementProposal est maintenant importé depuis filtered_requests_view.dart

/// Page listant toutes les demandes de remplacement en cours
/// Accessible depuis le Drawer
class ReplacementRequestsListPage extends StatefulWidget {
  const ReplacementRequestsListPage({super.key});

  @override
  State<ReplacementRequestsListPage> createState() =>
      _ReplacementRequestsListPageState();
}

class _ReplacementRequestsListPageState
    extends State<ReplacementRequestsListPage>
    with TickerProviderStateMixin {
  final _notificationService = ReplacementNotificationService();
  final _userRepository = UserRepository();
  final _exchangeService = ShiftExchangeService();
  final _planningRepository = PlanningRepository();
  String? _currentUserId;
  String? _currentStationId;
  User? _currentUser;
  DateTime _selectedDate = DateTime.now();
  TabController? _mainTabController;
  TabController? _replacementSubTabController;
  TabController? _agentQuerySubTabController;
  bool _isChief = false;
  final _agentQueryService = AgentQueryService();

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  @override
  void dispose() {
    _mainTabController?.dispose();
    _replacementSubTabController?.dispose();
    _agentQuerySubTabController?.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final user = await UserStorageHelper.loadUser();
    if (mounted && user != null) {
      // Initialiser le BadgeCountService
      if (user.id.isNotEmpty && user.station.isNotEmpty) {
        BadgeCountService().initialize(user.id, user.station, user);
      }

      setState(() {
        _currentUserId = user.id;
        _currentStationId = user.station;
        _currentUser = user;
        _isChief = user.status == 'chief' || user.status == 'leader';
        // Initialiser les TabControllers
        _mainTabController = TabController(length: 3, vsync: this);
        _replacementSubTabController = TabController(length: 4, vsync: this);
        _agentQuerySubTabController = TabController(length: 3, vsync: this);
      });
    }
  }

  /// Calcule le nombre de propositions d'échange nécessitant la validation de CE leader spécifique
  /// en utilisant la même logique que getProposalsRequiringValidationForLeader
  Future<int> _getExchangeValidationCount(
    QuerySnapshot proposalsSnapshot,
  ) async {
    if (_currentUser == null ||
        _currentUserId == null ||
        _currentStationId == null) {
      return 0;
    }

    final userTeam = _currentUser!.team;
    final leaderKey = '${userTeam}_$_currentUserId';
    int count = 0;

    for (final doc in proposalsSnapshot.docs) {
      final proposalData = doc.data() as Map<String, dynamic>;
      final validations =
          proposalData['leaderValidations'] as Map<String, dynamic>? ?? {};

      // Si ce leader a déjà validé, on passe
      if (validations.containsKey(leaderKey)) {
        continue;
      }

      // Récupérer les équipes de l'initiateur et du proposeur
      final proposerTeam = proposalData['proposerTeamId'] as String?;
      final requestId = proposalData['requestId'] as String?;

      // Vérifier si ce leader fait partie des équipes concernées
      if (proposerTeam == userTeam) {
        count++;
        continue;
      }

      // Pour l'équipe de l'initiateur, on doit récupérer le planning
      if (requestId != null) {
        try {
          // On pourrait aussi extraire initiatorTeamId s'il est stocké dans la proposition
          // Sinon on doit récupérer la demande et son planning
          // Pour l'instant, on compte si le proposeur est dans l'équipe
          // La logique complète nécessiterait de récupérer chaque request
        } catch (e) {
          // Ignorer les erreurs
        }
      }
    }

    return count;
  }

  /// Retourne le chemin de collection pour les demandes de remplacement automatiques
  String _getCollectionPath() {
    return EnvironmentConfig.getCollectionPath(
        'replacements/automatic/replacementRequests', _currentStationId);
  }

  /// Retourne le chemin de collection pour les propositions de remplacement manuel
  String _getManualReplacementProposalsPath(String stationId) {
    return EnvironmentConfig.getCollectionPath(
        'replacements/manual/proposals', stationId);
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
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

  Future<void> _selectMonthYear() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('fr', 'FR'),
      helpText: 'Sélectionner un mois',
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserId == null ||
        _mainTabController == null ||
        _replacementSubTabController == null ||
        _agentQuerySubTabController == null) {
      return Scaffold(
        appBar: CustomAppBar(
          title: 'Demandes de remplacement',
          bottomColor: KColors.appNameColor,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Demandes de remplacement',
        bottomColor: KColors.appNameColor,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: _buildMainTabBar(),
        ),
      ),
      body: TabBarView(
        controller: _mainTabController,
        children: [
          _buildReplacementsContent(),
          _buildExchangesContent(),
          _buildAgentQueriesContent(),
        ],
      ),
    );
  }

  Widget _buildMainTabBar() {
    final badgeService = BadgeCountService();

    return ValueListenableBuilder<bool>(
      valueListenable: badgeService.hasReplacementPending,
      builder: (context, hasReplacementPending, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: badgeService.hasReplacementValidation,
          builder: (context, hasReplacementValidation, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: badgeService.hasExchangePending,
              builder: (context, hasExchangePending, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: badgeService.hasExchangeValidation,
                  builder: (context, hasExchangeValidation, _) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: badgeService.hasExchangeNeedingSelection,
                      builder: (context, hasExchangeNeedingSelection, _) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: badgeService.hasAgentQueryPending,
                          builder: (context, hasAgentQueryPending, _) {
                            final isDark =
                                Theme.of(context).brightness == Brightness.dark;
                            final tabColor = isDark
                                ? Colors.white
                                : KColors.appNameColor;
                            return TabBar(
                              controller: _mainTabController,
                              labelColor: tabColor,
                              unselectedLabelColor: tabColor.withValues(
                                alpha: 0.7,
                              ),
                              indicatorColor: tabColor,
                              tabs: [
                                Tab(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Flexible(
                                        child: Text(
                                          'Remplacements',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (hasReplacementPending ||
                                          hasReplacementValidation) ...[
                                        const SizedBox(width: 8),
                                        if (hasReplacementPending)
                                          Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: KColors.appNameColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        if (hasReplacementPending &&
                                            hasReplacementValidation)
                                          const SizedBox(width: 6),
                                        if (hasReplacementValidation)
                                          Container(
                                            width: 12,
                                            height: 12,
                                            decoration: const BoxDecoration(
                                              color: Colors.purple,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                                Tab(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Flexible(
                                        child: Text(
                                          'Échanges',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (hasExchangePending ||
                                          hasExchangeNeedingSelection ||
                                          hasExchangeValidation) ...[
                                        const SizedBox(width: 8),
                                        if (hasExchangePending ||
                                            hasExchangeNeedingSelection)
                                          Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: KColors.appNameColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        if ((hasExchangePending ||
                                                hasExchangeNeedingSelection) &&
                                            hasExchangeValidation)
                                          const SizedBox(width: 6),
                                        if (hasExchangeValidation)
                                          Container(
                                            width: 12,
                                            height: 12,
                                            decoration: const BoxDecoration(
                                              color: Colors.blue,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                                Tab(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Flexible(
                                        child: Text(
                                          'Recherches',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (hasAgentQueryPending) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: KColors.appNameColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildReplacementsContent() {
    if (_currentUserId == null || _currentStationId == null) {
      return Column(
        children: [
          IconTabBar(
            controller: _replacementSubTabController!,
            tabs: replacementSubTabs,
            selectedColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : KColors.appNameColor,
            unselectedColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.white70
                : KColors.appNameColor.withValues(alpha: 0.7),
          ),
          Expanded(child: Container()),
        ],
      );
    }

    // Utiliser le BadgeCountService pour les compteurs centralisés
    final badgeService = BadgeCountService();

    return ValueListenableBuilder<int>(
      valueListenable: badgeService.replacementPendingCount,
      builder: (context, pendingCount, _) {
        return ValueListenableBuilder<int>(
          valueListenable: badgeService.replacementMyRequestsCount,
          builder: (context, myRequestsCount, _) {
            return ValueListenableBuilder<int>(
              valueListenable: badgeService.replacementToValidateCount,
              builder: (context, validationCount, _) {
                return Column(
                  children: [
                    // Sous-onglets avec icônes et badges
                    IconTabBar(
                      controller: _replacementSubTabController!,
                      tabs: replacementSubTabs,
                      selectedColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : KColors.appNameColor,
                      unselectedColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : KColors.appNameColor.withValues(alpha: 0.7),
                      badgeCounts: {
                        ReplacementSubTab.pending: pendingCount,
                        ReplacementSubTab.myRequests: myRequestsCount,
                        ReplacementSubTab.toValidate: validationCount,
                      },
                      badgeColors: {
                        ReplacementSubTab.pending: KColors.appNameColor,
                        ReplacementSubTab.myRequests: KColors.appNameColor,
                        ReplacementSubTab.toValidate: Colors.blue,
                      },
                    ),
                    // Contenu des sous-onglets
                    Expanded(
                      child: TabBarView(
                        controller: _replacementSubTabController,
                        children: replacementSubTabs.map((config) {
                          // Pour l'historique, ajouter le navigateur mensuel
                          if (config.type == ReplacementSubTab.history) {
                            return _buildHistoryTabWithNavigator();
                          }
                          // Pour les autres onglets, affichage normal
                          return FilteredRequestsView(
                            subTab: config.type,
                            currentUserId: _currentUserId,
                            currentStationId: _currentStationId,
                            currentUser: _currentUser,
                            selectedMonth: null,
                            buildCard: _buildRequestCard,
                            buildManualCard: _buildManualProposalCard,
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryTabWithNavigator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        // Navigateur mensuel stylisé
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
            color: isDark
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
                icon: Icon(
                  Icons.chevron_left_rounded,
                  color: KColors.appNameColor,
                ),
                onPressed: () {
                  setState(() {
                    _selectedDate = DateTime(
                      _selectedDate.year,
                      _selectedDate.month - 1,
                    );
                  });
                },
                tooltip: 'Mois précédent',
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _selectMonthYear,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 16,
                        color: KColors.appNameColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatMonthYear(_selectedDate),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: KColors.appNameColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right_rounded,
                  color: KColors.appNameColor,
                ),
                onPressed: () {
                  setState(() {
                    _selectedDate = DateTime(
                      _selectedDate.year,
                      _selectedDate.month + 1,
                    );
                  });
                },
                tooltip: 'Mois suivant',
              ),
            ],
          ),
        ),
        // Liste de l'historique
        Expanded(
          child: FilteredRequestsView(
            subTab: ReplacementSubTab.history,
            currentUserId: _currentUserId,
            currentStationId: _currentStationId,
            currentUser: _currentUser,
            selectedMonth: _selectedDate,
            buildCard: _buildRequestCard,
            buildManualCard: _buildManualProposalCard,
          ),
        ),
      ],
    );
  }

  Widget _buildExchangesContent() {
    // Afficher le widget de contenu d'échange
    return const ExchangeContentWidget();
  }

  // ============================================================
  // ONGLET RECHERCHES (AgentQuery)
  // ============================================================

  Widget _buildAgentQueriesContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final agentQuerySelectedColor =
        isDark ? Colors.white : KColors.appNameColor;
    final agentQueryUnselectedColor = isDark
        ? Colors.white70
        : KColors.appNameColor.withValues(alpha: 0.6);

    if (_currentUserId == null || _currentStationId == null) {
      return Column(
        children: [
          AgentQueryIconTabBar(
            controller: _agentQuerySubTabController!,
            tabs: agentQuerySubTabs,
            selectedColor: agentQuerySelectedColor,
            unselectedColor: agentQueryUnselectedColor,
          ),
          Expanded(child: Container()),
        ],
      );
    }

    final badgeService = BadgeCountService();

    return ValueListenableBuilder<int>(
      valueListenable: badgeService.agentQueryPendingCount,
      builder: (context, pendingCount, _) {
        return ValueListenableBuilder<int>(
          valueListenable: badgeService.agentQueryMyRequestsCount,
          builder: (context, myRequestsCount, _) {
            return Column(
              children: [
                AgentQueryIconTabBar(
                  controller: _agentQuerySubTabController!,
                  tabs: agentQuerySubTabs,
                  selectedColor: agentQuerySelectedColor,
                  unselectedColor: agentQueryUnselectedColor,
                  badgeCounts: {
                    AgentQuerySubTab.pending: pendingCount,
                    AgentQuerySubTab.myRequests: myRequestsCount,
                  },
                  badgeColors: {
                    AgentQuerySubTab.pending: KColors.appNameColor,
                    AgentQuerySubTab.myRequests: KColors.appNameColor,
                  },
                ),
                Expanded(
                  child: TabBarView(
                    controller: _agentQuerySubTabController,
                    children: agentQuerySubTabs.map((config) {
                      if (config.type == AgentQuerySubTab.history) {
                        return _buildAgentQueryHistoryTab();
                      }
                      return _buildAgentQueryTab(config.type);
                    }).toList(),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAgentQueryTab(AgentQuerySubTab subTab) {
    return StreamBuilder<List<AgentQuery>>(
      stream: AgentQueryRepository().watchAll(stationId: _currentStationId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allQueries = snapshot.data ?? [];
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        final queries = allQueries.where((q) {
          final startDate = DateTime(
            q.startTime.year,
            q.startTime.month,
            q.startTime.day,
          );
          final isFuture =
              startDate.isAfter(today) || startDate.isAtSameMomentAs(today);
          if (!isFuture) return false;

          switch (subTab) {
            case AgentQuerySubTab.pending:
              // Demandes en attente où je suis notifié (pas créateur) et n'ai pas encore refusé
              return q.status == AgentQueryStatus.pending &&
                  q.createdById != _currentUserId &&
                  q.notifiedUserIds.contains(_currentUserId) &&
                  !q.declinedByUserIds.contains(_currentUserId);
            case AgentQuerySubTab.myRequests:
              // Mes demandes créées (en attente) — toujours visibles même si refusé
              return q.status == AgentQueryStatus.pending &&
                  q.createdById == _currentUserId;
            case AgentQuerySubTab.history:
              return false; // handled separately
          }
        }).toList();

        if (queries.isEmpty) {
          return _buildAgentQueryEmptyState(subTab);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: queries.length,
          itemBuilder: (context, index) =>
              _buildAgentQueryCard(queries[index], subTab),
        );
      },
    );
  }

  Widget _buildAgentQueryHistoryTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        // Navigateur mensuel (même style que Remplacements > Historique)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
            color: isDark
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
                icon: Icon(
                  Icons.chevron_left_rounded,
                  color: KColors.appNameColor,
                ),
                onPressed: () {
                  setState(() {
                    _selectedDate = DateTime(
                      _selectedDate.year,
                      _selectedDate.month - 1,
                    );
                  });
                },
                tooltip: 'Mois précédent',
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _selectMonthYear,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 16,
                        color: KColors.appNameColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatMonthYear(_selectedDate),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: KColors.appNameColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right_rounded,
                  color: KColors.appNameColor,
                ),
                onPressed: () {
                  setState(() {
                    _selectedDate = DateTime(
                      _selectedDate.year,
                      _selectedDate.month + 1,
                    );
                  });
                },
                tooltip: 'Mois suivant',
              ),
            ],
          ),
        ),
        // Liste des recherches historiques pour le mois sélectionné
        Expanded(
          child: StreamBuilder<List<AgentQuery>>(
            stream: AgentQueryRepository().watchAll(
              stationId: _currentStationId!,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allQueries = snapshot.data ?? [];
              final queries = allQueries
                  .where(
                    (q) =>
                        q.status != AgentQueryStatus.pending &&
                        q.status != AgentQueryStatus.cancelled &&
                        q.startTime.year == _selectedDate.year &&
                        q.startTime.month == _selectedDate.month,
                  )
                  .toList();

              if (queries.isEmpty) {
                return _buildAgentQueryEmptyState(AgentQuerySubTab.history);
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: queries.length,
                itemBuilder: (context, index) => _buildAgentQueryCard(
                  queries[index],
                  AgentQuerySubTab.history,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAgentQueryEmptyState(AgentQuerySubTab subTab) {
    switch (subTab) {
      case AgentQuerySubTab.pending:
        return const AppEmptyState(
          icon: Icons.manage_search_rounded,
          headline: 'Aucune recherche disponible',
          subtitle: 'Il n\'y a pas de recherches compatibles',
        );
      case AgentQuerySubTab.myRequests:
        return const AppEmptyState(
          icon: Icons.person_search_rounded,
          headline: 'Aucune recherche en cours',
          subtitle: 'Vous n\'avez pas de recherches en cours',
        );
      case AgentQuerySubTab.history:
        return const AppEmptyState(
          icon: Icons.history,
          headline: 'Aucun historique',
          subtitle: 'Il n\'y a pas d\'entrées pour cette période',
        );
    }
  }

  Widget _buildAgentQueryCard(AgentQuery query, AgentQuerySubTab subTab) {
    return AgentQueryTileWrapper(
      key: ValueKey(query.id),
      query: query,
      subTab: subTab,
      currentUserId: _currentUserId,
      onCancel: () => _cancelAgentQuery(query),
      onAccept: () => _showAgentQueryAcceptDialog(query),
      onDecline: () => _respondToAgentQuery(query, accepted: false),
      onShowNotified: () => _showAgentQueryWaveDialog(query),
      onResendNotifications: () => _resendAgentQueryNotifications(query),
      onMarkAsSeen: _currentUserId != null
          ? () => _agentQueryService.markQueryAsSeen(
              queryId: query.id,
              stationId: _currentStationId ?? query.station,
              userId: _currentUserId!,
            )
          : null,
    );
  }

  // ── AgentQuery : dialog vague-style ─────────────────────────────────────────

  Future<void> _showAgentQueryWaveDialog(AgentQuery query) async {
    // 1. Charger tous les agents de la station + le planning pour récupérer agentsId
    List<String> planningAgentIds = [];
    try {
      final planning = await _planningRepository.getById(
        query.planningId,
        stationId: _currentStationId,
      );
      planningAgentIds = planning?.agentsId ?? [];
    } catch (_) {}

    List<User> allStationUsers = [];
    try {
      allStationUsers = await _userRepository.getByStation(
        query.station.isNotEmpty ? query.station : (_currentStationId ?? ''),
      );
    } catch (_) {}

    if (!mounted) return;

    // 2. Construire les entrées pour chaque agent notifié
    final notifiedEntries = query.notifiedUserIds.map((uid) {
      final user = allStationUsers.cast<User?>().firstWhere(
        (u) => u?.id == uid,
        orElse: () => null,
      );
      final name = user?.displayName ?? uid;
      final isMatched = query.matchedAgentId == uid;
      final hasDeclined = query.declinedByUserIds.contains(uid);
      final hasSeen = query.seenByUserIds.contains(uid);

      AgentNotifiedStatus status;
      if (isMatched) {
        status = AgentNotifiedStatus.validated;
      } else if (hasDeclined) {
        status = AgentNotifiedStatus.declined;
      } else if (hasSeen) {
        status = AgentNotifiedStatus.seen;
      } else {
        status = AgentNotifiedStatus.waiting;
      }

      return AgentStatusEntry(name: name, status: status);
    }).toList();

    // 3. Agents non-notifiés : tous les agents de la station hors notifiés
    final nonNotifiedUsers = allStationUsers
        .where((u) => !query.notifiedUserIds.contains(u.id))
        .toList();

    // Sous-catégorie 1 : En astreinte (dans le planning cible)
    final onDutyEntries = nonNotifiedUsers
        .where((u) => planningAgentIds.contains(u.id))
        .map(
          (u) => AgentStatusEntry(
            name: u.displayName,
            status: AgentNotifiedStatus.notNotified,
          ),
        )
        .toList();

    // Sous-catégorie 2 : Sous-qualifiés (n'ont pas tous les skills requis)
    final underQualifiedEntries = nonNotifiedUsers
        .where(
          (u) =>
              !planningAgentIds.contains(u.id) &&
              u.isActiveForReplacement &&
              query.requiredSkills.isNotEmpty &&
              !query.requiredSkills.every((s) => u.skills.contains(s)),
        )
        .map(
          (u) => AgentStatusEntry(
            name: u.displayName,
            status: AgentNotifiedStatus.notNotified,
          ),
        )
        .toList();

    // Sous-catégorie 3 : En arrêt maladie
    final sickLeaveEntries = nonNotifiedUsers
        .where((u) =>
            u.agentAvailabilityStatus == AgentAvailabilityStatus.sickLeave)
        .map((u) => AgentStatusEntry(
              name: u.displayName,
              status: AgentNotifiedStatus.notNotified,
            ))
        .toList();

    // Sous-catégorie 4 : Suspendus d'engagement
    final suspendedEntries = nonNotifiedUsers
        .where((u) =>
            u.agentAvailabilityStatus ==
            AgentAvailabilityStatus.suspendedFromDuty)
        .map((u) => AgentStatusEntry(
              name: u.displayName,
              status: AgentNotifiedStatus.notNotified,
            ))
        .toList();

    // 4. Construire les groupes — non-notifiés en premier, notifiés ensuite
    final primary = Theme.of(context).colorScheme.primary;
    final nonNotifiedSubGroups = [
      if (onDutyEntries.isNotEmpty)
        AgentSubGroup(label: 'Agents en astreinte', agents: onDutyEntries),
      if (underQualifiedEntries.isNotEmpty)
        AgentSubGroup(label: 'Agents sous-qualifiés', agents: underQualifiedEntries),
      if (sickLeaveEntries.isNotEmpty)
        AgentSubGroup(label: 'Agents en arrêt maladie', agents: sickLeaveEntries),
      if (suspendedEntries.isNotEmpty)
        AgentSubGroup(label: 'Agents suspendus', agents: suspendedEntries),
    ];
    final groups = <AgentGroup>[
      if (nonNotifiedSubGroups.isNotEmpty)
        AgentGroup(
          label: 'Agents non-notifiés',
          color: Colors.grey.shade600,
          subGroups: nonNotifiedSubGroups,
          initiallyExpanded: true,
        ),
      if (notifiedEntries.isNotEmpty)
        AgentGroup(
          label: 'Agents notifiés',
          color: primary,
          agents: notifiedEntries,
          initiallyExpanded: true,
        ),
    ];

    if (!mounted) return;

    await NotifiedAgentsSheet.show(
      context: context,
      headerColor: primary,
      headerIcon: Icons.manage_search_rounded,
      title: 'Agents notifiés',
      groups: groups,
    );
  }

  // ── AgentQuery : dialog acceptation avec sélection d'horaires ────────────

  Future<void> _showAgentQueryAcceptDialog(AgentQuery query) async {
    if (_currentUser == null) return;

    // Résoudre le nom de station
    String stationName = query.station;
    final sdisId = SDISContext().currentSDISId;
    if (sdisId != null && sdisId.isNotEmpty && query.station.isNotEmpty) {
      try {
        stationName = await StationNameCache().getStationName(
          sdisId,
          query.station,
        );
      } catch (_) {}
    }

    // Récupérer l'équipe depuis le planning
    String team = '';
    if (query.planningId.isNotEmpty) {
      try {
        final planning = await _planningRepository.getById(
          query.planningId,
          stationId: _currentStationId,
        );
        team = planning?.team ?? '';
      } catch (_) {}
    }

    if (!mounted) return;

    DateTime selectedStart = query.startTime;
    DateTime selectedEnd = query.endTime;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AgentQueryAcceptDialog(
        query: query,
        stationName: stationName,
        team: team,
        onStartChanged: (dt) => selectedStart = dt,
        onEndChanged: (dt) => selectedEnd = dt,
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final success = await _agentQueryService.acceptQueryPartial(
        query: query,
        respondingAgent: _currentUser!,
        acceptedStart: selectedStart,
        acceptedEnd: selectedEnd,
      );
      if (!mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Un autre agent a déjà accepté cette recherche.'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vous avez rejoint l\'astreinte !'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ── AgentQuery : relancer les notifications ──────────────────────────────

  Future<void> _resendAgentQueryNotifications(AgentQuery query) async {
    // Les agents à re-notifier = notifiés - ayant répondu (déclineurs + matché)
    final targetIds = query.notifiedUserIds
        .where(
          (id) =>
              !query.declinedByUserIds.contains(id) &&
              id != query.matchedAgentId,
        )
        .toList();
    if (targetIds.isEmpty) return;

    try {
      await _agentQueryService.resendNotifications(
        query: query,
        targetUserIds: targetIds,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Notifications renvoyées à ${targetIds.length} agent${targetIds.length > 1 ? 's' : ''}.',
          ),
          backgroundColor: Colors.orange.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildResponseBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _respondToAgentQuery(
    AgentQuery query, {
    required bool accepted,
  }) async {
    if (_currentUser == null) return;

    if (accepted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Accepter la recherche ?'),
          content: Text(
            'Vous allez rejoindre l\'astreinte "${query.onCallLevelName}" du ${_formatDateTime(query.startTime)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: KColors.appNameColor,
              ),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    try {
      final success = await _agentQueryService.respondToQuery(
        query: query,
        respondingAgent: _currentUser!,
        accepted: accepted,
      );

      if (!mounted) return;

      if (accepted && !success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Un autre agent a déjà accepté cette recherche.'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accepted
                  ? 'Vous avez rejoint l\'astreinte !'
                  : 'Recherche refusée.',
            ),
            backgroundColor: accepted ? Colors.green : Colors.grey,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _cancelAgentQuery(AgentQuery query) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la recherche ?'),
        content: const Text(
          'Les agents notifiés ne pourront plus accepter cette recherche.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Annuler la recherche'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _agentQueryService.cancelQuery(query: query);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recherche annulée.'),
          backgroundColor: Colors.grey,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteRequest(ReplacementRequest request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer la demande ?"),
        content: const Text(
          "Cette action est irréversible. Voulez-vous vraiment supprimer cette demande de remplacement ?",
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
        await _notificationService.cancelReplacementRequest(
          request.id,
          stationId: request.station,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
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

  /// Convertit le sous-onglet en mode de vue pour les tuiles unifiées
  TileViewMode _subTabToViewMode(ReplacementSubTab subTab) {
    switch (subTab) {
      case ReplacementSubTab.pending:
        return TileViewMode.pending;
      case ReplacementSubTab.myRequests:
        return TileViewMode.myRequests;
      case ReplacementSubTab.toValidate:
        return TileViewMode.toValidate;
      case ReplacementSubTab.history:
        return TileViewMode.history;
    }
  }

  Widget _buildRequestCard(
    ReplacementRequest request,
    ReplacementSubTab subTab,
  ) {
    final viewMode = _subTabToViewMode(subTab);

    // En mode "Mes demandes", le tap ouvre le BottomSheet d'actions
    VoidCallback? onTapCallback;
    if (viewMode == TileViewMode.myRequests) {
      onTapCallback = () => _showRequestActionsBottomSheet(request);
    }

    return ReplacementTileWrapper(
      request: request,
      currentUserId: _currentUserId ?? '',
      stationId: _currentStationId ?? '',
      viewMode: viewMode,
      onTap: onTapCallback,
      onDelete: () => _deleteRequest(request),
      onAccept: () =>
          _handleRequestTap(request), // Ouvre le dialog de confirmation
      onRefuse: () => _declineReplacementRequest(request), // Refuse directement
      onValidate: () =>
          _handleRequestTap(request), // À ajuster pour la validation chef
      onWaveTap: () => request.requestType == RequestType.availability
          ? _showNotifiedUsersDialog(request)
          : _showWaveDetailsDialog(request),
      onMarkAsSeen: () => _markRequestAsSeen(request.id),
      onSkipToNextWave: () => _skipToNextWave(request),
      onResendNotifications: () => _showResendNotificationsDialog(request),
    );
  }

  /// Affiche le BottomSheet d'actions pour une demande de remplacement automatique
  Future<void> _showRequestActionsBottomSheet(
    ReplacementRequest request,
  ) async {
    // Charger le nom du demandeur
    final requesterName = await _getRequesterName(request.requesterId);

    // Résoudre le nom de la station
    String stationName = request.station;
    final sdisId = SDISContext().currentSDISId;
    if (sdisId != null && request.station.isNotEmpty) {
      stationName = await StationNameCache().getStationName(
        sdisId,
        request.station,
      );
    }

    if (!mounted) return;

    // Déterminer si le bouton de renotification doit être affiché
    // Pour les remplacements automatiques : seulement à partir de la vague 5
    final showResendButton = request.currentWave >= 5;

    RequestActionsBottomSheet.show(
      context: context,
      requestType: request.isSOS
          ? UnifiedRequestType.sosReplacement
          : UnifiedRequestType.automaticReplacement,
      initiatorName: requesterName,
      team: request.team,
      station: stationName,
      startTime: request.startTime,
      endTime: request.endTime,
      onResendNotifications: showResendButton
          ? () => _showResendNotificationsDialog(request)
          : null,
      onDelete: () => _deleteRequest(request),
    );
  }

  // Ancienne méthode _buildRequestCard conservée temporairement pour référence
  Widget _buildRequestCardOld(ReplacementRequest request) {
    print(
      '[DEBUG SOS BUILD] Building card for request ${request.id}: isSOS = ${request.isSOS}',
    );
    return FutureBuilder<Map<String, dynamic>>(
      future:
          Future.wait([
            _getRequesterName(request.requesterId),
            UserStorageHelper.loadUser().then((user) => user),
            _canAcceptRequest(request),
            _hasUserDeclined(request.id),
            _hasUserPendingAcceptance(request.id),
          ]).then(
            (results) => {
              'requesterName': results[0] as String,
              'currentUser': results[1],
              'canAccept': results[2] as bool,
              'hasDeclined': results[3] as bool,
              'hasPendingAcceptance': results[4] as bool,
            },
          ),
      builder: (context, snapshot) {
        final requesterName =
            snapshot.data?['requesterName'] as String? ?? 'Chargement...';
        final currentUser = snapshot.data?['currentUser'] as User?;
        final canAccept = snapshot.data?['canAccept'] as bool? ?? false;
        final hasDeclined = snapshot.data?['hasDeclined'] as bool? ?? false;
        final hasPendingAcceptance =
            snapshot.data?['hasPendingAcceptance'] as bool? ?? false;
        // Permettre la suppression uniquement si c'est sa propre demande (donc uniquement dans "Mes demandes")
        final canDelete =
            currentUser != null && currentUser.id == request.requesterId;

        // Phase 3 - Vérifier si l'utilisateur est notifié
        final isNotified =
            currentUser != null &&
            request.notifiedUserIds.contains(currentUser.id);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: InkWell(
            // Phase 3 FIX: Seuls les utilisateurs notifiés peuvent ouvrir le dialog
            // ET pas d'acceptation en attente de validation
            onTap:
                request.status == ReplacementRequestStatus.pending &&
                    isNotified &&
                    !hasPendingAcceptance
                ? () => _handleRequestTap(request)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // En-tête avec nom et badge
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: request.isSOS
                            ? Colors.red
                            : Colors.blue,
                        radius: 20,
                        child: Icon(
                          request.isSOS ? Icons.warning : Icons.person,
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
                              requesterName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Badges de statut et vague
                            Row(
                              children: [
                                // Badge de statut
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: hasDeclined
                                        ? Colors.red.shade100
                                        : (hasPendingAcceptance
                                              ? Colors.green.shade100
                                              : (request.status ==
                                                        ReplacementRequestStatus
                                                            .accepted
                                                    ? Colors.green.shade100
                                                    : Colors.orange.shade100)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        hasDeclined
                                            ? Icons.cancel
                                            : (hasPendingAcceptance
                                                  ? Icons.schedule
                                                  : (request.status ==
                                                            ReplacementRequestStatus
                                                                .accepted
                                                        ? Icons.check_circle
                                                        : Icons.access_time)),
                                        size: 14,
                                        color: hasDeclined
                                            ? Colors.red.shade700
                                            : (hasPendingAcceptance
                                                  ? Colors.green.shade700
                                                  : (request.status ==
                                                            ReplacementRequestStatus
                                                                .accepted
                                                        ? Colors.green.shade700
                                                        : Colors
                                                              .orange
                                                              .shade700)),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        hasDeclined
                                            ? 'Refusé'
                                            : (hasPendingAcceptance
                                                  ? 'En attente de validation'
                                                  : (request.status ==
                                                            ReplacementRequestStatus
                                                                .accepted
                                                        ? 'Accepté'
                                                        : 'En attente')),
                                        style: TextStyle(
                                          color: hasDeclined
                                              ? Colors.red.shade700
                                              : (hasPendingAcceptance
                                                    ? Colors.green.shade700
                                                    : (request.status ==
                                                              ReplacementRequestStatus
                                                                  .accepted
                                                          ? Colors
                                                                .green
                                                                .shade700
                                                          : Colors
                                                                .orange
                                                                .shade700)),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Phase 3 - Badge "Non notifié" si visible mais pas notifié (cliquable)
                                if (request.status ==
                                        ReplacementRequestStatus.pending &&
                                    !isNotified) ...[
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () =>
                                        request.requestType ==
                                            RequestType.availability
                                        ? _showNotifiedUsersDialog(request)
                                        : _showWaveDetailsDialog(request),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.visibility_off,
                                            size: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Non notifié',
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 2),
                                          Icon(
                                            Icons.info_outline,
                                            size: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                // Indicateur de vague/personnes notifiées (afficher pour toutes les demandes)
                                if ((request.status ==
                                            ReplacementRequestStatus.pending &&
                                        isNotified) ||
                                    request.status ==
                                        ReplacementRequestStatus.accepted) ...[
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () =>
                                        request.requestType ==
                                            RequestType.availability
                                        ? _showNotifiedUsersDialog(request)
                                        : _showWaveDetailsDialog(request),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            request.requestType ==
                                                RequestType.availability
                                            ? Colors.teal.shade100
                                            : Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color:
                                              request.requestType ==
                                                  RequestType.availability
                                              ? Colors.teal.shade300
                                              : Colors.blue.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            request.requestType ==
                                                    RequestType.availability
                                                ? Icons.people_outline
                                                : Icons.waves,
                                            size: 14,
                                            color:
                                                request.requestType ==
                                                    RequestType.availability
                                                ? Colors.teal.shade700
                                                : Colors.blue.shade700,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            request.requestType ==
                                                    RequestType.availability
                                                ? '${request.notifiedUserIds.length} notifiés'
                                                : 'Vague ${request.currentWave}',
                                            style: TextStyle(
                                              color:
                                                  request.requestType ==
                                                      RequestType.availability
                                                  ? Colors.teal.shade700
                                                  : Colors.blue.shade700,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 2),
                                          Icon(
                                            Icons.info_outline,
                                            size: 14,
                                            color:
                                                request.requestType ==
                                                    RequestType.availability
                                                ? Colors.teal.shade700
                                                : Colors.blue.shade700,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Bouton de suppression (uniquement pour leaders/admins)
                      if (canDelete) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                          onPressed: () => _deleteRequest(request),
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
                              'Du ${_formatDateTime(request.status == ReplacementRequestStatus.accepted && request.acceptedStartTime != null ? request.acceptedStartTime! : request.startTime)}',
                              style: const TextStyle(fontSize: 14),
                            ),
                            Text(
                              'Au ${_formatDateTime(request.status == ReplacementRequestStatus.accepted && request.acceptedEndTime != null ? request.acceptedEndTime! : request.endTime)}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Station et équipe
                  if (request.station.isNotEmpty || request.team != null) ...[
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
                        if (request.station.isNotEmpty && request.team != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '•',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                        if (request.team != null) ...[
                          Icon(
                            Icons.group,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Équipe ${request.team}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],

                  // Affichage du remplaçant trouvé (si accepté)
                  if (request.status == ReplacementRequestStatus.accepted &&
                      request.replacerId != null) ...[
                    const SizedBox(height: 12),
                    FutureBuilder<User?>(
                      future: _userRepository.getById(request.replacerId!),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const SizedBox.shrink();
                        }
                        final replacer = snapshot.data!;
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                request.requestType == RequestType.availability
                                ? Colors.blue.shade50
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  request.requestType ==
                                      RequestType.availability
                                  ? Colors.blue.shade200
                                  : Colors.green.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                request.requestType == RequestType.availability
                                    ? Icons.person_search
                                    : Icons.person_pin,
                                color:
                                    request.requestType ==
                                        RequestType.availability
                                    ? Colors.blue.shade700
                                    : Colors.green.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      request.requestType ==
                                              RequestType.availability
                                          ? 'Agent disponible :'
                                          : 'Remplaçant :',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            request.requestType ==
                                                RequestType.availability
                                            ? Colors.blue.shade700
                                            : Colors.green.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      replacer.displayName,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],

                  // Mention si l'utilisateur a une acceptation en attente de validation
                  if (hasPendingAcceptance) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 16,
                            color: Colors.green.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Votre acceptation est en attente de validation par le chef d\'équipe',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Mention si l'utilisateur a déjà refusé
                  if (hasDeclined) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Vous avez déjà décliné cette demande',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Phase 3 - Mention si l'utilisateur n'est pas notifié
                  if (!isNotified &&
                      request.status == ReplacementRequestStatus.pending &&
                      currentUser?.id != request.requesterId) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Vous pouvez voir cette demande mais vous n\'êtes pas encore notifié pour y répondre',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Bouton DEV uniquement : Passer à la vague suivante
                  if (kDebugMode &&
                      request.status == ReplacementRequestStatus.pending &&
                      request.requestType == RequestType.replacement) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _skipToNextWave(request),
                        icon: const Icon(Icons.fast_forward, size: 18),
                        label: const Text('DEV: Passer à la vague suivante'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Bouton d'action
                  SizedBox(
                    width: double.infinity,
                    child: request.status == ReplacementRequestStatus.accepted
                        ? FilledButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.check_circle, size: 18),
                            label: Text(
                              request.requestType == RequestType.availability
                                  ? 'Agent trouvé'
                                  : 'Remplacement accepté',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.grey,
                              disabledBackgroundColor: Colors.grey.shade300,
                            ),
                          )
                        : hasPendingAcceptance
                        ? FilledButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.schedule, size: 18),
                            label: const Text('En attente de validation'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              disabledBackgroundColor: Colors.green.shade300,
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: (canAccept && !hasDeclined)
                                ? () => _handleRequestTap(request)
                                : (hasDeclined
                                      ? () => _handleRequestTap(request)
                                      : null),
                            icon: const Icon(
                              Icons.visibility_outlined,
                              size: 18,
                            ),
                            label: const Text('Voir le remplacement'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: (canAccept && !hasDeclined)
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey,
                              side: BorderSide(
                                color: (canAccept && !hasDeclined)
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey.shade400,
                              ),
                              disabledForegroundColor: Colors.grey.shade400,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildManualProposalCard(
    ManualReplacementProposal proposal,
    ReplacementSubTab subTab,
  ) {
    final viewMode = _subTabToViewMode(subTab);

    // En mode "Mes demandes", le tap ouvre le BottomSheet d'actions
    VoidCallback? onTapCallback;
    if (viewMode == TileViewMode.myRequests) {
      onTapCallback = () => _showManualProposalActionsBottomSheet(proposal);
    }

    return ManualProposalTileWrapper(
      proposal: proposal,
      currentUserId: _currentUserId ?? '',
      viewMode: viewMode,
      station: _currentStationId,
      onTap: onTapCallback,
      onDelete: () => _deleteManualProposal(proposal),
      onAccept: () => _acceptManualProposal(proposal),
      onRefuse: () => _declineManualProposal(proposal),
      onResendNotifications: () => _resendManualProposalNotification(proposal),
    );
  }

  /// Affiche le BottomSheet d'actions pour une proposition de remplacement manuel
  Future<void> _showManualProposalActionsBottomSheet(
    ManualReplacementProposal proposal,
  ) async {
    // Résoudre le nom de la station et l'équipe (non stockée en Firestore)
    String stationName = _currentStationId ?? '';
    String? teamName = proposal.replacedTeam;

    final sdisId = SDISContext().currentSDISId;
    if (sdisId != null &&
        _currentStationId != null &&
        _currentStationId!.isNotEmpty) {
      stationName = await StationNameCache().getStationName(
        sdisId,
        _currentStationId!,
      );
    }

    // Charger l'équipe depuis le profil utilisateur si non disponible dans le document
    if (teamName == null && proposal.replacedId.isNotEmpty) {
      final user = await _userRepository.getById(proposal.replacedId);
      teamName = user?.team;
    }

    if (!mounted) return;

    RequestActionsBottomSheet.show(
      context: context,
      requestType: UnifiedRequestType.manualReplacement,
      initiatorName: proposal.replacedName,
      team: teamName,
      station: stationName,
      startTime: proposal.startTime,
      endTime: proposal.endTime,
      onResendNotifications: () => _resendManualProposalNotification(proposal),
      onDelete: () => _deleteManualProposal(proposal),
    );
  }

  /// Relance la notification pour une proposition de remplacement manuel
  Future<void> _resendManualProposalNotification(
    ManualReplacementProposal proposal,
  ) async {
    // TODO: Implémenter la logique de renotification pour les propositions manuelles
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notification de relance envoyée'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  // Ancienne méthode _buildManualProposalCard conservée temporairement pour référence
  Widget _buildManualProposalCardOld(ManualReplacementProposal proposal) {
    // Déterminer si l'utilisateur est le remplacé
    final bool isReplaced = proposal.replacedId == _currentUserId;
    // Déterminer si l'utilisateur est le remplaçant désigné
    final bool isDesignatedReplacer = proposal.replacerId == _currentUserId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => _handleManualProposalTap(proposal),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête avec badge "Proposition manuelle"
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: isReplaced ? Colors.green : Colors.purple,
                    radius: 20,
                    child: Icon(
                      isReplaced ? Icons.person_search : Icons.person_add,
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
                          proposal.proposerName,
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
                            color: isReplaced
                                ? Colors.green.shade100
                                : Colors.purple.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isReplaced
                                    ? Icons.check_circle
                                    : Icons.touch_app,
                                size: 14,
                                color: isReplaced
                                    ? Colors.green.shade700
                                    : Colors.purple.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isReplaced
                                    ? 'Remplacement proposé'
                                    : 'Proposition manuelle',
                                style: TextStyle(
                                  color: isReplaced
                                      ? Colors.green.shade700
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
                  ),
                  // Icône de suppression pour le propriétaire (remplacé)
                  if (isReplaced) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 20,
                      ),
                      onPressed: () => _deleteManualProposal(proposal),
                      tooltip: 'Supprimer la proposition',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Informations sur le remplacement
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isReplaced
                      ? Colors.green.shade50
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isReplaced
                        ? Colors.green.shade200
                        : Colors.blue.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.swap_horiz,
                          size: 16,
                          color: isReplaced
                              ? Colors.green.shade700
                              : Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isReplaced
                              ? '${proposal.replacerName} vous remplacera'
                              : 'Remplacer ${proposal.replacedName}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isReplaced
                                ? Colors.green.shade900
                                : Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

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
                          'Du ${_formatDateTime(proposal.startTime)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        Text(
                          'Au ${_formatDateTime(proposal.endTime)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Boutons d'action (uniquement pour le remplaçant désigné)
              // Convention UX : [ Refuser (gauche) ]  [ Accepter (droite) ]
              if (isDesignatedReplacer)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _declineManualProposal(proposal),
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
                      child: FilledButton.icon(
                        onPressed: () => _acceptManualProposal(proposal),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Accepter'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String> _getRequesterName(String userId) async {
    try {
      final user = await _userRepository.getById(userId);
      return user != null ? user.displayName : 'Agent $userId';
    } catch (e) {
      return 'Agent $userId';
    }
  }

  /// Gère le tap sur une proposition manuelle (actuellement ne fait rien)
  void _handleManualProposalTap(ManualReplacementProposal proposal) {
    // Optionnel : afficher un dialog avec plus de détails
  }

  /// Accepte une proposition de remplacement manuel
  Future<void> _acceptManualProposal(ManualReplacementProposal proposal) async {
    try {
      if (_currentStationId == null) {
        throw Exception('Station ID non disponible');
      }

      // Vérifier que c'est bien le remplaçant désigné qui accepte
      if (_currentUserId != proposal.replacerId) {
        throw Exception(
          'Seul le remplaçant désigné peut accepter cette proposition',
        );
      }

      final proposalsPath = _getManualReplacementProposalsPath(
        _currentStationId!,
      );
      debugPrint(
        '[DEBUG Manual Accept] Updating proposal at: $proposalsPath/${proposal.id}',
      );

      // Créer un document dans manualReplacementAcceptances (sous-collection du proposal)
      await FirebaseFirestore.instance
          .collection(proposalsPath)
          .doc(proposal.id)
          .collection('acceptances')
          .add({
            'proposalId': proposal.id,
            'replacerId': proposal.replacerId,
            'acceptedAt': FieldValue.serverTimestamp(),
          });

      // Mettre à jour le statut de la proposition
      await FirebaseFirestore.instance
          .collection(proposalsPath)
          .doc(proposal.id)
          .update({'status': 'accepted'});

      // IMPORTANT: Créer un Subshift pour que le remplacement apparaisse
      // dans la HomePage et la PlanningPage
      final subshiftId = 'manual_${proposal.id}';
      final subshift = Subshift(
        id: subshiftId,
        planningId: proposal.planningId,
        replacedId: proposal.replacedId,
        replacerId: proposal.replacerId,
        start: proposal.startTime,
        end: proposal.endTime,
      );

      debugPrint('[DEBUG Manual Accept] Creating subshift: $subshiftId');
      await SubshiftRepository().save(subshift, stationId: _currentStationId);
      debugPrint('[DEBUG Manual Accept] Subshift created successfully');

      // Mettre à jour planning.agents pour refléter le remplacement
      await ReplacementNotificationService.updatePlanningAgentsForReplacement(
        planningId: proposal.planningId,
        stationId: _currentStationId!,
        replacedId: proposal.replacedId,
        replacerId: proposal.replacerId,
        start: proposal.startTime,
        end: proposal.endTime,
      );

      debugPrint('[DEBUG Manual Accept] Proposal accepted successfully');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Proposition acceptée'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error accepting manual proposal: $e');
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

  /// Refuse une proposition de remplacement manuel
  Future<void> _declineManualProposal(
    ManualReplacementProposal proposal,
  ) async {
    try {
      if (_currentStationId == null) {
        throw Exception('Station ID non disponible');
      }

      // Vérifier que c'est bien le remplaçant désigné qui refuse
      if (_currentUserId != proposal.replacerId) {
        throw Exception(
          'Seul le remplaçant désigné peut refuser cette proposition',
        );
      }

      final proposalsPath = _getManualReplacementProposalsPath(
        _currentStationId!,
      );
      debugPrint(
        '[DEBUG Manual Decline] Declining proposal at: $proposalsPath/${proposal.id}',
      );

      // Mettre à jour le statut de la proposition
      await FirebaseFirestore.instance
          .collection(proposalsPath)
          .doc(proposal.id)
          .update({'status': 'declined'});

      debugPrint('[DEBUG Manual Decline] Proposal declined successfully');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Proposition refusée'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error declining manual proposal: $e');
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

  /// Supprime une proposition de remplacement manuel (par le propriétaire/remplacé)
  Future<void> _deleteManualProposal(ManualReplacementProposal proposal) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer la proposition ?"),
        content: const Text(
          "Cette action est irréversible. Voulez-vous vraiment supprimer cette proposition de remplacement ?",
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
        if (_currentStationId == null) {
          throw Exception('Station ID non disponible');
        }

        // Vérifier que c'est bien le propriétaire (remplacé) qui supprime
        if (_currentUserId != proposal.replacedId) {
          throw Exception('Seul le créateur de la demande peut la supprimer');
        }

        final proposalsPath = _getManualReplacementProposalsPath(
          _currentStationId!,
        );
        debugPrint(
          '[DEBUG Manual Delete] Deleting proposal at: $proposalsPath/${proposal.id}',
        );

        // Supprimer la proposition
        await FirebaseFirestore.instance
            .collection(proposalsPath)
            .doc(proposal.id)
            .delete();

        debugPrint('[DEBUG Manual Delete] Proposal deleted successfully');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Proposition supprimée'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error deleting manual proposal: $e');
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

  /// Vérifie si l'utilisateur courant peut voir cette demande
  /// Phase 3 - Visibilité étendue : Tous les agents de la station peuvent voir toutes les demandes
  Future<bool> _canViewRequest(ReplacementRequest request) async {
    if (_currentUserId == null) return false;

    try {
      // Récupérer l'utilisateur courant
      final currentUser = await UserStorageHelper.loadUser();
      if (currentUser == null) return false;

      // Phase 3 : TOUS les agents de la même station peuvent voir la demande
      // La station est stockée directement dans la demande
      if (request.station == currentUser.station) {
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Error checking view permission: $e');
      return false;
    }
  }

  /// Vérifie si l'utilisateur courant peut accepter cette demande
  Future<bool> _canAcceptRequest(ReplacementRequest request) async {
    if (_currentUserId == null) return false;
    if (request.status != ReplacementRequestStatus.pending) return false;

    try {
      // Seuls les utilisateurs de la vague en cours ou d'une vague passée peuvent accepter
      final notifiedUserIds = request.notifiedUserIds;
      return notifiedUserIds.contains(_currentUserId);
    } catch (e) {
      debugPrint('Error checking accept permission: $e');
      return false;
    }
  }

  /// Vérifie si l'utilisateur courant a refusé cette demande
  Future<bool> _hasUserDeclined(String requestId) async {
    if (_currentUserId == null) return false;

    try {
      final currentUser = await UserStorageHelper.loadUser();
      if (currentUser == null) return false;

      final declinesPath = EnvironmentConfig.getCollectionPath(
          'replacements/automatic/replacementRequestDeclines',
          currentUser.station);

      final snapshot = await FirebaseFirestore.instance
          .collection(declinesPath)
          .where('requestId', isEqualTo: requestId)
          .where('userId', isEqualTo: _currentUserId)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking decline status: $e');
      return false;
    }
  }

  /// Refuse une demande de remplacement directement depuis la tuile
  /// Enregistre le refus et met à jour la liste des refusés sur la demande
  Future<void> _declineReplacementRequest(ReplacementRequest request) async {
    if (_currentUserId == null || _currentStationId == null) return;

    try {
      final declinesPath = EnvironmentConfig.getCollectionPath(
          'replacements/automatic/replacementRequestDeclines',
          _currentStationId);
      final requestsPath = EnvironmentConfig.getCollectionPath(
          'replacements/automatic/replacementRequests', _currentStationId);

      // 1. Enregistrer le refus dans la collection des declines
      await FirebaseFirestore.instance.collection(declinesPath).add({
        'requestId': request.id,
        'userId': _currentUserId,
        'declinedAt': Timestamp.now(),
      });

      // 2. Mettre à jour declinedByUserIds sur la demande
      await FirebaseFirestore.instance
          .collection(requestsPath)
          .doc(request.id)
          .update({
            'declinedByUserIds': FieldValue.arrayUnion([_currentUserId]),
          });

      debugPrint(
        '✅ Decline recorded for request ${request.id} by user $_currentUserId',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demande de remplacement refusée'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error declining request: $e');
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

  /// Vérifie si l'utilisateur a une acceptation en attente de validation pour cette demande
  Future<bool> _hasUserPendingAcceptance(String requestId) async {
    if (_currentUserId == null) return false;

    try {
      final currentUser = await UserStorageHelper.loadUser();
      if (currentUser == null) return false;

      final acceptancesPath = EnvironmentConfig.getCollectionPath(
          'replacements/automatic/replacementAcceptances', currentUser.station);

      debugPrint(
        '🔍 [PENDING_ACCEPTANCE] Checking for user $_currentUserId on request $requestId at path: $acceptancesPath',
      );

      final snapshot = await FirebaseFirestore.instance
          .collection(acceptancesPath)
          .where('requestId', isEqualTo: requestId)
          .where('userId', isEqualTo: _currentUserId)
          .where('status', isEqualTo: 'pendingValidation')
          .limit(1)
          .get();

      final hasPending = snapshot.docs.isNotEmpty;
      debugPrint(
        '🔍 [PENDING_ACCEPTANCE] Found ${snapshot.docs.length} pending acceptance(s): $hasPending',
      );

      return hasPending;
    } catch (e) {
      debugPrint('Error checking pending acceptance: $e');
      return false;
    }
  }

  /// DEV uniquement : Passe à la vague suivante en simulant les Cloud Functions
  Future<void> _skipToNextWave(ReplacementRequest request) async {
    try {
      final currentUser = await UserStorageHelper.loadUser();
      if (currentUser == null) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⏳ Passage à la vague suivante...'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Simuler le passage à la vague suivante (DEV uniquement)
      await _notificationService.simulateNextWave(request.id, request.station);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Vague suivante traitée !'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error skipping to next wave: $e');
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

  Future<void> _handleRequestTap(ReplacementRequest request) async {
    if (_currentUserId == null) return;

    // Ouvrir le dialog de demande de remplacement
    final result = await showReplacementRequestDialog(
      context,
      requestId: request.id,
      currentUserId: _currentUserId!,
      stationId: request.station,
    );

    // Rafraîchir si nécessaire
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remplacement accepté'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Affiche le dialog avec les détails des vagues de notification
  Future<void> _showWaveDetailsDialog(ReplacementRequest request) async {
    try {
      // Récupérer le demandeur pour connaître ses compétences
      final requester = await _userRepository.getById(
        request.requesterId,
        stationId: request.station,
      );
      if (requester == null) return;

      // Récupérer tous les utilisateurs de la station (utiliser getByStation pour multi-SDIS)
      final allUsers = await _userRepository.getByStation(request.station);
      final stationUsers = allUsers
          .where((u) => u.id != request.requesterId)
          .toList();

      // Récupérer le planning pour exclure les agents en astreinte et connaître l'équipe
      final planningsPath = EnvironmentConfig.getCollectionPath(
        'plannings',
        request.station,
      );
      final planningDoc = await _notificationService.firestore
          .collection(planningsPath)
          .doc(request.planningId)
          .get();

      final agentsInPlanning = <String>[];
      String planningTeam = request.team ?? '';
      if (planningDoc.exists) {
        final data = planningDoc.data();
        agentsInPlanning.addAll(List<String>.from(data?['agentsId'] ?? []));
        planningTeam = data?['team'] as String? ?? request.team ?? '';
      }

      // Récupérer la configuration de la station pour déterminer le mode
      final stationsPath = EnvironmentConfig.stationsCollectionPath;
      final stationDoc = await _notificationService.firestore
          .collection(stationsPath)
          .doc(request.station)
          .get();

      ReplacementMode replacementMode = ReplacementMode.similarity;
      bool allowUnderQualified = false;
      if (stationDoc.exists) {
        final station = Station.fromJson({
          'id': stationDoc.id,
          ...stationDoc.data()!,
        });
        replacementMode = station.replacementMode;
        allowUnderQualified = station.allowUnderQualifiedAutoAcceptance;
      }

      final Map<int, List<User>> waveGroups = {};
      int maxWave = 5; // Par défaut pour le mode similarité

      // MODE SIMILARITÉ : Calculer les vagues selon les compétences
      final waveCalculationService = WaveCalculationService();

      // Calculer les poids de rareté des compétences
      final skillRarityWeights = waveCalculationService
          .calculateSkillRarityWeights(
            teamMembers: allUsers,
            requesterSkills: requester.skills,
          );

      // Calculer la vague de chaque candidat
      for (final user in stationUsers) {
        final wave = waveCalculationService.calculateWave(
          requester: requester,
          candidate: user,
          planningTeam: planningTeam,
          agentsInPlanning: agentsInPlanning,
          skillRarityWeights: skillRarityWeights,
        );
        waveGroups.putIfAbsent(wave, () => []).add(user);
      }

      // Trier chaque vague par nom
      waveGroups.forEach((wave, users) {
        users.sort((a, b) {
          final cmp = a.lastName.toLowerCase().compareTo(
            b.lastName.toLowerCase(),
          );
          return cmp != 0
              ? cmp
              : a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
        });
      });

      // Ajouter les vagues vides pour afficher toutes les vagues possibles
      for (int i = 0; i <= maxWave; i++) {
        waveGroups.putIfAbsent(i, () => []);
      }

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _WaveDetailsDialog(
          request: request,
          waveGroups: waveGroups,
          notifiedUserIds: request.notifiedUserIds,
          replacementMode: replacementMode,
          allowUnderQualified: allowUnderQualified,
          requester: requester,
          planningTeam: planningTeam,
          agentsInPlanning: agentsInPlanning,
        ),
      );
    } catch (e) {
      debugPrint('Error showing wave details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Marque une demande comme vue par l'utilisateur courant
  Future<void> _markRequestAsSeen(String requestId) async {
    if (_currentUserId == null) return;

    try {
      final path = _getCollectionPath();
      await _notificationService.firestore
          .collection(path)
          .doc(requestId)
          .update({
            'seenByUserIds': FieldValue.arrayUnion([_currentUserId]),
          });
      debugPrint(
        '[DEBUG] Marked request $requestId as seen by $_currentUserId',
      );
    } catch (e) {
      debugPrint('Error marking request as seen: $e');
    }
  }

  /// Affiche la liste des utilisateurs notifiés pour une demande de disponibilité
  Future<void> _showNotifiedUsersDialog(ReplacementRequest request) async {
    try {
      // Récupérer les utilisateurs notifiés
      final notifiedUsers = <User>[];
      for (final userId in request.notifiedUserIds) {
        final user = await _userRepository.getById(userId);
        if (user != null) {
          notifiedUsers.add(user);
        }
      }

      // Trier par nom
      notifiedUsers.sort((a, b) {
        final cmp = a.lastName.toLowerCase().compareTo(
          b.lastName.toLowerCase(),
        );
        return cmp != 0
            ? cmp
            : a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            title: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.people_outline_rounded,
                    size: 18,
                    color: Colors.purple.shade400,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(child: Text('Agents notifiés')),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: notifiedUsers.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'Aucun agent n\'a été notifié',
                          style: TextStyle(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: notifiedUsers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final user = notifiedUsers[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.04)
                                : Colors.purple.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.purple.withValues(
                                alpha: isDark ? 0.25 : 0.15,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.purple.withValues(
                                  alpha: isDark ? 0.25 : 0.15,
                                ),
                                child: Text(
                                  user.initials,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.purple.shade400,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.displayName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.group_rounded,
                                          size: 12,
                                          color: isDark
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Équipe ${user.team}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Colors.grey[400]
                                                : Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: KColors.appNameColor,
                ),
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      debugPrint('Error showing notified users: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Affiche le dialog de confirmation pour relancer les notifications
  /// Uniquement pour les demandes de remplacement automatique en vague 5
  Future<void> _showResendNotificationsDialog(
    ReplacementRequest request,
  ) async {
    // Vérifier que c'est bien une demande en vague 5
    if (request.currentWave != 5) {
      debugPrint(
        'Cannot resend notifications: not in wave 5 (current: ${request.currentWave})',
      );
      return;
    }

    // Calculer le nombre d'utilisateurs à relancer
    // Utilisateurs notifiés qui n'ont pas refusé (état "En attente" ou "Vu")
    final usersToNotify = request.notifiedUserIds
        .where((userId) => !request.declinedByUserIds.contains(userId))
        .toList();

    if (usersToNotify.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucun utilisateur à relancer'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Afficher le dialog de confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.notifications_active_rounded,
                  size: 18,
                  color: Colors.orange.shade400,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text('Relancer les notifications')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Voulez-vous relancer une notification à tous les agents qui n\'ont pas encore répondu ?',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: isDark ? 0.12 : 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.orange.withValues(
                      alpha: isDark ? 0.35 : 0.25,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.people_rounded,
                      color: Colors.orange.shade400,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${usersToNotify.length} agent${usersToNotify.length > 1 ? 's' : ''} ser${usersToNotify.length > 1 ? 'ont' : 'a'} notifié${usersToNotify.length > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.orange[300]
                            : Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Relancer'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    // Envoyer les notifications de relance
    try {
      await _resendNotificationsToUsers(request, usersToNotify);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Notifications relancées à ${usersToNotify.length} agent${usersToNotify.length > 1 ? 's' : ''}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error resending notifications: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la relance: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Envoie les notifications de relance aux utilisateurs spécifiés
  Future<void> _resendNotificationsToUsers(
    ReplacementRequest request,
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return;

    // Créer un trigger de notification pour la relance
    final notificationTriggersPath = EnvironmentConfig.getCollectionPath(
      'notificationTriggers',
      request.station,
    );

    // requesterName résolu par CF via décryptage
    await _notificationService.firestore
        .collection(notificationTriggersPath)
        .add({
          'type': 'replacement_reminder',
          'requestId': request.id,
          'requesterId': request.requesterId,
          'targetUserIds': userIds,
          'startTime': Timestamp.fromDate(request.startTime),
          'endTime': Timestamp.fromDate(request.endTime),
          'createdAt': FieldValue.serverTimestamp(),
          'processed': false,
        });

    debugPrint(
      '📨 Resent notifications to ${userIds.length} users for request ${request.id}',
    );
  }
}

/// Dialog d'acceptation d'une AgentQuery avec sélection de disponibilité.
/// Retourne true si l'utilisateur confirme, false/null sinon.
/// Structure identique à ReplacementRequestDialog.
class _AgentQueryAcceptDialog extends StatefulWidget {
  final AgentQuery query;
  final String stationName;
  final String team;
  final ValueChanged<DateTime> onStartChanged;
  final ValueChanged<DateTime> onEndChanged;

  const _AgentQueryAcceptDialog({
    required this.query,
    required this.stationName,
    required this.team,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  @override
  State<_AgentQueryAcceptDialog> createState() =>
      _AgentQueryAcceptDialogState();
}

class _AgentQueryAcceptDialogState extends State<_AgentQueryAcceptDialog> {
  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header — même structure que ReplacementRequestDialog
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context, false),
                  tooltip: 'Annuler',
                ),
                const Expanded(
                  child: Text(
                    'Recherche d\'un agent',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          // Contenu scrollable
          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Période demandée
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.blue.shade900
                            : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? Colors.blue.shade700
                              : Colors.blue.shade200,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16),
                              const SizedBox(width: 8),
                              const Text(
                                'Période:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('Du: '),
                              Text(
                                _fmt(widget.query.startTime),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Text('Au: '),
                              Text(
                                _fmt(widget.query.endTime),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Sélection disponibilité
                    AvailabilityPickerSection(
                      rangeStart: widget.query.startTime,
                      rangeEnd: widget.query.endTime,
                      onStartChanged: widget.onStartChanged,
                      onEndChanged: widget.onEndChanged,
                    ),
                    // Station
                    if (widget.stationName.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.stationName,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                    // Équipe
                    if (widget.team.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.group, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            'Équipe ${widget.team}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Boutons d'action — même style que ReplacementRequestDialog
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey.shade900
                  : Colors.grey.shade50,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade800
                      : Colors.grey.shade200,
                ),
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close, size: 20),
                    label: const Text('Annuler'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.check, size: 20),
                    label: const Text('Rejoindre'),
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget pour afficher les détails des vagues de notification
class _WaveDetailsDialog extends StatefulWidget {
  final ReplacementRequest request;
  final Map<int, List<User>> waveGroups;
  final List<String> notifiedUserIds;
  final ReplacementMode replacementMode;
  final bool allowUnderQualified;
  final User requester;
  final String planningTeam;
  final List<String> agentsInPlanning;

  const _WaveDetailsDialog({
    required this.request,
    required this.waveGroups,
    required this.notifiedUserIds,
    required this.replacementMode,
    required this.allowUnderQualified,
    required this.requester,
    required this.planningTeam,
    required this.agentsInPlanning,
  });

  @override
  State<_WaveDetailsDialog> createState() => _WaveDetailsDialogState();
}

class _WaveDetailsDialogState extends State<_WaveDetailsDialog> {
  final Set<int> _expandedWaves = {};
  Set<String> _declinedUserIds = {};
  Set<String> _validatedUserIds = {};

  @override
  void initState() {
    super.initState();
    _loadDeclines();
    _loadValidatedAcceptances();
  }

  Future<void> _loadDeclines() async {
    try {
      final currentUser = await UserStorageHelper.loadUser();
      if (currentUser == null) return;

      final declinesPath = EnvironmentConfig.getCollectionPath(
          'replacements/automatic/replacementRequestDeclines',
          currentUser.station);

      final snapshot = await FirebaseFirestore.instance
          .collection(declinesPath)
          .where('requestId', isEqualTo: widget.request.id)
          .get();

      if (mounted) {
        setState(() {
          _declinedUserIds = snapshot.docs
              .map((doc) => doc.data()['userId'] as String)
              .toSet();
        });
      }
    } catch (e) {
      debugPrint('Error loading declines: $e');
    }
  }

  Future<void> _loadValidatedAcceptances() async {
    try {
      final currentUser = await UserStorageHelper.loadUser();
      if (currentUser == null) return;

      final acceptancesPath = EnvironmentConfig.getCollectionPath(
          'replacements/automatic/replacementAcceptances', currentUser.station);

      final acceptancesSnapshot = await FirebaseFirestore.instance
          .collection(acceptancesPath)
          .where('requestId', isEqualTo: widget.request.id)
          .where('status', isEqualTo: 'validated')
          .get();

      final validatedFromAcceptances = acceptancesSnapshot.docs
          .map((doc) => doc.data()['userId'] as String)
          .toSet();

      // Charger les Subshifts pour trouver les acceptations automatiques
      final subshiftRepo = SubshiftRepository();
      final subshifts = await subshiftRepo.getByPlanningId(
        widget.request.planningId,
      );

      debugPrint(
        '🔍 [WaveDialog] Loading validated acceptances for request ${widget.request.id}',
      );
      debugPrint(
        '  Request period: ${widget.request.startTime} - ${widget.request.endTime}',
      );
      debugPrint('  Request requesterId: ${widget.request.requesterId}');
      debugPrint('  Found ${subshifts.length} subshifts for planning');

      // Identifier les utilisateurs qui ont accepté automatiquement pour cette demande
      final validatedFromSubshifts = <String>{};
      for (final subshift in subshifts) {
        debugPrint(
          '  Checking subshift: replacedId=${subshift.replacedId}, replacerId=${subshift.replacerId}, period=${subshift.start} - ${subshift.end}',
        );

        // Vérifier si le Subshift correspond à cette demande de remplacement
        // Le Subshift peut couvrir toute ou partie de la demande (acceptation partielle)
        final matchesReplacer =
            subshift.replacedId == widget.request.requesterId;
        final overlapsTime =
            subshift.start.isBefore(widget.request.endTime) &&
            subshift.end.isAfter(widget.request.startTime);

        debugPrint(
          '    matchesReplacer=$matchesReplacer, overlapsTime=$overlapsTime',
        );

        if (matchesReplacer && overlapsTime) {
          validatedFromSubshifts.add(subshift.replacerId);
          debugPrint('    ✅ Added to validated: ${subshift.replacerId}');
        }
      }

      debugPrint(
        '  Total validated from subshifts: ${validatedFromSubshifts.length}',
      );
      debugPrint('  Validated user IDs: $validatedFromSubshifts');

      if (mounted) {
        setState(() {
          // Combiner les deux sources de validation
          _validatedUserIds = {
            ...validatedFromAcceptances,
            ...validatedFromSubshifts,
          };
        });
      }
    } catch (e) {
      debugPrint('Error loading validated acceptances: $e');
    }
  }

  String _getWaveLabel(int wave) {
    // Mode similarité : utiliser les descriptions basées sur les compétences
    switch (wave) {
      case 0:
        return "Agents non-notifiés";
      case 1:
        return "Vague 1 : Équipe (hors astreinte)";
      case 2:
        return "Vague 2 : Compétences identiques";
      case 3:
        return "Vague 3 : Compétences très proches (80%+)";
      case 4:
        return "Vague 4 : Compétences proches (60%+)";
      case 5:
        return "Vague 5 : Autres agents";
      default:
        return "Vague $wave";
    }
  }

  /// Retourne le label de la sous-catégorie pour les agents non-notifiés
  String _getNonNotifiedCategoryLabel(NonNotifiedCategory category) {
    switch (category) {
      case NonNotifiedCategory.onDuty:
        return "Agents en astreinte";
      case NonNotifiedCategory.replacing:
        return "Agents remplaçants";
      case NonNotifiedCategory.underQualified:
        return "Agents sous-qualifiés";
      case NonNotifiedCategory.sickLeave:
        return "Agents en arrêt maladie";
      case NonNotifiedCategory.suspendedFromDuty:
        return "Agents suspendus";
    }
  }

  String _getWaveTimingInfo(int wave) {
    final currentWave = widget.request.currentWave;
    final lastWaveSentAt = widget.request.lastWaveSentAt;

    if (wave < currentWave) {
      // Vague déjà envoyée
      return "Déjà notifiés";
    } else if (wave == currentWave) {
      // Vague en cours
      if (lastWaveSentAt != null) {
        final elapsed = DateTime.now().difference(lastWaveSentAt);
        if (elapsed.inMinutes < 60) {
          return "Envoyé il y a ${elapsed.inMinutes} min";
        } else if (elapsed.inHours < 24) {
          return "Envoyé il y a ${elapsed.inHours}h";
        } else {
          return "Envoyé il y a ${elapsed.inDays}j";
        }
      }
      return "En cours d'envoi";
    } else {
      // Vague future
      if (lastWaveSentAt != null) {
        // Calculer le temps restant (délai par défaut: 30 min)
        const delayMinutes = 30;
        final nextWaveTime = lastWaveSentAt.add(
          const Duration(minutes: delayMinutes),
        );
        final remaining = nextWaveTime.difference(DateTime.now());

        if (remaining.isNegative) {
          return "En attente d'envoi";
        } else if (remaining.inMinutes < 60) {
          return "Dans ${remaining.inMinutes} min";
        } else if (remaining.inHours < 24) {
          return "Dans ${remaining.inHours}h";
        } else {
          return "Dans ${remaining.inDays}j";
        }
      }
      return "Non encore envoyé";
    }
  }

  Color _getWaveColor(int wave) {
    final currentWave = widget.request.currentWave;
    if (wave < currentWave) {
      return Colors.grey;
    } else if (wave == currentWave) {
      return Colors.green;
    } else {
      return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sortedWaves = widget.waveGroups.keys.toList()..sort();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Material(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                color: Colors.blue.shade700,
                child: Row(
                  children: [
                    const Icon(
                      Icons.waves_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Détails des vagues',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              // Liste
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: sortedWaves.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                  itemBuilder: (context, index) {
                    final wave = sortedWaves[index];
                    final users = widget.waveGroups[wave]!;
                    final isExpanded = _expandedWaves.contains(wave);
                    final waveColor = _getWaveColor(wave);
                    final timingInfo = _getWaveTimingInfo(wave);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedWaves.remove(wave);
                              } else {
                                _expandedWaves.add(wave);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  color: waveColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _getWaveLabel(wave),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: waveColor,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (wave != 0) ...[
                                        const SizedBox(height: 1),
                                        Text(
                                          timingInfo,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Colors.grey[400]
                                                : Colors.grey[600],
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: waveColor.withValues(
                                      alpha: isDark ? 0.2 : 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: waveColor.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    '${users.length}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: waveColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isExpanded)
                          wave == 0
                              ? _buildNonNotifiedUsersSection(users, isDark)
                              : Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    20,
                                    10,
                                  ),
                                  child: Column(
                                    children: users.map((user) {
                                      final isNotified = widget.notifiedUserIds
                                          .contains(user.id);
                                      final hasDeclined = _declinedUserIds
                                          .contains(user.id);
                                      final hasSeen = widget
                                          .request
                                          .seenByUserIds
                                          .contains(user.id);
                                      final isValidated =
                                          _validatedUserIds.contains(user.id) ||
                                          (widget.request.status ==
                                                  ReplacementRequestStatus
                                                      .accepted &&
                                              widget.request.replacerId ==
                                                  user.id);
                                      final isPendingValidation = widget
                                          .request
                                          .pendingValidationUserIds
                                          .contains(user.id);

                                      String statusLabel;
                                      Color statusColor;
                                      IconData statusIcon;

                                      if (hasDeclined) {
                                        statusLabel = 'Refusé';
                                        statusColor = Colors.red.shade400;
                                        statusIcon = Icons.cancel_rounded;
                                      } else if (isValidated) {
                                        statusLabel = 'Validé';
                                        statusColor = Colors.green.shade400;
                                        statusIcon = Icons.check_circle_rounded;
                                      } else if (isPendingValidation) {
                                        statusLabel = 'En attente valid.';
                                        statusColor = Colors.green.shade400;
                                        statusIcon = Icons.schedule_rounded;
                                      } else if (hasSeen) {
                                        statusLabel = 'Vu';
                                        statusColor = isDark
                                            ? Colors.grey[400]!
                                            : Colors.grey.shade600;
                                        statusIcon = Icons.visibility_rounded;
                                      } else if (isNotified) {
                                        statusLabel = 'En attente';
                                        statusColor = Colors.orange.shade400;
                                        statusIcon = Icons.schedule_rounded;
                                      } else {
                                        statusLabel = 'Non notifié';
                                        statusColor = isDark
                                            ? Colors.grey[500]!
                                            : Colors.grey.shade500;
                                        statusIcon =
                                            Icons.person_outline_rounded;
                                      }

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 3,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              statusIcon,
                                              size: 15,
                                              color: statusColor,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                user.displayName,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: hasDeclined
                                                      ? (isDark
                                                            ? Colors.grey[500]
                                                            : Colors
                                                                  .grey
                                                                  .shade500)
                                                      : null,
                                                  fontWeight:
                                                      isNotified ||
                                                          isValidated ||
                                                          isPendingValidation
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                  decoration: hasDeclined
                                                      ? TextDecoration
                                                            .lineThrough
                                                      : null,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(
                                                  alpha: isDark ? 0.18 : 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                statusLabel,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: statusColor,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Construit la section des agents non-notifiés avec sous-catégories
  Widget _buildNonNotifiedUsersSection(List<User> users, bool isDark) {
    final waveCalculationService = WaveCalculationService();

    // Grouper les utilisateurs par sous-catégorie
    final Map<NonNotifiedCategory, List<User>> categorizedUsers = {};

    for (final user in users) {
      final category = waveCalculationService.getNonNotifiedCategory(
        requester: widget.requester,
        candidate: user,
        planningTeam: widget.planningTeam,
        agentsInPlanning: widget.agentsInPlanning,
      );

      if (category != null) {
        categorizedUsers.putIfAbsent(category, () => []).add(user);
      }
    }

    // Trier les catégories par ordre : onDuty, replacing, underQualified, sickLeave, suspendedFromDuty
    final orderedCategories = [
      NonNotifiedCategory.onDuty,
      NonNotifiedCategory.replacing,
      NonNotifiedCategory.underQualified,
      NonNotifiedCategory.sickLeave,
      NonNotifiedCategory.suspendedFromDuty,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: orderedCategories
            .where((category) {
              return categorizedUsers.containsKey(category) &&
                  categorizedUsers[category]!.isNotEmpty;
            })
            .map((category) {
              final categoryUsers = categorizedUsers[category]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      _getNonNotifiedCategoryLabel(category),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey[400] : Colors.grey.shade600,
                      ),
                    ),
                  ),
                  ...categoryUsers.map((user) {
                    return Padding(
                      padding: const EdgeInsets.only(
                        left: 12,
                        top: 3,
                        bottom: 3,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 14,
                            color: isDark
                                ? Colors.grey[500]
                                : Colors.grey.shade500,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              user.displayName,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey.shade600,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.07)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Non notifié',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey.shade500,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              );
            })
            .toList(),
      ),
    );
  }
}
