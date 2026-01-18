import 'package:cloud_firestore/cloud_firestore.dart';

/// Statut d'une proposition d'échange
enum ShiftExchangeProposalStatus {
  pendingSelection, // En attente de sélection par agent A
  selectedByInitiator, // Sélectionnée par A, en attente validation chefs
  validated, // Validé par tous les chefs requis
  rejected, // Rejeté par au moins 1 chef
}

/// État de validation d'une équipe
enum TeamValidationState {
  pending, // Aucun chef n'a répondu
  validatedTemporarily, // Au moins 1 chef a accepté, aucun refus
  autoValidated, // Proposeur est chef (définitif)
  rejected, // Au moins 1 chef a refusé (définitif)
}

/// Validation d'un chef d'équipe
class LeaderValidation {
  final String leaderId; // Chef validant
  final String team; // Équipe concernée
  final bool approved; // true/false
  final String? comment; // Motif si refus (obligatoire)
  final DateTime validatedAt;

  LeaderValidation({
    required this.leaderId,
    required this.team,
    required this.approved,
    this.comment,
    required this.validatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'leaderId': leaderId,
      'team': team,
      'approved': approved,
      if (comment != null) 'comment': comment,
      'validatedAt': Timestamp.fromDate(validatedAt),
    };
  }

  factory LeaderValidation.fromJson(Map<String, dynamic> json) {
    return LeaderValidation(
      leaderId: json['leaderId'] as String,
      team: json['team'] as String,
      approved: json['approved'] as bool,
      comment: json['comment'] as String?,
      validatedAt: (json['validatedAt'] as Timestamp).toDate(),
    );
  }
}

/// Modèle pour une proposition d'échange de garde
class ShiftExchangeProposal {
  final String id;
  final String requestId; // FK vers ShiftExchangeRequest
  final String proposerId; // Agent B (équipe 2)
  final String proposerName; // Nom du proposeur (cache)

  // Propositions multiples: liste des plannings proposés
  final List<String> proposedPlanningIds; // NOUVEAU: plusieurs astreintes

  // Planning sélectionné par l'initiateur (parmi proposedPlanningIds)
  final String? selectedPlanningId; // NOUVEAU: astreinte choisie par A

  // Liste des plannings refusés (pour permettre de refuser individuellement)
  final List<String> rejectedPlanningIds; // NOUVEAU: astreintes refusées par les chefs

  // Anciens champs (compatibilité): gardés pour migration
  final String? proposerPlanningId; // DEPRECATED: une seule astreinte
  final DateTime? proposerStartTime; // DEPRECATED
  final DateTime? proposerEndTime; // DEPRECATED

  // Détection chef-proposeur
  final bool isProposerChief; // NOUVEAU: true si proposeur est chef
  final String? proposerTeamId; // NOUVEAU: ID équipe du proposeur

  // Détection chef-initiateur
  final bool isInitiatorChief; // NOUVEAU: true si initiateur est chef
  final String? initiatorTeamId; // NOUVEAU: ID équipe de l'initiateur

  final ShiftExchangeProposalStatus status;
  final DateTime createdAt;

  // Validations des chefs d'équipe
  final Map<String, LeaderValidation> leaderValidations; // team → validation

  // État de finalisation
  final bool isFinalized; // NOUVEAU: true quand échange complet

  final DateTime? acceptedAt;
  final DateTime? rejectedAt;

  ShiftExchangeProposal({
    required this.id,
    required this.requestId,
    required this.proposerId,
    required this.proposerName,
    required this.proposedPlanningIds,
    this.selectedPlanningId,
    this.rejectedPlanningIds = const [],
    this.proposerPlanningId, // DEPRECATED: pour compatibilité
    this.proposerStartTime, // DEPRECATED
    this.proposerEndTime, // DEPRECATED
    this.isProposerChief = false,
    this.proposerTeamId,
    this.isInitiatorChief = false,
    this.initiatorTeamId,
    required this.status,
    required this.createdAt,
    this.leaderValidations = const {},
    this.isFinalized = false,
    this.acceptedAt,
    this.rejectedAt,
  });

  /// Conversion vers JSON pour Firestore
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'requestId': requestId,
      'proposerId': proposerId,
      'proposerName': proposerName,
      'proposedPlanningIds': proposedPlanningIds,
      if (selectedPlanningId != null) 'selectedPlanningId': selectedPlanningId,
      'rejectedPlanningIds': rejectedPlanningIds,
      'isProposerChief': isProposerChief,
      if (proposerTeamId != null) 'proposerTeamId': proposerTeamId,
      'isInitiatorChief': isInitiatorChief,
      if (initiatorTeamId != null) 'initiatorTeamId': initiatorTeamId,
      // Anciens champs pour compatibilité
      if (proposerPlanningId != null) 'proposerPlanningId': proposerPlanningId,
      if (proposerStartTime != null) 'proposerStartTime': Timestamp.fromDate(proposerStartTime!),
      if (proposerEndTime != null) 'proposerEndTime': Timestamp.fromDate(proposerEndTime!),
      'status': status.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      'leaderValidations': leaderValidations
          .map((key, value) => MapEntry(key, value.toJson())),
      'isFinalized': isFinalized,
      if (acceptedAt != null) 'acceptedAt': Timestamp.fromDate(acceptedAt!),
      if (rejectedAt != null) 'rejectedAt': Timestamp.fromDate(rejectedAt!),
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

    // Gestion migration: ancien format (proposerPlanningId) vs nouveau (proposedPlanningIds)
    List<String> planningIds;
    String? legacyPlanningId;
    DateTime? legacyStartTime;
    DateTime? legacyEndTime;

    if (json.containsKey('proposedPlanningIds')) {
      // Nouveau format
      planningIds = List<String>.from(json['proposedPlanningIds'] as List);
    } else if (json.containsKey('proposerPlanningId')) {
      // Ancien format: migration automatique
      legacyPlanningId = json['proposerPlanningId'] as String;
      planningIds = [legacyPlanningId];
      legacyStartTime = json['proposerStartTime'] != null
          ? (json['proposerStartTime'] as Timestamp).toDate()
          : null;
      legacyEndTime = json['proposerEndTime'] != null
          ? (json['proposerEndTime'] as Timestamp).toDate()
          : null;
    } else {
      planningIds = [];
    }

    return ShiftExchangeProposal(
      id: json['id'] as String,
      requestId: json['requestId'] as String,
      proposerId: json['proposerId'] as String,
      proposerName: json['proposerName'] as String,
      proposedPlanningIds: planningIds,
      selectedPlanningId: json['selectedPlanningId'] as String?,
      rejectedPlanningIds: (json['rejectedPlanningIds'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      proposerPlanningId: legacyPlanningId,
      proposerStartTime: legacyStartTime,
      proposerEndTime: legacyEndTime,
      isProposerChief: json['isProposerChief'] as bool? ?? false,
      proposerTeamId: json['proposerTeamId'] as String?,
      isInitiatorChief: json['isInitiatorChief'] as bool? ?? false,
      initiatorTeamId: json['initiatorTeamId'] as String?,
      status: ShiftExchangeProposalStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => ShiftExchangeProposalStatus.pendingSelection,
      ),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      leaderValidations: validations,
      isFinalized: json['isFinalized'] as bool? ?? false,
      acceptedAt: json['acceptedAt'] != null
          ? (json['acceptedAt'] as Timestamp).toDate()
          : null,
      rejectedAt: json['rejectedAt'] != null
          ? (json['rejectedAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Copie avec modifications
  ShiftExchangeProposal copyWith({
    String? id,
    String? requestId,
    String? proposerId,
    String? proposerName,
    List<String>? proposedPlanningIds,
    String? selectedPlanningId,
    List<String>? rejectedPlanningIds,
    String? proposerPlanningId,
    DateTime? proposerStartTime,
    DateTime? proposerEndTime,
    bool? isProposerChief,
    String? proposerTeamId,
    bool? isInitiatorChief,
    String? initiatorTeamId,
    ShiftExchangeProposalStatus? status,
    DateTime? createdAt,
    Map<String, LeaderValidation>? leaderValidations,
    bool? isFinalized,
    DateTime? acceptedAt,
    DateTime? rejectedAt,
  }) {
    return ShiftExchangeProposal(
      id: id ?? this.id,
      requestId: requestId ?? this.requestId,
      proposerId: proposerId ?? this.proposerId,
      proposerName: proposerName ?? this.proposerName,
      proposedPlanningIds: proposedPlanningIds ?? this.proposedPlanningIds,
      selectedPlanningId: selectedPlanningId ?? this.selectedPlanningId,
      rejectedPlanningIds: rejectedPlanningIds ?? this.rejectedPlanningIds,
      proposerPlanningId: proposerPlanningId ?? this.proposerPlanningId,
      proposerStartTime: proposerStartTime ?? this.proposerStartTime,
      proposerEndTime: proposerEndTime ?? this.proposerEndTime,
      isProposerChief: isProposerChief ?? this.isProposerChief,
      proposerTeamId: proposerTeamId ?? this.proposerTeamId,
      isInitiatorChief: isInitiatorChief ?? this.isInitiatorChief,
      initiatorTeamId: initiatorTeamId ?? this.initiatorTeamId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      leaderValidations: leaderValidations ?? this.leaderValidations,
      isFinalized: isFinalized ?? this.isFinalized,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      rejectedAt: rejectedAt ?? this.rejectedAt,
    );
  }

  /// Calcule l'état de validation de chaque équipe
  Map<String, TeamValidationState> get teamValidationStates {
    final states = <String, TeamValidationState>{};

    // Grouper les validations par équipe
    for (var entry in leaderValidations.entries) {
      // CRITICAL: La clé est au format "teamId_leaderId", on doit extraire uniquement teamId
      final keyParts = entry.key.split('_');
      final teamId = keyParts.isNotEmpty ? keyParts[0] : entry.key;
      final validation = entry.value;

      // Si l'équipe est déjà dans les états, vérifier la cohérence
      if (!states.containsKey(teamId)) {
        // Première validation pour cette équipe
        if (validation.approved) {
          states[teamId] = TeamValidationState.validatedTemporarily;
        } else {
          states[teamId] = TeamValidationState.rejected;
        }
      } else {
        // Équipe déjà présente: appliquer la logique de priorité au refus
        if (!validation.approved) {
          // Un refus annule toute validation temporaire
          states[teamId] = TeamValidationState.rejected;
        }
        // Si déjà validée temporairement et nouvelle acceptation, reste validée
      }
    }

    // Ajouter l'auto-validation si initiateur est chef
    if (isInitiatorChief && initiatorTeamId != null) {
      states[initiatorTeamId!] = TeamValidationState.autoValidated;
    }

    // Ajouter l'auto-validation si proposeur est chef
    if (isProposerChief && proposerTeamId != null) {
      states[proposerTeamId!] = TeamValidationState.autoValidated;
    }

    return states;
  }

  /// Vérifie si l'échange peut être finalisé
  bool get canBeFinalized {
    if (isFinalized) return false;
    if (status != ShiftExchangeProposalStatus.selectedByInitiator) return false;

    final states = teamValidationStates;

    // Vérifier qu'il y a bien 2 équipes
    if (states.length != 2) return false;

    // Toutes les équipes doivent être validées (temp ou auto)
    return states.values.every((state) =>
        state == TeamValidationState.validatedTemporarily ||
        state == TeamValidationState.autoValidated);
  }

  /// Vérifie si au moins une équipe a refusé
  bool get hasAnyRejection {
    return teamValidationStates.values
        .any((state) => state == TeamValidationState.rejected);
  }

  /// DEPRECATED: Utilisez teamValidationStates à la place
  @Deprecated('Utilisez teamValidationStates pour une logique multi-chefs complète')
  bool get allLeadersValidated {
    if (leaderValidations.length != 2) return false;
    return leaderValidations.values.every((v) => v.approved);
  }

  /// DEPRECATED: Utilisez hasAnyRejection à la place
  @Deprecated('Utilisez hasAnyRejection pour une logique multi-chefs complète')
  bool get anyLeaderRejected {
    if (leaderValidations.isEmpty) return false;
    return leaderValidations.values.any((v) => !v.approved);
  }
}
