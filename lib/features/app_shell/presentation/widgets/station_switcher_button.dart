import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/user_stations_repository.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/station_selection_dialog.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/snake_bar_widget.dart';

/// Bouton pour changer de station
/// Affiché uniquement si l'utilisateur appartient à plusieurs stations
class StationSwitcherButton extends StatefulWidget {
  const StationSwitcherButton({super.key});

  @override
  State<StationSwitcherButton> createState() => _StationSwitcherButtonState();
}

class _StationSwitcherButtonState extends State<StationSwitcherButton> {
  List<String>? _userStations;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserStations();
    userNotifier.addListener(_onUserChanged);
  }

  @override
  void dispose() {
    userNotifier.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    _loadUserStations();
  }

  Future<void> _loadUserStations() async {
    final user = userNotifier.value;
    if (user == null) {
      setState(() {
        _userStations = null;
        _isLoading = false;
      });
      return;
    }

    final userStationsRepo = UserStationsRepository();
    final userStations = await userStationsRepo.getUserStations(user.id);

    if (mounted) {
      setState(() {
        _userStations = userStations?.stations;
        _isLoading = false;
      });
    }
  }

  Future<void> _showStationSwitcher() async {
    if (_userStations == null || _userStations!.length < 2) {
      return;
    }

    if (!mounted) return;

    final selectedStation = await StationSelectionDialog.show(
      context: context,
      stations: _userStations!,
    );

    if (selectedStation == null || !mounted) return;

    // Charger le profil utilisateur pour la nouvelle station
    final user = userNotifier.value;
    if (user == null) return;

    final repo = LocalRepository();
    final newUser = await repo.loadUserForStation(user.id, selectedStation);

    if (!mounted) return;

    if (newUser != null) {
      // Mettre à jour l'utilisateur dans le storage et le notifier
      await UserStorageHelper.saveUser(newUser);
      userNotifier.value = newUser;

      if (!mounted) return;

      // Charger le nom de la station pour le message
      final sdisId = SDISContext().currentSDISId;
      final stationName = sdisId != null
          ? await StationNameCache().getStationName(sdisId, newUser.station)
          : newUser.station;

      if (!mounted) return;

      // Afficher un message de confirmation
      SnakebarWidget.showSnackBar(
        context,
        'Station changée: $stationName',
        Theme.of(context).colorScheme.primary,
      );
    } else {
      if (!mounted) return;

      SnakebarWidget.showSnackBar(
        context,
        'Erreur lors du changement de station',
        Theme.of(context).colorScheme.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ne rien afficher pendant le chargement
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    // Ne rien afficher si l'utilisateur n'a qu'une seule station
    if (_userStations == null || _userStations!.length < 2) {
      return const SizedBox.shrink();
    }

    // Afficher le bouton de changement de station
    return IconButton(
      onPressed: _showStationSwitcher,
      icon: Icon(
        Icons.swap_horiz,
        color: Theme.of(context).colorScheme.primary,
      ),
      tooltip: 'Changer de station',
    );
  }
}
