/// Exception pour une date/plage horaire spécifique (férié, événement)
class ShiftException {
  final String id;
  final DateTime startDateTime; // Date et heure de début
  final DateTime endDateTime; // Date et heure de fin
  final String? teamId; // Équipe de garde (null = annulation)
  final String reason; // "Noël", "14 juillet", etc.
  final String? ruleId; // Règle concernée (null = toutes les règles)
  final int maxAgents; // Nombre maximum d'agents pour cette exception

  const ShiftException({
    required this.id,
    required this.startDateTime,
    required this.endDateTime,
    this.teamId,
    required this.reason,
    this.ruleId,
    this.maxAgents = 6,
  });

  ShiftException copyWith({
    String? id,
    DateTime? startDateTime,
    DateTime? endDateTime,
    String? teamId,
    String? reason,
    String? ruleId,
    int? maxAgents,
  }) => ShiftException(
    id: id ?? this.id,
    startDateTime: startDateTime ?? this.startDateTime,
    endDateTime: endDateTime ?? this.endDateTime,
    teamId: teamId ?? this.teamId,
    reason: reason ?? this.reason,
    ruleId: ruleId ?? this.ruleId,
    maxAgents: maxAgents ?? this.maxAgents,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'startDateTime': startDateTime.toIso8601String(),
    'endDateTime': endDateTime.toIso8601String(),
    'teamId': teamId,
    'reason': reason,
    'ruleId': ruleId,
    'maxAgents': maxAgents,
  };

  factory ShiftException.fromJson(Map<String, dynamic> json) => ShiftException(
    id: json['id'],
    startDateTime: DateTime.parse(json['startDateTime']),
    endDateTime: DateTime.parse(json['endDateTime']),
    teamId: json['teamId'],
    reason: json['reason'],
    ruleId: json['ruleId'],
    maxAgents: json['maxAgents'] ?? 6,
  );
}
