class User {
  final String id;
  final String lastName;
  final String firstName;
  final String station;
  final String status;
  final bool admin;
  final String team;
  final List<String> skills;
  final String? positionId; // ID du poste occupé par l'agent
  final List<String> keySkills; // Compétences-clés critiques

  // Alertes personnalisées
  final bool personalAlertEnabled; // Alerte avant astreinte personnelle
  final int personalAlertBeforeShiftHours; // Heures avant l'astreinte

  final bool chiefAlertEnabled; // Alerte changement équipe (chef uniquement)
  final int chiefAlertBeforeShiftHours; // Heures avant l'astreinte

  final bool anomalyAlertEnabled; // Alerte anomalies planning (chef uniquement)
  final int anomalyAlertDaysBefore; // Jours avant pour détecter les anomalies

  User({
    required this.id,
    required this.lastName,
    required this.firstName,
    required this.station,
    required this.status,
    this.admin = false,
    required this.team,
    required this.skills,
    this.positionId,
    this.keySkills = const [], // Par défaut : liste vide
    this.personalAlertEnabled = false,
    this.personalAlertBeforeShiftHours = 1,
    this.chiefAlertEnabled = false,
    this.chiefAlertBeforeShiftHours = 1,
    this.anomalyAlertEnabled = false,
    this.anomalyAlertDaysBefore = 14,
  });

  /// Permet de dupliquer l'objet avec des champs modifiés
  User copyWith({
    String? id,
    String? lastName,
    String? firstName,
    String? station,
    String? status,
    bool? admin,
    String? team,
    List<String>? skills,
    String? positionId,
    List<String>? keySkills,
    bool? personalAlertEnabled,
    int? personalAlertBeforeShiftHours,
    bool? chiefAlertEnabled,
    int? chiefAlertBeforeShiftHours,
    bool? anomalyAlertEnabled,
    int? anomalyAlertDaysBefore,
  }) {
    return User(
      id: id ?? this.id,
      lastName: lastName ?? this.lastName,
      firstName: firstName ?? this.firstName,
      station: station ?? this.station,
      status: status ?? this.status,
      admin: admin ?? this.admin,
      team: team ?? this.team,
      skills: skills ?? this.skills,
      positionId: positionId ?? this.positionId,
      keySkills: keySkills ?? this.keySkills,
      personalAlertEnabled: personalAlertEnabled ?? this.personalAlertEnabled,
      personalAlertBeforeShiftHours:
          personalAlertBeforeShiftHours ?? this.personalAlertBeforeShiftHours,
      chiefAlertEnabled: chiefAlertEnabled ?? this.chiefAlertEnabled,
      chiefAlertBeforeShiftHours:
          chiefAlertBeforeShiftHours ?? this.chiefAlertBeforeShiftHours,
      anomalyAlertEnabled: anomalyAlertEnabled ?? this.anomalyAlertEnabled,
      anomalyAlertDaysBefore:
          anomalyAlertDaysBefore ?? this.anomalyAlertDaysBefore,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'lastName': lastName,
    'firstName': firstName,
    'station': station,
    'status': status,
    'admin': admin,
    'team': team,
    'skills': skills,
    if (positionId != null) 'positionId': positionId,
    'keySkills': keySkills,
    'personalAlertEnabled': personalAlertEnabled,
    'personalAlertBeforeShiftHours': personalAlertBeforeShiftHours,
    'chiefAlertEnabled': chiefAlertEnabled,
    'chiefAlertBeforeShiftHours': chiefAlertBeforeShiftHours,
    'anomalyAlertEnabled': anomalyAlertEnabled,
    'anomalyAlertDaysBefore': anomalyAlertDaysBefore,
  };

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'],
    lastName: json['lastName'],
    firstName: json['firstName'],
    station: json['station'],
    status: json['status'],
    admin: json['admin'] ?? false,
    team: json['team'],
    skills: List<String>.from(json['skills']),
    positionId: json['positionId'] as String?,
    keySkills: json['keySkills'] != null
        ? List<String>.from(json['keySkills'])
        : [],
    personalAlertEnabled: json['personalAlertEnabled'] as bool? ?? true,
    personalAlertBeforeShiftHours:
        json['personalAlertBeforeShiftHours'] as int? ?? 1,
    chiefAlertEnabled: json['chiefAlertEnabled'] as bool? ?? true,
    chiefAlertBeforeShiftHours: json['chiefAlertBeforeShiftHours'] as int? ?? 1,
    anomalyAlertEnabled: json['anomalyAlertEnabled'] as bool? ?? true,
    anomalyAlertDaysBefore: json['anomalyAlertDaysBefore'] as int? ?? 14,
  );

  static User empty() => User(
    id: "",
    firstName: "Inconnu",
    lastName: "",
    station: "",
    status: "",
    admin: false,
    team: "",
    skills: [],
  );
}
