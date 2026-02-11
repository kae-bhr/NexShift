class User {
  final String id; // Matricule
  final String? authUid; // Firebase Auth UID (nouveau)
  final String? email; // Email pro pompier (nouveau)
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
    this.authUid,
    this.email,
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
    String? authUid,
    String? email,
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
      authUid: authUid ?? this.authUid,
      email: email ?? this.email,
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

  /// Sérialisation complète (pour stockage local uniquement — SharedPreferences).
  /// NE PAS utiliser pour écrire dans Firestore : les PII seraient en clair.
  Map<String, dynamic> toJson() => {
    'id': id,
    if (authUid != null) 'authUid': authUid,
    if (email != null) 'email': email,
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

  /// Sérialisation pour Firestore : exclut les PII (firstName, lastName, email).
  /// Le chiffrement de ces champs est géré exclusivement par les Cloud Functions.
  Map<String, dynamic> toFirestoreJson() => {
    'id': id,
    if (authUid != null) 'authUid': authUid,
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
    id: json['id'] ?? json['matricule'] ?? '',
    authUid: json['authUid'] as String?,
    email: json['email'] as String?,
    lastName: json['lastName'] ?? '',
    firstName: json['firstName'] ?? '',
    station: json['station'] ?? '',
    status: json['status'] ?? 'agent',
    admin: json['admin'] ?? false,
    team: json['team'] ?? '',
    skills: json['skills'] != null ? List<String>.from(json['skills']) : [],
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
    authUid: null,
    email: null,
    firstName: "Inconnu",
    lastName: "",
    station: "",
    status: "",
    admin: false,
    team: "",
    skills: [],
  );

  /// Vérifie si l'utilisateur a un compte Firebase Auth lié
  bool get hasAuthAccount => authUid != null && authUid!.isNotEmpty;

  /// Nom complet de l'utilisateur
  String get fullName => '$firstName $lastName'.trim();

  /// Nom d'affichage : nom complet si disponible, sinon "Agent {matricule}"
  String get displayName {
    if (firstName.isEmpty && lastName.isEmpty) return 'Agent $id';
    return '$firstName $lastName'.trim();
  }

  /// Initiales pour avatar. '?' si aucun nom.
  String get initials {
    final fi = firstName.isNotEmpty ? firstName[0] : '';
    final li = lastName.isNotEmpty ? lastName[0] : '';
    if (fi.isEmpty && li.isEmpty) return '?';
    return '$fi$li'.toUpperCase();
  }

  /// Vrai si l'utilisateur est pré-enregistré (pas encore de compte Firebase Auth).
  bool get isPreRegistered => !hasAuthAccount;

  /// Retourne le nom de la station (à charger via StationNameCache)
  /// IMPORTANT: Ceci est l'ID - utilisez StationNameCache.getStationName() pour le nom
  String get stationId => station;
}
