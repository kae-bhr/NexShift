import 'package:cloud_firestore/cloud_firestore.dart';

/// Représente un agent présent sur un planning avec ses horaires et son niveau d'astreinte.
/// Source unique de vérité pour la présence des agents.
class PlanningAgent {
  final String agentId;
  final DateTime start;
  final DateTime end;
  final String levelId;
  final String? replacedAgentId; // null = agent de base, sinon ID de l'agent remplacé
  final bool isExchange;
  final bool checkedByChief;
  final DateTime? checkedAt;
  final String? checkedBy;

  const PlanningAgent({
    required this.agentId,
    required this.start,
    required this.end,
    required this.levelId,
    this.replacedAgentId,
    this.isExchange = false,
    this.checkedByChief = false,
    this.checkedAt,
    this.checkedBy,
  });

  PlanningAgent copyWith({
    String? agentId,
    DateTime? start,
    DateTime? end,
    String? levelId,
    String? replacedAgentId,
    bool? isExchange,
    bool? checkedByChief,
    DateTime? checkedAt,
    String? checkedBy,
  }) =>
      PlanningAgent(
        agentId: agentId ?? this.agentId,
        start: start ?? this.start,
        end: end ?? this.end,
        levelId: levelId ?? this.levelId,
        replacedAgentId: replacedAgentId ?? this.replacedAgentId,
        isExchange: isExchange ?? this.isExchange,
        checkedByChief: checkedByChief ?? this.checkedByChief,
        checkedAt: checkedAt ?? this.checkedAt,
        checkedBy: checkedBy ?? this.checkedBy,
      );

  Map<String, dynamic> toJson() => {
        'agentId': agentId,
        'start': Timestamp.fromDate(start),
        'end': Timestamp.fromDate(end),
        'levelId': levelId,
        if (replacedAgentId != null) 'replacedAgentId': replacedAgentId,
        'isExchange': isExchange,
        'checkedByChief': checkedByChief,
        if (checkedAt != null) 'checkedAt': Timestamp.fromDate(checkedAt!),
        if (checkedBy != null) 'checkedBy': checkedBy,
      };

  factory PlanningAgent.fromJson(Map<String, dynamic> json) {
    DateTime parseDateTime(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.parse(value);
      throw Exception('Invalid date format: $value');
    }

    return PlanningAgent(
      agentId: json['agentId'] as String,
      start: parseDateTime(json['start']),
      end: parseDateTime(json['end']),
      levelId: json['levelId'] as String? ?? '',
      replacedAgentId: json['replacedAgentId'] as String?,
      isExchange: json['isExchange'] as bool? ?? false,
      checkedByChief: json['checkedByChief'] as bool? ?? false,
      checkedAt: json['checkedAt'] != null
          ? parseDateTime(json['checkedAt'])
          : null,
      checkedBy: json['checkedBy'] as String?,
    );
  }
}
