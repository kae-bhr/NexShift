import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/planning_agent_model.dart';

class Planning {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final String station;
  final String team;
  final List<PlanningAgent> agents;
  final int maxAgents; // Nombre maximum d'agents autorisés

  Planning({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.station,
    required this.team,
    required this.agents,
    this.maxAgents = 6,
  });

  /// Getter de compatibilité : retourne les IDs des agents de base (non remplaçants)
  List<String> get agentsId =>
      agents.where((a) => a.replacedAgentId == null).map((a) => a.agentId).toSet().toList();

  factory Planning.empty() {
    return Planning(
      id: '',
      startTime: DateTime.now(),
      endTime: DateTime.now(),
      station: '',
      team: '',
      agents: [],
      maxAgents: 6,
    );
  }

  factory Planning.fromJson(Map<String, dynamic> json) {
    // Gérer les deux formats: Timestamp (Firestore) et String (JSON)
    DateTime parseDateTime(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      } else if (value is String) {
        return DateTime.parse(value);
      }
      throw Exception('Invalid date format: $value');
    }

    final startTime = parseDateTime(json['startTime']);
    final endTime = parseDateTime(json['endTime']);

    // Nouveau format : liste d'agents avec horaires/niveaux
    List<PlanningAgent> agents;
    if (json['agents'] != null) {
      agents = (json['agents'] as List<dynamic>)
          .map((e) => PlanningAgent.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (json['agentsId'] != null) {
      // Ancien format : synthétiser depuis agentsId
      agents = (json['agentsId'] as List<dynamic>)
          .map((e) => PlanningAgent(
                agentId: e as String,
                start: startTime,
                end: endTime,
                levelId: '',
              ))
          .toList();
    } else {
      agents = [];
    }

    return Planning(
      id: json['id'] as String,
      startTime: startTime,
      endTime: endTime,
      station: json['station'] as String,
      team: json['team'] as String,
      agents: agents,
      maxAgents: json['maxAgents'] as int? ?? 6,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'station': station,
      'team': team,
      'agents': agents.map((a) => a.toJson()).toList(),
      'maxAgents': maxAgents,
    };
  }

  Planning copyWith({
    String? id,
    DateTime? startTime,
    DateTime? endTime,
    String? station,
    String? team,
    List<PlanningAgent>? agents,
    int? maxAgents,
  }) {
    return Planning(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      station: station ?? this.station,
      team: team ?? this.team,
      agents: agents ?? this.agents,
      maxAgents: maxAgents ?? this.maxAgents,
    );
  }
}
