import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/home/presentation/pages/home_page.dart';
import 'package:nexshift_app/features/planning/presentation/pages/planning_page.dart';
import 'package:nexshift_app/features/settings/presentation/pages/settings_page.dart';
import 'package:nexshift_app/features/settings/presentation/pages/admin_page.dart';
import 'package:nexshift_app/features/station/presentation/pages/station_shell_page.dart';
import 'package:nexshift_app/features/skills/presentation/pages/skills_page.dart';
import 'package:nexshift_app/features/app_shell/presentation/widgets/navbar_widget.dart';
import 'package:nexshift_app/features/teams/presentation/pages/team_page.dart';
import 'package:nexshift_app/features/availability/presentation/pages/add_availability_page.dart';
import 'package:nexshift_app/features/replacement/presentation/pages/replacement_requests_list_page.dart';
import 'package:nexshift_app/core/services/badge_count_service.dart';
import 'package:nexshift_app/core/services/subscription_service.dart';
import 'package:nexshift_app/core/services/cloud_functions_service.dart';

class WidgetTree extends StatefulWidget {
  const WidgetTree({super.key});

  @override
  State<WidgetTree> createState() => _WidgetTreeState();
}

class _WidgetTreeState extends State<WidgetTree> {
  late PageController _pageController;
  // Les pages sont créées dans le State et non plus comme variable globale,
  // pour éviter que HomePage/PlanningPage soient instanciées avant que
  // SDISContext et userNotifier soient restaurés au démarrage.
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    debugPrint('🏠 [WIDGET_TREE] initState() called');
    _pages = [HomePage(), PlanningPage()];
    _pageController = PageController(initialPage: selectedPageNotifier.value);
    // Sync PageView with notifier
    selectedPageNotifier.addListener(_onPageNotifierChanged);
    // Initialiser le BadgeCountService dès que l'utilisateur est disponible
    userNotifier.addListener(_onUserChanged);
    _initializeBadgeService();
  }

  void _onUserChanged() {
    _initializeBadgeService();
  }

  void _initializeBadgeService() {
    final user = userNotifier.value;
    if (user != null && user.id.isNotEmpty && user.station.isNotEmpty) {
      debugPrint(
        '🏠 [WIDGET_TREE] Initializing BadgeCountService for user ${user.id}',
      );
      BadgeCountService().initialize(user.id, user.station, user);
    }
  }

  @override
  void dispose() {
    selectedPageNotifier.removeListener(_onPageNotifierChanged);
    userNotifier.removeListener(_onUserChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onPageNotifierChanged() {
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        selectedPageNotifier.value,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onPageChanged(int index) {
    selectedPageNotifier.value = index;
  }

  Future<bool> _onWillPop() async {
    final shouldPop = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.exit_to_app,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Quitter l\'application',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Voulez-vous vraiment quitter NexShift ?',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200, width: 1),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Vos données seront sauvegardées',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.only(right: 16, bottom: 16, left: 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Rester', style: TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Quitter', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
    return shouldPop ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Row(
            children: [
              Image.asset(
                "assets/images/NexShift.png",
                width: MediaQuery.of(context).size.width * 0.3,
                fit: BoxFit.contain,
              ),
              Lottie.asset(
                "assets/lotties/animated_logo.json", // animated_logo
                fit: BoxFit.contain,
                width: MediaQuery.of(context).size.width * 0.12,
              ),
            ],
          ),
          toolbarHeight: 40,
          leading: DrawerButton(color: Theme.of(context).colorScheme.primary),
          actions: [
            // Bouton paramètres
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsPage()),
                );
              },
              icon: Icon(
                Icons.settings,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        drawer: ValueListenableBuilder(
          valueListenable: userNotifier,
          builder: (context, user, child) {
            debugPrint(
              '🎨 [DRAWER] Building drawer with user: ${user != null ? '${user.firstName} ${user.lastName} (id=${user.id})' : 'NULL'}',
            );
            return Drawer(
              child: Column(
                children: [
                  SizedBox(
                    height: 115.0,
                    child: DrawerHeader(
                      child: RichText(
                        textAlign: TextAlign.justify,
                        text: TextSpan(
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.tertiary,
                            fontSize: KTextStyle.descriptionTextStyle.fontSize,
                            fontFamily:
                                KTextStyle.descriptionTextStyle.fontFamily,
                          ),
                          children: [
                            const TextSpan(
                              text: 'Bonjour ',
                              style: TextStyle(fontWeight: FontWeight.w300),
                            ),
                            TextSpan(
                              text: user?.displayName ?? "",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SkillsPage(),
                            ),
                          );
                        },
                        child: ListTile(
                          minTileHeight: 0.0,
                          leading: Icon(
                            Icons.workspace_premium,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(
                            "Mes compétences",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.tertiary,
                              fontSize:
                                  KTextStyle.descriptionTextStyle.fontSize,
                              fontFamily:
                                  KTextStyle.descriptionTextStyle.fontFamily,
                              fontWeight:
                                  KTextStyle.descriptionTextStyle.fontWeight,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: user != null
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        TeamPage(teamId: user.team),
                                  ),
                                );
                              }
                            : null,
                        child: ListTile(
                          minTileHeight: 0.0,
                          leading: Icon(
                            Icons.group,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(
                            "Mon équipe",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.tertiary,
                              fontSize:
                                  KTextStyle.descriptionTextStyle.fontSize,
                              fontFamily:
                                  KTextStyle.descriptionTextStyle.fontFamily,
                              fontWeight:
                                  KTextStyle.descriptionTextStyle.fontWeight,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const StationShellPage(),
                            ),
                          );
                        },
                        child: ListTile(
                          minTileHeight: 0.0,
                          leading: Icon(
                            Icons.home_work,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(
                            "Ma caserne",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.tertiary,
                              fontSize:
                                  KTextStyle.descriptionTextStyle.fontSize,
                              fontFamily:
                                  KTextStyle.descriptionTextStyle.fontFamily,
                              fontWeight:
                                  KTextStyle.descriptionTextStyle.fontWeight,
                            ),
                          ),
                        ),
                      ),
                      // Administration - visible pour admins, chefs de centre et chefs de garde
                      if (user != null &&
                          (user.admin ||
                              user.status == KConstants.statusLeader))
                        FutureBuilder<int>(
                          future: CloudFunctionsService()
                              .getPendingMembershipRequestsCount(
                                stationId: user.station,
                              ),
                          builder: (context, snapshot) {
                            final pendingCount = snapshot.data ?? 0;
                            return TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const AdminPage(),
                                  ),
                                );
                              },
                              child: ListTile(
                                minTileHeight: 0.0,
                                leading: Badge(
                                  isLabelVisible: pendingCount > 0,
                                  label: Text('$pendingCount'),
                                  child: Icon(
                                    Icons.admin_panel_settings,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                                title: Text(
                                  "Administration",
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.tertiary,
                                    fontSize: KTextStyle
                                        .descriptionTextStyle
                                        .fontSize,
                                    fontFamily: KTextStyle
                                        .descriptionTextStyle
                                        .fontFamily,
                                    fontWeight: KTextStyle
                                        .descriptionTextStyle
                                        .fontWeight,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      // Utiliser le BadgeCountService pour les pastilles du drawer
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const ReplacementRequestsListPage(),
                            ),
                          );
                        },
                        child: ValueListenableBuilder<bool>(
                          valueListenable: BadgeCountService().hasReplacementPending,
                          builder: (context, hasReplacementPending, _) {
                            return ValueListenableBuilder<bool>(
                              valueListenable: BadgeCountService().hasExchangePending,
                              builder: (context, hasExchangePending, _) {
                                return ValueListenableBuilder<bool>(
                                  valueListenable: BadgeCountService().hasAgentQueryPending,
                                  builder: (context, hasAgentQueryPending, _) {
                                    return ValueListenableBuilder<bool>(
                                      valueListenable: BadgeCountService().hasExchangeNeedingSelection,
                                      builder: (context, hasExchangeNeedingSelection, _) {
                                        return ValueListenableBuilder<bool>(
                                          valueListenable: BadgeCountService().hasReplacementValidation,
                                          builder: (context, hasReplacementValidation, _) {
                                            return ValueListenableBuilder<bool>(
                                              valueListenable: BadgeCountService().hasExchangeValidation,
                                              builder: (context, hasExchangeValidation, _) {
                                                // Pastille 1 : appNameColor si n'importe quelle demande pending ou sélection à faire
                                                final hasPending =
                                                    hasReplacementPending ||
                                                    hasExchangePending ||
                                                    hasAgentQueryPending ||
                                                    hasExchangeNeedingSelection;
                                                // Pastille 2 : blue si validation en attente
                                                final hasValidation =
                                                    hasReplacementValidation ||
                                                    hasExchangeValidation;

                                                return ListTile(
                                                  minTileHeight: 0.0,
                                                  leading: Icon(
                                                    Icons.swap_horiz,
                                                    color: Theme.of(context).colorScheme.primary,
                                                  ),
                                                  title: Text(
                                                    "Demandes",
                                                    style: TextStyle(
                                                      color: Theme.of(context).colorScheme.tertiary,
                                                      fontSize: KTextStyle.descriptionTextStyle.fontSize,
                                                      fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
                                                      fontWeight: KTextStyle.descriptionTextStyle.fontWeight,
                                                    ),
                                                  ),
                                                  trailing: (!hasPending && !hasValidation)
                                                      ? const SizedBox.shrink()
                                                      : Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            // Pastille appNameColor : demandes en attente
                                                            if (hasPending)
                                                              Container(
                                                                width: 12,
                                                                height: 12,
                                                                decoration: BoxDecoration(
                                                                  color: KColors.appNameColor,
                                                                  shape: BoxShape.circle,
                                                                ),
                                                              ),
                                                            if (hasPending && hasValidation)
                                                              const SizedBox(width: 6),
                                                            // Pastille blue : validations en attente
                                                            if (hasValidation)
                                                              Container(
                                                                width: 12,
                                                                height: 12,
                                                                decoration: const BoxDecoration(
                                                                  color: Colors.blue,
                                                                  shape: BoxShape.circle,
                                                                ),
                                                              ),
                                                          ],
                                                        ),
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
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        body: Column(
          children: [
            const _SubscriptionBanner(),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                children: _pages,
              ),
            ),
          ],
        ),
        floatingActionButton: ValueListenableBuilder<int>(
          valueListenable: selectedPageNotifier,
          builder: (context, selectedPage, child) {
            // Afficher le FAB uniquement sur HomePage (0) et PlanningPage (1)
            if (selectedPage != 0 && selectedPage != 1) {
              return const SizedBox.shrink();
            }

            return FloatingActionButton.extended(
              backgroundColor: Theme.of(context).colorScheme.primary,
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddAvailabilityPage(),
                  ),
                );
                // Si une disponibilité a été ajoutée, on pourrait recharger les données ici
                if (result == true) {
                  // Notifier les pages pour qu'elles se rechargent
                  // Pour l'instant on ne fait rien, les pages se rechargeront d'elles-mêmes
                }
              },
              label: const Icon(Icons.volunteer_activism),
              tooltip: 'Ajouter une disponibilité',
            );
          },
        ),
        bottomNavigationBar: const NavbarWidget(),
      ),
    );
  }
}

/// Bannière affichée sous l'AppBar quand l'abonnement expire bientôt
class _SubscriptionBanner extends StatefulWidget {
  const _SubscriptionBanner();

  @override
  State<_SubscriptionBanner> createState() => _SubscriptionBannerState();
}

class _SubscriptionBannerState extends State<_SubscriptionBanner> {
  bool _collapsed = false;

  String _formatEndDate() {
    final endDate = SubscriptionService().endDateNotifier.value;
    if (endDate == null) return "Votre abonnement expire bientôt";
    final d = endDate.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return "Votre abonnement expire le $dd/$mm $hh:$min";
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SubscriptionStatus>(
      valueListenable: subscriptionStatusNotifier,
      builder: (context, status, _) {
        if (status != SubscriptionStatus.expiringSoon) {
          return const SizedBox.shrink();
        }

        if (_collapsed) {
          return GestureDetector(
            onTap: () => setState(() => _collapsed = false),
            child: SizedBox(
              width: double.infinity,
              height: 18,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Ligne horizontale orange
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: Container(height: 2, color: Colors.orange[700]),
                  ),
                  // Encart arrondi en bas à droite avec icône
                  Positioned(
                    right: 16,
                    top: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.orange[700],
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: const Icon(
                        Icons.timer_outlined,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return GestureDetector(
          onTap: () => setState(() => _collapsed = true),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            color: Colors.orange[700],
            child: Text(
              _formatEndDate(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }
}
