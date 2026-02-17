import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/services/subscription_service.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EnterApp {
  static Future<void> build(BuildContext context, String id, {User? user}) async {
    debugPrint('🟣 [ENTER_APP] Starting EnterApp.build with userId=$id, user passed=${user != null}');

    // Gestion de l'identification de l'utilisateur
    User loadedUser;
    if (user != null) {
      // Utiliser le user déjà chargé (cas multi-station avec sélection)
      loadedUser = user;
      debugPrint('🟣 [ENTER_APP] Using pre-loaded user: ${user.firstName} ${user.lastName}, station=${user.station}');
    } else {
      // Charger le user depuis Firestore (cas connexion standard)
      final repo = LocalRepository();
      debugPrint('🟣 [ENTER_APP] Loading user profile...');
      loadedUser = await repo.getUserProfile(id);
      debugPrint('🟣 [ENTER_APP] User profile loaded: ${loadedUser.firstName} ${loadedUser.lastName}, station=${loadedUser.station}');
    }

    // Extraire le SDIS ID de l'email Firebase
    String? sdisId;
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser != null && firebaseUser.email != null) {
      final email = firebaseUser.email!;
      if (email.endsWith('@nexshift.app')) {
        final parts = email.split('@')[0].split('_');
        if (parts.isNotEmpty) {
          sdisId = parts[0];
          debugPrint('🟣 [ENTER_APP] Extracted SDIS ID from email: $sdisId');
        }
      }
    }

    // Vérifier l'abonnement de la caserne
    if (sdisId != null && loadedUser.station.isNotEmpty) {
      final subStatus = await SubscriptionService().checkOnce(
        sdisId,
        loadedUser.station,
      );
      debugPrint('🟣 [ENTER_APP] Subscription status: $subStatus');

      if (subStatus == SubscriptionStatus.expired) {
        debugPrint('🟣 [ENTER_APP] Subscription expired - blocking access');
        subscriptionStatusNotifier.value = subStatus;
        // On laisse passer : main.dart bloquera avec la page d'expiration
      }

      // Démarrer l'écoute en temps réel pour la bannière
      SubscriptionService().startListening(sdisId, loadedUser.station);
      subscriptionStatusNotifier.value = subStatus;
    }

    // Définir le contexte SDIS global pour que les repositories aient le bon chemin
    if (sdisId != null && sdisId.isNotEmpty) {
      SDISContext().setCurrentSDISId(sdisId);
    }

    // Sauvegarder l'utilisateur ET le SDIS ID
    await UserStorageHelper.saveUser(loadedUser, sdisId: sdisId);
    debugPrint('🟣 [ENTER_APP] User saved to local storage with SDIS ID: $sdisId');

    // Gestion du token d'authentification
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(KConstants.authentifiedKey, true);
    debugPrint('🟣 [ENTER_APP] Authentication key saved to SharedPreferences');

    // IMPORTANT: Mettre à jour isUserAuthentifiedNotifier AVANT userNotifier
    // pour éviter un rebuild intermédiaire qui naviguerait vers WelcomePage
    isUserAuthentifiedNotifier.value = true;
    debugPrint('🟣 [ENTER_APP] isUserAuthentifiedNotifier set to true');

    // Maintenant on peut mettre à jour le userNotifier
    // Le MaterialApp détectera ce changement et naviguera automatiquement
    // vers WidgetTree ou ProfileCompletionPage selon le profil
    userNotifier.value = loadedUser;
    debugPrint('🟣 [ENTER_APP] userNotifier.value updated');
    debugPrint('🟣 [ENTER_APP] EnterApp.build completed - MaterialApp should now navigate');
  }
}
