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
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
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
    try {
      final teamRepo = TeamRepository();
      final truckRepo = TruckRepository();
      final userRepo = UserRepository();
      final positionRepo = PositionRepository();

      final currentUser = await UserStorageHelper.loadUser();
      final userStation = currentUser?.station ?? KConstants.station;

      // Filtrer toutes les données par station de l'utilisateur
      final users = await userRepo.getByStation(userStation);
      final teams = await teamRepo.getByStation(userStation);
      final trucks = await truckRepo.getByStation(userStation);
      final positions = currentUser != null
          ? await positionRepo.getPositionsByStation(currentUser.station).first
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
          _currentUser?.station ?? KConstants.station,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.primary),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.groups), text: 'Équipes'),
            Tab(icon: Icon(Icons.people), text: 'Agents'),
            Tab(icon: Icon(Icons.local_shipping), text: 'Véhicules'),
            Tab(icon: Icon(Icons.calendar_today), text: 'Astreintes'),
          ],
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
