enum ReplacementMode {
  similarity, // Mode par similarité (système actuel)
  position, // Mode par poste (nouveau système hiérarchique)
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

  // Autoriser la recherche d'agents sous-qualifiés (en mode position)
  final bool allowUnderQualifiedReplacement;

  const Station({
    required this.id,
    required this.name,
    this.notificationWaveDelayMinutes = 30, // Délai par défaut: 30 minutes
    this.maxAgentsPerShift = 6, // Valeur par défaut: 6 agents
    this.replacementMode = ReplacementMode.similarity, // Mode par défaut: similarité
    this.allowUnderQualifiedReplacement = false, // Par défaut: désactivé
  });

  Station copyWith({
    String? id,
    String? name,
    int? notificationWaveDelayMinutes,
    int? maxAgentsPerShift,
    ReplacementMode? replacementMode,
    bool? allowUnderQualifiedReplacement,
  }) =>
      Station(
        id: id ?? this.id,
        name: name ?? this.name,
        notificationWaveDelayMinutes: notificationWaveDelayMinutes ?? this.notificationWaveDelayMinutes,
        maxAgentsPerShift: maxAgentsPerShift ?? this.maxAgentsPerShift,
        replacementMode: replacementMode ?? this.replacementMode,
        allowUnderQualifiedReplacement: allowUnderQualifiedReplacement ?? this.allowUnderQualifiedReplacement,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notificationWaveDelayMinutes': notificationWaveDelayMinutes,
        'maxAgentsPerShift': maxAgentsPerShift,
        'replacementMode': replacementMode.name,
        'allowUnderQualifiedReplacement': allowUnderQualifiedReplacement,
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
        allowUnderQualifiedReplacement: json['allowUnderQualifiedReplacement'] as bool? ?? false,
      );
}
