import 'package:uuid/uuid.dart';

/// Représente une plage de disponibilité pour un agent.
/// Contrairement aux astreintes (obligatoires), les disponibilités sont basées
/// sur le volontariat. Un agent peut se rendre disponible sur des créneaux
/// horaires même s'il n'y a pas d'astreinte planifiée.
class Availability {
  final String id;
  final String agentId; // L'agent qui se rend disponible
  final DateTime start; // Début de la disponibilité
  final DateTime end; // Fin de la disponibilité
  final String? planningId; // Optionnel : référence à un planning existant
  final String? levelId; // Optionnel : niveau de disponibilité choisi (isAvailability == true)

  Availability({
    required this.id,
    required this.agentId,
    required this.start,
    required this.end,
    this.planningId,
    this.levelId,
  });

  factory Availability.create({
    required String agentId,
    required DateTime start,
    required DateTime end,
    String? planningId,
    String? levelId,
  }) {
    return Availability(
      id: const Uuid().v4(),
      agentId: agentId,
      start: start,
      end: end,
      planningId: planningId,
      levelId: levelId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'agentId': agentId,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'planningId': planningId,
        if (levelId != null) 'levelId': levelId,
      };

  factory Availability.fromJson(Map<String, dynamic> json) => Availability(
        id: json['id'],
        agentId: json['agentId'],
        start: DateTime.parse(json['start']),
        end: DateTime.parse(json['end']),
        planningId: json['planningId'],
        levelId: json['levelId'] as String?,
      );

  Availability copyWith({
    String? id,
    String? agentId,
    DateTime? start,
    DateTime? end,
    String? planningId,
    String? levelId,
  }) {
    return Availability(
      id: id ?? this.id,
      agentId: agentId ?? this.agentId,
      start: start ?? this.start,
      end: end ?? this.end,
      planningId: planningId ?? this.planningId,
      levelId: levelId ?? this.levelId,
    );
  }
}
