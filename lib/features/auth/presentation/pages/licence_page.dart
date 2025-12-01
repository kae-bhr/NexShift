import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/repositories/auth_repository.dart';
import 'package:nexshift_app/features/auth/presentation/pages/licence_confirmation_page.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/snake_bar_widget.dart';

class LicencePage extends StatefulWidget {
  const LicencePage({super.key});

  @override
  State<LicencePage> createState() => _LicencePageState();
}

class _LicencePageState extends State<LicencePage> {
  bool isLicenceVisible = false;
  Icon licenceIcon = const Icon(Icons.visibility_off);
  TextEditingController controllerLicence = TextEditingController();
  bool _isLoading = false;
  final _authRepo = AuthRepository();

  @override
  void dispose() {
    controllerLicence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: "Licence"),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const HeroWidget(),
                  Text(
                    "Insérez votre licence",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.tertiary,
                      fontSize: KTextStyle.descriptionTextStyle.fontSize,
                      fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
                      fontWeight: KTextStyle.descriptionTextStyle.fontWeight,
                    ),
                  ),
                  const SizedBox(height: 10.0),
                  TextField(
                    controller: controllerLicence,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.tertiary,
                      fontSize: KTextStyle.descriptionTextStyle.fontSize,
                      fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
                      fontWeight: KTextStyle.descriptionTextStyle.fontWeight,
                    ),
                    obscureText: !isLicenceVisible,
                    decoration: InputDecoration(
                      hintText: 'Licence',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15.0),
                      ),
                      prefixIcon: const Icon(
                        Icons.shield_rounded,
                        color: Colors.grey,
                      ),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            isLicenceVisible = !isLicenceVisible;
                            if (isLicenceVisible) {
                              licenceIcon = const Icon(
                                Icons.visibility,
                                color: Colors.grey,
                              );
                            } else {
                              licenceIcon = const Icon(
                                Icons.visibility_off,
                                color: Colors.grey,
                              );
                            }
                          });
                        },
                        icon: licenceIcon,
                      ),
                    ),
                    onEditingComplete: () {
                      onLoginPressed();
                    },
                  ),
                  const SizedBox(height: 10.0),
                  FilledButton(
                    onPressed: _isLoading ? null : onLoginPressed,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 40.0),
                    ),
                    child: const Text("Valider la licence"),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  void onLoginPressed() async {
    final licence = controllerLicence.text.trim();
    final colorScheme = Theme.of(context).colorScheme;

    // Vérification que le champ n'est pas vide
    if (licence.isEmpty) {
      SnakebarWidget.showSnackBar(
        context,
        'Veuillez entrer un numéro de licence.',
        colorScheme.error,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Validation de la licence via Firebase/Firestore
      final auth = await _authRepo.getLicence(licence);

      if (auth == null) {
        // Licence non trouvée
        setState(() => _isLoading = false);
        if (!mounted) return;

        SnakebarWidget.showSnackBar(
          context,
          'Licence invalide ou inexistante.',
          colorScheme.error,
        );
        return;
      }

      // Vérifier si la licence a déjà été consommée
      if (auth.consumed) {
        setState(() => _isLoading = false);
        if (!mounted) return;

        SnakebarWidget.showSnackBar(
          context,
          'Cette licence a déjà été utilisée le ${_formatDate(auth.consumedAt)}.',
          colorScheme.error,
        );
        return;
      }

      // Licence valide et non consommée, redirection vers LicenceConfirmationPage
      setState(() => _isLoading = false);
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => LicenceConfirmationPage(
            licence: licence,
            auth: auth,
          ),
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;

      SnakebarWidget.showSnackBar(
        context,
        'Erreur lors de la validation de la licence: $e',
        colorScheme.error,
      );
    }
  }

  /// Formate une date pour affichage
  String _formatDate(DateTime? date) {
    if (date == null) return 'date inconnue';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
