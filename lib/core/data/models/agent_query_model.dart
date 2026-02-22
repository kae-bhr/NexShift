import 'package:cloud_firestore/cloud_firestore.dart';

/// Statut d'une recherche automatique d'agent.
enum AgentQueryStatus {
  pending, // En attente de réponse
  matched, // Un agent a accepté
  cancelled, // Annulée par le créateur
}

/// Demande de recherche automatique d'agent pour compléter une astreinte.
/// Stockée dans : /sdis/{sdisId}/stations/{stationId}/replacements/queries/{queryId}
///
/// Une demande = un agent trouvé. Le premier agent qui accepte est retenu ;
/// la demande passe alors en [AgentQueryStatus.matched] et est archivée.
class AgentQuery {
  final String id;
  final String createdById; // ID (matricule) du leader/admin ayant créé la demande
  final String createdByName; // Nom d'affichage (cache)
  final String planningId; // Astreinte cible
  final DateTime startTime;
  final DateTime endTime;
  final String station;
  final String onCallLevelId; // ID du niveau d'astreinte à attribuer à l'agent trouvé
  final String onCallLevelName; // Nom du niveau (cache pour affichage)
  final List<String> requiredSkills; // Compétences requises (filtrage des notifiés)
  final AgentQueryStatus status;
  final DateTime createdAt;
  final DateTime? completedAt; // Date à laquelle un agent a accepté ou la demande a été annulée
  final String? matchedAgentId; // ID de l'agent ayant accepté
  final String? matchedAgentName; // Nom de l'agent (cache)
  final List<String> notifiedUserIds; // IDs des agents notifiés
  final List<String> declinedByUserIds; // IDs des agents ayant refusé
  final List<String> seenByUserIds; // IDs des agents ayant vu la demande

  AgentQuery({
    required this.id,
    required this.createdById,
    required this.createdByName,
    required this.planningId,
    required this.startTime,
    required this.endTime,
    required this.station,
    required this.onCallLevelId,
    required this.onCallLevelName,
    required this.requiredSkills,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.matchedAgentId,
    this.matchedAgentName,
    this.notifiedUserIds = const [],
    this.declinedByUserIds = const [],
    this.seenByUserIds = const [],
  });

  /// Conversion vers JSON pour Firestore.
  /// Pas de PII dans ce modèle.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdById': createdById,
      'createdByName': createdByName,
      'planningId': planningId,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'station': station,
      'onCallLevelId': onCallLevelId,
      'onCallLevelName': onCallLevelName,
      'requiredSkills': requiredSkills,
      'status': status.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
      if (matchedAgentId != null) 'matchedAgentId': matchedAgentId,
      if (matchedAgentName != null) 'matchedAgentName': matchedAgentName,
      'notifiedUserIds': notifiedUserIds,
      'declinedByUserIds': declinedByUserIds,
      'seenByUserIds': seenByUserIds,
    };
  }

  /// Création depuis JSON Firestore.
  factory AgentQuery.fromJson(Map<String, dynamic> json) {
    return AgentQuery(
      id: json['id'] as String,
      createdById: json['createdById'] as String,
      createdByName: json['createdByName'] as String? ?? '',
      planningId: json['planningId'] as String,
      startTime: (json['startTime'] as Timestamp).toDate(),
      endTime: (json['endTime'] as Timestamp).toDate(),
      station: json['station'] as String,
      onCallLevelId: json['onCallLevelId'] as String,
      onCallLevelName: json['onCallLevelName'] as String? ?? '',
      requiredSkills: json['requiredSkills'] != null
          ? List<String>.from(json['requiredSkills'] as List)
          : const [],
      status: AgentQueryStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => AgentQueryStatus.pending,
      ),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      completedAt: json['completedAt'] != null
          ? (json['completedAt'] as Timestamp).toDate()
          : null,
      matchedAgentId: json['matchedAgentId'] as String?,
      matchedAgentName: json['matchedAgentName'] as String?,
      notifiedUserIds: json['notifiedUserIds'] != null
          ? List<String>.from(json['notifiedUserIds'] as List)
          : const [],
      declinedByUserIds: json['declinedByUserIds'] != null
          ? List<String>.from(json['declinedByUserIds'] as List)
          : const [],
      seenByUserIds: json['seenByUserIds'] != null
          ? List<String>.from(json['seenByUserIds'] as List)
          : const [],
    );
  }

  /// Copie avec modifications.
  AgentQuery copyWith({
    String? id,
    String? createdById,
    String? createdByName,
    String? planningId,
    DateTime? startTime,
    DateTime? endTime,
    String? station,
    String? onCallLevelId,
    String? onCallLevelName,
    List<String>? requiredSkills,
    AgentQueryStatus? status,
    DateTime? createdAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    String? matchedAgentId,
    bool clearMatchedAgentId = false,
    String? matchedAgentName,
    bool clearMatchedAgentName = false,
    List<String>? notifiedUserIds,
    List<String>? declinedByUserIds,
    List<String>? seenByUserIds,
  }) {
    return AgentQuery(
      id: id ?? this.id,
      createdById: createdById ?? this.createdById,
      createdByName: createdByName ?? this.createdByName,
      planningId: planningId ?? this.planningId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      station: station ?? this.station,
      onCallLevelId: onCallLevelId ?? this.onCallLevelId,
      onCallLevelName: onCallLevelName ?? this.onCallLevelName,
      requiredSkills: requiredSkills ?? this.requiredSkills,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      completedAt:
          clearCompletedAt ? null : (completedAt ?? this.completedAt),
      matchedAgentId:
          clearMatchedAgentId ? null : (matchedAgentId ?? this.matchedAgentId),
      matchedAgentName: clearMatchedAgentName
          ? null
          : (matchedAgentName ?? this.matchedAgentName),
      notifiedUserIds: notifiedUserIds ?? this.notifiedUserIds,
      declinedByUserIds: declinedByUserIds ?? this.declinedByUserIds,
      seenByUserIds: seenByUserIds ?? this.seenByUserIds,
    );
  }
}
