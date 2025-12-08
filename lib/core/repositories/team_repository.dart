import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';
import 'package:nexshift_app/core/config/environment_config.dart';

class TeamRepository {
  static const _collectionName = 'teams';
  final FirestoreService _firestore = FirestoreService();

  /// Retourne le chemin de collection selon l'environnement
  String _getCollectionPath(String? stationId) {
    return EnvironmentConfig.getCollectionPath(_collectionName, stationId);
  }

  /// Récupère toutes les équipes depuis Firestore
  Future<List<Team>> getAll() async {
    try {
      final data = await _firestore.getAll(_collectionName);
      return data.map((e) => Team.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  /// Récupère les équipes d'une station spécifique
  Future<List<Team>> getByStation(String stationId) async {
    try {
      final collectionPath = _getCollectionPath(stationId);

      // En mode dev (sous-collections), on récupère toutes les équipes de la sous-collection
      // En mode prod (collections plates), on filtre par stationId
      if (EnvironmentConfig.useStationSubcollections) {
        final data = await _firestore.getAll(collectionPath);
        return data.map((e) => Team.fromJson(e)).toList();
      } else {
        final data = await _firestore.getWhere(
          collectionPath,
          'stationId',
          stationId,
        );
        return data.map((e) => Team.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('Firestore error in getByStation: $e');
      rethrow;
    }
  }

  /// Récupère une équipe par son ID
  /// IMPORTANT: Nécessite stationId en mode dev (sous-collections)
  Future<Team?> getById(String id, {String? stationId}) async {
    try {
      // En mode dev, on doit avoir le stationId pour construire le chemin
      if (EnvironmentConfig.useStationSubcollections && stationId == null) {
        throw Exception('stationId required in dev mode for getById');
      }

      final collectionPath = _getCollectionPath(stationId);
      final data = await _firestore.getById(collectionPath, id);
      if (data != null) {
        return Team.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Firestore error in getById: $e');
      rethrow;
    }
  }

  /// Sauvegarde toutes les équipes
  Future<void> saveAll(List<Team> teams) async {
    try {
      final operations = teams.map((team) => {
        'type': 'set',
        'collection': _collectionName,
        'id': team.id,
        'data': team.toJson(),
      }).toList();
      await _firestore.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during saveAll: $e');
      rethrow;
    }
  }

  /// Met à jour ou insère une équipe
  Future<void> upsert(Team team) async {
    try {
      final collectionPath = _getCollectionPath(team.stationId);
      await _firestore.upsert(collectionPath, team.id, team.toJson());
    } catch (e) {
      debugPrint('Firestore error during upsert: $e');
      rethrow;
    }
  }

  /// Supprime une équipe
  Future<void> delete(String id, {String? stationId}) async {
    try {
      // En mode dev, on doit avoir le stationId pour construire le chemin
      if (EnvironmentConfig.useStationSubcollections && stationId == null) {
        throw Exception('stationId required in dev mode for delete');
      }

      final collectionPath = _getCollectionPath(stationId);
      await _firestore.delete(collectionPath, id);
    } catch (e) {
      debugPrint('Firestore error during delete: $e');
      rethrow;
    }
  }

  /// Supprime toutes les équipes
  Future<void> clear() async {
    try {
      final all = await getAll();
      final operations = all.map((t) => {
        'type': 'delete',
        'collection': _collectionName,
        'id': t.id,
      }).toList();
      await _firestore.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during clear: $e');
      rethrow;
    }
  }
}
