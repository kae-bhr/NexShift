import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Cache simple pour les noms de stations
/// Évite de recharger le nom à chaque fois
class StationNameCache {
  static final StationNameCache _instance = StationNameCache._internal();
  factory StationNameCache() => _instance;
  StationNameCache._internal();

  final Map<String, String> _cache = {};

  /// Récupère le nom d'une station par son ID
  /// Utilise le cache si disponible, sinon charge depuis Firestore
  Future<String> getStationName(String sdisId, String stationId) async {
    final key = '$sdisId/$stationId';

    // Si en cache, retourner directement
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    try {
      // Charger depuis Firestore
      final doc = await FirebaseFirestore.instance
          .collection('sdis')
          .doc(sdisId)
          .collection('stations')
          .doc(stationId)
          .get();

      if (doc.exists) {
        final name = doc.data()?['name'] as String? ?? stationId;
        _cache[key] = name;
        return name;
      }
    } catch (e) {
      debugPrint('❌ Error loading station name: $e');
    }

    // Fallback : retourner l'ID
    return stationId;
  }

  /// Récupère le nom d'une station de manière synchrone (depuis le cache uniquement)
  /// Retourne l'ID si pas en cache
  String getStationNameSync(String sdisId, String stationId) {
    final key = '$sdisId/$stationId';
    return _cache[key] ?? stationId;
  }

  /// Précharge le nom d'une station dans le cache
  Future<void> preload(String sdisId, String stationId) async {
    await getStationName(sdisId, stationId);
  }

  /// Vide le cache
  void clear() {
    _cache.clear();
  }

  /// Supprime une entrée spécifique du cache
  void remove(String sdisId, String stationId) {
    final key = '$sdisId/$stationId';
    _cache.remove(key);
  }
}
