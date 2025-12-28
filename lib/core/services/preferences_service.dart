import 'package:shared_preferences/shared_preferences.dart';

/// Service de gestion des préférences locales de l'application
class PreferencesService {
  static const String _keyLastSdisId = 'last_sdis_id';

  /// Sauvegarde le dernier SDIS sélectionné par l'utilisateur
  Future<void> saveLastSdisId(String sdisId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSdisId, sdisId);
  }

  /// Récupère le dernier SDIS sélectionné par l'utilisateur
  /// Retourne null si aucun SDIS n'a été sauvegardé
  Future<String?> getLastSdisId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSdisId);
  }

  /// Efface le dernier SDIS sauvegardé
  Future<void> clearLastSdisId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastSdisId);
  }
}
