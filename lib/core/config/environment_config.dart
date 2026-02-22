import 'package:nexshift_app/core/data/datasources/sdis_context.dart';

/// Configuration de l'environnement
class EnvironmentConfig {
  /// Helper pour construire le chemin d'une sous-collection d'une station
  /// /sdis/{sdisId}/stations/{stationId}/{collectionName}
  static String getCollectionPath(String collectionName, String? stationId) {
    final sdisId = SDISContext().currentSDISId;
    if (sdisId != null &&
        sdisId.isNotEmpty &&
        stationId != null &&
        stationId.isNotEmpty) {
      return 'sdis/$sdisId/stations/$stationId/$collectionName';
    }
    // Fallback si le contexte SDIS n'est pas encore chargé
    return collectionName;
  }

  /// Retourne le chemin de la collection stations
  /// /sdis/{sdisId}/stations
  static String get stationsCollectionPath {
    final sdisId = SDISContext().currentSDISId;
    if (sdisId != null && sdisId.isNotEmpty) {
      return 'sdis/$sdisId/stations';
    }
    return 'stations';
  }

  /// Retourne le chemin de la collection user_notifications au niveau SDIS
  /// /sdis/{sdisId}/user_notifications
  static String get userNotificationsCollectionPath {
    final sdisId = SDISContext().currentSDISId;
    if (sdisId != null && sdisId.isNotEmpty) {
      return 'sdis/$sdisId/user_notifications';
    }
    return 'user_notifications';
  }
}
