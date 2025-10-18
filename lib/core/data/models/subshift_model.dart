import 'package:uuid/uuid.dart';

class Subshift {
  final String id;
  final String replacedId;
  final String replacerId;
  final DateTime start;
  final DateTime end;
  final String planningId;

  Subshift({
    required this.id,
    required this.replacedId,
    required this.replacerId,
    required this.start,
    required this.end,
    required this.planningId,
  });

  factory Subshift.create({
    required String replacedId,
    required String replacerId,
    required DateTime start,
    required DateTime end,
    required String planningId,
  }) {
    return Subshift(
      id: const Uuid().v4(),
      replacedId: replacedId,
      replacerId: replacerId,
      start: start,
      end: end,
      planningId: planningId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'replacedId': replacedId,
    'replacerId': replacerId,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'planningId': planningId,
  };

  factory Subshift.fromJson(Map<String, dynamic> json) => Subshift(
    id: json['id'],
    replacedId: json['replacedId'],
    replacerId: json['replacerId'],
    start: DateTime.parse(json['start']),
    end: DateTime.parse(json['end']),
    planningId: json['planningId'],
  );
}
