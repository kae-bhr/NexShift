import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/availability_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';
import 'package:nexshift_app/core/config/environment_config.dart';

class AvailabilityRepository {
  static const _collectionName = 'availabilities';
  final FirestoreService _firestoreService;
  final FirebaseFirestore? _directFirestore;
  final String? _stationId;

  /// Constructeur par défaut (production). Passer [stationId] pour utiliser
  /// le chemin scopé à la station (requis pour toutes les opérations en prod).
  AvailabilityRepository({FirestoreService? firestoreService, String? stationId})
      : _firestoreService = firestoreService ?? FirestoreService(),
        _directFirestore = null,
        _stationId = stationId;

  /// Constructeur pour les tests avec Firestore direct.
  /// [stationId] optionnel pour les tests qui n'ont pas de contexte station.
  AvailabilityRepository.forTest(FirebaseFirestore firestore, {String? stationId})
      : _directFirestore = firestore,
        _firestoreService = FirestoreService(),
        _stationId = stationId;

  /// Retourne le chemin de collection selon l'environnement.
  /// Si un stationId est fourni, utilise le chemin scopé :
  ///   /sdis/{sdisId}/stations/{stationId}/availabilities
  /// Sinon, fallback sur la collection racine (legacy).
  String _getCollectionPath() {
    final sid = _stationId;
    if (sid != null && sid.isNotEmpty) {
      return EnvironmentConfig.getCollectionPath(_collectionName, sid);
    }
    return _collectionName;
  }

  /// Récupère toutes les disponibilités
  Future<List<Availability>> getAll() async {
    try {
      final path = _getCollectionPath();

      // Mode test
      if (_directFirestore != null) {
        final snapshot = await _directFirestore.collection(path).get();
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return Availability.fromJson(data);
        }).toList();
      }

      // Mode production
      final data = await _firestoreService.getAll(path);
      return data.map((e) => Availability.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  /// Récupère une disponibilité par ID
  Future<Availability?> getById(String id) async {
    try {
      final path = _getCollectionPath();

      if (_directFirestore != null) {
        final doc = await _directFirestore.collection(path).doc(id).get();
        if (!doc.exists) return null;
        final data = doc.data()!;
        data['id'] = doc.id;
        return Availability.fromJson(data);
      }

      final data = await _firestoreService.getById(path, id);
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
      final path = _getCollectionPath();
      final data = await _firestoreService.getWhere(path, 'agentId', agentId);
      return data.map((e) => Availability.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getByAgentId: $e');
      rethrow;
    }
  }

  /// Récupère les disponibilités pour un planning spécifique
  Future<List<Availability>> getByPlanningId(String planningId) async {
    try {
      final path = _getCollectionPath();
      final data = await _firestoreService.getWhere(path, 'planningId', planningId);
      return data.map((e) => Availability.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getByPlanningId: $e');
      rethrow;
    }
  }

  /// Récupère les disponibilités dans une plage temporelle
  Future<List<Availability>> getInRange(DateTime start, DateTime end) async {
    try {
      final path = _getCollectionPath();
      final data = await _firestoreService.getInDateRange(
        path,
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

  /// Stream temps réel des disponibilités dans une plage temporelle.
  /// Utile pour les mises à jour en direct dans planning_team_details_page.
  Stream<List<Availability>> watchInRange(DateTime start, DateTime end) {
    final path = _getCollectionPath();
    final firestore = _directFirestore ?? FirebaseFirestore.instance;

    return firestore
        .collection(path)
        .where('start', isLessThan: Timestamp.fromDate(end))
        .where('end', isGreaterThan: Timestamp.fromDate(start))
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return Availability.fromJson(data);
            }).toList());
  }

  /// Ajoute ou met à jour une disponibilité
  Future<void> upsert(Availability availability) async {
    try {
      final path = _getCollectionPath();

      // Mode test
      if (_directFirestore != null) {
        await _directFirestore
            .collection(path)
            .doc(availability.id)
            .set(availability.toJson());
        return;
      }

      // Mode production
      await _firestoreService.upsert(path, availability.id, availability.toJson());
    } catch (e) {
      debugPrint('Firestore error during upsert: $e');
      rethrow;
    }
  }

  /// Supprime une disponibilité par son ID
  Future<void> delete(String id) async {
    try {
      final path = _getCollectionPath();

      if (_directFirestore != null) {
        await _directFirestore.collection(path).doc(id).delete();
        return;
      }

      await _firestoreService.delete(path, id);
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
      final path = _getCollectionPath();
      final all = await getAll();
      if (all.isNotEmpty) {
        final operations = all.map((a) => {
          'type': 'delete',
          'collection': path,
          'id': a.id,
        }).toList();
        await _firestoreService.batchWrite(operations);
      }
    } catch (e) {
      debugPrint('Firestore error during clear: $e');
      rethrow;
    }
  }
}
