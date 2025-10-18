import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/availability_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';

class AvailabilityRepository {
  static const _collectionName = 'availabilities';
  final FirestoreService _firestore = FirestoreService();

  /// Récupère toutes les disponibilités
  Future<List<Availability>> getAll() async {
    try {
      final data = await _firestore.getAll(_collectionName);
      return data.map((e) => Availability.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  /// Récupère une disponibilité par ID
  Future<Availability?> getById(String id) async {
    try {
      final data = await _firestore.getById(_collectionName, id);
      if (data != null) {
        return Availability.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Firestore error in getById: $e');
      rethrow;
    }
  }

  /// Récupère les disponibilités d'un agent spécifique
  Future<List<Availability>> getByAgentId(String agentId) async {
    try {
      final data = await _firestore.getWhere(_collectionName, 'agentId', agentId);
      return data.map((e) => Availability.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getByAgentId: $e');
      rethrow;
    }
  }

  /// Récupère les disponibilités pour un planning spécifique
  Future<List<Availability>> getByPlanningId(String planningId) async {
    try {
      final data = await _firestore.getWhere(_collectionName, 'planningId', planningId);
      return data.map((e) => Availability.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getByPlanningId: $e');
      rethrow;
    }
  }

  /// Récupère les disponibilités dans une plage temporelle
  Future<List<Availability>> getInRange(DateTime start, DateTime end) async {
    try {
      final data = await _firestore.getInDateRange(
        _collectionName,
        'start',
        'end',
        start,
        end,
      );
      return data.map((e) => Availability.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getInRange: $e');
      rethrow;
    }
  }

  /// Ajoute ou met à jour une disponibilité
  Future<void> upsert(Availability availability) async {
    try {
      await _firestore.upsert(_collectionName, availability.id, availability.toJson());
    } catch (e) {
      debugPrint('Firestore error during upsert: $e');
      rethrow;
    }
  }

  /// Supprime une disponibilité par son ID
  Future<void> delete(String id) async {
    try {
      await _firestore.delete(_collectionName, id);
    } catch (e) {
      debugPrint('Firestore error during delete: $e');
      rethrow;
    }
  }

  /// Supprime une disponibilité en cours (cas particulier)
  /// Si la disponibilité est en cours, on la découpe :
  /// - L'heure de fin devient l'heure actuelle
  /// - On conserve le segment déjà consommé
  Future<void> deleteOngoing(String id) async {
    try {
      final availability = await getById(id);
      if (availability == null) return;

      final now = DateTime.now();

      // Si la disponibilité n'a pas encore commencé, suppression normale
      if (availability.start.isAfter(now)) {
        await delete(id);
      } else if (availability.end.isAfter(now)) {
        // La disponibilité est en cours : on découpe
        final updated = availability.copyWith(end: now);
        await upsert(updated);
      } else {
        // La disponibilité est déjà terminée, suppression normale
        await delete(id);
      }
    } catch (e) {
      debugPrint('Firestore error during deleteOngoing: $e');
      rethrow;
    }
  }

  /// Supprime toutes les disponibilités
  Future<void> clear() async {
    try {
      final all = await getAll();
      if (all.isNotEmpty) {
        final operations = all.map((a) => {
          'type': 'delete',
          'collection': _collectionName,
          'id': a.id,
        }).toList();
        await _firestore.batchWrite(operations);
      }
    } catch (e) {
      debugPrint('Firestore error during clear: $e');
      rethrow;
    }
  }
}
