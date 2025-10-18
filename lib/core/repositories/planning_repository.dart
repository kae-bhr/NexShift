import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';

class PlanningRepository {
  static const _collectionName = 'plannings';
  final FirestoreService _firestore = FirestoreService();

  /// Récupère tous les plannings
  Future<List<Planning>> getAll() async {
    try {
      final data = await _firestore.getAll(_collectionName);
      return data.map((e) => Planning.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  /// Récupère tous les plannings dans une période
  Future<List<Planning>> getAllInRange(DateTime start, DateTime end) async {
    try {
      final data = await _firestore.getInDateRange(
        _collectionName,
        'startTime',
        'endTime',
        start,
        end,
      );

      final plannings = data.map((e) => Planning.fromJson(e)).toList();

      return plannings;
    } catch (e) {
      rethrow;
    }
  }

  /// Récupère les plannings pour un utilisateur spécifique
  Future<List<Planning>> getForUser(
    String userId, {
    DateTime? start,
    DateTime? end,
  }) async {
    try {
      List<Planning> plannings;

      if (start != null && end != null) {
        plannings = await getAllInRange(start, end);
      } else {
        plannings = await getAll();
      }

      return plannings.where((p) => p.agentsId.contains(userId)).toList();
    } catch (e) {
      debugPrint('Firestore error in getForUser: $e');
      rethrow;
    }
  }

  /// Récupère les plannings pour une équipe
  Future<List<Planning>> getForTeam(
    String teamId, {
    DateTime? start,
    DateTime? end,
  }) async {
    try {
      List<Planning> plannings;

      if (start != null && end != null) {
        plannings = await getAllInRange(start, end);
      } else {
        plannings = await getAll();
      }

      return plannings.where((p) => p.team == teamId).toList();
    } catch (e) {
      debugPrint('Firestore error in getForTeam: $e');
      rethrow;
    }
  }

  /// Récupère un planning par ID
  Future<Planning?> getById(String id) async {
    try {
      final data = await _firestore.getById(_collectionName, id);
      if (data != null) {
        return Planning.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Firestore error in getById: $e');
      rethrow;
    }
  }

  /// Sauvegarde un planning
  Future<void> save(Planning planning) async {
    try {
      await _firestore.upsert(_collectionName, planning.id, planning.toJson());
    } catch (e) {
      debugPrint('Firestore error during save: $e');
      rethrow;
    }
  }

  /// Sauvegarde tous les plannings (remplace la liste complète)
  Future<void> saveAll(List<Planning> plannings) async {
    try {
      final operations = plannings
          .map(
            (planning) => {
              'type': 'set',
              'collection': _collectionName,
              'id': planning.id,
              'data': planning.toJson(),
            },
          )
          .toList();
      await _firestore.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during saveAll: $e');
      rethrow;
    }
  }

  /// Supprime un planning
  Future<void> delete(String id) async {
    try {
      await _firestore.delete(_collectionName, id);
    } catch (e) {
      debugPrint('Firestore error during delete: $e');
      rethrow;
    }
  }

  /// Supprime tous les plannings à partir d'une date
  Future<void> deleteFuturePlannings(DateTime fromDate) async {
    try {
      final all = await getAll();
      final toDelete = all
          .where((p) => !p.startTime.isBefore(fromDate))
          .toList();

      if (toDelete.isNotEmpty) {
        final operations = toDelete
            .map(
              (planning) => {
                'type': 'delete',
                'collection': _collectionName,
                'id': planning.id,
              },
            )
            .toList();
        await _firestore.batchWrite(operations);
      }
    } catch (e) {
      debugPrint('Firestore error during deleteFuturePlannings: $e');
      rethrow;
    }
  }

  /// Supprime tous les plannings dans une plage de dates
  Future<void> deletePlanningsInRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final all = await getAll();
      final toDelete = all.where((p) {
        // Supprimer les plannings qui chevauchent la plage
        return !p.endTime.isBefore(startDate) && !p.startTime.isAfter(endDate);
      }).toList();

      if (toDelete.isNotEmpty) {
        final operations = toDelete
            .map(
              (planning) => {
                'type': 'delete',
                'collection': _collectionName,
                'id': planning.id,
              },
            )
            .toList();
        await _firestore.batchWrite(operations);
      }
    } catch (e) {
      debugPrint('Firestore error during deletePlanningsInRange: $e');
      rethrow;
    }
  }

  /// Vide tous les plannings
  Future<void> clear() async {
    try {
      final all = await getAll();
      if (all.isNotEmpty) {
        final operations = all
            .map(
              (p) => {
                'type': 'delete',
                'collection': _collectionName,
                'id': p.id,
              },
            )
            .toList();
        await _firestore.batchWrite(operations);
      }
    } catch (e) {
      debugPrint('Firestore error during clear: $e');
      rethrow;
    }
  }
}
