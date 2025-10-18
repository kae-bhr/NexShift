import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/utils/subshift_normalizer.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';

class SubshiftRepository {
  static const _collectionName = 'subshifts';
  final FirestoreService _firestore = FirestoreService();

  Future<List<Subshift>> getAll() async {
    try {
      final data = await _firestore.getAll(_collectionName);
      return data.map((e) => Subshift.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  Future<Subshift?> getById(String id) async {
    try {
      final data = await _firestore.getById(_collectionName, id);
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
      final data = await _firestore.getWhere(_collectionName, 'planningId', planningId);
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

      final operations = all.map((s) => {
        'type': 'set',
        'collection': _collectionName,
        'id': s.id,
        'data': s.toJson(),
      }).toList();
      await _firestore.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during save: $e');
      rethrow;
    }
  }

  Future<void> saveAll(List<Subshift> subshifts) async {
    try {
      final operations = subshifts.map((subshift) => {
        'type': 'set',
        'collection': _collectionName,
        'id': subshift.id,
        'data': subshift.toJson(),
      }).toList();
      await _firestore.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during saveAll: $e');
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    try {
      await _firestore.delete(_collectionName, id);
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
        await _firestore.batchWrite(operations);
      }
    } catch (e) {
      debugPrint('Firestore error during clear: $e');
      rethrow;
    }
  }
}
