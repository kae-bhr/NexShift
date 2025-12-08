import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/shift_exception_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';
import 'package:nexshift_app/core/config/environment_config.dart';

class ShiftExceptionRepository {
  static const _collectionName = 'shift_exceptions';
  final FirestoreService _firestore = FirestoreService();

  /// Génère le chemin de collection en fonction de l'environnement et de la station
  String _getCollectionPath(String? stationId) {
    return EnvironmentConfig.getCollectionPath(_collectionName, stationId);
  }

  /// Récupère toutes les exceptions d'une station
  Future<List<ShiftException>> getAll({String? stationId}) async {
    if (EnvironmentConfig.useStationSubcollections && stationId == null) {
      throw Exception('stationId required in dev mode for getAll');
    }

    try {
      final collectionPath = _getCollectionPath(stationId);
      final data = await _firestore.getAll(collectionPath);
      return data.map((e) => ShiftException.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  /// Récupère les exceptions pour une année spécifique
  Future<List<ShiftException>> getByYear(int year, {String? stationId}) async {
    if (EnvironmentConfig.useStationSubcollections && stationId == null) {
      throw Exception('stationId required in dev mode for getByYear');
    }

    final all = await getAll(stationId: stationId);
    final yearStart = DateTime(year, 1, 1);
    final yearEnd = DateTime(year + 1, 1, 1);
    return all.where((e) {
      // Inclure si l'exception chevauche l'année
      return e.startDateTime.isBefore(yearEnd) &&
          e.endDateTime.isAfter(yearStart);
    }).toList()..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
  }

  /// Récupère une exception par ID
  Future<ShiftException?> getById(String id, {String? stationId}) async {
    if (EnvironmentConfig.useStationSubcollections && stationId == null) {
      throw Exception('stationId required in dev mode for getById');
    }

    try {
      final collectionPath = _getCollectionPath(stationId);
      final data = await _firestore.getById(collectionPath, id);
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
  Future<List<ShiftException>> getByDateTime(DateTime dateTime, {String? stationId}) async {
    if (EnvironmentConfig.useStationSubcollections && stationId == null) {
      throw Exception('stationId required in dev mode for getByDateTime');
    }

    final all = await getAll(stationId: stationId);
    return all.where((e) {
      return e.startDateTime.isBefore(dateTime) &&
          e.endDateTime.isAfter(dateTime);
    }).toList();
  }

  /// Ajoute ou met à jour une exception
  Future<void> upsert(ShiftException exception, {String? stationId}) async {
    if (EnvironmentConfig.useStationSubcollections && stationId == null) {
      throw Exception('stationId required in dev mode for upsert');
    }

    try {
      final collectionPath = _getCollectionPath(stationId);
      await _firestore.upsert(collectionPath, exception.id, exception.toJson());
    } catch (e) {
      debugPrint('Firestore error during upsert: $e');
      rethrow;
    }
  }

  /// Supprime une exception
  Future<void> delete(String id, {String? stationId}) async {
    if (EnvironmentConfig.useStationSubcollections && stationId == null) {
      throw Exception('stationId required in dev mode for delete');
    }

    try {
      final collectionPath = _getCollectionPath(stationId);
      await _firestore.delete(collectionPath, id);
    } catch (e) {
      debugPrint('Firestore error during delete: $e');
      rethrow;
    }
  }

  /// Supprime toutes les exceptions d'une année
  Future<void> deleteByYear(int year, {String? stationId}) async {
    if (EnvironmentConfig.useStationSubcollections && stationId == null) {
      throw Exception('stationId required in dev mode for deleteByYear');
    }

    try {
      final collectionPath = _getCollectionPath(stationId);
      final all = await getAll(stationId: stationId);
      final toDelete = all.where((e) => e.startDateTime.year == year).toList();

      if (toDelete.isNotEmpty) {
        final operations = toDelete.map((e) => {
          'type': 'delete',
          'collection': collectionPath,
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
  Future<void> clear({String? stationId}) async {
    if (EnvironmentConfig.useStationSubcollections && stationId == null) {
      throw Exception('stationId required in dev mode for clear');
    }

    try {
      final collectionPath = _getCollectionPath(stationId);
      final all = await getAll(stationId: stationId);
      if (all.isNotEmpty) {
        final operations = all.map((e) => {
          'type': 'delete',
          'collection': collectionPath,
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
