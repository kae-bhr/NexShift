import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/replacement_acceptance_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';

class ReplacementAcceptanceRepository {
  // Chemin: /sdis/{sdisId}/stations/{stationId}/replacements/automatic/replacementAcceptances
  final FirestoreService _firestoreService;
  final FirebaseFirestore? _directFirestore;

  /// Constructeur par défaut (production)
  ReplacementAcceptanceRepository({FirestoreService? firestoreService})
      : _firestoreService = firestoreService ?? FirestoreService(),
        _directFirestore = null;

  /// Constructeur pour les tests avec Firestore direct
  ReplacementAcceptanceRepository.forTest(FirebaseFirestore firestore)
      : _directFirestore = firestore,
        _firestoreService = FirestoreService();

  /// Retourne le chemin de collection selon l'environnement
  /// /sdis/{sdisId}/stations/{stationId}/replacements/automatic/replacementAcceptances
  String _getCollectionPath(String stationId) {
    if (EnvironmentConfig.useStationSubcollections && stationId.isNotEmpty) {
      final sdisId = SDISContext().currentSDISId;
      if (sdisId != null && sdisId.isNotEmpty) {
        return 'sdis/$sdisId/stations/$stationId/replacements/automatic/replacementAcceptances';
      }
      // Fallback legacy sans SDIS
      return 'stations/$stationId/replacements/automatic/replacementAcceptances';
    }
    return 'replacementAcceptances'; // Fallback pour ancien système
  }

  /// Récupère toutes les acceptations
  Future<List<ReplacementAcceptance>> getAll({required String stationId}) async {
    try {
      final collectionPath = _getCollectionPath(stationId);

      // Mode test
      if (_directFirestore != null) {
        final snapshot = await _directFirestore.collection(collectionPath).get();
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return ReplacementAcceptance.fromJson(data);
        }).toList();
      }

      // Mode production
      final data = await _firestoreService.getAll(collectionPath);
      return data.map((e) => ReplacementAcceptance.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  /// Récupère une acceptation par ID
  Future<ReplacementAcceptance?> getById(String id, {required String stationId}) async {
    try {
      final collectionPath = _getCollectionPath(stationId);
      final data = await _firestoreService.getById(collectionPath, id);
      if (data != null) {
        return ReplacementAcceptance.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Firestore error in getById: $e');
      rethrow;
    }
  }

  /// Récupère les acceptations pour une demande de remplacement spécifique
  Future<List<ReplacementAcceptance>> getByRequestId(String requestId, {required String stationId}) async {
    try {
      final collectionPath = _getCollectionPath(stationId);
      final data = await _firestoreService.getWhere(collectionPath, 'requestId', requestId);
      return data.map((e) => ReplacementAcceptance.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getByRequestId: $e');
      rethrow;
    }
  }

  /// Récupère les acceptations d'un utilisateur spécifique
  Future<List<ReplacementAcceptance>> getByUserId(String userId, {required String stationId}) async {
    try {
      final collectionPath = _getCollectionPath(stationId);
      final data = await _firestoreService.getWhere(collectionPath, 'userId', userId);
      return data.map((e) => ReplacementAcceptance.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getByUserId: $e');
      rethrow;
    }
  }

  /// Récupère les acceptations en attente de validation pour une équipe spécifique
  /// Utilisé par les chefs d'équipe pour voir les acceptations à valider
  Future<List<ReplacementAcceptance>> getPendingForTeam(String teamId, {required String stationId}) async {
    try {
      final collectionPath = _getCollectionPath(stationId);

      // Mode test
      if (_directFirestore != null) {
        final snapshot = await _directFirestore
            .collection(collectionPath)
            .where('chiefTeamId', isEqualTo: teamId)
            .where('status', isEqualTo: 'pendingValidation')
            .get();
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return ReplacementAcceptance.fromJson(data);
        }).toList();
      }

      // Mode production - Nécessite un index composite dans Firestore
      final data = await _firestoreService.getWhereMultiple(collectionPath, {
        'chiefTeamId': teamId,
        'status': 'pendingValidation',
      });
      return data.map((e) => ReplacementAcceptance.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getPendingForTeam: $e');
      rethrow;
    }
  }

  /// Récupère les acceptations avec un statut spécifique
  Future<List<ReplacementAcceptance>> getByStatus(
    ReplacementAcceptanceStatus status,
    {required String stationId}
  ) async {
    try {
      final collectionPath = _getCollectionPath(stationId);
      final data = await _firestoreService.getWhere(
        collectionPath,
        'status',
        status.toString().split('.').last,
      );
      return data.map((e) => ReplacementAcceptance.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getByStatus: $e');
      rethrow;
    }
  }

  /// Ajoute ou met à jour une acceptation
  Future<void> upsert(ReplacementAcceptance acceptance, {required String stationId}) async {
    try {
      final collectionPath = _getCollectionPath(stationId);

      // Mode test
      if (_directFirestore != null) {
        await _directFirestore
            .collection(collectionPath)
            .doc(acceptance.id)
            .set(acceptance.toJson());
        return;
      }

      // Mode production
      await _firestoreService.upsert(collectionPath, acceptance.id, acceptance.toJson());
    } catch (e) {
      debugPrint('Firestore error during upsert: $e');
      rethrow;
    }
  }

  /// Valide une acceptation (appelé par le chef d'équipe)
  Future<void> validate(
    String acceptanceId,
    String validatedBy,
    {required String stationId, String? comment}
  ) async {
    try {
      final acceptance = await getById(acceptanceId, stationId: stationId);
      if (acceptance == null) {
        throw Exception('Acceptation non trouvée: $acceptanceId');
      }

      final updated = acceptance.copyWith(
        status: ReplacementAcceptanceStatus.validated,
        validatedBy: validatedBy,
        validationComment: comment,
        validatedAt: DateTime.now(),
      );

      await upsert(updated, stationId: stationId);
    } catch (e) {
      debugPrint('Firestore error during validate: $e');
      rethrow;
    }
  }

  /// Rejette une acceptation (appelé par le chef d'équipe)
  Future<void> reject(
    String acceptanceId,
    String rejectedBy,
    String rejectionReason,
    {required String stationId}
  ) async {
    try {
      if (rejectionReason.trim().isEmpty) {
        throw Exception('Le motif de refus est obligatoire');
      }

      final acceptance = await getById(acceptanceId, stationId: stationId);
      if (acceptance == null) {
        throw Exception('Acceptation non trouvée: $acceptanceId');
      }

      final updated = acceptance.copyWith(
        status: ReplacementAcceptanceStatus.rejected,
        rejectedBy: rejectedBy,
        rejectionReason: rejectionReason,
        rejectedAt: DateTime.now(),
      );

      await upsert(updated, stationId: stationId);

      // Retirer l'utilisateur de pendingValidationUserIds dans la demande de remplacement
      final requestsPath = EnvironmentConfig.useStationSubcollections && stationId.isNotEmpty
          ? (SDISContext().currentSDISId != null && SDISContext().currentSDISId!.isNotEmpty
              ? 'sdis/${SDISContext().currentSDISId}/stations/$stationId/replacements'
              : 'stations/$stationId/replacements')
          : 'replacementRequests';

      await _firestoreService.firestore.collection(requestsPath).doc(acceptance.requestId).update({
        'pendingValidationUserIds': FieldValue.arrayRemove([acceptance.userId]),
      });
      debugPrint('✅ User removed from pendingValidationUserIds after rejection: ${acceptance.userId}');
    } catch (e) {
      debugPrint('Firestore error during reject: $e');
      rethrow;
    }
  }

  /// Supprime une acceptation par son ID
  Future<void> delete(String id, {required String stationId}) async {
    try {
      final collectionPath = _getCollectionPath(stationId);
      await _firestoreService.delete(collectionPath, id);
    } catch (e) {
      debugPrint('Firestore error during delete: $e');
      rethrow;
    }
  }

  /// Supprime toutes les acceptations pour une demande spécifique
  Future<void> deleteByRequestId(String requestId, {required String stationId}) async {
    try {
      final acceptances = await getByRequestId(requestId, stationId: stationId);
      if (acceptances.isNotEmpty) {
        final collectionPath = _getCollectionPath(stationId);
        final operations = acceptances.map((a) => {
          'type': 'delete',
          'collection': collectionPath,
          'id': a.id,
        }).toList();
        await _firestoreService.batchWrite(operations);
      }
    } catch (e) {
      debugPrint('Firestore error during deleteByRequestId: $e');
      rethrow;
    }
  }

  /// Supprime toutes les acceptations
  Future<void> clear({required String stationId}) async {
    try {
      final all = await getAll(stationId: stationId);
      if (all.isNotEmpty) {
        final collectionPath = _getCollectionPath(stationId);
        final operations = all.map((a) => {
          'type': 'delete',
          'collection': collectionPath,
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
