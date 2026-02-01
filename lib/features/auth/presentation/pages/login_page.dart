import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/user_model.dart' as models;
import 'package:nexshift_app/core/presentation/widgets/hero_widget.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/services/firebase_auth_service.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/auth/presentation/pages/confirmation_page.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/presentation/pages/subscription_expired_page.dart';
import 'package:nexshift_app/core/services/subscription_service.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/enter_app_widget.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/password_strength_field_widget.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/snake_bar_widget.dart';
import 'package:nexshift_app/features/auth/presentation/widgets/station_selection_dialog.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/features/app_shell/presentation/widgets/widget_tree.dart';

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
      debugPrint('🔵 [LOGIN] Attempting login for matricule=$id');
      final authResult = await repo.loginWithStations(id, pw, sdisId: widget.sdisId);

      // Cas 1: Utilisateur avec une seule station
      if (authResult.hasSingleStation && authResult.user != null) {
        _navigateAfterLogin(authResult.user!.id, user: authResult.user);
        return;
      }

      // Cas 2: Utilisateur avec plusieurs stations - afficher le menu de sélection
      if (authResult.needsStationSelection && authResult.userStations != null) {
        if (!mounted) return;

        debugPrint('🔵 [LOGIN] Showing station selection dialog with ${authResult.userStations!.stations.length} stations: ${authResult.userStations!.stations}');

        final selectedStation = await StationSelectionDialog.show(
          context: context,
          stations: authResult.userStations!.stations,
        );

        debugPrint('🔵 [LOGIN] User selected station: $selectedStation');

        if (selectedStation != null) {
          debugPrint('🔵 [LOGIN] Loading user profile for matricule=$id, station=$selectedStation');

          // Charger le profil utilisateur pour la station sélectionnée
          final user = await repo.loadUserForStation(id, selectedStation);

          debugPrint('🔵 [LOGIN] User profile loaded: ${user != null ? 'SUCCESS (id=${user.id}, station=${user.station})' : 'NULL'}');

          if (!mounted) return;

          if (user != null) {
            debugPrint('🔵 [LOGIN] Calling _navigateAfterLogin with userId=${user.id} and user object');
            _navigateAfterLogin(user.id, user: user);
          } else {
            debugPrint('❌ [LOGIN] User is null, showing error');
            SnakebarWidget.showSnackBar(
              context,
              'Erreur lors du chargement du profil pour cette station.',
              colorScheme.error,
            );
          }
        } else {
          debugPrint('⚠️ [LOGIN] User cancelled station selection (selectedStation is null)');
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
  void _navigateAfterLogin(String userId, {models.User? user}) async {
    debugPrint('🟢 [LOGIN] _navigateAfterLogin called with userId=$userId, user=${user != null ? '${user.firstName} ${user.lastName} (${user.station})' : 'NULL'}, chgtPw=${widget.chgtPw}');

    if (widget.chgtPw) {
      // Pour le changement de mot de passe, on met à jour les notifiers puis on navigue
      debugPrint('🟢 [LOGIN] Calling EnterApp.build() for password change flow');
      await EnterApp.build(context, userId, user: user);
      debugPrint('🟢 [LOGIN] Navigating to ConfirmationPage');
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => ConfirmationPage(id: userId),
        ),
        (route) => false,
      );
    } else {
      // NOUVELLE STRATÉGIE: Navigation impérative pour forcer le changement de page
      // On met à jour les notifiers puis on fait un pushAndRemoveUntil vers WidgetTree

      debugPrint('🟢 [LOGIN] Updating notifiers');
      await EnterApp.build(context, userId, user: user);

      debugPrint('🟢 [LOGIN] Force navigation');
      if (!mounted) return;

      // Vérifier si l'abonnement est expiré avant de naviguer
      final Widget destination;
      if (subscriptionStatusNotifier.value == SubscriptionStatus.expired) {
        debugPrint('🟢 [LOGIN] Redirecting to SubscriptionExpiredPage');
        destination = const SubscriptionExpiredPage();
      } else {
        debugPrint('🟢 [LOGIN] Redirecting to WidgetTree');
        destination = const WidgetTree();
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => destination),
        (route) => false,
      );
    }
    debugPrint('🟢 [LOGIN] _navigateAfterLogin completed');
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
