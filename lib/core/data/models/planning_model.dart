import 'package:cloud_firestore/cloud_firestore.dart';

class Planning {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final String station;
  final String team;
  final List<String> agentsId;
  final int maxAgents; // Nombre maximum d'agents autorisés

  Planning({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.station,
    required this.team,
    required this.agentsId,
    this.maxAgents = 6,
  });

  factory Planning.empty() {
    return Planning(
      id: '',
      startTime: DateTime.now(),
      endTime: DateTime.now(),
      station: '',
      team: '',
      agentsId: [],
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

    return Planning(
      id: json['id'] as String,
      startTime: parseDateTime(json['startTime']),
      endTime: parseDateTime(json['endTime']),
      station: json['station'] as String,
      team: json['team'] as String,
      agentsId: (json['agentsId'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
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
      'agentsId': agentsId,
      'maxAgents': maxAgents,
    };
  }

  Planning copyWith({
    String? id,
    DateTime? startTime,
    DateTime? endTime,
    String? station,
    String? team,
    List<String>? agentsId,
    int? maxAgents,
  }) {
    return Planning(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      station: station ?? this.station,
      team: team ?? this.team,
      agentsId: agentsId ?? this.agentsId,
      maxAgents: maxAgents ?? this.maxAgents,
    );
  }
}
