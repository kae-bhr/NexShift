import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_proposal_model.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';

/// Service de gestion des échanges de garde
///
/// Phase 1 : Stub service - Interfaces définies, implémentation à venir
class ExchangeService {
  final FirebaseFirestore _firestore;

  ExchangeService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Crée une demande d'échange de garde
  ///
  /// [requester] : Utilisateur demandant l'échange
  /// [planningId] : ID du planning à échanger
  /// [startTime] : Début de la garde à échanger
  /// [endTime] : Fin de la garde à échanger
  /// [mode] : Mode de notification (similarity/position/manual)
  ///
  /// Returns : ID de la demande créée
  ///
  /// Note : Pour le mode manuel, notification uniquement à l'utilisateur sélectionné (pas de vagues)
  Future<String> createExchangeRequest({
    required User requester,
    required String planningId,
    required DateTime startTime,
    required DateTime endTime,
    required ReplacementMode mode,
  }) async {
    // TODO Phase 7 : Implémenter la création de demande d'échange
    // 1. Créer le document ShiftExchangeRequest
    // 2. Déclencher les notifications selon le mode :
    //    - similarity/position : Vagues progressives
    //    - manual : Notification directe à l'utilisateur sélectionné
    throw UnimplementedError('ExchangeService.createExchangeRequest() - À implémenter en Phase 7');
  }

  /// Propose un échange en réponse à une demande
  ///
  /// [exchangeRequestId] : ID de la demande d'échange
  /// [proposer] : Utilisateur proposant l'échange
  /// [proposedPlanningId] : ID du planning proposé en échange
  /// [startTime] : Début de la garde proposée
  /// [endTime] : Fin de la garde proposée
  ///
  /// Notifie le demandeur de la nouvelle proposition
  Future<void> proposeExchange({
    required String exchangeRequestId,
    required User proposer,
    required String proposedPlanningId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    // TODO Phase 7 : Implémenter la proposition d'échange
    // 1. Créer le document ShiftExchangeProposal
    // 2. Notifier le demandeur (utilisateur A)
    throw UnimplementedError('ExchangeService.proposeExchange() - À implémenter en Phase 7');
  }

  /// Le demandeur répond à une proposition
  ///
  /// [proposalId] : ID de la proposition
  /// [accepted] : true si accepté, false si refusé
  /// [rejectionReason] : Motif du refus (si refusé)
  ///
  /// Si accepté : Notifie les deux chefs d'équipe
  /// Si refusé : Permet au proposeur de proposer une autre garde
  Future<void> requesterRespond({
    required String proposalId,
    required bool accepted,
    String? rejectionReason,
  }) async {
    // TODO Phase 7 : Implémenter la réponse du demandeur
    // 1. Mettre à jour la proposition
    // 2. Si accepté :
    //    - Trouver les deux chefs d'équipe
    //    - Notifier les deux chefs
    //    - Mettre à jour status → 'pending_leaders'
    // 3. Si refusé :
    //    - Notifier le proposeur avec le motif
    //    - Permettre une nouvelle proposition
    throw UnimplementedError('ExchangeService.requesterRespond() - À implémenter en Phase 7');
  }

  /// Un chef d'équipe valide ou rejette une proposition
  ///
  /// [proposalId] : ID de la proposition
  /// [leaderId] : ID du chef
  /// [validated] : true si validé, false si rejeté
  /// [comment] : Commentaire optionnel
  ///
  /// Si les deux chefs valident : Crée les deux subshifts (A→B et B→A)
  /// Si au moins un chef rejette : Annule l'échange
  Future<void> leaderValidate({
    required String proposalId,
    required String leaderId,
    required bool validated,
    String? comment,
  }) async {
    // TODO Phase 7 : Implémenter la validation par chef
    // 1. Enregistrer la validation du chef
    // 2. Vérifier si les deux chefs ont répondu
    // 3. Si les deux ont validé :
    //    - Créer deux subshifts (A→B dans planning A, B→A dans planning B)
    //    - Marquer la proposition comme 'validated_by_leaders'
    //    - Marquer la demande d'échange comme 'completed'
    //    - Notifier les deux agents
    // 4. Si au moins un a rejeté :
    //    - Annuler l'échange
    //    - Notifier les deux agents
    throw UnimplementedError('ExchangeService.leaderValidate() - À implémenter en Phase 7');
  }

  /// Récupère les demandes d'échange pour un utilisateur
  ///
  /// [userId] : ID de l'utilisateur
  /// [stationId] : ID de la caserne
  ///
  /// Returns : Stream des demandes d'échange
  Stream<List<ShiftExchangeRequest>> getExchangeRequests({
    required String userId,
    required String stationId,
  }) {
    // TODO Phase 7 : Implémenter la requête
    // Récupérer les demandes où :
    // - userId est le demandeur OU
    // - userId est dans notifiedUserIds
    throw UnimplementedError('ExchangeService.getExchangeRequests() - À implémenter en Phase 7');
  }

  /// Récupère les propositions pour une demande d'échange
  ///
  /// [exchangeRequestId] : ID de la demande d'échange
  ///
  /// Returns : Stream des propositions
  Stream<List<ShiftExchangeProposal>> getProposalsForExchange({
    required String exchangeRequestId,
  }) {
    // TODO Phase 7 : Implémenter la requête
    throw UnimplementedError('ExchangeService.getProposalsForExchange() - À implémenter en Phase 7');
  }

  /// Annule une demande d'échange
  ///
  /// [exchangeRequestId] : ID de la demande à annuler
  /// [userId] : ID de l'utilisateur (doit être le demandeur)
  Future<void> cancelExchangeRequest({
    required String exchangeRequestId,
    required String userId,
  }) async {
    // TODO Phase 7 : Implémenter l'annulation
    // 1. Vérifier que userId est le demandeur
    // 2. Mettre à jour status → 'cancelled'
    // 3. Notifier les utilisateurs déjà notifiés
    throw UnimplementedError('ExchangeService.cancelExchangeRequest() - À implémenter en Phase 7');
  }
}
