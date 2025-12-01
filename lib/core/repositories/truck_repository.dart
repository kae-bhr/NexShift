import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/trucks_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';

class TruckRepository {
  static const _collectionName = 'trucks';
  final FirestoreService _firestoreService;
  final FirebaseFirestore? _directFirestore;

  /// Constructeur par défaut (production)
  TruckRepository({FirestoreService? firestoreService})
      : _firestoreService = firestoreService ?? FirestoreService(),
        _directFirestore = null;

  /// Constructeur pour les tests avec Firestore direct
  TruckRepository.forTest(FirebaseFirestore firestore)
      : _directFirestore = firestore,
        _firestoreService = FirestoreService();

  Future<List<Truck>> getAll() async {
    try {
      // Mode test
      if (_directFirestore != null) {
        final snapshot = await _directFirestore.collection(_collectionName).get();
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return Truck.fromJson(data);
        }).toList();
      }
      // Mode production
      final data = await _firestoreService.getAll(_collectionName);
      return data.map((e) => Truck.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  Future<Truck?> getById(int id) async {
    try {
      // Mode test
      if (_directFirestore != null) {
        final doc = await _directFirestore.collection(_collectionName).doc(id.toString()).get();
        if (!doc.exists) return null;
        final data = doc.data()!;
        data['id'] = doc.id;
        return Truck.fromJson(data);
      }
      // Mode production
      final data = await _firestoreService.getById(_collectionName, id.toString());
      if (data != null) {
        return Truck.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Firestore error in getById: $e');
      rethrow;
    }
  }

  Future<List<Truck>> getByStation(String stationName) async {
    try {
      // Mode test
      if (_directFirestore != null) {
        final snapshot = await _directFirestore
            .collection(_collectionName)
            .where('station', isEqualTo: stationName)
            .get();
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return Truck.fromJson(data);
        }).toList();
      }
      // Mode production
      final data = await _firestoreService.getWhere(_collectionName, 'station', stationName);
      return data.map((e) => Truck.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getByStation: $e');
      rethrow;
    }
  }

  /// Get the next available ID for a new truck (global unique ID for Firestore)
  Future<int> getNextId() async {
    try {
      final allTrucks = await getAll();
      if (allTrucks.isEmpty) {
        return 1;
      }
      return allTrucks.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1;
    } catch (e) {
      debugPrint('Error getting next truck ID: $e');
      rethrow;
    }
  }

  /// Get the next display number for a specific truck type
  /// Le numéro d'affichage est unique par type (VSAV1, VSAV2, VTU1, VTU2, etc.)
  Future<int> getNextDisplayNumber(String type, String station) async {
    try {
      final allTrucks = await getByStation(station);
      // Filtrer les véhicules du même type
      final sameTrucks = allTrucks.where((t) => t.type == type).toList();

      if (sameTrucks.isEmpty) {
        return 1;
      }

      // Retourner le plus grand displayNumber de ce type + 1
      return sameTrucks
              .map((t) => t.displayNumber)
              .reduce((a, b) => a > b ? a : b) +
          1;
    } catch (e) {
      debugPrint('Error getting next display number for type $type: $e');
      rethrow;
    }
  }

  Future<void> save(Truck truck) async {
    try {
      // Mode test
      if (_directFirestore != null) {
        await _directFirestore.collection(_collectionName).doc(truck.id.toString()).set(truck.toJson());
        return;
      }
      // Mode production
      await _firestoreService.upsert(_collectionName, truck.id.toString(), truck.toJson());
    } catch (e) {
      debugPrint('Firestore error during save: $e');
      rethrow;
    }
  }

  Future<void> saveAll(List<Truck> trucks) async {
    try {
      final operations = trucks.map((truck) => {
        'type': 'set',
        'collection': _collectionName,
        'id': truck.id.toString(),
        'data': truck.toJson(),
      }).toList();
      await _firestoreService.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during saveAll: $e');
      rethrow;
    }
  }

  Future<void> delete(int id) async {
    try {
      // Mode test
      if (_directFirestore != null) {
        await _directFirestore.collection(_collectionName).doc(id.toString()).delete();
        return;
      }
      // Mode production
      await _firestoreService.delete(_collectionName, id.toString());
    } catch (e) {
      debugPrint('Firestore error during delete: $e');
      rethrow;
    }
  }

  Future<void> clear() async {
    try {
      final all = await getAll();
      if (all.isEmpty) return;

      // Mode test: supprimer individuellement
      if (_directFirestore != null) {
        for (final truck in all) {
          await _directFirestore.collection(_collectionName).doc(truck.id.toString()).delete();
        }
        return;
      }
      // Mode production: utiliser batchWrite
      final operations = all.map((t) => {
        'type': 'delete',
        'collection': _collectionName,
        'id': t.id.toString(),
      }).toList();
      await _firestoreService.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during clear: $e');
      rethrow;
    }
  }
}
