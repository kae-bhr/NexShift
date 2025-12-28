import 'package:cloud_firestore/cloud_firestore.dart';

/// Statut d'une proposition d'échange
enum ShiftExchangeProposalStatus {
  pendingRequester, // En attente de réponse du demandeur
  acceptedByRequester, // Acceptée par le demandeur
  rejectedByRequester, // Rejetée par le demandeur
  pendingLeaders, // En attente de validation des chefs d'équipe
  validatedByLeaders, // Validée par les deux chefs
  rejectedByLeaders, // Rejetée par au moins un chef
}

/// Réponse du demandeur à une proposition
enum RequesterResponse {
  pending, // Pas encore répondu
  accepted, // Accepté
  rejected, // Refusé
}

/// Validation d'un chef d'équipe
class LeaderValidation {
  final bool validated;
  final DateTime validatedAt;
  final String? comment;

  LeaderValidation({
    required this.validated,
    required this.validatedAt,
    this.comment,
  });

  Map<String, dynamic> toJson() {
    return {
      'validated': validated,
      'validatedAt': Timestamp.fromDate(validatedAt),
      if (comment != null) 'comment': comment,
    };
  }

  factory LeaderValidation.fromJson(Map<String, dynamic> json) {
    return LeaderValidation(
      validated: json['validated'] as bool,
      validatedAt: (json['validatedAt'] as Timestamp).toDate(),
      comment: json['comment'] as String?,
    );
  }
}

/// Modèle pour une proposition d'échange de garde
class ShiftExchangeProposal {
  final String id;
  final String exchangeRequestId; // FK vers shiftExchangeRequests
  final String proposerId; // ID de l'utilisateur proposant l'échange
  final String proposerName; // Nom du proposeur (cache)
  final String proposedPlanningId; // ID du planning proposé en échange
  final DateTime proposedStartTime; // Début de la garde proposée
  final DateTime proposedEndTime; // Fin de la garde proposée
  final ShiftExchangeProposalStatus status;

  // Réponse du demandeur
  final RequesterResponse requesterResponse;
  final DateTime? requesterResponseAt;
  final String? requesterRejectionReason;

  // Validations des chefs d'équipe
  final Map<String, LeaderValidation>
      leaderValidations; // Map<leaderId, LeaderValidation>

  final DateTime createdAt;
  final DateTime? completedAt;

  ShiftExchangeProposal({
    required this.id,
    required this.exchangeRequestId,
    required this.proposerId,
    required this.proposerName,
    required this.proposedPlanningId,
    required this.proposedStartTime,
    required this.proposedEndTime,
    required this.status,
    this.requesterResponse = RequesterResponse.pending,
    this.requesterResponseAt,
    this.requesterRejectionReason,
    this.leaderValidations = const {},
    required this.createdAt,
    this.completedAt,
  });

  /// Conversion vers JSON pour Firestore
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'exchangeRequestId': exchangeRequestId,
      'proposerId': proposerId,
      'proposerName': proposerName,
      'proposedPlanningId': proposedPlanningId,
      'proposedStartTime': Timestamp.fromDate(proposedStartTime),
      'proposedEndTime': Timestamp.fromDate(proposedEndTime),
      'status': status.toString().split('.').last,
      'requesterResponse': requesterResponse.toString().split('.').last,
      if (requesterResponseAt != null)
        'requesterResponseAt': Timestamp.fromDate(requesterResponseAt!),
      if (requesterRejectionReason != null)
        'requesterRejectionReason': requesterRejectionReason,
      'leaderValidations': leaderValidations
          .map((key, value) => MapEntry(key, value.toJson())),
      'createdAt': Timestamp.fromDate(createdAt),
      if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
    };
  }

  /// Création depuis JSON Firestore
  factory ShiftExchangeProposal.fromJson(Map<String, dynamic> json) {
    // Parse leaderValidations
    Map<String, LeaderValidation> validations = {};
    if (json['leaderValidations'] != null) {
      final validationsData = json['leaderValidations'];
      if (validationsData is Map) {
        for (var entry in validationsData.entries) {
          validations[entry.key.toString()] = LeaderValidation.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }

    return ShiftExchangeProposal(
      id: json['id'] as String,
      exchangeRequestId: json['exchangeRequestId'] as String,
      proposerId: json['proposerId'] as String,
      proposerName: json['proposerName'] as String,
      proposedPlanningId: json['proposedPlanningId'] as String,
      proposedStartTime: (json['proposedStartTime'] as Timestamp).toDate(),
      proposedEndTime: (json['proposedEndTime'] as Timestamp).toDate(),
      status: ShiftExchangeProposalStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => ShiftExchangeProposalStatus.pendingRequester,
      ),
      requesterResponse: RequesterResponse.values.firstWhere(
        (e) => e.toString().split('.').last == json['requesterResponse'],
        orElse: () => RequesterResponse.pending,
      ),
      requesterResponseAt: json['requesterResponseAt'] != null
          ? (json['requesterResponseAt'] as Timestamp).toDate()
          : null,
      requesterRejectionReason: json['requesterRejectionReason'] as String?,
      leaderValidations: validations,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      completedAt: json['completedAt'] != null
          ? (json['completedAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Copie avec modifications
  ShiftExchangeProposal copyWith({
    String? id,
    String? exchangeRequestId,
    String? proposerId,
    String? proposerName,
    String? proposedPlanningId,
    DateTime? proposedStartTime,
    DateTime? proposedEndTime,
    ShiftExchangeProposalStatus? status,
    RequesterResponse? requesterResponse,
    DateTime? requesterResponseAt,
    String? requesterRejectionReason,
    Map<String, LeaderValidation>? leaderValidations,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return ShiftExchangeProposal(
      id: id ?? this.id,
      exchangeRequestId: exchangeRequestId ?? this.exchangeRequestId,
      proposerId: proposerId ?? this.proposerId,
      proposerName: proposerName ?? this.proposerName,
      proposedPlanningId: proposedPlanningId ?? this.proposedPlanningId,
      proposedStartTime: proposedStartTime ?? this.proposedStartTime,
      proposedEndTime: proposedEndTime ?? this.proposedEndTime,
      status: status ?? this.status,
      requesterResponse: requesterResponse ?? this.requesterResponse,
      requesterResponseAt: requesterResponseAt ?? this.requesterResponseAt,
      requesterRejectionReason:
          requesterRejectionReason ?? this.requesterRejectionReason,
      leaderValidations: leaderValidations ?? this.leaderValidations,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  /// Vérifie si les deux chefs ont validé
  bool get allLeadersValidated {
    if (leaderValidations.length != 2) return false;
    return leaderValidations.values.every((v) => v.validated);
  }

  /// Vérifie si au moins un chef a refusé
  bool get anyLeaderRejected {
    if (leaderValidations.isEmpty) return false;
    return leaderValidations.values.any((v) => !v.validated);
  }
}
