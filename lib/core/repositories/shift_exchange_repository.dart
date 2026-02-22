import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_proposal_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';

class ShiftExchangeRepository {
  // Chemin: /sdis/{sdisId}/stations/{stationId}/replacements/exchange/shiftExchangeRequests
  // Chemin: /sdis/{sdisId}/stations/{stationId}/replacements/exchange/shiftExchangeProposals
  final FirestoreService _firestoreService;
  final FirebaseFirestore? _directFirestore;
  final PlanningRepository _planningRepository;

  /// Constructeur par défaut (production)
  ShiftExchangeRepository({
    FirestoreService? firestoreService,
    PlanningRepository? planningRepository,
  }) : _firestoreService = firestoreService ?? FirestoreService(),
       _directFirestore = null,
       _planningRepository = planningRepository ?? PlanningRepository();

  /// Constructeur pour les tests avec Firestore direct
  ShiftExchangeRepository.forTest(FirebaseFirestore firestore)
    : _directFirestore = firestore,
      _firestoreService = FirestoreService(),
      _planningRepository = PlanningRepository();

  /// Retourne le chemin de collection selon l'environnement
  /// /sdis/{sdisId}/stations/{stationId}/replacements/exchange/{subcollection}
  String _getCollectionPath(String stationId, String subcollection) {
    return EnvironmentConfig.getCollectionPath(
        'replacements/exchange/$subcollection', stationId);
  }

  // ============================================================================
  // MÉTHODES POUR SHIFT EXCHANGE REQUESTS
  // ============================================================================

  /// Récupère toutes les demandes d'échange
  Future<List<ShiftExchangeRequest>> getAllRequests({
    required String stationId,
  }) async {
    try {
      final collectionPath = _getCollectionPath(
        stationId,
        'shiftExchangeRequests',
      );

      // Mode test
      if (_directFirestore != null) {
        final snapshot = await _directFirestore
            .collection(collectionPath)
            .get();
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return ShiftExchangeRequest.fromJson(data);
        }).toList();
      }

      // Mode production
      final data = await _firestoreService.getAll(collectionPath);
      return data.map((e) => ShiftExchangeRequest.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAllRequests: $e');
      rethrow;
    }
  }

  /// Récupère une demande d'échange par ID
  Future<ShiftExchangeRequest?> getRequestById(
    String id, {
    required String stationId,
  }) async {
    try {
      final collectionPath = _getCollectionPath(
        stationId,
        'shiftExchangeRequests',
      );
      final data = await _firestoreService.getById(collectionPath, id);
      if (data != null) {
        return ShiftExchangeRequest.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Firestore error in getRequestById: $e');
      rethrow;
    }
  }

  /// Récupère les demandes d'échange d'un utilisateur
  Future<List<ShiftExchangeRequest>> getRequestsByInitiator(
    String initiatorId, {
    required String stationId,
  }) async {
    try {
      final collectionPath = _getCollectionPath(
        stationId,
        'shiftExchangeRequests',
      );
      final data = await _firestoreService.getWhere(
        collectionPath,
        'initiatorId',
        initiatorId,
      );
      return data.map((e) => ShiftExchangeRequest.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getRequestsByInitiator: $e');
      rethrow;
    }
  }

  /// Récupère les demandes ouvertes
  Future<List<ShiftExchangeRequest>> getOpenRequests({
    required String stationId,
  }) async {
    try {
      final collectionPath = _getCollectionPath(
        stationId,
        'shiftExchangeRequests',
      );
      final data = await _firestoreService.getWhere(
        collectionPath,
        'status',
        'open',
      );
      return data.map((e) => ShiftExchangeRequest.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getOpenRequests: $e');
      rethrow;
    }
  }

  /// Récupère les demandes ouvertes pour lesquelles l'utilisateur possède les compétences requises
  /// Filtre également pour exclure les demandes de la même équipe que l'utilisateur
  Future<List<ShiftExchangeRequest>> getAvailableRequestsForUser(
    String userId,
    List<String> userKeySkills, {
    required String stationId,
  }) async {
    try {
      debugPrint(
        '🔍 [EXCHANGE_REPO] getAvailableRequestsForUser for userId=$userId, stationId=$stationId',
      );
      final openRequests = await getOpenRequests(stationId: stationId);
      debugPrint(
        '🔍 [EXCHANGE_REPO] Found ${openRequests.length} open requests',
      );

      // Récupérer l'équipe de l'utilisateur depuis ses plannings
      String? userTeam;
      try {
        final userPlannings = await _planningRepository.getForUser(
          userId,
          stationId: stationId,
        );
        if (userPlannings.isNotEmpty) {
          userTeam = userPlannings.first.team;
          debugPrint('🔍 [EXCHANGE_REPO] User $userId is in team: $userTeam');
        } else {
          debugPrint('🔍 [EXCHANGE_REPO] User $userId has no plannings');
        }
      } catch (e) {
        debugPrint('❌ [EXCHANGE_REPO] Error fetching user team: $e');
      }

      debugPrint('🔍 [EXCHANGE_REPO] User keySkills: $userKeySkills');

      // Récupérer toutes les propositions de l'utilisateur pour vérification de secours
      // (pour les anciennes demandes qui n'ont pas proposedByUserIds peuplé)
      final allProposals = await getAllProposals(stationId: stationId);
      final userProposalRequestIds = allProposals
          .where((p) => p.proposerId == userId)
          .map((p) => p.requestId)
          .toSet();
      debugPrint(
        '🔍 [EXCHANGE_REPO] User has proposals for ${userProposalRequestIds.length} requests',
      );

      // Filtrer les demandes
      final filteredRequests = <ShiftExchangeRequest>[];
      for (final request in openRequests) {
        debugPrint(
          '🔍 [EXCHANGE_REPO] Checking request ${request.id} from ${request.initiatorName}',
        );

        // Exclure ses propres demandes
        if (request.initiatorId == userId) {
          debugPrint('  ❌ Excluded: own request');
          continue;
        }

        // Exclure les demandes refusées par l'utilisateur
        if (request.refusedByUserIds.contains(userId)) {
          debugPrint('  ❌ Excluded: user refused this request');
          continue;
        }

        // Exclure les demandes pour lesquelles l'utilisateur a déjà proposé
        // Vérification 1: via le champ proposedByUserIds (nouvelles demandes)
        // Vérification 2: via les propositions existantes (anciennes demandes sans le champ)
        if (request.proposedByUserIds.contains(userId) ||
            userProposalRequestIds.contains(request.id)) {
          debugPrint('  ❌ Excluded: user already proposed for this request');
          continue;
        }

        // Vérifier les compétences requises
        final userSkillsSet = Set<String>.from(userKeySkills);
        final requiredSkillsSet = Set<String>.from(request.requiredKeySkills);
        debugPrint('  🔍 Required skills: ${request.requiredKeySkills}');
        if (requiredSkillsSet.difference(userSkillsSet).isNotEmpty) {
          final missingSkills = requiredSkillsSet.difference(userSkillsSet);
          debugPrint('  ❌ Excluded: missing skills $missingSkills');
          continue;
        }

        // Vérifier que la demande provient d'une équipe différente
        if (userTeam != null) {
          try {
            final requestPlanning = await _planningRepository.getById(
              request.initiatorPlanningId,
              stationId: stationId,
            );
            if (requestPlanning != null) {
              debugPrint('  🔍 Request is from team: ${requestPlanning.team}');
              if (requestPlanning.team == userTeam) {
                // Même équipe, exclure cette demande
                debugPrint('  ❌ Excluded: same team');
                continue;
              }
            } else {
              debugPrint(
                '  ⚠️ Could not find planning ${request.initiatorPlanningId}',
              );
            }
          } catch (e) {
            debugPrint('  ❌ Error checking request team: $e');
          }
        }

        debugPrint('  ✅ Request ${request.id} is available for user');
        filteredRequests.add(request);
      }

      debugPrint(
        '🔍 [EXCHANGE_REPO] Filtered requests: ${filteredRequests.length} available',
      );
      return filteredRequests;
    } catch (e) {
      debugPrint('Firestore error in getAvailableRequestsForUser: $e');
      rethrow;
    }
  }

  /// Ajoute ou met à jour une demande d'échange
  Future<void> upsertRequest(
    ShiftExchangeRequest request, {
    required String stationId,
  }) async {
    try {
      final collectionPath = _getCollectionPath(
        stationId,
        'shiftExchangeRequests',
      );

      // Mode test
      if (_directFirestore != null) {
        await _directFirestore
            .collection(collectionPath)
            .doc(request.id)
            .set(request.toJson());
        return;
      }

      // Mode production
      await _firestoreService.upsert(
        collectionPath,
        request.id,
        request.toJson(),
      );
    } catch (e) {
      debugPrint('Firestore error during upsertRequest: $e');
      rethrow;
    }
  }

  /// Supprime une demande d'échange
  Future<void> deleteRequest(String id, {required String stationId}) async {
    try {
      final collectionPath = _getCollectionPath(
        stationId,
        'shiftExchangeRequests',
      );
      await _firestoreService.delete(collectionPath, id);
    } catch (e) {
      debugPrint('Firestore error during deleteRequest: $e');
      rethrow;
    }
  }

  // ============================================================================
  // MÉTHODES POUR SHIFT EXCHANGE PROPOSALS
  // ============================================================================

  /// Récupère toutes les propositions d'échange
  Future<List<ShiftExchangeProposal>> getAllProposals({
    required String stationId,
  }) async {
    try {
      final collectionPath = _getCollectionPath(
        stationId,
        'shiftExchangeProposals',
      );

      // Mode test
      if (_directFirestore != null) {
        final snapshot = await _directFirestore
            .collection(collectionPath)
            .get();
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return ShiftExchangeProposal.fromJson(data);
        }).toList();
      }

      // Mode production
      final data = await _firestoreService.getAll(collectionPath);
      return data.map((e) => ShiftExchangeProposal.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAllProposals: $e');
      rethrow;
    }
  }

  /// Récupère une proposition par ID
  Future<ShiftExchangeProposal?> getProposalById(
    String id, {
    required String stationId,
  }) async {
    try {
      final collectionPath = _getCollectionPath(
        stationId,
        'shiftExchangeProposals',
      );
      final data = await _firestoreService.getById(collectionPath, id);
      if (data != null) {
        return ShiftExchangeProposal.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Firestore error in getProposalById: $e');
      rethrow;
    }
  }

  /// Récupère les propositions pour une demande spécifique
  Future<List<ShiftExchangeProposal>> getProposalsByRequestId(
    String requestId, {
    required String stationId,
  }) async {
    try {
      final collectionPath = _getCollectionPath(
        stationId,
        'shiftExchangeProposals',
      );
      final data = await _firestoreService.getWhere(
        collectionPath,
        'requestId',
        requestId,
      );
      return data.map((e) => ShiftExchangeProposal.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getProposalsByRequestId: $e');
      rethrow;
    }
  }

  /// Récupère les propositions d'un utilisateur
  Future<List<ShiftExchangeProposal>> getProposalsByProposer(
    String proposerId, {
    required String stationId,
  }) async {
    try {
      final collectionPath = _getCollectionPath(
        stationId,
        'shiftExchangeProposals',
      );
      final data = await _firestoreService.getWhere(
        collectionPath,
        'proposerId',
        proposerId,
      );
      return data.map((e) => ShiftExchangeProposal.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getProposalsByProposer: $e');
      rethrow;
    }
  }

  /// Récupère les propositions par statut
  Future<List<ShiftExchangeProposal>> getProposalsByStatus(
    ShiftExchangeProposalStatus status, {
    required String stationId,
  }) async {
    try {
      final collectionPath = _getCollectionPath(
        stationId,
        'shiftExchangeProposals',
      );
      final statusString = status.toString().split('.').last;

      // Mode test
      if (_directFirestore != null) {
        final snapshot = await _directFirestore
            .collection(collectionPath)
            .where('status', isEqualTo: statusString)
            .get();
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return ShiftExchangeProposal.fromJson(data);
        }).toList();
      }

      // Mode production
      final data = await _firestoreService.getWhere(
        collectionPath,
        'status',
        statusString,
      );
      return data.map((e) => ShiftExchangeProposal.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getProposalsByStatus: $e');
      rethrow;
    }
  }

  /// Récupère les propositions en attente de validation pour une équipe
  /// Utilisé par les chefs d'équipe
  Future<List<ShiftExchangeProposal>> getPendingProposalsForTeam(
    String teamId, {
    required String stationId,
  }) async {
    try {
      final collectionPath = _getCollectionPath(
        stationId,
        'shiftExchangeProposals',
      );

      // Mode test
      if (_directFirestore != null) {
        final snapshot = await _directFirestore
            .collection(collectionPath)
            .where('status', isEqualTo: 'pendingValidation')
            .get();

        // Filtrer les propositions où la validation de cette équipe est manquante
        return snapshot.docs
            .map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return ShiftExchangeProposal.fromJson(data);
            })
            .where((proposal) {
              // Retourner si cette équipe n'a pas encore validé
              return !proposal.leaderValidations.containsKey(teamId);
            })
            .toList();
      }

      // Mode production
      final data = await _firestoreService.getWhere(
        collectionPath,
        'status',
        'pendingValidation',
      );
      final proposals = data
          .map((e) => ShiftExchangeProposal.fromJson(e))
          .toList();

      // Filtrer les propositions où la validation de cette équipe est manquante
      return proposals.where((proposal) {
        return !proposal.leaderValidations.containsKey(teamId);
      }).toList();
    } catch (e) {
      debugPrint('Firestore error in getPendingProposalsForTeam: $e');
      rethrow;
    }
  }

  /// Ajoute ou met à jour une proposition d'échange
  Future<void> upsertProposal(
    ShiftExchangeProposal proposal, {
    required String stationId,
  }) async {
    try {
      final collectionPath = _getCollectionPath(
        stationId,
        'shiftExchangeProposals',
      );

      // Mode test
      if (_directFirestore != null) {
        await _directFirestore
            .collection(collectionPath)
            .doc(proposal.id)
            .set(proposal.toJson());
        return;
      }

      // Mode production
      await _firestoreService.upsert(
        collectionPath,
        proposal.id,
        proposal.toJson(),
      );
    } catch (e) {
      debugPrint('Firestore error during upsertProposal: $e');
      rethrow;
    }
  }

  /// Supprime une proposition
  Future<void> deleteProposal(String id, {required String stationId}) async {
    try {
      final collectionPath = _getCollectionPath(
        stationId,
        'shiftExchangeProposals',
      );
      await _firestoreService.delete(collectionPath, id);
    } catch (e) {
      debugPrint('Firestore error during deleteProposal: $e');
      rethrow;
    }
  }

  /// Supprime toutes les propositions d'une demande
  Future<void> deleteProposalsByRequestId(
    String requestId, {
    required String stationId,
  }) async {
    try {
      final proposals = await getProposalsByRequestId(
        requestId,
        stationId: stationId,
      );
      if (proposals.isNotEmpty) {
        final collectionPath = _getCollectionPath(
          stationId,
          'shiftExchangeProposals',
        );
        final operations = proposals
            .map(
              (p) => {
                'type': 'delete',
                'collection': collectionPath,
                'id': p.id,
              },
            )
            .toList();
        await _firestoreService.batchWrite(operations);
      }
    } catch (e) {
      debugPrint('Firestore error during deleteProposalsByRequestId: $e');
      rethrow;
    }
  }
}
