import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';

/// Statut d'une demande d'échange de garde
enum ShiftExchangeRequestStatus {
  pending, // En attente de proposition
  cancelled, // Annulée par le demandeur
  completed, // Échange complété
}

/// Modèle pour une demande d'échange de garde
class ShiftExchangeRequest {
  final String id;
  final String requesterId; // ID de l'utilisateur demandant l'échange
  final String requesterName; // Nom du demandeur (cache)
  final String proposedPlanningId; // ID du planning que le demandeur souhaite échanger
  final DateTime proposedStartTime; // Début de la garde à échanger
  final DateTime proposedEndTime; // Fin de la garde à échanger
  final String stationId; // ID de la caserne
  final String teamId; // ID de l'équipe
  final ShiftExchangeRequestStatus status;
  final int currentWave; // Vague de notification actuelle (comme pour remplacements)
  final List<String> notifiedUserIds; // IDs des utilisateurs notifiés
  final DateTime? lastWaveSentAt; // Date d'envoi de la dernière vague
  final ReplacementMode mode; // Mode : similarity, position, ou manual
  final DateTime createdAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  ShiftExchangeRequest({
    required this.id,
    required this.requesterId,
    required this.requesterName,
    required this.proposedPlanningId,
    required this.proposedStartTime,
    required this.proposedEndTime,
    required this.stationId,
    required this.teamId,
    required this.status,
    this.currentWave = 0,
    this.notifiedUserIds = const [],
    this.lastWaveSentAt,
    required this.mode,
    required this.createdAt,
    this.completedAt,
    this.cancelledAt,
  });

  /// Conversion vers JSON pour Firestore
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'requesterId': requesterId,
      'requesterName': requesterName,
      'proposedPlanningId': proposedPlanningId,
      'proposedStartTime': Timestamp.fromDate(proposedStartTime),
      'proposedEndTime': Timestamp.fromDate(proposedEndTime),
      'stationId': stationId,
      'teamId': teamId,
      'status': status.toString().split('.').last,
      'currentWave': currentWave,
      'notifiedUserIds': notifiedUserIds,
      if (lastWaveSentAt != null)
        'lastWaveSentAt': Timestamp.fromDate(lastWaveSentAt!),
      'mode': mode.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
      if (cancelledAt != null)
        'cancelledAt': Timestamp.fromDate(cancelledAt!),
    };
  }

  /// Création depuis JSON Firestore
  factory ShiftExchangeRequest.fromJson(Map<String, dynamic> json) {
    return ShiftExchangeRequest(
      id: json['id'] as String,
      requesterId: json['requesterId'] as String,
      requesterName: json['requesterName'] as String,
      proposedPlanningId: json['proposedPlanningId'] as String,
      proposedStartTime: (json['proposedStartTime'] as Timestamp).toDate(),
      proposedEndTime: (json['proposedEndTime'] as Timestamp).toDate(),
      stationId: json['stationId'] as String,
      teamId: json['teamId'] as String,
      status: ShiftExchangeRequestStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => ShiftExchangeRequestStatus.pending,
      ),
      currentWave: json['currentWave'] as int? ?? 0,
      notifiedUserIds: json['notifiedUserIds'] != null
          ? List<String>.from(json['notifiedUserIds'] as List)
          : const [],
      lastWaveSentAt: json['lastWaveSentAt'] != null
          ? (json['lastWaveSentAt'] as Timestamp).toDate()
          : null,
      mode: ReplacementMode.values.firstWhere(
        (e) => e.toString().split('.').last == json['mode'],
        orElse: () => ReplacementMode.similarity,
      ),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      completedAt: json['completedAt'] != null
          ? (json['completedAt'] as Timestamp).toDate()
          : null,
      cancelledAt: json['cancelledAt'] != null
          ? (json['cancelledAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Copie avec modifications
  ShiftExchangeRequest copyWith({
    String? id,
    String? requesterId,
    String? requesterName,
    String? proposedPlanningId,
    DateTime? proposedStartTime,
    DateTime? proposedEndTime,
    String? stationId,
    String? teamId,
    ShiftExchangeRequestStatus? status,
    int? currentWave,
    List<String>? notifiedUserIds,
    DateTime? lastWaveSentAt,
    ReplacementMode? mode,
    DateTime? createdAt,
    DateTime? completedAt,
    DateTime? cancelledAt,
  }) {
    return ShiftExchangeRequest(
      id: id ?? this.id,
      requesterId: requesterId ?? this.requesterId,
      requesterName: requesterName ?? this.requesterName,
      proposedPlanningId: proposedPlanningId ?? this.proposedPlanningId,
      proposedStartTime: proposedStartTime ?? this.proposedStartTime,
      proposedEndTime: proposedEndTime ?? this.proposedEndTime,
      stationId: stationId ?? this.stationId,
      teamId: teamId ?? this.teamId,
      status: status ?? this.status,
      currentWave: currentWave ?? this.currentWave,
      notifiedUserIds: notifiedUserIds ?? this.notifiedUserIds,
      lastWaveSentAt: lastWaveSentAt ?? this.lastWaveSentAt,
      mode: mode ?? this.mode,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
    );
  }
}
