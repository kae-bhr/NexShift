import 'package:cloud_firestore/cloud_firestore.dart';

/// Statut d'une demande d'échange de garde
enum ShiftExchangeRequestStatus {
  open, // En attente de proposition
  proposalSelected, // Agent A a sélectionné une proposition
  accepted, // Échange validé et effectué
  cancelled, // Annulée par le demandeur
}

/// Modèle pour une demande d'échange de garde
class ShiftExchangeRequest {
  final String id;
  final String initiatorId; // Agent A (équipe 1)
  final String initiatorName; // Nom de l'initiateur (cache)
  final String initiatorPlanningId; // Astreinte offerte par A
  final DateTime initiatorStartTime;
  final DateTime initiatorEndTime;
  final String station;
  final String? initiatorTeam; // Équipe de l'initiateur (pour filtrage)

  // Compétences clés requises pour répondre
  final List<String> requiredKeySkills; // keySkills de l'initiateur

  final ShiftExchangeRequestStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;

  // Liste des propositions reçues
  final List<String> proposalIds; // FKs vers ShiftExchangeProposal

  // ID de la proposition sélectionnée par l'initiateur
  final String? selectedProposalId;

  // Liste des utilisateurs ayant refusé cette demande
  final List<String> refusedByUserIds;

  // Liste des utilisateurs ayant déjà soumis une proposition
  final List<String> proposedByUserIds;

  ShiftExchangeRequest({
    required this.id,
    required this.initiatorId,
    required this.initiatorName,
    required this.initiatorPlanningId,
    required this.initiatorStartTime,
    required this.initiatorEndTime,
    required this.station,
    this.initiatorTeam,
    required this.requiredKeySkills,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.proposalIds = const [],
    this.selectedProposalId,
    this.refusedByUserIds = const [],
    this.proposedByUserIds = const [],
  });

  /// Conversion vers JSON pour Firestore
  /// Le champ initiatorName n'est pas persisté — résolu via déchiffrement CF.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'initiatorId': initiatorId,
      'initiatorPlanningId': initiatorPlanningId,
      'initiatorStartTime': Timestamp.fromDate(initiatorStartTime),
      'initiatorEndTime': Timestamp.fromDate(initiatorEndTime),
      'station': station,
      if (initiatorTeam != null) 'initiatorTeam': initiatorTeam,
      'requiredKeySkills': requiredKeySkills,
      'status': status.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
      'proposalIds': proposalIds,
      if (selectedProposalId != null) 'selectedProposalId': selectedProposalId,
      'refusedByUserIds': refusedByUserIds,
      'proposedByUserIds': proposedByUserIds,
    };
  }

  /// Création depuis JSON Firestore
  factory ShiftExchangeRequest.fromJson(Map<String, dynamic> json) {
    return ShiftExchangeRequest(
      id: json['id'] as String,
      initiatorId: json['initiatorId'] as String,
      initiatorName: json['initiatorName'] as String,
      initiatorPlanningId: json['initiatorPlanningId'] as String,
      initiatorStartTime: (json['initiatorStartTime'] as Timestamp).toDate(),
      initiatorEndTime: (json['initiatorEndTime'] as Timestamp).toDate(),
      station: json['station'] as String,
      initiatorTeam: json['initiatorTeam'] as String?,
      requiredKeySkills: json['requiredKeySkills'] != null
          ? List<String>.from(json['requiredKeySkills'] as List)
          : const [],
      status: ShiftExchangeRequestStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => ShiftExchangeRequestStatus.open,
      ),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      completedAt: json['completedAt'] != null
          ? (json['completedAt'] as Timestamp).toDate()
          : null,
      proposalIds: json['proposalIds'] != null
          ? List<String>.from(json['proposalIds'] as List)
          : const [],
      selectedProposalId: json['selectedProposalId'] as String?,
      refusedByUserIds: json['refusedByUserIds'] != null
          ? List<String>.from(json['refusedByUserIds'] as List)
          : const [],
      proposedByUserIds: json['proposedByUserIds'] != null
          ? List<String>.from(json['proposedByUserIds'] as List)
          : const [],
    );
  }

  /// Copie avec modifications
  ShiftExchangeRequest copyWith({
    String? id,
    String? initiatorId,
    String? initiatorName,
    String? initiatorPlanningId,
    DateTime? initiatorStartTime,
    DateTime? initiatorEndTime,
    String? station,
    String? initiatorTeam,
    List<String>? requiredKeySkills,
    ShiftExchangeRequestStatus? status,
    DateTime? createdAt,
    DateTime? completedAt,
    List<String>? proposalIds,
    String? selectedProposalId,
    List<String>? refusedByUserIds,
    List<String>? proposedByUserIds,
  }) {
    return ShiftExchangeRequest(
      id: id ?? this.id,
      initiatorId: initiatorId ?? this.initiatorId,
      initiatorName: initiatorName ?? this.initiatorName,
      initiatorPlanningId: initiatorPlanningId ?? this.initiatorPlanningId,
      initiatorStartTime: initiatorStartTime ?? this.initiatorStartTime,
      initiatorEndTime: initiatorEndTime ?? this.initiatorEndTime,
      station: station ?? this.station,
      initiatorTeam: initiatorTeam ?? this.initiatorTeam,
      requiredKeySkills: requiredKeySkills ?? this.requiredKeySkills,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      proposalIds: proposalIds ?? this.proposalIds,
      selectedProposalId: selectedProposalId ?? this.selectedProposalId,
      refusedByUserIds: refusedByUserIds ?? this.refusedByUserIds,
      proposedByUserIds: proposedByUserIds ?? this.proposedByUserIds,
    );
  }
}
