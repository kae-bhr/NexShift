import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';

class StationRepository {
  static const _collectionName = 'stations';
  final FirestoreService _firestore = FirestoreService();

  /// Récupère toutes les stations depuis Firestore
  Future<List<Station>> getAll() async {
    try {
      final data = await _firestore.getAll(_collectionName);
      return data.map((e) => Station.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  /// Récupère une station par son ID
  Future<Station?> getById(String id) async {
    try {
      final data = await _firestore.getById(_collectionName, id);
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
      final operations = stations.map((station) => {
        'type': 'set',
        'collection': _collectionName,
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
      await _firestore.upsert(_collectionName, station.id, station.toJson());
    } catch (e) {
      debugPrint('Firestore error during upsert: $e');
      rethrow;
    }
  }

  /// Supprime une station
  Future<void> delete(String id) async {
    try {
      await _firestore.delete(_collectionName, id);
    } catch (e) {
      debugPrint('Firestore error during delete: $e');
      rethrow;
    }
  }

  /// Supprime toutes les stations
  Future<void> clear() async {
    try {
      final all = await getAll();
      final operations = all.map((s) => {
        'type': 'delete',
        'collection': _collectionName,
        'id': s.id,
      }).toList();
      await _firestore.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during clear: $e');
      rethrow;
    }
  }
}
