import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/agent_query_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';
import 'package:nexshift_app/core/config/environment_config.dart';

/// Repository pour les demandes de recherche automatique d'agent.
/// Chemin Firestore : /sdis/{sdisId}/stations/{stationId}/replacements/queries/{queryId}
class AgentQueryRepository {
  static const String _subcollection = 'agentQueries';

  final FirestoreService _firestoreService;
  final FirebaseFirestore? _directFirestore;

  /// Constructeur par défaut (production)
  AgentQueryRepository({FirestoreService? firestoreService})
      : _firestoreService = firestoreService ?? FirestoreService(),
        _directFirestore = null;

  /// Constructeur pour les tests avec Firestore direct
  AgentQueryRepository.forTest(FirebaseFirestore firestore)
      : _directFirestore = firestore,
        _firestoreService = FirestoreService();

  /// Retourne le chemin de collection.
  /// /sdis/{sdisId}/stations/{stationId}/replacements/queries/agentQueries
  String _getCollectionPath(String stationId) {
    return EnvironmentConfig.getCollectionPath(
        'replacements/queries/$_subcollection', stationId);
  }

  // ============================================================================
  // LECTURE
  // ============================================================================

  /// Récupère toutes les demandes d'une station.
  Future<List<AgentQuery>> getAll({required String stationId}) async {
    try {
      final path = _getCollectionPath(stationId);

      if (_directFirestore != null) {
        final snapshot = await _directFirestore.collection(path).get();
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return AgentQuery.fromJson(data);
        }).toList();
      }

      final data = await _firestoreService.getAll(path);
      return data.map((e) => AgentQuery.fromJson(e)).toList();
    } catch (e) {
      debugPrint('AgentQueryRepository.getAll error: $e');
      rethrow;
    }
  }

  /// Récupère une demande par ID.
  Future<AgentQuery?> getById({
    required String queryId,
    required String stationId,
  }) async {
    try {
      final path = _getCollectionPath(stationId);

      if (_directFirestore != null) {
        final doc = await _directFirestore.collection(path).doc(queryId).get();
        if (!doc.exists) return null;
        final data = doc.data()!;
        data['id'] = doc.id;
        return AgentQuery.fromJson(data);
      }

      final data = await _firestoreService.getById(path, queryId);
      return data != null ? AgentQuery.fromJson(data) : null;
    } catch (e) {
      debugPrint('AgentQueryRepository.getById error: $e');
      rethrow;
    }
  }

  /// Stream temps réel de toutes les demandes d'une station.
  Stream<List<AgentQuery>> watchAll({required String stationId}) {
    final path = _getCollectionPath(stationId);
    final firestore = _directFirestore ?? FirebaseFirestore.instance;

    return firestore
        .collection(path)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return AgentQuery.fromJson(data);
            }).toList());
  }

  /// Stream des demandes en attente (pour pastilles).
  Stream<List<AgentQuery>> watchPending({required String stationId}) {
    final path = _getCollectionPath(stationId);
    final firestore = _directFirestore ?? FirebaseFirestore.instance;

    return firestore
        .collection(path)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return AgentQuery.fromJson(data);
            }).toList());
  }

  // ============================================================================
  // ÉCRITURE
  // ============================================================================

  /// Crée une nouvelle demande et retourne l'ID généré.
  Future<String> create({
    required AgentQuery query,
    required String stationId,
  }) async {
    try {
      final path = _getCollectionPath(stationId);

      if (_directFirestore != null) {
        final docRef = _directFirestore.collection(path).doc(query.id);
        await docRef.set(query.toJson());
        return query.id;
      }

      await _firestoreService.upsert(path, query.id, query.toJson());
      return query.id;
    } catch (e) {
      debugPrint('AgentQueryRepository.create error: $e');
      rethrow;
    }
  }

  /// Met à jour une demande existante.
  Future<void> update({
    required AgentQuery query,
    required String stationId,
  }) async {
    try {
      final path = _getCollectionPath(stationId);

      if (_directFirestore != null) {
        await _directFirestore
            .collection(path)
            .doc(query.id)
            .set(query.toJson());
        return;
      }

      await _firestoreService.upsert(path, query.id, query.toJson());
    } catch (e) {
      debugPrint('AgentQueryRepository.update error: $e');
      rethrow;
    }
  }

  /// Met à jour des champs spécifiques d'une demande (évite les écrasements concurrents).
  Future<void> updateFields({
    required String queryId,
    required String stationId,
    required Map<String, dynamic> fields,
  }) async {
    try {
      final path = _getCollectionPath(stationId);
      final firestore = _directFirestore ?? FirebaseFirestore.instance;
      await firestore.collection(path).doc(queryId).update(fields);
    } catch (e) {
      debugPrint('AgentQueryRepository.updateFields error: $e');
      rethrow;
    }
  }

  /// Annule une demande.
  Future<void> cancel({
    required String queryId,
    required String stationId,
  }) async {
    try {
      await updateFields(
        queryId: queryId,
        stationId: stationId,
        fields: {
          'status': 'cancelled',
          'completedAt': Timestamp.fromDate(DateTime.now()),
        },
      );
    } catch (e) {
      debugPrint('AgentQueryRepository.cancel error: $e');
      rethrow;
    }
  }

  /// Supprime une demande.
  Future<void> delete({
    required String queryId,
    required String stationId,
  }) async {
    try {
      final path = _getCollectionPath(stationId);

      if (_directFirestore != null) {
        await _directFirestore.collection(path).doc(queryId).delete();
        return;
      }

      await _firestoreService.delete(path, queryId);
    } catch (e) {
      debugPrint('AgentQueryRepository.delete error: $e');
      rethrow;
    }
  }
}
