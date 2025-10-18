import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/shift_exception_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';

class ShiftExceptionRepository {
  static const _collectionName = 'shift_exceptions';
  final FirestoreService _firestore = FirestoreService();

  /// Récupère toutes les exceptions
  Future<List<ShiftException>> getAll() async {
    try {
      final data = await _firestore.getAll(_collectionName);
      return data.map((e) => ShiftException.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  /// Récupère les exceptions pour une année spécifique
  Future<List<ShiftException>> getByYear(int year) async {
    final all = await getAll();
    final yearStart = DateTime(year, 1, 1);
    final yearEnd = DateTime(year + 1, 1, 1);
    return all.where((e) {
      // Inclure si l'exception chevauche l'année
      return e.startDateTime.isBefore(yearEnd) &&
          e.endDateTime.isAfter(yearStart);
    }).toList()..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
  }

  /// Récupère une exception par ID
  Future<ShiftException?> getById(String id) async {
    try {
      final data = await _firestore.getById(_collectionName, id);
      if (data != null) {
        return ShiftException.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Firestore error in getById: $e');
      rethrow;
    }
  }

  /// Récupère les exceptions qui chevauchent une date/heure donnée
  Future<List<ShiftException>> getByDateTime(DateTime dateTime) async {
    final all = await getAll();
    return all.where((e) {
      return e.startDateTime.isBefore(dateTime) &&
          e.endDateTime.isAfter(dateTime);
    }).toList();
  }

  /// Ajoute ou met à jour une exception
  Future<void> upsert(ShiftException exception) async {
    try {
      await _firestore.upsert(_collectionName, exception.id, exception.toJson());
    } catch (e) {
      debugPrint('Firestore error during upsert: $e');
      rethrow;
    }
  }

  /// Supprime une exception
  Future<void> delete(String id) async {
    try {
      await _firestore.delete(_collectionName, id);
    } catch (e) {
      debugPrint('Firestore error during delete: $e');
      rethrow;
    }
  }

  /// Supprime toutes les exceptions d'une année
  Future<void> deleteByYear(int year) async {
    try {
      final all = await getAll();
      final toDelete = all.where((e) => e.startDateTime.year == year).toList();

      if (toDelete.isNotEmpty) {
        final operations = toDelete.map((e) => {
          'type': 'delete',
          'collection': _collectionName,
          'id': e.id,
        }).toList();
        await _firestore.batchWrite(operations);
      }
    } catch (e) {
      debugPrint('Firestore error during deleteByYear: $e');
      rethrow;
    }
  }

  /// Supprime toutes les exceptions
  Future<void> clear() async {
    try {
      final all = await getAll();
      if (all.isNotEmpty) {
        final operations = all.map((e) => {
          'type': 'delete',
          'collection': _collectionName,
          'id': e.id,
        }).toList();
        await _firestore.batchWrite(operations);
      }
    } catch (e) {
      debugPrint('Firestore error during clear: $e');
      rethrow;
    }
  }
}
