import 'package:flutter/material.dart';

/// Type de rotation pour les astreintes
enum ShiftRotationType {
  daily('Quotidienne', 'Rotation chaque jour'),
  weekly('Hebdomadaire', 'Rotation chaque semaine'),
  monthly('Mensuelle', 'Rotation chaque mois'),
  custom('Personnalisée', 'Intervalle personnalisé'),
  none('Non affectée', 'Plage sans équipe assignée');

  final String label;
  final String description;

  const ShiftRotationType(this.label, this.description);
}

/// Jours de la semaine applicables
class DaysOfWeek {
  final bool monday;
  final bool tuesday;
  final bool wednesday;
  final bool thursday;
  final bool friday;
  final bool saturday;
  final bool sunday;

  const DaysOfWeek({
    this.monday = false,
    this.tuesday = false,
    this.wednesday = false,
    this.thursday = false,
    this.friday = false,
    this.saturday = false,
    this.sunday = false,
  });

  /// Retourne true si au moins un jour est sélectionné
  bool get hasAnyDay =>
      monday ||
      tuesday ||
      wednesday ||
      thursday ||
      friday ||
      saturday ||
      sunday;

  /// Retourne true si le jour donné (1=lundi, 7=dimanche) est sélectionné
  bool isDaySelected(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return monday;
      case DateTime.tuesday:
        return tuesday;
      case DateTime.wednesday:
        return wednesday;
      case DateTime.thursday:
        return thursday;
      case DateTime.friday:
        return friday;
      case DateTime.saturday:
        return saturday;
      case DateTime.sunday:
        return sunday;
      default:
        return false;
    }
  }

  /// Tous les jours de la semaine
  static const DaysOfWeek all = DaysOfWeek(
    monday: true,
    tuesday: true,
    wednesday: true,
    thursday: true,
    friday: true,
    saturday: true,
    sunday: true,
  );

  /// Jours ouvrés (lundi-vendredi)
  static const DaysOfWeek weekdays = DaysOfWeek(
    monday: true,
    tuesday: true,
    wednesday: true,
    thursday: true,
    friday: true,
  );

  /// Weekend (samedi-dimanche)
  static const DaysOfWeek weekend = DaysOfWeek(saturday: true, sunday: true);

  DaysOfWeek copyWith({
    bool? monday,
    bool? tuesday,
    bool? wednesday,
    bool? thursday,
    bool? friday,
    bool? saturday,
    bool? sunday,
  }) => DaysOfWeek(
    monday: monday ?? this.monday,
    tuesday: tuesday ?? this.tuesday,
    wednesday: wednesday ?? this.wednesday,
    thursday: thursday ?? this.thursday,
    friday: friday ?? this.friday,
    saturday: saturday ?? this.saturday,
    sunday: sunday ?? this.sunday,
  );

  Map<String, dynamic> toJson() => {
    'monday': monday,
    'tuesday': tuesday,
    'wednesday': wednesday,
    'thursday': thursday,
    'friday': friday,
    'saturday': saturday,
    'sunday': sunday,
  };

  factory DaysOfWeek.fromJson(Map<String, dynamic> json) => DaysOfWeek(
    monday: json['monday'] ?? false,
    tuesday: json['tuesday'] ?? false,
    wednesday: json['wednesday'] ?? false,
    thursday: json['thursday'] ?? false,
    friday: json['friday'] ?? false,
    saturday: json['saturday'] ?? false,
    sunday: json['sunday'] ?? false,
  );

  String toDisplayString() {
    final days = <String>[];
    if (monday) days.add('Lun');
    if (tuesday) days.add('Mar');
    if (wednesday) days.add('Mer');
    if (thursday) days.add('Jeu');
    if (friday) days.add('Ven');
    if (saturday) days.add('Sam');
    if (sunday) days.add('Dim');
    return days.isEmpty ? 'Aucun jour' : days.join(', ');
  }
}

/// Règle de génération d'astreintes
class ShiftRule {
  final String id;
  final String name;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final bool spansNextDay; // true si l'astreinte se termine le lendemain
  final ShiftRotationType rotationType;
  final List<String> teamIds; // IDs des équipes participantes
  final int rotationIntervalDays; // Pour rotation custom
  final DaysOfWeek applicableDays;
  final bool isActive;
  final DateTime startDate; // Date de début d'application de la règle
  final DateTime?
  endDate; // Date de fin d'application de la règle (null = indéfini)
  final int priority; // Pour gérer les conflits (0 = plus haute priorité)
  final int maxAgents; // Nombre maximum d'agents pour cette astreinte

  const ShiftRule({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    this.spansNextDay = false,
    required this.rotationType,
    required this.teamIds,
    this.rotationIntervalDays = 1,
    required this.applicableDays,
    this.isActive = true,
    required this.startDate,
    this.endDate,
    this.priority = 0,
    this.maxAgents = 6,
  });

  ShiftRule copyWith({
    String? id,
    String? name,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    bool? spansNextDay,
    ShiftRotationType? rotationType,
    List<String>? teamIds,
    int? rotationIntervalDays,
    DaysOfWeek? applicableDays,
    bool? isActive,
    DateTime? startDate,
    DateTime? endDate,
    int? priority,
    int? maxAgents,
  }) => ShiftRule(
    id: id ?? this.id,
    name: name ?? this.name,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    spansNextDay: spansNextDay ?? this.spansNextDay,
    rotationType: rotationType ?? this.rotationType,
    teamIds: teamIds ?? this.teamIds,
    rotationIntervalDays: rotationIntervalDays ?? this.rotationIntervalDays,
    applicableDays: applicableDays ?? this.applicableDays,
    isActive: isActive ?? this.isActive,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    priority: priority ?? this.priority,
    maxAgents: maxAgents ?? this.maxAgents,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startTime': '${startTime.hour}:${startTime.minute}',
    'endTime': '${endTime.hour}:${endTime.minute}',
    'spansNextDay': spansNextDay,
    'rotationType': rotationType.name,
    'teamIds': teamIds,
    'rotationIntervalDays': rotationIntervalDays,
    'applicableDays': applicableDays.toJson(),
    'isActive': isActive,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'priority': priority,
    'maxAgents': maxAgents,
  };

  factory ShiftRule.fromJson(Map<String, dynamic> json) {
    final startTimeParts = (json['startTime'] as String).split(':');
    final endTimeParts = (json['endTime'] as String).split(':');

    return ShiftRule(
      id: json['id'],
      name: json['name'],
      startTime: TimeOfDay(
        hour: int.parse(startTimeParts[0]),
        minute: int.parse(startTimeParts[1]),
      ),
      endTime: TimeOfDay(
        hour: int.parse(endTimeParts[0]),
        minute: int.parse(endTimeParts[1]),
      ),
      spansNextDay: json['spansNextDay'] ?? false,
      rotationType: ShiftRotationType.values.firstWhere(
        (e) => e.name == json['rotationType'],
        orElse: () => ShiftRotationType.daily,
      ),
      teamIds: List<String>.from(json['teamIds']),
      rotationIntervalDays: json['rotationIntervalDays'] ?? 1,
      applicableDays: DaysOfWeek.fromJson(json['applicableDays']),
      isActive: json['isActive'] ?? true,
      startDate: DateTime.parse(json['startDate']),
      endDate: json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
      priority: json['priority'] ?? 0,
      maxAgents: json['maxAgents'] ?? 6,
    );
  }

  String getTimeRangeString() {
    final start =
        '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
    final end =
        '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
    return spansNextDay ? '$start - $end (+1j)' : '$start - $end';
  }
}
