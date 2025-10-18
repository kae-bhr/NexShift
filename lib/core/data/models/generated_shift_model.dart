/// Planning généré à partir des règles
class GeneratedShift {
  final String id;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final String? teamId; // null si plage non affectée
  final String ruleId; // Référence à la règle source
  final String ruleName;
  final bool isException; // Généré depuis une exception
  final String? exceptionReason;

  const GeneratedShift({
    required this.id,
    required this.startDateTime,
    required this.endDateTime,
    this.teamId,
    required this.ruleId,
    required this.ruleName,
    this.isException = false,
    this.exceptionReason,
  });

  GeneratedShift copyWith({
    String? id,
    DateTime? startDateTime,
    DateTime? endDateTime,
    String? teamId,
    String? ruleId,
    String? ruleName,
    bool? isException,
    String? exceptionReason,
  }) => GeneratedShift(
    id: id ?? this.id,
    startDateTime: startDateTime ?? this.startDateTime,
    endDateTime: endDateTime ?? this.endDateTime,
    teamId: teamId ?? this.teamId,
    ruleId: ruleId ?? this.ruleId,
    ruleName: ruleName ?? this.ruleName,
    isException: isException ?? this.isException,
    exceptionReason: exceptionReason ?? this.exceptionReason,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'startDateTime': startDateTime.toIso8601String(),
    'endDateTime': endDateTime.toIso8601String(),
    'teamId': teamId,
    'ruleId': ruleId,
    'ruleName': ruleName,
    'isException': isException,
    'exceptionReason': exceptionReason,
  };

  factory GeneratedShift.fromJson(Map<String, dynamic> json) => GeneratedShift(
    id: json['id'],
    startDateTime: DateTime.parse(json['startDateTime']),
    endDateTime: DateTime.parse(json['endDateTime']),
    teamId: json['teamId'],
    ruleId: json['ruleId'],
    ruleName: json['ruleName'],
    isException: json['isException'] ?? false,
    exceptionReason: json['exceptionReason'],
  );

  Duration get duration => endDateTime.difference(startDateTime);

  bool get isUnassigned => teamId == null;

  String getDisplayTimeRange() {
    final startStr =
        '${startDateTime.hour.toString().padLeft(2, '0')}:${startDateTime.minute.toString().padLeft(2, '0')}';
    final endStr =
        '${endDateTime.hour.toString().padLeft(2, '0')}:${endDateTime.minute.toString().padLeft(2, '0')}';

    if (startDateTime.day != endDateTime.day) {
      return '$startStr - $endStr (+1j)';
    }
    return '$startStr - $endStr';
  }
}
