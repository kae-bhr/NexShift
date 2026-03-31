import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/services/push_notification_service.dart';
import 'package:nexshift_app/core/services/local_reminder_service.dart';
import 'package:nexshift_app/core/services/subscription_service.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EnterApp {
  /// Restaure la session depuis le cache local au démarrage de l'app.
  /// Appelé uniquement si Firebase Auth a déjà un utilisateur courant.
  /// Retourne true si la restauration a réussi.
  static Future<bool> restore() async {
    debugPrint('🟣 [ENTER_APP] restore() called');

    // 1. Vérifier que Firebase Auth a bien un utilisateur courant
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      debugPrint('🟣 [ENTER_APP] restore() - no Firebase user, skipping');
      return false;
    }

    // 2. Résoudre le SDIS ID EN PREMIER (avant de toucher userNotifier)
    // Priorité : claims Firebase (source de vérité) > email @nexshift.app > cache SharedPreferences
    // Le cache peut être périmé (ex : SDIS ID 50 stocké alors que le vrai est 30).
    String? resolvedSdisId;

    // 2a. Claims Firebase (source de vérité)
    try {
      final tokenResult = await firebaseUser.getIdTokenResult();
      final claims = tokenResult.claims;
      if (claims != null && claims['sdisId'] is String) {
        final claimsSdisId = claims['sdisId'] as String;
        if (claimsSdisId.isNotEmpty) {
          resolvedSdisId = claimsSdisId;
          debugPrint('🟣 [ENTER_APP] restore() - SDIS ID from claims: $resolvedSdisId');
        }
      }
    } catch (e) {
      debugPrint('🟣 [ENTER_APP] restore() - failed to read Firebase claims: $e');
    }

    // 2b. Email @nexshift.app
    if (resolvedSdisId == null || resolvedSdisId.isEmpty) {
      final email = firebaseUser.email;
      if (email != null && email.endsWith('@nexshift.app')) {
        final parts = email.split('@')[0].split('_');
        if (parts.isNotEmpty && parts[0].isNotEmpty) {
          resolvedSdisId = parts[0];
          debugPrint('🟣 [ENTER_APP] restore() - SDIS ID from email: $resolvedSdisId');
        }
      }
    }

    // 2c. Cache SharedPreferences (fallback)
    if (resolvedSdisId == null || resolvedSdisId.isEmpty) {
      final cachedSdisId = await UserStorageHelper.loadSdisId();
      if (cachedSdisId != null && cachedSdisId.isNotEmpty) {
        resolvedSdisId = cachedSdisId;
        debugPrint('🟣 [ENTER_APP] restore() - SDIS ID from cache: $resolvedSdisId');
      }
    }

    if (resolvedSdisId != null && resolvedSdisId.isNotEmpty) {
      SDISContext().setCurrentSDISId(resolvedSdisId);
      // Mettre à jour le cache si la valeur a changé ou était absente
      await UserStorageHelper.saveSdisId(resolvedSdisId);
      debugPrint('🟣 [ENTER_APP] restore() - SDIS context set: $resolvedSdisId');
    } else {
      debugPrint('🟣 [ENTER_APP] restore() - could not resolve SDIS ID');
    }

    // 3. Lire le user en cache SANS appeler UserStorageHelper.loadUser()
    // car loadUser() met à jour userNotifier immédiatement, ce qui déclenche
    // HomePage._onUserChanged() avant que SDISContext soit prêt.
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(KConstants.userKey);
    if (jsonString == null) {
      debugPrint('🟣 [ENTER_APP] restore() - no cached user, skipping');
      return false;
    }
    late User cachedUser;
    try {
      cachedUser = User.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('🟣 [ENTER_APP] restore() - error parsing cached user: $e');
      return false;
    }
    debugPrint('🟣 [ENTER_APP] restore() - cached user found: ${cachedUser.firstName} ${cachedUser.lastName}');

    // 4. Relancer l'écoute abonnement
    final effectiveSdisId = SDISContext().currentSDISId;
    if (effectiveSdisId != null && effectiveSdisId.isNotEmpty && cachedUser.station.isNotEmpty) {
      final subStatus = await SubscriptionService().checkOnce(effectiveSdisId, cachedUser.station);
      subscriptionStatusNotifier.value = subStatus;
      SubscriptionService().startListening(effectiveSdisId, cachedUser.station);
      debugPrint('🟣 [ENTER_APP] restore() - subscription status: $subStatus');
    }

    // 5. Préchauffer le StationNameCache pour éviter l'affichage de l'ID brut
    if (effectiveSdisId != null && effectiveSdisId.isNotEmpty && cachedUser.station.isNotEmpty) {
      try {
        await StationNameCache().preload(effectiveSdisId, cachedUser.station);
        debugPrint('🟣 [ENTER_APP] restore() - station name preloaded');
      } catch (e) {
        debugPrint('🟣 [ENTER_APP] restore() - station name preload failed (non-blocking): $e');
      }
    }

    // 6. Mettre à jour les notifiers dans le bon ordre
    // SDISContext est déjà prêt → les listeners de userNotifier (HomePage._onUserChanged)
    // pourront charger les données correctement dès le premier appel.
    // isUserAuthentifiedNotifier AVANT userNotifier pour éviter un rebuild vers WelcomePage.
    isUserAuthentifiedNotifier.value = true;
    userNotifier.value = cachedUser;
    debugPrint('🟣 [ENTER_APP] restore() - notifiers updated');

    // 7. Sauvegarder le FCM token maintenant que le contexte SDIS est prêt
    if (cachedUser.authUid != null && cachedUser.authUid!.isNotEmpty) {
      try {
        await PushNotificationService().saveUserToken(cachedUser.id, authUid: cachedUser.authUid);
        debugPrint('🟣 [ENTER_APP] restore() - FCM token saved');
      } catch (e) {
        debugPrint('🟣 [ENTER_APP] restore() - FCM token save failed (non-blocking): $e');
      }
    }

    // 8. Planifier le rappel quotidien local
    try {
      await LocalReminderService().reschedule(cachedUser);
      debugPrint('🟣 [ENTER_APP] restore() - local reminder scheduled');
    } catch (e) {
      debugPrint('🟣 [ENTER_APP] restore() - local reminder scheduling failed (non-blocking): $e');
    }

    debugPrint('🟣 [ENTER_APP] restore() completed successfully');
    return true;
  }

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

    // Extraire le SDIS ID — priorité : email @nexshift.app > claims Firebase
    String? sdisId;
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      final email = firebaseUser.email;
      if (email != null && email.endsWith('@nexshift.app')) {
        final parts = email.split('@')[0].split('_');
        if (parts.isNotEmpty && parts[0].isNotEmpty) {
          sdisId = parts[0];
          debugPrint('🟣 [ENTER_APP] Extracted SDIS ID from email: $sdisId');
        }
      }

      // Fallback : lire les custom claims Firebase (ex : comptes test@test.fr)
      if (sdisId == null || sdisId.isEmpty) {
        try {
          final tokenResult = await firebaseUser.getIdTokenResult();
          final claims = tokenResult.claims;
          if (claims != null && claims['sdisId'] is String) {
            final claimsSdisId = claims['sdisId'] as String;
            if (claimsSdisId.isNotEmpty) {
              sdisId = claimsSdisId;
              debugPrint('🟣 [ENTER_APP] Extracted SDIS ID from claims: $sdisId');
            }
          }
        } catch (e) {
          debugPrint('🟣 [ENTER_APP] Failed to read Firebase claims for SDIS ID: $e');
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

    // Sauvegarder le token FCM maintenant que le contexte SDIS est prêt
    // (SDISContext configuré + stationId disponible)
    if (loadedUser.authUid != null && loadedUser.authUid!.isNotEmpty) {
      try {
        await PushNotificationService().saveUserToken(
          loadedUser.id,
          authUid: loadedUser.authUid,
        );
        debugPrint('🟣 [ENTER_APP] FCM token saved for user: ${loadedUser.id}');
      } catch (e) {
        debugPrint('🟣 [ENTER_APP] Failed to save FCM token (non-blocking): $e');
      }
    }

    // IMPORTANT: Mettre à jour isUserAuthentifiedNotifier AVANT userNotifier
    // pour éviter un rebuild intermédiaire qui naviguerait vers WelcomePage
    isUserAuthentifiedNotifier.value = true;
    debugPrint('🟣 [ENTER_APP] isUserAuthentifiedNotifier set to true');

    // Maintenant on peut mettre à jour le userNotifier
    // Le MaterialApp détectera ce changement et naviguera automatiquement
    // vers WidgetTree ou ProfileCompletionPage selon le profil
    userNotifier.value = loadedUser;
    debugPrint('🟣 [ENTER_APP] userNotifier.value updated');

    // Planifier le rappel quotidien local
    try {
      await LocalReminderService().reschedule(loadedUser);
      debugPrint('🟣 [ENTER_APP] build() - local reminder scheduled');
    } catch (e) {
      debugPrint('🟣 [ENTER_APP] build() - local reminder scheduling failed (non-blocking): $e');
    }

    debugPrint('🟣 [ENTER_APP] EnterApp.build completed - MaterialApp should now navigate');
  }
}
