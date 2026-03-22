import 'package:cloud_firestore/cloud_firestore.dart';

/// Statut d'un événement d'équipe.
enum TeamEventStatus {
  upcoming, // À venir
  cancelled, // Annulé
}

/// Étendue des destinataires d'un événement.
enum TeamEventScope {
  station, // Toute la caserne
  team, // Une équipe spécifique
  agents, // Agents spécifiques
}

/// Événement d'équipe ou de caserne (manœuvre, FMPA, réunion...).
/// Stocké dans : /sdis/{sdisId}/stations/{stationId}/teamEvents/{eventId}
///
/// L'organisateur est automatiquement dans [acceptedUserIds] à la création.
/// Plusieurs agents peuvent accepter (contrairement à AgentQuery qui est "premier arrivé").
class TeamEvent {
  final String id;
  final String createdById;
  final String createdByName; // cache, non persisté
  final String title;
  final int? iconCodePoint; // codePoint d'une icône Material (nullable)
  final String? description;
  final String? location;
  final DateTime startTime;
  final DateTime endTime;
  final String stationId;
  final TeamEventScope scope;
  final String? teamId; // si scope == team
  final List<String> targetAgentIds; // si scope == agents
  final String? planningId; // si intra-planning (FMPA liée à une astreinte)
  final TeamEventStatus status;
  final DateTime createdAt;
  final DateTime? cancelledAt;
  final List<String> invitedUserIds;
  final List<String> acceptedUserIds;
  final List<String> declinedUserIds;
  final List<String> seenByUserIds;
  final List<String> checkedUserIds; // présence physique confirmée par l'organisateur/admin

  TeamEvent({
    required this.id,
    required this.createdById,
    required this.createdByName,
    required this.title,
    this.iconCodePoint,
    this.description,
    this.location,
    required this.startTime,
    required this.endTime,
    required this.stationId,
    required this.scope,
    this.teamId,
    this.targetAgentIds = const [],
    this.planningId,
    required this.status,
    required this.createdAt,
    this.cancelledAt,
    this.invitedUserIds = const [],
    this.acceptedUserIds = const [],
    this.declinedUserIds = const [],
    this.seenByUserIds = const [],
    this.checkedUserIds = const [],
  });

  /// Conversion vers JSON pour Firestore.
  /// createdByName n'est pas persisté (résolu à l'affichage).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdById': createdById,
      'title': title,
      if (iconCodePoint != null) 'iconCodePoint': iconCodePoint,
      if (description != null) 'description': description,
      if (location != null) 'location': location,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'stationId': stationId,
      'scope': scope.toString().split('.').last,
      if (teamId != null) 'teamId': teamId,
      'targetAgentIds': targetAgentIds,
      if (planningId != null) 'planningId': planningId,
      'status': status.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      if (cancelledAt != null) 'cancelledAt': Timestamp.fromDate(cancelledAt!),
      'invitedUserIds': invitedUserIds,
      'acceptedUserIds': acceptedUserIds,
      'declinedUserIds': declinedUserIds,
      'seenByUserIds': seenByUserIds,
      'checkedUserIds': checkedUserIds,
    };
  }

  /// Création depuis JSON Firestore.
  factory TeamEvent.fromJson(Map<String, dynamic> json) {
    return TeamEvent(
      id: json['id'] as String,
      createdById: json['createdById'] as String,
      createdByName: json['createdByName'] as String? ?? '',
      title: json['title'] as String,
      iconCodePoint: json['iconCodePoint'] as int?,
      description: json['description'] as String?,
      location: json['location'] as String?,
      startTime: (json['startTime'] as Timestamp).toDate(),
      endTime: (json['endTime'] as Timestamp).toDate(),
      stationId: json['stationId'] as String,
      scope: TeamEventScope.values.firstWhere(
        (e) => e.toString().split('.').last == json['scope'],
        orElse: () => TeamEventScope.station,
      ),
      teamId: json['teamId'] as String?,
      targetAgentIds: json['targetAgentIds'] != null
          ? List<String>.from(json['targetAgentIds'] as List)
          : const [],
      planningId: json['planningId'] as String?,
      status: TeamEventStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => TeamEventStatus.upcoming,
      ),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      cancelledAt: json['cancelledAt'] != null
          ? (json['cancelledAt'] as Timestamp).toDate()
          : null,
      invitedUserIds: json['invitedUserIds'] != null
          ? List<String>.from(json['invitedUserIds'] as List)
          : const [],
      acceptedUserIds: json['acceptedUserIds'] != null
          ? List<String>.from(json['acceptedUserIds'] as List)
          : const [],
      declinedUserIds: json['declinedUserIds'] != null
          ? List<String>.from(json['declinedUserIds'] as List)
          : const [],
      seenByUserIds: json['seenByUserIds'] != null
          ? List<String>.from(json['seenByUserIds'] as List)
          : const [],
      checkedUserIds: json['checkedUserIds'] != null
          ? List<String>.from(json['checkedUserIds'] as List)
          : const [],
    );
  }

  /// Copie avec modifications.
  TeamEvent copyWith({
    String? id,
    String? createdById,
    String? createdByName,
    String? title,
    int? iconCodePoint,
    bool clearIconCodePoint = false,
    String? description,
    bool clearDescription = false,
    String? location,
    bool clearLocation = false,
    DateTime? startTime,
    DateTime? endTime,
    String? stationId,
    TeamEventScope? scope,
    String? teamId,
    bool clearTeamId = false,
    List<String>? targetAgentIds,
    String? planningId,
    bool clearPlanningId = false,
    TeamEventStatus? status,
    DateTime? createdAt,
    DateTime? cancelledAt,
    bool clearCancelledAt = false,
    List<String>? invitedUserIds,
    List<String>? acceptedUserIds,
    List<String>? declinedUserIds,
    List<String>? seenByUserIds,
    List<String>? checkedUserIds,
  }) {
    return TeamEvent(
      id: id ?? this.id,
      createdById: createdById ?? this.createdById,
      createdByName: createdByName ?? this.createdByName,
      title: title ?? this.title,
      iconCodePoint: clearIconCodePoint ? null : (iconCodePoint ?? this.iconCodePoint),
      description: clearDescription ? null : (description ?? this.description),
      location: clearLocation ? null : (location ?? this.location),
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      stationId: stationId ?? this.stationId,
      scope: scope ?? this.scope,
      teamId: clearTeamId ? null : (teamId ?? this.teamId),
      targetAgentIds: targetAgentIds ?? this.targetAgentIds,
      planningId: clearPlanningId ? null : (planningId ?? this.planningId),
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      cancelledAt: clearCancelledAt ? null : (cancelledAt ?? this.cancelledAt),
      invitedUserIds: invitedUserIds ?? this.invitedUserIds,
      acceptedUserIds: acceptedUserIds ?? this.acceptedUserIds,
      declinedUserIds: declinedUserIds ?? this.declinedUserIds,
      seenByUserIds: seenByUserIds ?? this.seenByUserIds,
      checkedUserIds: checkedUserIds ?? this.checkedUserIds,
    );
  }
}
