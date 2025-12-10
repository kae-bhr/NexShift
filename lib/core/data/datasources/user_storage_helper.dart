import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';

/// Gère la persistance locale de l'utilisateur connecté
/// et synchronise avec le ValueNotifier [userNotifier].
class UserStorageHelper {
  // ---- Sauvegarde ----
  /// Sauvegarde l'utilisateur dans SharedPreferences
  /// NOTE: Ne met PAS à jour userNotifier - cela doit être fait par l'appelant
  /// pour contrôler l'ordre des mises à jour avec isUserAuthentifiedNotifier
  static Future<void> saveUser(User user) async {
    debugPrint('💾 [USER_STORAGE] saveUser() called for: ${user.firstName} ${user.lastName} (${user.station})');
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(user.toJson());
    await prefs.setString(KConstants.userKey, jsonString);
    debugPrint('💾 [USER_STORAGE] saveUser() - user saved to storage');
  }

  // ---- Chargement ----
  static Future<User?> loadUser() async {
    debugPrint('💾 [USER_STORAGE] loadUser() called');
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(KConstants.userKey);

    if (jsonString == null) {
      debugPrint('💾 [USER_STORAGE] loadUser() - no user in storage');
      return null;
    }
    try {
      final Map<String, dynamic> map = jsonDecode(jsonString);
      final user = User.fromJson(map);
      debugPrint('💾 [USER_STORAGE] loadUser() - found user: ${user.firstName} ${user.lastName} (${user.station})');
      debugPrint('💾 [USER_STORAGE] loadUser() - updating userNotifier');
      userNotifier.value = user;
      return user;
    } catch (e) {
      debugPrint('💾 [USER_STORAGE] Erreur de parsing utilisateur: $e');
      return null;
    }
  }

  // ---- Suppression ----
  static Future<void> clearUser() async {
    debugPrint('💾 [USER_STORAGE] clearUser() called');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(KConstants.userKey);
    debugPrint('💾 [USER_STORAGE] clearUser() - user removed from storage');
  }

  // ---- Vérifie si un user est stocké ----
  static Future<bool> hasUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(KConstants.userKey);
  }
}
