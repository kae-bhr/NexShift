import 'package:nexshift_app/core/data/datasources/sdis_context.dart';

/// Configuration de l'environnement (dev/prod)
/// Détermine si on utilise l'architecture avec sous-collections (dev) ou collections plates (prod)
class EnvironmentConfig {
  // TODO: Changer en prod quand prêt pour la production
  static const String environment = 'dev'; // 'dev' ou 'prod'

  static bool get isDev => environment == 'dev';
  static bool get isProd => environment == 'prod';

  /// En mode dev, on utilise les sous-collections par station
  /// En mode prod, on continue d'utiliser les collections plates (legacy)
  static bool get useStationSubcollections => isDev;

  /// ID du projet Firebase selon l'environnement
  static String get firebaseProjectId {
    return isDev ? 'nexshift-dev' : 'nexshift-82473';
  }

  /// Helper pour construire le chemin de collection selon l'environnement
  /// En dev avec SDIS: /sdis/{sdisId}/stations/{stationId}/{collectionName}
  /// En dev sans SDIS (legacy): /stations/{stationId}/{collectionName}
  /// En prod: /{collectionName}
  static String getCollectionPath(String collectionName, String? stationId) {
    if (useStationSubcollections && stationId != null && stationId.isNotEmpty) {
      // Si un SDIS est défini dans le contexte, utiliser la structure multi-SDIS
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && sdisId.isNotEmpty) {
        return 'sdis/$sdisId/stations/$stationId/$collectionName';
      }
      // Sinon, utiliser l'ancienne structure (legacy)
      return 'stations/$stationId/$collectionName';
    }
    return collectionName;
  }

  /// Retourne le chemin de la collection stations
  /// En DEV avec SDIS: /sdis/{sdisId}/stations/{stationId}
  /// En DEV sans SDIS (legacy): /stations/{stationId}
  /// En PROD: /stations/{stationId}
  static String get stationsCollectionPath {
    if (useStationSubcollections) {
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && sdisId.isNotEmpty) {
        return 'sdis/$sdisId/stations';
      }
    }
    return 'stations';
  }
}
