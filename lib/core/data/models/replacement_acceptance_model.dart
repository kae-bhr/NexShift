import 'package:cloud_firestore/cloud_firestore.dart';

/// Statut d'une acceptation de remplacement
enum ReplacementAcceptanceStatus {
  pendingValidation, // En attente de validation par le chef
  validated, // Validée par le chef
  rejected, // Rejetée par le chef
}

/// Modèle pour une acceptation de remplacement en attente de validation
class ReplacementAcceptance {
  final String id;
  final String requestId; // FK vers replacementRequests
  final String userId; // ID de l'agent acceptant
  final String userName; // Nom de l'agent (cache pour affichage)
  final DateTime acceptedStartTime; // Heure de début acceptée
  final DateTime acceptedEndTime; // Heure de fin acceptée
  final ReplacementAcceptanceStatus status;
  final String? validatedBy; // ID du chef d'équipe/centre/admin qui a validé
  final String? validationComment; // Commentaire optionnel lors de la validation
  final String? rejectedBy; // ID du chef qui a rejeté
  final String? rejectionReason; // Motif du refus
  final DateTime createdAt; // Date de création de l'acceptation
  final DateTime? validatedAt; // Date de validation
  final DateTime? rejectedAt; // Date de rejet
  final DateTime? lastReminderSentAt; // Date du dernier rappel envoyé au chef
  final String chiefTeamId; // Équipe de l'astreinte concernée (pour notifier le bon chef)

  ReplacementAcceptance({
    required this.id,
    required this.requestId,
    required this.userId,
    required this.userName,
    required this.acceptedStartTime,
    required this.acceptedEndTime,
    required this.status,
    this.validatedBy,
    this.validationComment,
    this.rejectedBy,
    this.rejectionReason,
    required this.createdAt,
    this.validatedAt,
    this.rejectedAt,
    this.lastReminderSentAt,
    required this.chiefTeamId,
  });

  /// Conversion vers JSON pour Firestore
  /// Le champ userName n'est pas persisté — résolu via déchiffrement CF.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'requestId': requestId,
      'userId': userId,
      'acceptedStartTime': Timestamp.fromDate(acceptedStartTime),
      'acceptedEndTime': Timestamp.fromDate(acceptedEndTime),
      'status': status.toString().split('.').last,
      if (validatedBy != null) 'validatedBy': validatedBy,
      if (validationComment != null) 'validationComment': validationComment,
      if (rejectedBy != null) 'rejectedBy': rejectedBy,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      'createdAt': Timestamp.fromDate(createdAt),
      if (validatedAt != null) 'validatedAt': Timestamp.fromDate(validatedAt!),
      if (rejectedAt != null) 'rejectedAt': Timestamp.fromDate(rejectedAt!),
      if (lastReminderSentAt != null)
        'lastReminderSentAt': Timestamp.fromDate(lastReminderSentAt!),
      'chiefTeamId': chiefTeamId,
    };
  }

  /// Création depuis JSON Firestore
  factory ReplacementAcceptance.fromJson(Map<String, dynamic> json) {
    return ReplacementAcceptance(
      id: json['id'] as String,
      requestId: json['requestId'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      acceptedStartTime: (json['acceptedStartTime'] as Timestamp).toDate(),
      acceptedEndTime: (json['acceptedEndTime'] as Timestamp).toDate(),
      status: ReplacementAcceptanceStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => ReplacementAcceptanceStatus.pendingValidation,
      ),
      validatedBy: json['validatedBy'] as String?,
      validationComment: json['validationComment'] as String?,
      rejectedBy: json['rejectedBy'] as String?,
      rejectionReason: json['rejectionReason'] as String?,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      validatedAt: json['validatedAt'] != null
          ? (json['validatedAt'] as Timestamp).toDate()
          : null,
      rejectedAt: json['rejectedAt'] != null
          ? (json['rejectedAt'] as Timestamp).toDate()
          : null,
      lastReminderSentAt: json['lastReminderSentAt'] != null
          ? (json['lastReminderSentAt'] as Timestamp).toDate()
          : null,
      chiefTeamId: json['chiefTeamId'] as String? ?? '',
    );
  }

  /// Copie avec modifications
  ReplacementAcceptance copyWith({
    String? id,
    String? requestId,
    String? userId,
    String? userName,
    DateTime? acceptedStartTime,
    DateTime? acceptedEndTime,
    ReplacementAcceptanceStatus? status,
    String? validatedBy,
    String? validationComment,
    String? rejectedBy,
    String? rejectionReason,
    DateTime? createdAt,
    DateTime? validatedAt,
    DateTime? rejectedAt,
    DateTime? lastReminderSentAt,
    String? chiefTeamId,
  }) {
    return ReplacementAcceptance(
      id: id ?? this.id,
      requestId: requestId ?? this.requestId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      acceptedStartTime: acceptedStartTime ?? this.acceptedStartTime,
      acceptedEndTime: acceptedEndTime ?? this.acceptedEndTime,
      status: status ?? this.status,
      validatedBy: validatedBy ?? this.validatedBy,
      validationComment: validationComment ?? this.validationComment,
      rejectedBy: rejectedBy ?? this.rejectedBy,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      createdAt: createdAt ?? this.createdAt,
      validatedAt: validatedAt ?? this.validatedAt,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      lastReminderSentAt: lastReminderSentAt ?? this.lastReminderSentAt,
      chiefTeamId: chiefTeamId ?? this.chiefTeamId,
    );
  }

  /// Calcule les compétences manquantes chez l'accepteur par rapport au demandeur
  /// Retourne les compétences que possède le demandeur mais pas l'accepteur
  static List<String> getMissingSkills(
    List<String> requesterSkills,
    List<String> acceptorSkills,
  ) {
    final requesterSkillsSet = Set<String>.from(requesterSkills);
    final acceptorSkillsSet = Set<String>.from(acceptorSkills);
    return requesterSkillsSet.difference(acceptorSkillsSet).toList();
  }

  /// Calcule les compétences communes entre le demandeur et l'accepteur
  static List<String> getCommonSkills(
    List<String> requesterSkills,
    List<String> acceptorSkills,
  ) {
    final requesterSkillsSet = Set<String>.from(requesterSkills);
    final acceptorSkillsSet = Set<String>.from(acceptorSkills);
    return requesterSkillsSet.intersection(acceptorSkillsSet).toList();
  }

  /// Calcule les compétences supplémentaires que possède l'accepteur mais pas le demandeur
  static List<String> getExtraSkills(
    List<String> requesterSkills,
    List<String> acceptorSkills,
  ) {
    final requesterSkillsSet = Set<String>.from(requesterSkills);
    final acceptorSkillsSet = Set<String>.from(acceptorSkills);
    return acceptorSkillsSet.difference(requesterSkillsSet).toList();
  }
}
