import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/sdis_model.dart';

/// Dialog de sélection du SDIS
/// Affiché au lancement de l'app pour choisir le SDIS avant le login
class SDISSelectionDialog extends StatelessWidget {
  final List<SDIS> sdisList;

  const SDISSelectionDialog({
    super.key,
    required this.sdisList,
  });

  /// Affiche le dialog et retourne le SDIS sélectionné
  static Future<SDIS?> show({
    required BuildContext context,
    required List<SDIS> sdisList,
  }) {
    return showDialog<SDIS>(
      context: context,
      barrierDismissible: false, // L'utilisateur doit choisir
      builder: (context) => SDISSelectionDialog(sdisList: sdisList),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.location_city, color: Colors.red),
          SizedBox(width: 12),
          Text('Sélectionnez votre SDIS'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: sdisList.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final sdis = sdisList[index];
            return _SDISCard(
              sdis: sdis,
              onTap: () => Navigator.of(context).pop(sdis),
            );
          },
        ),
      ),
    );
  }
}

class _SDISCard extends StatelessWidget {
  final SDIS sdis;
  final VoidCallback onTap;

  const _SDISCard({
    required this.sdis,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Icône de département
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    sdis.id,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Nom du SDIS
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sdis.fullName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Département ${sdis.name} (${sdis.id})',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              // Icône de flèche
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
}
