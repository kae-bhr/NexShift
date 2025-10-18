import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';

class TeamRepository {
  static const _collectionName = 'teams';
  final FirestoreService _firestore = FirestoreService();

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

  /// Récupère une équipe par son ID
  Future<Team?> getById(String id) async {
    try {
      final data = await _firestore.getById(_collectionName, id);
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
      await _firestore.upsert(_collectionName, team.id, team.toJson());
    } catch (e) {
      debugPrint('Firestore error during upsert: $e');
      rethrow;
    }
  }

  /// Supprime une équipe
  Future<void> delete(String id) async {
    try {
      await _firestore.delete(_collectionName, id);
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
