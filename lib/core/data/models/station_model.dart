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

  const Station({
    required this.id,
    required this.name,
    this.notificationWaveDelayMinutes = 30, // Délai par défaut: 30 minutes
    this.maxAgentsPerShift = 6, // Valeur par défaut: 6 agents
    this.replacementMode = ReplacementMode.similarity, // Mode par défaut: similarité
    this.allowUnderQualifiedAutoAcceptance = false, // Par défaut: désactivé
    this.skillWeights = const {}, // Par défaut : vide (toutes à 1.0)
  });

  Station copyWith({
    String? id,
    String? name,
    int? notificationWaveDelayMinutes,
    int? maxAgentsPerShift,
    ReplacementMode? replacementMode,
    bool? allowUnderQualifiedAutoAcceptance,
    Map<String, double>? skillWeights,
  }) =>
      Station(
        id: id ?? this.id,
        name: name ?? this.name,
        notificationWaveDelayMinutes: notificationWaveDelayMinutes ?? this.notificationWaveDelayMinutes,
        maxAgentsPerShift: maxAgentsPerShift ?? this.maxAgentsPerShift,
        replacementMode: replacementMode ?? this.replacementMode,
        allowUnderQualifiedAutoAcceptance: allowUnderQualifiedAutoAcceptance ?? this.allowUnderQualifiedAutoAcceptance,
        skillWeights: skillWeights ?? this.skillWeights,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notificationWaveDelayMinutes': notificationWaveDelayMinutes,
        'maxAgentsPerShift': maxAgentsPerShift,
        'replacementMode': replacementMode.name,
        'allowUnderQualifiedAutoAcceptance': allowUnderQualifiedAutoAcceptance,
        'skillWeights': skillWeights,
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
      );
}
