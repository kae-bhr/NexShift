import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
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

    await UserStorageHelper.saveUser(loadedUser);
    debugPrint('🟣 [ENTER_APP] User saved to local storage');

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
