import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/utils/subshift_normalizer.dart';
import 'package:nexshift_app/core/config/environment_config.dart';

class SubshiftRepository {
  final FirebaseFirestore? _directFirestore;

  /// Constructeur par défaut (production)
  SubshiftRepository()
      : _directFirestore = null;

  /// Constructeur pour les tests avec Firestore direct
  SubshiftRepository.forTest(FirebaseFirestore firestore)
      : _directFirestore = firestore;

  /// Retourne le chemin de collection selon l'environnement
  /// /sdis/{sdisId}/stations/{stationId}/replacements/all/subshifts
  String _getCollectionPath(String? stationId, {String? requestId}) {
    return EnvironmentConfig.getCollectionPath('replacements/all/subshifts', stationId);
  }

  Future<List<Subshift>> getAll({String? stationId, String? requestId}) async {
    try {
      final collectionPath = _getCollectionPath(stationId, requestId: requestId);
      debugPrint('🔍 [SubshiftRepository] getAll() - collectionPath: "$collectionPath", stationId: "$stationId"');

      final firestore = _directFirestore ?? FirebaseFirestore.instance;
      final snapshot = await firestore.collection(collectionPath).get();
      final subshifts = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Subshift.fromJson(data);
      }).toList();
      debugPrint('🔍 [SubshiftRepository] getAll() - Found ${subshifts.length} subshifts');
      for (final s in subshifts) {
        debugPrint('   → Subshift ${s.id}: ${s.replacedId} -> ${s.replacerId} (${s.start} to ${s.end})');
      }
      return subshifts;
    } catch (e) {
      debugPrint('❌ [SubshiftRepository] Firestore error in getAll: $e');
      rethrow;
    }
  }

  Future<Subshift?> getById(String id, {String? stationId, String? requestId}) async {
    try {
      final collectionPath = _getCollectionPath(stationId, requestId: requestId);
      final firestore = _directFirestore ?? FirebaseFirestore.instance;
      final doc = await firestore.collection(collectionPath).doc(id).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        data['id'] = doc.id;
        return Subshift.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Firestore error in getById: $e');
      rethrow;
    }
  }

  Future<List<Subshift>> getByPlanningId(String planningId, {String? stationId, String? requestId}) async {
    try {
      final collectionPath = _getCollectionPath(stationId, requestId: requestId);
      final firestore = _directFirestore ?? FirebaseFirestore.instance;
      final snapshot = await firestore
          .collection(collectionPath)
          .where('planningId', isEqualTo: planningId)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Subshift.fromJson(data);
      }).toList();
    } catch (e) {
      debugPrint('Firestore error in getByPlanningId: $e');
      rethrow;
    }
  }

  Future<void> save(Subshift subshift, {String? stationId, String? requestId}) async {
    try {
      final collectionPath = _getCollectionPath(stationId, requestId: requestId);
      final subshifts = await getAll(stationId: stationId, requestId: requestId);
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

      final firestore = _directFirestore ?? FirebaseFirestore.instance;
      final batch = firestore.batch();
      for (final s in all) {
        batch.set(firestore.collection(collectionPath).doc(s.id), s.toJson());
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Firestore error during save: $e');
      rethrow;
    }
  }

  Future<void> saveAll(List<Subshift> subshifts, {String? stationId, String? requestId}) async {
    try {
      final collectionPath = _getCollectionPath(stationId, requestId: requestId);
      final firestore = _directFirestore ?? FirebaseFirestore.instance;
      final batch = firestore.batch();
      for (final subshift in subshifts) {
        batch.set(firestore.collection(collectionPath).doc(subshift.id), subshift.toJson());
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Firestore error during saveAll: $e');
      rethrow;
    }
  }

  Future<void> delete(String id, {String? stationId, String? requestId}) async {
    try {
      final collectionPath = _getCollectionPath(stationId, requestId: requestId);
      final firestore = _directFirestore ?? FirebaseFirestore.instance;
      await firestore.collection(collectionPath).doc(id).delete();
    } catch (e) {
      debugPrint('Firestore error during delete: $e');
      rethrow;
    }
  }

  /// Met à jour le statut "checkedByChief" d'un subshift
  Future<void> toggleCheck(String id, {
    required bool checked,
    required String checkedBy,
    String? stationId,
    String? requestId,
  }) async {
    try {
      final collectionPath = _getCollectionPath(stationId, requestId: requestId);
      final data = {
        'checkedByChief': checked,
        'checkedAt': checked ? DateTime.now().toIso8601String() : null,
        'checkedBy': checked ? checkedBy : null,
      };

      final firestore = _directFirestore ?? FirebaseFirestore.instance;
      await firestore.collection(collectionPath).doc(id).update(data);
    } catch (e) {
      debugPrint('Firestore error during toggleCheck: $e');
      rethrow;
    }
  }

  Future<void> clear({String? stationId, String? requestId}) async {
    try {
      final collectionPath = _getCollectionPath(stationId, requestId: requestId);
      final all = await getAll(stationId: stationId, requestId: requestId);

      if (all.isEmpty) return;

      final firestore = _directFirestore ?? FirebaseFirestore.instance;
      final batch = firestore.batch();
      for (final s in all) {
        batch.delete(firestore.collection(collectionPath).doc(s.id));
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Firestore error during clear: $e');
      rethrow;
    }
  }
}
