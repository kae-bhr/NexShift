import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service de gestion des préférences locales de l'application
class PreferencesService {
  static const String _keyLastSdisId = 'last_sdis_id';
  static const String _keyPresenceViewMode = 'presence_view_mode';

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

  /// Sauvegarde le mode de vue de la section présence (chronologique / personnel)
  Future<void> savePresenceViewMode(PresenceViewMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPresenceViewMode, mode.name);
  }

  /// Charge le mode de vue persisté et met à jour [presenceViewModeNotifier]
  Future<void> loadPresenceViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyPresenceViewMode);
    if (stored != null) {
      presenceViewModeNotifier.value = PresenceViewMode.values.firstWhere(
        (m) => m.name == stored,
        orElse: () => PresenceViewMode.chronological,
      );
    }
  }
}
