import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/sdis_model.dart';
import 'package:nexshift_app/core/repositories/sdis_repository.dart';
import 'package:nexshift_app/core/services/preferences_service.dart';
import 'package:nexshift_app/features/auth/presentation/pages/login_page.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';

/// Page de sélection du SDIS
/// Première page de l'application, permet de choisir le SDIS avant le login
class SDISSelectionPage extends StatefulWidget {
  const SDISSelectionPage({super.key});

  @override
  State<SDISSelectionPage> createState() => _SDISSelectionPageState();
}

class _SDISSelectionPageState extends State<SDISSelectionPage> {
  final SDISRepository _sdisRepository = SDISRepository();
  final PreferencesService _preferencesService = PreferencesService();
  List<SDIS> _sdisList = [];
  bool _isLoading = true;
  String? _error;
  String? _lastSdisId;

  @override
  void initState() {
    super.initState();
    _loadSDIS();
  }

  Future<void> _loadSDIS() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Charger le dernier SDIS sélectionné et la liste des SDIS en parallèle
      final results = await Future.wait([
        _preferencesService.getLastSdisId(),
        _sdisRepository.getAllSDIS(),
      ]);

      final lastSdisId = results[0] as String?;
      final sdisList = results[1] as List<SDIS>;

      // Réorganiser la liste pour mettre le dernier SDIS en tête
      List<SDIS> reorderedList = [];
      if (lastSdisId != null) {
        final lastSdis = sdisList.where((s) => s.id == lastSdisId).firstOrNull;
        if (lastSdis != null) {
          reorderedList.add(lastSdis);
          reorderedList.addAll(sdisList.where((s) => s.id != lastSdisId));
        } else {
          reorderedList = sdisList;
        }
      } else {
        reorderedList = sdisList;
      }

      setState(() {
        _lastSdisId = lastSdisId;
        _sdisList = reorderedList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Erreur lors du chargement des SDIS: $e';
        _isLoading = false;
      });
    }
  }

  void _onSDISSelected(SDIS sdis) async {
    // Sauvegarder le SDIS sélectionné
    await _preferencesService.saveLastSdisId(sdis.id);

    // Naviguer vers la page de login avec le SDIS sélectionné
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LoginPage(chgtPw: false, sdisId: sdis.id),
        ),
      );
    }
  }

  /// Construit la liste des SDIS avec le dernier en tête si disponible
  List<Widget> _buildSDISList() {
    List<Widget> widgets = [];

    for (int i = 0; i < _sdisList.length; i++) {
      final sdis = _sdisList[i];
      final isLastSelected = _lastSdisId != null && sdis.id == _lastSdisId;

      // Ajouter la carte SDIS
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: _SDISCard(
            sdis: sdis,
            onTap: () => _onSDISSelected(sdis),
            isLastSelected: isLastSelected,
          ),
        ),
      );

      // Ajouter un divider après le premier élément si c'est le dernier sélectionné
      if (i == 0 && isLastSelected && _sdisList.length > 1) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                Expanded(child: Divider(color: Colors.grey[300])),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Text(
                    'Autres SDIS',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: Colors.grey[300])),
              ],
            ),
          ),
        );
      }
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HeroWidget(),

                  // Titre de sélection
                  Text(
                    'Sélectionnez votre SDIS',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Liste des SDIS ou chargement/erreur
                  if (_isLoading)
                    const CircularProgressIndicator()
                  else if (_error != null)
                    Column(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.red[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadSDIS,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    )
                  else if (_sdisList.isEmpty)
                    const Text(
                      'Aucun SDIS disponible',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    Column(
                      children: _buildSDISList(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SDISCard extends StatelessWidget {
  final SDIS sdis;
  final VoidCallback onTap;
  final bool isLastSelected;

  const _SDISCard({
    required this.sdis,
    required this.onTap,
    this.isLastSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isLastSelected ? 6 : 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isLastSelected
            ? BorderSide(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                width: 2,
              )
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              // Icône de département
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    sdis.id,
                    style: TextStyle(
                      fontSize: 24,
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            sdis.fullName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isLastSelected) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .primaryColor
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Récent',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Département ${sdis.name}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              // Icône de flèche
              Icon(Icons.arrow_forward_ios, size: 20, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
