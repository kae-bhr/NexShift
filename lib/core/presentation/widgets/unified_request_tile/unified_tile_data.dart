import 'unified_tile_enums.dart';

/// Données d'un agent pour l'affichage dans une colonne
class AgentColumnData {
  /// ID de l'agent
  final String agentId;

  /// Nom complet de l'agent
  final String agentName;

  /// Équipe de l'agent (optionnel)
  final String? team;

  /// Date/heure de début
  final DateTime startTime;

  /// Date/heure de fin
  final DateTime endTime;

  /// Station
  final String station;

  const AgentColumnData({
    required this.agentId,
    required this.agentName,
    this.team,
    required this.startTime,
    required this.endTime,
    required this.station,
  });

  /// Crée une copie avec un nom de station différent
  AgentColumnData withStation(String stationName) {
    return AgentColumnData(
      agentId: agentId,
      agentName: agentName,
      team: team,
      startTime: startTime,
      endTime: endTime,
      station: stationName,
    );
  }
}

/// Données d'un chef pour l'en-tête de validation
class ChiefValidationData {
  /// ID du chef
  final String chiefId;

  /// Nom du chef
  final String chiefName;

  /// Équipe du chef
  final String? team;

  /// Statut de validation (null = pas encore répondu)
  final bool? hasValidated;

  const ChiefValidationData({
    required this.chiefId,
    required this.chiefName,
    this.team,
    this.hasValidated,
  });
}

/// Modèle de données unifié pour toutes les tuiles de demande
class UnifiedTileData {
  /// Identifiant unique de la demande
  final String id;

  /// Type de demande (auto, SOS, manuel, échange)
  final UnifiedRequestType requestType;

  /// Statut actuel de la demande
  final TileStatus status;

  /// Date de création de la demande
  final DateTime createdAt;

  /// Données de la colonne gauche (demandeur/initiateur)
  final AgentColumnData leftColumn;

  /// Données de la colonne droite (remplaçant/proposeur) - nullable si pas encore de réponse
  final AgentColumnData? rightColumn;

  /// Liste des chefs pour l'en-tête de validation (optionnel)
  final List<ChiefValidationData>? validationChiefs;

  /// IDs des utilisateurs ayant vu la demande
  final List<String> seenByUserIds;

  /// IDs des utilisateurs ayant refusé
  final List<String> declinedByUserIds;

  /// IDs des utilisateurs notifiés
  final List<String> notifiedUserIds;

  /// Numéro de vague actuel (pour remplacement auto)
  final int? currentWave;

  /// Nombre de propositions (pour échanges)
  final int? proposalCount;

  /// Mode SOS activé
  final bool isSOS;

  /// Données supplémentaires spécifiques au type
  final Map<String, dynamic> extraData;

  const UnifiedTileData({
    required this.id,
    required this.requestType,
    required this.status,
    required this.createdAt,
    required this.leftColumn,
    this.rightColumn,
    this.validationChiefs,
    this.seenByUserIds = const [],
    this.declinedByUserIds = const [],
    this.notifiedUserIds = const [],
    this.currentWave,
    this.proposalCount,
    this.isSOS = false,
    this.extraData = const {},
  });

  /// Vérifie si un utilisateur a vu cette demande
  bool hasBeenSeenBy(String userId) => seenByUserIds.contains(userId);

  /// Vérifie si un utilisateur a refusé cette demande
  bool hasBeenDeclinedBy(String userId) => declinedByUserIds.contains(userId);

  /// Vérifie si un utilisateur est notifié pour cette demande
  bool isUserNotified(String userId) => notifiedUserIds.contains(userId);

  /// Vérifie si la demande a un remplaçant/proposeur assigné
  bool get hasRightColumn => rightColumn != null;

  /// Vérifie si la demande nécessite une validation chef
  bool get requiresChiefValidation =>
      validationChiefs != null && validationChiefs!.isNotEmpty;

  /// Remplace le nom de station dans les deux colonnes
  UnifiedTileData withStationName(String stationName) {
    return copyWith(
      leftColumn: leftColumn.withStation(stationName),
      rightColumn: rightColumn?.withStation(stationName),
    );
  }

  /// Crée une copie avec des valeurs modifiées
  UnifiedTileData copyWith({
    String? id,
    UnifiedRequestType? requestType,
    TileStatus? status,
    DateTime? createdAt,
    AgentColumnData? leftColumn,
    AgentColumnData? rightColumn,
    bool clearRightColumn = false,
    List<ChiefValidationData>? validationChiefs,
    bool clearValidationChiefs = false,
    List<String>? seenByUserIds,
    List<String>? declinedByUserIds,
    List<String>? notifiedUserIds,
    int? currentWave,
    int? proposalCount,
    bool? isSOS,
    Map<String, dynamic>? extraData,
  }) {
    return UnifiedTileData(
      id: id ?? this.id,
      requestType: requestType ?? this.requestType,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      leftColumn: leftColumn ?? this.leftColumn,
      rightColumn:
          clearRightColumn ? null : (rightColumn ?? this.rightColumn),
      validationChiefs: clearValidationChiefs
          ? null
          : (validationChiefs ?? this.validationChiefs),
      seenByUserIds: seenByUserIds ?? this.seenByUserIds,
      declinedByUserIds: declinedByUserIds ?? this.declinedByUserIds,
      notifiedUserIds: notifiedUserIds ?? this.notifiedUserIds,
      currentWave: currentWave ?? this.currentWave,
      proposalCount: proposalCount ?? this.proposalCount,
      isSOS: isSOS ?? this.isSOS,
      extraData: extraData ?? this.extraData,
    );
  }
}
