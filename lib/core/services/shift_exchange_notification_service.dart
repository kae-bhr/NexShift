import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_request_model.dart';
import 'package:nexshift_app/core/data/models/shift_exchange_proposal_model.dart';

/// Service de notifications pour les échanges d'astreintes
/// Gère toutes les notifications liées au workflow des échanges
class ShiftExchangeNotificationService {
  static final ShiftExchangeNotificationService _instance = ShiftExchangeNotificationService._internal();
  factory ShiftExchangeNotificationService() => _instance;
  ShiftExchangeNotificationService._internal();

  /// Envoie une notification push via le système de triggers
  /// (sera traitée par la Cloud Function qui écoute notificationTriggers)
  Future<void> _sendPushNotification({
    required List<String> targetUserIds,
    required String type,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      if (targetUserIds.isEmpty) {
        debugPrint('⚠️ [ShiftExchangeNotif] No target users for push notification');
        return;
      }

      // Créer un trigger qui sera traité par la Cloud Function
      final triggerData = {
        'type': type,
        'targetUserIds': targetUserIds,
        'title': title,
        'body': body,
        'data': data,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      };

      await FirebaseFirestore.instance
          .collection('notificationTriggers')
          .add(triggerData);

      debugPrint('✅ [ShiftExchangeNotif] Push notification trigger created for ${targetUserIds.length} user(s)');
    } catch (e) {
      debugPrint('❌ [ShiftExchangeNotif] Error creating push notification trigger: $e');
    }
  }

  /// Crée une notification dans Firestore
  Future<void> _createNotification({
    required String userId,
    required String sdisId,
    required String stationId,
    required String type,
    required String title,
    required String body,
    required Map<String, dynamic> data,
    String? actionUrl,
  }) async {
    try {
      final notificationData = {
        'userId': userId,
        'type': type,
        'title': title,
        'body': body,
        'data': data,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
        if (actionUrl != null) 'actionUrl': actionUrl,
      };

      await FirebaseFirestore.instance
          .collection('sdis')
          .doc(sdisId)
          .collection('stations')
          .doc(stationId)
          .collection('notifications')
          .add(notificationData);

      debugPrint('✅ [ShiftExchangeNotif] Notification "$type" sent to user $userId');
    } catch (e) {
      debugPrint('❌ [ShiftExchangeNotif] Error creating notification: $e');
      rethrow;
    }
  }

  /// Notifie l'agent A qu'une nouvelle proposition a été reçue
  ///
  /// Appelé lors de createProposal()
  /// - Agent B vient de proposer ses astreintes
  /// - Notifier A: "Nouvelle proposition de [nom B] pour votre échange"
  Future<void> notifyProposalCreated({
    required ShiftExchangeRequest request,
    required ShiftExchangeProposal proposal,
    required String sdisId,
    required String stationId,
  }) async {
    try {
      debugPrint('📬 [ShiftExchangeNotif] Notifying proposal created...');

      await _createNotification(
        userId: request.initiatorId,
        sdisId: sdisId,
        stationId: stationId,
        type: 'shift_exchange_proposal_received',
        title: 'Nouvelle proposition d\'échange',
        body: '${proposal.proposerName} propose ${proposal.proposedPlanningIds.length} astreinte(s) en échange',
        data: {
          'requestId': request.id,
          'proposalId': proposal.id,
          'proposerName': proposal.proposerName,
          'planningsCount': proposal.proposedPlanningIds.length,
        },
        actionUrl: '/shift-exchange?requestId=${request.id}',
      );

      // Envoyer notification push via FCM
      await _sendPushNotification(
        targetUserIds: [request.initiatorId],
        type: 'shift_exchange_proposal_received',
        title: 'Nouvelle proposition d\'échange',
        body: '${proposal.proposerName} propose ${proposal.proposedPlanningIds.length} astreinte(s) en échange',
        data: {
          'requestId': request.id,
          'proposalId': proposal.id,
          'proposerName': proposal.proposerName,
        },
      );
    } catch (e) {
      debugPrint('❌ [ShiftExchangeNotif] Error notifying proposal created: $e');
    }
  }

  /// Notifie les chefs des 2 équipes qu'une proposition a été sélectionnée
  ///
  /// Appelé lors de selectProposal()
  /// - Agent A a sélectionné une proposition
  /// - Notifier les chefs des 2 équipes: "Validation requise pour échange [nom A] ↔ [nom B]"
  Future<void> notifyProposalSelected({
    required ShiftExchangeRequest request,
    required ShiftExchangeProposal proposal,
    required List<String> chiefIds,
    required String sdisId,
    required String stationId,
  }) async {
    try {
      debugPrint('📬 [ShiftExchangeNotif] Notifying proposal selected to ${chiefIds.length} chiefs...');

      for (final chiefId in chiefIds) {
        // Ne pas notifier le proposeur s'il est chef (auto-validé)
        if (chiefId == proposal.proposerId && proposal.isProposerChief) {
          debugPrint('⏭️  [ShiftExchangeNotif] Skipping chief $chiefId (auto-validated as proposer)');
          continue;
        }

        await _createNotification(
          userId: chiefId,
          sdisId: sdisId,
          stationId: stationId,
          type: 'shift_exchange_validation_required',
          title: 'Validation d\'échange requise',
          body: 'Échange entre ${request.initiatorName} et ${proposal.proposerName}',
          data: {
            'requestId': request.id,
            'proposalId': proposal.id,
            'initiatorName': request.initiatorName,
            'proposerName': proposal.proposerName,
          },
          actionUrl: '/shift-exchange/validation?proposalId=${proposal.id}',
        );
      }

      // Envoyer notifications push via FCM
      // Filtrer les chefs qui ne doivent pas être notifiés (auto-validés)
      final chiefsToNotify = chiefIds.where((chiefId) =>
        !(chiefId == proposal.proposerId && proposal.isProposerChief)
      ).toList();

      if (chiefsToNotify.isNotEmpty) {
        await _sendPushNotification(
          targetUserIds: chiefsToNotify,
          type: 'shift_exchange_validation_required',
          title: 'Validation d\'échange requise',
          body: 'Échange entre ${request.initiatorName} et ${proposal.proposerName}',
          data: {
            'requestId': request.id,
            'proposalId': proposal.id,
            'initiatorName': request.initiatorName,
            'proposerName': proposal.proposerName,
          },
        );
      }
    } catch (e) {
      debugPrint('❌ [ShiftExchangeNotif] Error notifying proposal selected: $e');
    }
  }

  /// Notifie les agents A et B que l'échange a été validé
  ///
  /// Appelé lors de validateProposal() quand canBeFinalized = true
  /// - Les 2 équipes ont validé l'échange
  /// - Notifier A et B: "✅ Échange validé ! Les Subshifts ont été créés"
  Future<void> notifyExchangeValidated({
    required ShiftExchangeRequest request,
    required ShiftExchangeProposal proposal,
    required String sdisId,
    required String stationId,
  }) async {
    try {
      debugPrint('📬 [ShiftExchangeNotif] Notifying exchange validated...');

      // Notifier l'initiateur (Agent A)
      await _createNotification(
        userId: request.initiatorId,
        sdisId: sdisId,
        stationId: stationId,
        type: 'shift_exchange_validated',
        title: '✅ Échange validé',
        body: 'Votre échange avec ${proposal.proposerName} a été validé par les chefs d\'équipe',
        data: {
          'requestId': request.id,
          'proposalId': proposal.id,
          'proposerName': proposal.proposerName,
        },
        actionUrl: '/planning',
      );

      // Notifier le proposeur (Agent B)
      await _createNotification(
        userId: proposal.proposerId,
        sdisId: sdisId,
        stationId: stationId,
        type: 'shift_exchange_validated',
        title: '✅ Échange validé',
        body: 'Votre proposition d\'échange avec ${request.initiatorName} a été validée par les chefs d\'équipe',
        data: {
          'requestId': request.id,
          'proposalId': proposal.id,
          'initiatorName': request.initiatorName,
        },
        actionUrl: '/planning',
      );

      // Envoyer notifications push via FCM
      await _sendPushNotification(
        targetUserIds: [request.initiatorId, proposal.proposerId],
        type: 'shift_exchange_validated',
        title: '✅ Échange validé',
        body: 'L\'échange entre ${request.initiatorName} et ${proposal.proposerName} a été validé',
        data: {
          'requestId': request.id,
          'proposalId': proposal.id,
        },
      );
    } catch (e) {
      debugPrint('❌ [ShiftExchangeNotif] Error notifying exchange validated: $e');
    }
  }

  /// Notifie l'agent A qu'une proposition a été refusée
  ///
  /// Appelé lors de rejectProposal()
  /// - Un chef a refusé l'échange
  /// - Notifier A: "❌ Proposition refusée par le chef - Motif: [raison]"
  Future<void> notifyProposalRejected({
    required ShiftExchangeRequest request,
    required ShiftExchangeProposal proposal,
    required String leaderName,
    required String rejectionReason,
    required String sdisId,
    required String stationId,
  }) async {
    try {
      debugPrint('📬 [ShiftExchangeNotif] Notifying proposal rejected...');

      await _createNotification(
        userId: request.initiatorId,
        sdisId: sdisId,
        stationId: stationId,
        type: 'shift_exchange_rejected',
        title: '❌ Proposition refusée',
        body: 'La proposition de ${proposal.proposerName} a été refusée',
        data: {
          'requestId': request.id,
          'proposalId': proposal.id,
          'proposerName': proposal.proposerName,
          'leaderName': leaderName,
          'rejectionReason': rejectionReason,
        },
        actionUrl: '/shift-exchange?requestId=${request.id}',
      );

      // Envoyer notification push via FCM
      await _sendPushNotification(
        targetUserIds: [request.initiatorId],
        type: 'shift_exchange_rejected',
        title: '❌ Proposition refusée',
        body: 'La proposition de ${proposal.proposerName} a été refusée par $leaderName',
        data: {
          'requestId': request.id,
          'proposalId': proposal.id,
          'proposerName': proposal.proposerName,
          'leaderName': leaderName,
          'rejectionReason': rejectionReason,
        },
      );
    } catch (e) {
      debugPrint('❌ [ShiftExchangeNotif] Error notifying proposal rejected: $e');
    }
  }

  /// Notifie le proposeur que son offre a été sélectionnée
  ///
  /// Appelé lors de selectProposal()
  /// - Agent A a sélectionné la proposition de B
  /// - Notifier B: "Votre proposition a été sélectionnée, en attente de validation"
  Future<void> notifyProposerSelected({
    required ShiftExchangeRequest request,
    required ShiftExchangeProposal proposal,
    required String sdisId,
    required String stationId,
  }) async {
    try {
      debugPrint('📬 [ShiftExchangeNotif] Notifying proposer selected...');

      await _createNotification(
        userId: proposal.proposerId,
        sdisId: sdisId,
        stationId: stationId,
        type: 'shift_exchange_proposer_selected',
        title: '🎯 Votre proposition sélectionnée',
        body: '${request.initiatorName} a sélectionné votre proposition. En attente de validation des chefs.',
        data: {
          'requestId': request.id,
          'proposalId': proposal.id,
          'initiatorName': request.initiatorName,
        },
        actionUrl: '/shift-exchange',
      );

      // Envoyer notification push via FCM
      await _sendPushNotification(
        targetUserIds: [proposal.proposerId],
        type: 'shift_exchange_proposer_selected',
        title: '🎯 Votre proposition sélectionnée',
        body: '${request.initiatorName} a sélectionné votre proposition',
        data: {
          'requestId': request.id,
          'proposalId': proposal.id,
          'initiatorName': request.initiatorName,
        },
      );
    } catch (e) {
      debugPrint('❌ [ShiftExchangeNotif] Error notifying proposer selected: $e');
    }
  }
}
