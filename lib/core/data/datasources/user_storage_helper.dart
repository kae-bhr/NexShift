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
  static Future<void> saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(user.toJson());
    await prefs.setString(KConstants.userKey, jsonString);
    userNotifier.value = user;
  }

  // ---- Chargement ----
  static Future<User?> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(KConstants.userKey);

    if (jsonString == null) return null;
    try {
      final Map<String, dynamic> map = jsonDecode(jsonString);
      final user = User.fromJson(map);
      userNotifier.value = user;
      return user;
    } catch (e) {
      debugPrint('Erreur de parsing utilisateur: $e');
      return null;
    }
  }

  // ---- Suppression ----
  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(KConstants.userKey);
  }

  // ---- Vérifie si un user est stocké ----
  static Future<bool> hasUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(KConstants.userKey);
  }
}
