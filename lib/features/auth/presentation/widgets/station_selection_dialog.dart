import 'package:flutter/material.dart';

/// Dialog pour permettre à l'utilisateur de choisir sa station
/// Affiché quand un utilisateur appartient à plusieurs stations
class StationSelectionDialog extends StatelessWidget {
  final List<String> stations;
  final Function(String) onStationSelected;

  const StationSelectionDialog({
    super.key,
    required this.stations,
    required this.onStationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Titre
            const Text(
              'Sélectionner votre station',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Vous êtes affecté(e) à plusieurs stations.\nChoisissez celle que vous souhaitez utiliser.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Liste des stations
            ...stations.map((station) => _buildStationCard(context, station)),

            const SizedBox(height: 16),

            // Bouton annuler
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationCard(BuildContext context, String station) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          onStationSelected(station);
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Icône de caserne
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
              const SizedBox(width: 16),

              // Nom de la station
              Expanded(
                child: Text(
                  station,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              // Icône flèche
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Méthode statique pour afficher le dialog facilement
  static Future<String?> show({
    required BuildContext context,
    required List<String> stations,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false, // L'utilisateur doit choisir
      builder: (context) => StationSelectionDialog(
        stations: stations,
        onStationSelected: (station) {
          Navigator.of(context).pop(station);
        },
      ),
    );
  }
}
