import 'package:flutter/material.dart';
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/services/firebase_auth_service.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/auth/presentation/pages/confirmation_page.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/enter_app_widget.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/password_strength_field_widget.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/snake_bar_widget.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/station_selection_dialog.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.chgtPw,
    this.sdisId,
  });

  final bool chgtPw;
  final String? sdisId; // ID du SDIS pour l'architecture multi-SDIS

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool isPasswordVisible = false;
  Icon passwordIcon = Icon(Icons.visibility_off);
  TextEditingController controllerId = TextEditingController();
  TextEditingController controllerPw = TextEditingController();

  @override
  void dispose() {
    controllerId.dispose();
    controllerPw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(title: "Connexion"),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              HeroWidget(),
              Text(
                widget.chgtPw
                    ? "Veuillez vous réauthentifier"
                    : "Insérez vos identifiants de connexion",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                  fontSize: KTextStyle.descriptionTextStyle.fontSize,
                  fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
                  fontWeight: KTextStyle.descriptionTextStyle.fontWeight,
                ),
              ),
              SizedBox(height: 10.0),
              TextField(
                controller: controllerId,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                  fontSize: KTextStyle.descriptionTextStyle.fontSize,
                  fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
                  fontWeight: KTextStyle.descriptionTextStyle.fontWeight,
                ),
                decoration: InputDecoration(
                  hintText: 'Matricule',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15.0),
                  ),
                  prefixIcon: const Icon(Icons.person, color: Colors.grey),
                ),
                onEditingComplete: () {
                  setState(() {});
                },
              ),
              SizedBox(height: 10.0),
              PasswordStrengthField(
                controller: controllerPw,
                hintText: 'Mot de passe',
                isVisible: isPasswordVisible,
                onToggle: () =>
                    setState(() => isPasswordVisible = !isPasswordVisible),
                showStrengthBar: false,
              ),
              SizedBox(height: 10.0),
              FilledButton(
                onPressed: () {
                  onLoginPressed();
                },
                style: FilledButton.styleFrom(
                  minimumSize: Size(double.infinity, 40.0),
                ),
                child: Text("Se connecter", style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void onLoginPressed() async {
    final id = controllerId.text.trim();
    final pw = controllerPw.text.trim();
    final colorScheme = Theme.of(context).colorScheme;

    if (id.isEmpty || pw.isEmpty) {
      SnakebarWidget.showSnackBar(
        context,
        'Veuillez remplir les deux champs.',
        colorScheme.error,
      );
      return;
    }

    final repo = LocalRepository();
    try {
      // Login with Firebase Auth - nouvelle version avec gestion multi-stations et multi-SDIS
      final authResult = await repo.loginWithStations(id, pw, sdisId: widget.sdisId);

      // Cas 1: Utilisateur avec une seule station
      if (authResult.hasSingleStation && authResult.user != null) {
        _navigateAfterLogin(authResult.user!.id);
        return;
      }

      // Cas 2: Utilisateur avec plusieurs stations - afficher le menu de sélection
      if (authResult.needsStationSelection && authResult.userStations != null) {
        if (!mounted) return;

        final selectedStation = await StationSelectionDialog.show(
          context: context,
          stations: authResult.userStations!.stations,
        );

        if (selectedStation != null) {
          // Charger le profil utilisateur pour la station sélectionnée
          final user = await repo.loadUserForStation(id, selectedStation);

          if (!mounted) return;

          if (user != null) {
            _navigateAfterLogin(user.id);
          } else {
            SnakebarWidget.showSnackBar(
              context,
              'Erreur lors du chargement du profil pour cette station.',
              colorScheme.error,
            );
          }
        }
        return;
      }

      // Cas imprévu
      SnakebarWidget.showSnackBar(
        context,
        'Erreur lors de la connexion.',
        colorScheme.error,
      );
    } on UserProfileNotFoundException catch (e) {
      // L'authentification a réussi mais pas de profil dans Firestore
      // Afficher popup pour créer le profil
      await _showCreateProfileDialog(e.matricule, pw);
      return;
    } catch (e) {
      controllerPw.clear();
      SnakebarWidget.showSnackBar(
        context,
        'Mot de passe erroné.',
        colorScheme.error,
      );
      return;
    }
  }

  /// Navigue vers la page appropriée après connexion
  void _navigateAfterLogin(String userId) {
    if (!widget.chgtPw) {
      EnterApp.build(context, userId);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => ConfirmationPage(id: userId),
        ),
        (route) => false,
      );
    }
  }

  Future<void> _showCreateProfileDialog(
    String matricule,
    String password,
  ) async {
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Créer votre profil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Votre compte existe mais votre profil n\'est pas encore configuré.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: firstNameController,
              decoration: const InputDecoration(
                labelText: 'Prénom',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lastNameController,
              decoration: const InputDecoration(
                labelText: 'Nom',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              final firstName = firstNameController.text.trim();
              final lastName = lastNameController.text.trim();

              if (firstName.isEmpty || lastName.isEmpty) {
                SnakebarWidget.showSnackBar(
                  context,
                  'Veuillez remplir tous les champs.',
                  Theme.of(context).colorScheme.error,
                );
                return;
              }

              Navigator.pop(context, true);
            },
            child: const Text('Créer le profil'),
          ),
        ],
      ),
    );

    if (result == true) {
      final firstName = firstNameController.text.trim();
      final lastName = lastNameController.text.trim();

      try {
        // Créer le profil utilisateur dans Firestore
        final authService = FirebaseAuthService();
        final user = await authService.createUserProfile(
          matricule: matricule,
          firstName: firstName,
          lastName: lastName,
        );

        // Connecter l'utilisateur
        if (!widget.chgtPw) {
          EnterApp.build(context, user.id);
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => ConfirmationPage(id: user.id),
            ),
            (route) => false,
          );
        }
      } catch (e) {
        SnakebarWidget.showSnackBar(
          context,
          'Erreur lors de la création du profil: $e',
          Theme.of(context).colorScheme.error,
        );
      }
    } else {
      // Déconnecter l'utilisateur si annulation
      final authService = FirebaseAuthService();
      await authService.signOut();
    }
  }
}
