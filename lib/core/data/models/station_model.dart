import 'package:cloud_firestore/cloud_firestore.dart';

/// Mode de remplacement
enum ReplacementMode {
  similarity, // Mode par similarité (système actuel)
  manual, // Mode manuel (sélection directe)
  availability, // Demande de disponibilité (recherche par compétences)
}

class Station {
  final String id; // e.g., '50_N_SVLH'
  final String name; // e.g., 'Saint-Vaast-La-Hougue'

  // Configuration pour les notifications de remplacement progressives
  // Délai en minutes entre chaque vague de notifications
  final int notificationWaveDelayMinutes;

  // Nombre maximum d'agents par garde (appliqué aux règles/exceptions)
  final int maxAgentsPerShift;

  // Mode de remplacement automatique
  final ReplacementMode replacementMode;

  // Autoriser l'acceptation automatique d'agents sous-qualifiés
  final bool allowUnderQualifiedAutoAcceptance;

  // Pondération des compétences pour le calcul de similarité
  // Map<skillName, weight> - Par défaut, toutes les compétences ont un poids de 1.0
  final Map<String, double> skillWeights;

  // Pause nocturne des vagues de notifications
  final bool nightPauseEnabled;
  final String nightPauseStart; // Format "HH:mm"
  final String nightPauseEnd;   // Format "HH:mm"

  // Date de fin d'abonnement de la caserne (null = pas de limite)
  final DateTime? subscriptionEndDate;

  // Règles de positionnement automatique des niveaux d'astreinte
  // Niveau par défaut pour un agent de garde dans son équipe
  final String? defaultOnCallLevelId;
  // Niveau par défaut pour un remplaçant (si pas de distinction par durée)
  final String? replacementOnCallLevelId;
  // Activer la distinction de niveau selon la durée de remplacement
  final bool enableReplacementDurationThreshold;
  // Seuil en heures pour la distinction de durée
  final int replacementDurationThresholdHours;
  // Niveau si durée de remplacement < seuil
  final String? shortReplacementLevelId;
  // Niveau si durée de remplacement >= seuil
  final String? longReplacementLevelId;

  const Station({
    required this.id,
    required this.name,
    this.notificationWaveDelayMinutes = 30, // Délai par défaut: 30 minutes
    this.maxAgentsPerShift = 6, // Valeur par défaut: 6 agents
    this.replacementMode = ReplacementMode.similarity, // Mode par défaut: similarité
    this.allowUnderQualifiedAutoAcceptance = false, // Par défaut: désactivé
    this.skillWeights = const {}, // Par défaut : vide (toutes à 1.0)
    this.nightPauseEnabled = true, // Activé par défaut
    this.nightPauseStart = '23:00', // Début à 23h par défaut
    this.nightPauseEnd = '06:00', // Fin à 6h par défaut
    this.subscriptionEndDate,
    this.defaultOnCallLevelId,
    this.replacementOnCallLevelId,
    this.enableReplacementDurationThreshold = false,
    this.replacementDurationThresholdHours = 10,
    this.shortReplacementLevelId,
    this.longReplacementLevelId,
  });

  /// Vérifie si l'abonnement est expiré
  bool get isSubscriptionExpired {
    if (subscriptionEndDate == null) return false;
    return DateTime.now().isAfter(subscriptionEndDate!);
  }

  /// Vérifie si l'abonnement expire dans moins de 30 jours
  bool get isSubscriptionExpiringSoon {
    if (subscriptionEndDate == null) return false;
    final daysUntilExpiry = subscriptionEndDate!.difference(DateTime.now()).inDays;
    return daysUntilExpiry >= 0 && daysUntilExpiry <= 30;
  }

  /// Nombre de jours restants avant expiration
  int get daysUntilSubscriptionExpiry {
    if (subscriptionEndDate == null) return -1;
    return subscriptionEndDate!.difference(DateTime.now()).inDays;
  }

  Station copyWith({
    String? id,
    String? name,
    int? notificationWaveDelayMinutes,
    int? maxAgentsPerShift,
    ReplacementMode? replacementMode,
    bool? allowUnderQualifiedAutoAcceptance,
    Map<String, double>? skillWeights,
    bool? nightPauseEnabled,
    String? nightPauseStart,
    String? nightPauseEnd,
    DateTime? subscriptionEndDate,
    String? defaultOnCallLevelId,
    String? replacementOnCallLevelId,
    bool? enableReplacementDurationThreshold,
    int? replacementDurationThresholdHours,
    String? shortReplacementLevelId,
    String? longReplacementLevelId,
  }) =>
      Station(
        id: id ?? this.id,
        name: name ?? this.name,
        notificationWaveDelayMinutes: notificationWaveDelayMinutes ?? this.notificationWaveDelayMinutes,
        maxAgentsPerShift: maxAgentsPerShift ?? this.maxAgentsPerShift,
        replacementMode: replacementMode ?? this.replacementMode,
        allowUnderQualifiedAutoAcceptance: allowUnderQualifiedAutoAcceptance ?? this.allowUnderQualifiedAutoAcceptance,
        skillWeights: skillWeights ?? this.skillWeights,
        nightPauseEnabled: nightPauseEnabled ?? this.nightPauseEnabled,
        nightPauseStart: nightPauseStart ?? this.nightPauseStart,
        nightPauseEnd: nightPauseEnd ?? this.nightPauseEnd,
        subscriptionEndDate: subscriptionEndDate ?? this.subscriptionEndDate,
        defaultOnCallLevelId: defaultOnCallLevelId ?? this.defaultOnCallLevelId,
        replacementOnCallLevelId: replacementOnCallLevelId ?? this.replacementOnCallLevelId,
        enableReplacementDurationThreshold: enableReplacementDurationThreshold ?? this.enableReplacementDurationThreshold,
        replacementDurationThresholdHours: replacementDurationThresholdHours ?? this.replacementDurationThresholdHours,
        shortReplacementLevelId: shortReplacementLevelId ?? this.shortReplacementLevelId,
        longReplacementLevelId: longReplacementLevelId ?? this.longReplacementLevelId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notificationWaveDelayMinutes': notificationWaveDelayMinutes,
        'maxAgentsPerShift': maxAgentsPerShift,
        'replacementMode': replacementMode.name,
        'allowUnderQualifiedAutoAcceptance': allowUnderQualifiedAutoAcceptance,
        'skillWeights': skillWeights,
        'nightPauseEnabled': nightPauseEnabled,
        'nightPauseStart': nightPauseStart,
        'nightPauseEnd': nightPauseEnd,
        if (subscriptionEndDate != null)
          'subscriptionEndDate': Timestamp.fromDate(subscriptionEndDate!),
        if (defaultOnCallLevelId != null)
          'defaultOnCallLevelId': defaultOnCallLevelId,
        if (replacementOnCallLevelId != null)
          'replacementOnCallLevelId': replacementOnCallLevelId,
        'enableReplacementDurationThreshold': enableReplacementDurationThreshold,
        'replacementDurationThresholdHours': replacementDurationThresholdHours,
        if (shortReplacementLevelId != null)
          'shortReplacementLevelId': shortReplacementLevelId,
        if (longReplacementLevelId != null)
          'longReplacementLevelId': longReplacementLevelId,
      };

  factory Station.fromJson(Map<String, dynamic> json) => Station(
        id: json['id'] as String,
        name: json['name'] as String,
        notificationWaveDelayMinutes: json['notificationWaveDelayMinutes'] as int? ?? 30,
        maxAgentsPerShift: json['maxAgentsPerShift'] as int? ?? 6,
        replacementMode: json['replacementMode'] != null
            ? ReplacementMode.values.firstWhere(
                (e) => e.name == json['replacementMode'],
                orElse: () => ReplacementMode.similarity,
              )
            : ReplacementMode.similarity,
        allowUnderQualifiedAutoAcceptance: json['allowUnderQualifiedAutoAcceptance'] as bool? ??
            json['allowUnderQualifiedReplacement'] as bool? ?? false, // Fallback pour compatibilité
        skillWeights: json['skillWeights'] != null
            ? Map<String, double>.from(json['skillWeights'])
            : {},
        nightPauseEnabled: json['nightPauseEnabled'] as bool? ?? true,
        nightPauseStart: json['nightPauseStart'] as String? ?? '23:00',
        nightPauseEnd: json['nightPauseEnd'] as String? ?? '06:00',
        subscriptionEndDate: json['subscriptionEndDate'] != null
            ? (json['subscriptionEndDate'] as Timestamp).toDate()
            : null,
        defaultOnCallLevelId: json['defaultOnCallLevelId'] as String?,
        replacementOnCallLevelId: json['replacementOnCallLevelId'] as String?,
        enableReplacementDurationThreshold:
            json['enableReplacementDurationThreshold'] as bool? ?? false,
        replacementDurationThresholdHours:
            json['replacementDurationThresholdHours'] as int? ?? 10,
        shortReplacementLevelId: json['shortReplacementLevelId'] as String?,
        longReplacementLevelId: json['longReplacementLevelId'] as String?,
      );
}
