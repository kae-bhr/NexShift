import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/sdis_model.dart';
import 'package:nexshift_app/core/repositories/sdis_repository.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/auth/presentation/pages/create_account_page.dart';

/// Page de sélection du SDIS pour la création de compte
/// Permet de choisir le SDIS avant de créer un compte
class SDISSelectionForCreateAccountPage extends StatefulWidget {
  const SDISSelectionForCreateAccountPage({super.key});

  @override
  State<SDISSelectionForCreateAccountPage> createState() =>
      _SDISSelectionForCreateAccountPageState();
}

class _SDISSelectionForCreateAccountPageState
    extends State<SDISSelectionForCreateAccountPage> {
  final SDISRepository _sdisRepository = SDISRepository();
  List<SDIS> _sdisList = [];
  bool _isLoading = true;
  String? _error;

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

      final sdisList = await _sdisRepository.getAllSDIS();

      setState(() {
        _sdisList = sdisList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Erreur lors du chargement des SDIS: $e';
        _isLoading = false;
      });
    }
  }

  void _onSDISSelected(SDIS sdis) {
    // Naviguer vers la page de création de compte avec le SDIS sélectionné
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateAccountPage(sdisId: sdis.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => Navigator.pop(context),
          color: KColors.appNameColor,
        ),
        title: const Text('Sélection du SDIS'),
      ),
      body: SafeArea(
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
                const SizedBox(height: 8),
                const Text(
                  'Vous pourrez ensuite créer votre compte',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
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
                    children: _sdisList.map((sdis) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: _SDISCard(
                          sdis: sdis,
                          onTap: () => _onSDISSelected(sdis),
                        ),
                      );
                    }).toList(),
                  ),
              ],
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

  const _SDISCard({required this.sdis, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    Text(
                      sdis.fullName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
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
