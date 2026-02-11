import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/core/presentation/pages/terms_of_service_page.dart';
import 'package:nexshift_app/core/utils/constants.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  void _copyEmail(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: 'bhr.holzer@gmail.com'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Email copié dans le presse-papier'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: "À propos de NexShift",
        bottomColor: KColors.appNameColor,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          // Logo et version
          HeroWidget(),
          Center(
            child: Text(
              "Version 1.0.0",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 30),

          // Description de l'application
          _buildCard(
            context,
            icon: Icons.info_outline,
            title: "Présentation",
            content: [
              "NexShift est une application de gestion des plannings d'astreinte "
                  "développée spécifiquement pour les centres de secours et casernes de pompiers.",
              "",
              "Elle permet de gérer efficacement les effectifs, les compétences, "
                  "la composition des équipages et l'organisation des remplacements, "
                  "tout en garantissant le respect des normes réglementaires.",
            ],
          ),

          // Fonctionnalités principales
          _buildCard(
            context,
            icon: Icons.featured_play_list_outlined,
            title: "Fonctionnalités",
            content: [],
            customChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFeatureItem(
                  Icons.calendar_today,
                  "Gestion des plannings d'astreinte",
                ),
                _buildFeatureItem(Icons.people, "Visualisation des effectifs"),
                _buildFeatureItem(
                  Icons.swap_horiz,
                  "Organisation des remplacements",
                ),
                _buildFeatureItem(
                  Icons.local_fire_department,
                  "Composition des équipages",
                ),
                _buildFeatureItem(Icons.verified_user, "Suivi des compétences"),
                _buildFeatureItem(Icons.analytics, "Statistiques et analyses"),
              ],
            ),
          ),

          // Mentions légales
          _buildCard(
            context,
            icon: Icons.business,
            title: "Mentions légales",
            content: [
              "Éditeur : BHR",
              "Responsable : Benjamin HOLZER",
              "Adresse : 3 rue des Bouleaux",
              "50630 QUETTEHOU",
              "SIRET : 982 291 874",
              "",
              "Hébergement : Firebase (Google Cloud Platform)",
            ],
          ),

          // Contact
          _buildCard(
            context,
            icon: Icons.mail_outline,
            title: "Contact",
            content: ["Pour toute question, suggestion ou assistance :"],
            customChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: () => _copyEmail(context),
                icon: const Icon(Icons.email),
                label: const Text("bhr.holzer@gmail.com"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KColors.appNameColor,
                  side: BorderSide(color: KColors.appNameColor),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),

          // CGU
          _buildCard(
            context,
            icon: Icons.description_outlined,
            title: "Conditions Générales d'Utilisation",
            content: [
              "Consultez les CGU pour en savoir plus sur l'utilisation de l'application, "
                  "la protection des données et vos droits.",
            ],
            customChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TermsOfServicePage(),
                    ),
                  );
                },
                icon: const Icon(Icons.arrow_forward),
                label: const Text("Lire les CGU"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KColors.appNameColor,
                  side: BorderSide(color: KColors.appNameColor),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),

          // Licence et copyright
          _buildCard(
            context,
            icon: Icons.copyright,
            title: "Propriété intellectuelle",
            content: [
              "© 2025 BHR - Benjamin HOLZER",
              "Tous droits réservés.",
              "",
              "NexShift est une application propriétaire.\nAucun droit n'est transféré à l'utilisateur autre que celui d'exécuter l'application dans le cadre prévu par son usage normal.",
            ],
          ),

          // Licence d'utilisation
          _buildCard(
            context,
            icon: Icons.card_membership,
            title: "Licence d'utilisation",
            content: [
              "NexShift est disponible sous licence annuelle payante pour les centres de secours.",
              "",
              "L'application est gratuite, seule la licence d'utilisation annuelle est payante.",
            ],
          ),

          const SizedBox(height: 20),

          // Footer
          Center(
            child: Column(
              children: [
                Text(
                  "NexShift - L'avenir de la gestion d'astreinte",
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<String> content,
    Widget? customChild,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: KColors.appNameColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: KColors.appNameColor,
                    ),
                  ),
                ),
              ],
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...content.map((line) {
                if (line.isEmpty) {
                  return const SizedBox(height: 8);
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.tertiary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.justify,
                  ),
                );
              }).toList(),
            ],
            if (customChild != null) customChild,
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: KColors.appNameColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
