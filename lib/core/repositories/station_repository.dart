import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';

class StationRepository {
  static const _collectionName = 'stations';
  final FirestoreService _firestore = FirestoreService();

  /// Génère le chemin de collection en fonction de l'environnement
  String _getCollectionPath() {
    if (EnvironmentConfig.useStationSubcollections) {
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && sdisId.isNotEmpty) {
        return 'sdis/$sdisId/$_collectionName';
      }
    }
    return _collectionName;
  }

  /// Récupère toutes les stations depuis Firestore
  /// En mode DEV: /sdis/{sdisId}/stations
  /// En mode PROD: /stations
  Future<List<Station>> getAll() async {
    try {
      final collectionPath = _getCollectionPath();
      final data = await _firestore.getAll(collectionPath);
      return data.map((e) => Station.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  /// Récupère une station par son ID
  /// En mode DEV: /sdis/{sdisId}/stations/{stationId}
  /// En mode PROD: /stations/{stationId}
  Future<Station?> getById(String id) async {
    try {
      final collectionPath = _getCollectionPath();
      final data = await _firestore.getById(collectionPath, id);
      if (data != null) {
        return Station.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Firestore error in getById: $e');
      rethrow;
    }
  }

  /// Sauvegarde toutes les stations
  Future<void> saveAll(List<Station> stations) async {
    try {
      final collectionPath = _getCollectionPath();
      final operations = stations.map((station) => {
        'type': 'set',
        'collection': collectionPath,
        'id': station.id,
        'data': station.toJson(),
      }).toList();
      await _firestore.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during saveAll: $e');
      rethrow;
    }
  }

  /// Met à jour ou insère une station
  Future<void> upsert(Station station) async {
    try {
      final collectionPath = _getCollectionPath();
      await _firestore.upsert(collectionPath, station.id, station.toJson());
    } catch (e) {
      debugPrint('Firestore error during upsert: $e');
      rethrow;
    }
  }

  /// Supprime une station
  Future<void> delete(String id) async {
    try {
      final collectionPath = _getCollectionPath();
      await _firestore.delete(collectionPath, id);
    } catch (e) {
      debugPrint('Firestore error during delete: $e');
      rethrow;
    }
  }

  /// Supprime toutes les stations
  Future<void> clear() async {
    try {
      final collectionPath = _getCollectionPath();
      final all = await getAll();
      final operations = all.map((s) => {
        'type': 'delete',
        'collection': collectionPath,
        'id': s.id,
      }).toList();
      await _firestore.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during clear: $e');
      rethrow;
    }
  }
}
