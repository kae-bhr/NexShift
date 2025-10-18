import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/app_shell/presentation/widgets/widget_tree.dart';
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

    // Gestion de l'accès à l'application
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WidgetTree()),
      (route) => false,
    );
  }
}
