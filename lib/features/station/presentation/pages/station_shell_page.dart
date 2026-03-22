import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/data/models/trucks_model.dart';
import 'package:nexshift_app/core/data/models/position_model.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/repositories/truck_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/repositories/position_repository.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/features/station/presentation/pages/agents_tab_page.dart';
import 'package:nexshift_app/features/station/presentation/pages/teams_tab_page.dart';
import 'package:nexshift_app/features/station/presentation/pages/vehicles_tab_page.dart';
import 'package:nexshift_app/features/station/presentation/pages/planning_tab_page.dart';

/// Station management shell page with tabs for Agents, Teams, Vehicles, and Planning
class StationShellPage extends StatefulWidget {
  const StationShellPage({super.key});

  @override
  State<StationShellPage> createState() => _StationShellPageState();
}

class _StationShellPageState extends State<StationShellPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  User? _currentUser;
  String? _stationName;

  // Data
  List<User> _allUsers = [];
  List<Team> _allTeams = [];
  List<Truck> _allTrucks = [];
  List<Position> _allPositions = [];
  Map<String, List<User>> _usersByTeam = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    UserRepository.invalidateCache();
    try {
      final teamRepo = TeamRepository();
      final truckRepo = TruckRepository();
      final userRepo = UserRepository();
      final positionRepo = PositionRepository();

      final currentUser = await UserStorageHelper.loadUser();
      final userStation = currentUser?.station ?? KConstants.station;

      // Charger le nom de la station
      String? stationName;
      if (currentUser != null) {
        await SDISContext().ensureInitialized();
        final sdisId = SDISContext().currentSDISId;
        if (sdisId != null) {
          stationName = await StationNameCache().getStationName(sdisId, currentUser.station);
        }
      }

      // Filtrer toutes les données par station de l'utilisateur
      final users = await userRepo.getByStation(userStation);
      final teams = await teamRepo.getByStation(userStation);
      final trucks = await truckRepo.getByStation(userStation);
      final positions = currentUser != null
          ? await positionRepo
              .getPositionsByStation(currentUser.station)
              .first
              .catchError((_) => <Position>[])
          : <Position>[];

      // Group users by team
      final Map<String, List<User>> usersByTeam = {};

      for (final user in users) {
        // Only group users that have a team defined in the teams list
        if (teams.any((t) => t.id == user.team)) {
          usersByTeam.putIfAbsent(user.team, () => []).add(user);
        }
      }

      setState(() {
        _currentUser = currentUser;
        _stationName = stationName;
        _allUsers = users;
        _allTeams = teams;
        _allTrucks = trucks;
        _allPositions = positions;
        _usersByTeam = usersByTeam;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur de chargement: $e')));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _stationName ?? _currentUser?.station ?? KConstants.station,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        toolbarHeight: 40,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.primary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _StationExpandingTabBar(
            controller: _tabController,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                TeamsTabPage(
                  allUsers: _allUsers,
                  allTeams: _allTeams,
                  usersByTeam: _usersByTeam,
                  currentUser: _currentUser,
                  onDataChanged: _loadData,
                ),
                AgentsTabPage(
                  allUsers: _allUsers,
                  allTeams: _allTeams,
                  usersByTeam: _usersByTeam,
                  currentUser: _currentUser,
                  onDataChanged: _loadData,
                  allPositions: _allPositions,
                ),
                VehiclesTabPage(
                  allTrucks: _allTrucks,
                  currentUser: _currentUser,
                  onDataChanged: _loadData,
                ),
                const PlanningTabPage(),
              ],
            ),
    );
  }
}

class _StationExpandingTabBar extends StatelessWidget {
  final TabController controller;
  final Color color;

  static const _tabs = [
    (icon: Icons.groups, label: 'Équipes'),
    (icon: Icons.people, label: 'Agents'),
    (icon: Icons.local_shipping, label: 'Véhicules'),
    (icon: Icons.calendar_today, label: 'Astreintes'),
  ];

  const _StationExpandingTabBar({
    required this.controller,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final n = _tabs.length;
    const collapsedRatio = 1.0;
    const expandedRatio = 3.0;

    return AnimatedBuilder(
      animation: controller.animation!,
      builder: (context, _) {
        final animValue = controller.animation!.value;
        final fractions = List.generate(n, (i) =>
          (1.0 - (animValue - i).abs()).clamp(0.0, 1.0));
        final widths = fractions.map((f) =>
          collapsedRatio + f * (expandedRatio - collapsedRatio)).toList();
        final totalParts = widths.fold(0.0, (a, b) => a + b);
        final inactiveColor = color.withValues(alpha: 0.45);

        return SizedBox(
          width: screenWidth,
          height: 48,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(n, (i) {
                    final tab = _tabs[i];
                    final fraction = fractions[i];
                    final tabWidth = (widths[i] / totalParts) * screenWidth;
                    final iconColor = Color.lerp(inactiveColor, color, fraction)!;

                    return SizedBox(
                      width: tabWidth,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => controller.animateTo(i),
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            // Indicateur bas
                            Positioned(
                              bottom: 0,
                              left: 6,
                              right: 6,
                              child: Container(
                                height: 2.5,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: fraction),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            // Icône + label
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(tab.icon, size: 20, color: iconColor),
                                ClipRect(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: fraction,
                                    child: Opacity(
                                      opacity: fraction,
                                      child: Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Text(
                                          tab.label,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: color,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.clip,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
              Container(
                height: 1.5,
                color: color.withValues(alpha: 0.15),
              ),
            ],
          ),
        );
      },
    );
  }
}
