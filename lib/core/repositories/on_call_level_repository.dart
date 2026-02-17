import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/on_call_level_model.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';

class OnCallLevelRepository {
  static const _collectionName = 'onCallLevels';

  String _getCollectionPath(String stationId) {
    if (EnvironmentConfig.useStationSubcollections) {
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && sdisId.isNotEmpty) {
        return 'sdis/$sdisId/stations/$stationId/$_collectionName';
      }
    }
    return 'stations/$stationId/$_collectionName';
  }

  /// Récupère tous les niveaux d'astreinte d'une station, triés par order
  Future<List<OnCallLevel>> getAll(String stationId) async {
    try {
      final path = _getCollectionPath(stationId);
      final snapshot = await FirebaseFirestore.instance
          .collection(path)
          .orderBy('order')
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return OnCallLevel.fromJson(data);
      }).toList();
    } catch (e) {
      debugPrint('❌ [OnCallLevelRepository] Error in getAll: $e');
      rethrow;
    }
  }

  /// Récupère un niveau par son ID
  Future<OnCallLevel?> getById(String id, String stationId) async {
    try {
      final path = _getCollectionPath(stationId);
      final doc =
          await FirebaseFirestore.instance.collection(path).doc(id).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        data['id'] = doc.id;
        return OnCallLevel.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('❌ [OnCallLevelRepository] Error in getById: $e');
      rethrow;
    }
  }

  /// Crée un nouveau niveau d'astreinte
  Future<String> create(OnCallLevel level, String stationId) async {
    try {
      final path = _getCollectionPath(stationId);
      final docRef = await FirebaseFirestore.instance
          .collection(path)
          .add(level.toJson());
      return docRef.id;
    } catch (e) {
      debugPrint('❌ [OnCallLevelRepository] Error in create: $e');
      rethrow;
    }
  }

  /// Met à jour un niveau existant
  Future<void> update(OnCallLevel level, String stationId) async {
    try {
      final path = _getCollectionPath(stationId);
      await FirebaseFirestore.instance
          .collection(path)
          .doc(level.id)
          .update(level.toJson());
    } catch (e) {
      debugPrint('❌ [OnCallLevelRepository] Error in update: $e');
      rethrow;
    }
  }

  /// Supprime un niveau
  Future<void> delete(String id, String stationId) async {
    try {
      final path = _getCollectionPath(stationId);
      await FirebaseFirestore.instance.collection(path).doc(id).delete();
    } catch (e) {
      debugPrint('❌ [OnCallLevelRepository] Error in delete: $e');
      rethrow;
    }
  }

  /// Met à jour l'ordre de tous les niveaux en batch
  Future<void> reorder(List<OnCallLevel> levels, String stationId) async {
    try {
      final path = _getCollectionPath(stationId);
      final batch = FirebaseFirestore.instance.batch();
      for (int i = 0; i < levels.length; i++) {
        final ref =
            FirebaseFirestore.instance.collection(path).doc(levels[i].id);
        batch.update(ref, {'order': i});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('❌ [OnCallLevelRepository] Error in reorder: $e');
      rethrow;
    }
  }
}
