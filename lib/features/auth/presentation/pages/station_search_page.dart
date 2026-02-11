import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/station_repository.dart';
import 'package:nexshift_app/core/services/cloud_functions_service.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:nexshift_app/features/auth/presentation/pages/welcome_page.dart';
import 'package:nexshift_app/features/app_shell/presentation/widgets/widget_tree.dart';

/// Page de gestion des casernes
/// Accessible depuis :
/// - Première connexion (nouveau compte)
/// - Connexion sans acceptedStation
/// - Bouton "Changer de caserne" dans les paramètres
class StationSearchPage extends StatefulWidget {
  const StationSearchPage({super.key});

  @override
  State<StationSearchPage> createState() => _StationSearchPageState();
}

class _StationSearchPageState extends State<StationSearchPage> {
  final _searchController = TextEditingController();
  final _stationRepository = StationRepository();
  final _cloudFunctionsService = CloudFunctionsService();
  List<Station> _allStations = [];
  List<String> _acceptedStationIds = [];
  List<String> _pendingStationIds = [];
  bool _isLoading = true;
  bool _isActionInProgress = false;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase().trim();
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final sdisId = SDISContext().currentSDISId;
      if (sdisId == null) {
        throw Exception('SDIS non défini');
      }

      // Charger en parallèle les stations et les listes utilisateur
      final results = await Future.wait([
        _stationRepository.getAll(),
        _cloudFunctionsService.getUserStationLists(),
      ]);

      final stations = results[0] as List<Station>;
      final stationLists = results[1] as ({List<String> accepted, List<String> pending});

      setState(() {
        _allStations = stations;
        _acceptedStationIds = stationLists.accepted;
        _pendingStationIds = stationLists.pending;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Station> _getFilteredStations(List<Station> stations) {
    if (_searchQuery.isEmpty) return stations;
    return stations.where((station) {
      return station.name.toLowerCase().contains(_searchQuery) ||
          station.id.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  /// Stations acceptées (section haute)
  List<Station> get _acceptedStations {
    return _getFilteredStations(
      _allStations.where((s) => _acceptedStationIds.contains(s.id)).toList(),
    );
  }

  /// Autres stations du SDIS (section basse)
  List<Station> get _otherStations {
    return _getFilteredStations(
      _allStations.where((s) => !_acceptedStationIds.contains(s.id)).toList(),
    );
  }

  /// Rejoindre une station acceptée (changer de caserne active)
  Future<void> _joinStation(Station station) async {
    final user = userNotifier.value;
    if (user == null) return;

    // Si c'est déjà la station courante, ne rien faire
    if (user.station == station.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('C\'est déjà votre caserne actuelle')),
      );
      return;
    }

    setState(() => _isActionInProgress = true);

    try {
      final localRepo = LocalRepository();
      final newUser = await localRepo.loadUserForStation(user.id, station.id);

      if (!mounted) return;

      if (newUser != null) {
        await UserStorageHelper.saveUser(newUser);
        userNotifier.value = newUser;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Caserne changée vers ${station.name}'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WidgetTree()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors du chargement du profil pour cette station'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  /// Demander à rejoindre une station
  Future<void> _requestMembership(Station station) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Demande d\'adhésion'),
        content: Text(
          'Voulez-vous envoyer une demande d\'adhésion à la caserne ${station.name} ?\n\n'
          'Un administrateur devra approuver votre demande.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isActionInProgress = true);

    try {
      await _cloudFunctionsService.requestMembership(stationId: station.id);

      if (!mounted) return;

      // Mettre à jour localement la liste des pending
      setState(() {
        _pendingStationIds.add(station.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Demande envoyée à ${station.name}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _createStationWithCode() async {
    final codeController = TextEditingController();

    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Créer une nouvelle caserne'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Entrez le code d\'authentification fourni par NexShift pour créer votre caserne.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Code d\'authentification',
                hintText: 'Ex: CASERNE-XK7Y9',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
              textCapitalization: TextCapitalization.characters,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final code = codeController.text.trim();
              if (code.isNotEmpty) {
                Navigator.pop(context, code);
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    if (code == null || code.isEmpty) return;

    setState(() => _isActionInProgress = true);

    try {
      final creationResult = await _cloudFunctionsService.createStationWithCode(
        code: code,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Station "${creationResult.stationName}" créée avec succès !'),
          backgroundColor: Colors.green,
        ),
      );

      await firebase_auth.FirebaseAuth.instance.signOut();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const WelcomePage()),
        (route) => false,
      );

      Future.delayed(const Duration(milliseconds: 500), () {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Votre caserne a été créée avec succès ! '
                'Veuillez vous connecter pour y accéder.',
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 5),
            ),
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentStationId = userNotifier.value?.station;

    return Scaffold(
      appBar: CustomAppBar(title: "Gestion des casernes"),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isActionInProgress ? null : _createStationWithCode,
        backgroundColor: KColors.appNameColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_business),
        label: const Text('Créer une caserne'),
      ),
      body: Column(
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher par nom...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Contenu
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : _buildStationsList(currentStationId),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Widget _buildStationsList(String? currentStationId) {
    final accepted = _acceptedStations;
    final others = _otherStations;

    if (accepted.isEmpty && others.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty
                  ? 'Aucune caserne disponible'
                  : 'Aucune caserne trouvée',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Section: Mes casernes
        if (accepted.isNotEmpty) ...[
          _buildSectionHeader('Mes casernes', Icons.home, accepted.length),
          ...accepted.map((station) => _AcceptedStationCard(
                station: station,
                isCurrent: station.id == currentStationId,
                isLoading: _isActionInProgress,
                onJoin: () => _joinStation(station),
              )),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
        ],

        // Section: Autres casernes du SDIS
        if (others.isNotEmpty) ...[
          _buildSectionHeader('Autres casernes du SDIS', Icons.local_fire_department, others.length),
          ...others.map((station) => _OtherStationCard(
                station: station,
                isPending: _pendingStationIds.contains(station.id),
                isLoading: _isActionInProgress,
                onRequestMembership: () => _requestMembership(station),
              )),
        ],

        // Espace pour le FAB
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte pour une station acceptée (section "Mes casernes")
class _AcceptedStationCard extends StatelessWidget {
  final Station station;
  final bool isCurrent;
  final bool isLoading;
  final VoidCallback onJoin;

  const _AcceptedStationCard({
    required this.station,
    required this.isCurrent,
    required this.isLoading,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.local_fire_department,
                    color: Theme.of(context).primaryColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isCurrent)
                        Text(
                          'Caserne actuelle',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: isCurrent
                  ? FilledButton.tonal(
                      onPressed: null,
                      child: const Text('Caserne actuelle'),
                    )
                  : FilledButton.icon(
                      onPressed: isLoading ? null : onJoin,
                      icon: isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.login),
                      label: const Text('Rejoindre'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte pour une station non acceptée (section "Autres casernes")
class _OtherStationCard extends StatelessWidget {
  final Station station;
  final bool isPending;
  final bool isLoading;
  final VoidCallback onRequestMembership;

  const _OtherStationCard({
    required this.station,
    required this.isPending,
    required this.isLoading,
    required this.onRequestMembership,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.local_fire_department,
                    color: Colors.grey[600],
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    station.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: isPending
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: Icon(Icons.hourglass_top, color: Colors.orange[700]),
                      label: Text(
                        'Demande en attente',
                        style: TextStyle(color: Colors.orange[700]),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: isLoading ? null : onRequestMembership,
                      icon: isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: const Text('Demander à rejoindre'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
