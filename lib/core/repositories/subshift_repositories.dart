import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/utils/subshift_normalizer.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';

class SubshiftRepository {
  static const _collectionName = 'subshifts';
  final FirestoreService _firestoreService;
  final FirebaseFirestore? _directFirestore;

  /// Constructeur par défaut (production)
  SubshiftRepository({FirestoreService? firestoreService})
      : _firestoreService = firestoreService ?? FirestoreService(),
        _directFirestore = null;

  /// Constructeur pour les tests avec Firestore direct
  SubshiftRepository.forTest(FirebaseFirestore firestore)
      : _directFirestore = firestore,
        _firestoreService = FirestoreService();

  Future<List<Subshift>> getAll() async {
    try {
      // Mode test
      if (_directFirestore != null) {
        final snapshot = await _directFirestore.collection(_collectionName).get();
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return Subshift.fromJson(data);
        }).toList();
      }

      // Mode production
      final data = await _firestoreService.getAll(_collectionName);
      return data.map((e) => Subshift.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  Future<Subshift?> getById(String id) async {
    try {
      final data = await _firestoreService.getById(_collectionName, id);
      if (data != null) {
        return Subshift.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Firestore error in getById: $e');
      rethrow;
    }
  }

  Future<List<Subshift>> getByPlanningId(String planningId) async {
    try {
      final data = await _firestoreService.getWhere(_collectionName, 'planningId', planningId);
      return data.map((e) => Subshift.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getByPlanningId: $e');
      rethrow;
    }
  }

  Future<void> save(Subshift subshift) async {
    try {
      final subshifts = await getAll();
      final index = subshifts.indexWhere((s) => s.id == subshift.id);

      if (index != -1) {
        subshifts[index] = subshift;
      } else {
        subshifts.add(subshift);
      }

      // Normaliser tous les subshifts du même planning et remplacé
      final toNormalize = subshifts
          .where(
            (s) =>
                s.planningId == subshift.planningId &&
                s.replacedId == subshift.replacedId,
          )
          .toList();
      final others = subshifts
          .where(
            (s) =>
                !(s.planningId == subshift.planningId &&
                    s.replacedId == subshift.replacedId),
          )
          .toList();
      final normalized = normalizeSubshifts(toNormalize);
      final all = [...others, ...normalized];

      // Mode test : sauvegarder directement
      if (_directFirestore != null) {
        final batch = _directFirestore.batch();
        for (final s in all) {
          batch.set(_directFirestore.collection(_collectionName).doc(s.id), s.toJson());
        }
        await batch.commit();
        return;
      }

      // Mode production
      final operations = all.map((s) => {
        'type': 'set',
        'collection': _collectionName,
        'id': s.id,
        'data': s.toJson(),
      }).toList();
      await _firestoreService.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during save: $e');
      rethrow;
    }
  }

  Future<void> saveAll(List<Subshift> subshifts) async {
    try {
      // Mode test
      if (_directFirestore != null) {
        final batch = _directFirestore.batch();
        for (final subshift in subshifts) {
          batch.set(_directFirestore.collection(_collectionName).doc(subshift.id), subshift.toJson());
        }
        await batch.commit();
        return;
      }

      // Mode production
      final operations = subshifts.map((subshift) => {
        'type': 'set',
        'collection': _collectionName,
        'id': subshift.id,
        'data': subshift.toJson(),
      }).toList();
      await _firestoreService.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during saveAll: $e');
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    try {
      await _firestoreService.delete(_collectionName, id);
    } catch (e) {
      debugPrint('Firestore error during delete: $e');
      rethrow;
    }
  }

  Future<void> clear() async {
    try {
      final all = await getAll();
      if (all.isNotEmpty) {
        final operations = all.map((s) => {
          'type': 'delete',
          'collection': _collectionName,
          'id': s.id,
        }).toList();
        await _firestoreService.batchWrite(operations);
      }
    } catch (e) {
      debugPrint('Firestore error during clear: $e');
      rethrow;
    }
  }
}
