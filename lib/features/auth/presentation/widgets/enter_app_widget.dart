import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/app_shell/presentation/widgets/widget_tree.dart';
import 'package:nexshift_app/features/auth/presentation/pages/profile_completion_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EnterApp {
  static void build(BuildContext context, String id) async {
    // Gestion du token d'authentification
    isUserAuthentifiedNotifier.value = true;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      KConstants.authentifiedKey,
      isUserAuthentifiedNotifier.value,
    );

    // Gestion de l'identification de l'utilisateur
    final repo = LocalRepository();
    final user = await repo.getUserProfile(id);
    userNotifier.value = user;
    await UserStorageHelper.saveUser(user);

    // Vérifier que le context est toujours monté
    if (!context.mounted) return;

    // Vérifier si le profil est complet
    if (_isProfileIncomplete(user)) {
      // Rediriger vers la page de complétion du profil
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileCompletionPage(user: user),
        ),
        (route) => false,
      );
    } else {
      // Gestion de l'accès à l'application
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WidgetTree()),
        (route) => false,
      );
    }
  }

  /// Vérifie si le profil utilisateur est incomplet
  static bool _isProfileIncomplete(user) {
    return user.firstName.isEmpty || user.lastName.isEmpty;
  }
}
