import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:nexshift_app/features/auth/presentation/pages/station_search_page.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/features/app_shell/presentation/widgets/widget_tree.dart';
import 'package:nexshift_app/core/services/cloud_functions_service.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';

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
                keyboardType: TextInputType.text,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                  fontSize: KTextStyle.descriptionTextStyle.fontSize,
                  fontFamily: KTextStyle.descriptionTextStyle.fontFamily,
                  fontWeight: KTextStyle.descriptionTextStyle.fontWeight,
                ),
                decoration: InputDecoration(
                  hintText: 'Matricule ou Email',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15.0),
                  ),
                  prefixIcon: Icon(
                    Icons.person,
                    color: Colors.grey,
                  ),
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
              SizedBox(height: 8.0),
              TextButton(
                onPressed: () => _showPasswordResetDialog(),
                child: Text(
                  'Mot de passe oublié ?',
                  style: TextStyle(fontSize: 14),
                ),
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
    final authService = FirebaseAuthService();

    try {
      late final AuthenticationResult authResult;

      // Détecter si c'est un matricule ou un email
      String emailToUse = id;

      if (!id.contains('@')) {
        // C'est un matricule, récupérer l'email
        debugPrint('🔵 [LOGIN] Attempting login for matricule=$id');

        final sdisId = widget.sdisId ?? SDISContext().currentSDISId;
        if (sdisId == null) {
          SnakebarWidget.showSnackBar(
            context,
            'SDIS non défini',
            colorScheme.error,
          );
          return;
        }

        // Vérifier le cache local d'abord
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = 'matricule_email_${sdisId}_$id';
        final cachedEmail = prefs.getString(cacheKey);

        String? email;
        if (cachedEmail != null) {
          debugPrint('⚡ [LOGIN] Email found in cache for matricule: $id');
          email = cachedEmail;
        } else {
          // Pas en cache, appeler la Cloud Function
          final cloudFunctions = CloudFunctionsService();
          try {
            email = await cloudFunctions.getEmailByMatricule(
              matricule: id,
              sdisId: sdisId,
            );
          } catch (e) {
            debugPrint('❌ [LOGIN] Error getting email by matricule: $e');

            if (!mounted) return;

            SnakebarWidget.showSnackBar(
              context,
              'Erreur lors de la recherche du matricule',
              colorScheme.error,
            );
            return;
          }
        }

        if (!mounted) return;

        if (email == null) {
          SnakebarWidget.showSnackBar(
            context,
            'Matricule non trouvé',
            colorScheme.error,
          );
          return;
        }

        // Sauvegarder dans le cache pour les prochaines connexions
        await prefs.setString(cacheKey, email);

        debugPrint('✅ [LOGIN] Email found for matricule: $email');
        emailToUse = email;
      } else {
        debugPrint('🔵 [LOGIN] Attempting email login for: $id');
      }

      // Se connecter avec l'email (récupéré ou fourni)
      try {
        authResult = await authService.signInWithRealEmail(
          email: emailToUse,
          password: pw,
        );
      } catch (e) {
        // Si credential invalide et qu'on utilisait un email du cache (connexion par matricule),
        // l'email a peut-être changé en base : vérifier et retenter avec l'email frais
        if (!id.contains('@')) {
          final sdisId = widget.sdisId ?? SDISContext().currentSDISId;
          if (sdisId != null) {
            final prefs = await SharedPreferences.getInstance();
            final cacheKey = 'matricule_email_${sdisId}_$id';
            final cachedEmail = prefs.getString(cacheKey);

            debugPrint('🔄 [LOGIN] Credential failed with cached email, fetching fresh email from server');
            final cloudFunctions = CloudFunctionsService();
            final freshEmail = await cloudFunctions.getEmailByMatricule(
              matricule: id,
              sdisId: sdisId,
            );

            if (freshEmail != null && freshEmail != cachedEmail) {
              debugPrint('🔄 [LOGIN] Email changed: $cachedEmail -> $freshEmail, retrying');
              await prefs.setString(cacheKey, freshEmail);
              emailToUse = freshEmail;
              authResult = await authService.signInWithRealEmail(
                email: emailToUse,
                password: pw,
              );
            } else {
              // L'email n'a pas changé, c'est bien un mauvais mot de passe
              rethrow;
            }
          } else {
            rethrow;
          }
        } else {
          rethrow;
        }
      }

      // Vérifier si l'utilisateur a des stations dans ses claims
      if (authResult.claims == null || authResult.claims!.stations.isEmpty) {
        // L'utilisateur n'a pas de station (nouveau compte sans affiliation)
        // Rediriger vers la page de recherche de caserne
        if (!mounted) return;
        debugPrint('🔵 [LOGIN] User has no stations, redirecting to StationSearchPage');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const StationSearchPage(),
          ),
        );
        return;
      }

      final claims = authResult.claims!;
      final currentUser = firebase_auth.FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        debugPrint('❌ [LOGIN] No Firebase user after authentication');
        return;
      }

      // Cas 1: Une seule station
      if (claims.stations.length == 1) {
        final stationId = claims.stations.keys.first;
        final user = await repo.loadUserByAuthUidForStation(
          currentUser.uid,
          claims.sdisId,
          stationId,
        );

        if (!mounted) return;

        if (user != null) {
          _navigateAfterLogin(user.id, user: user);
        } else {
          // Profil introuvable (ex: retiré de la caserne, claims pas encore rafraîchis)
          debugPrint('🔵 [LOGIN] Profile not found for station $stationId, redirecting to StationSearchPage');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const StationSearchPage(),
            ),
          );
        }
        return;
      }

      // Cas 2: Plusieurs stations
      if (!mounted) return;
      final selectedStation = await StationSelectionDialog.show(
        context: context,
        stations: claims.stations.keys.toList(),
      );

      if (selectedStation != null) {
        final user = await repo.loadUserByAuthUidForStation(
          currentUser.uid,
          claims.sdisId,
          selectedStation,
        );

        if (!mounted) return;

        if (user != null) {
          _navigateAfterLogin(user.id, user: user);
        } else {
          // Profil introuvable pour cette station, rediriger vers gestion des casernes
          debugPrint('🔵 [LOGIN] Profile not found for station $selectedStation, redirecting to StationSearchPage');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const StationSearchPage(),
            ),
          );
        }
      }
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

  /// Affiche un dialog pour réinitialiser le mot de passe
  Future<void> _showPasswordResetDialog() async {
    final emailController = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Réinitialiser le mot de passe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Entrez votre email professionnel pour recevoir un lien de réinitialisation.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email professionnel',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
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
              final email = emailController.text.trim();
              if (email.isNotEmpty && email.contains('@')) {
                Navigator.pop(context, email);
              } else {
                SnakebarWidget.showSnackBar(
                  context,
                  'Veuillez entrer une adresse email valide.',
                  colorScheme.error,
                );
              }
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final authService = FirebaseAuthService();
        await authService.sendPasswordResetEmailReal(result);

        if (!mounted) return;

        SnakebarWidget.showSnackBar(
          context,
          'Email de réinitialisation envoyé à $result',
          colorScheme.primary,
        );
      } catch (e) {
        if (!mounted) return;

        SnakebarWidget.showSnackBar(
          context,
          'Erreur: ${e.toString()}',
          colorScheme.error,
        );
      }
    }
  }
}
