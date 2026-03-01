/// Statuts de disponibilité opérationnelle d'un agent.
/// Distinct du champ [User.status] qui représente le rôle (agent/chief/leader).
class AgentAvailabilityStatus {
  static const String active = 'active';
  static const String suspendedFromDuty = 'suspendedFromDuty';
  static const String sickLeave = 'sickLeave';
}

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
  final List<String> positionIds; // IDs des postes occupés par l'agent
  final List<String> keySkills; // Compétences-clés critiques

  // Disponibilité opérationnelle (suspension d'engagement / arrêt maladie)
  final String agentAvailabilityStatus; // Voir AgentAvailabilityStatus
  final DateTime? suspensionStartDate; // Date de début de suspension/arrêt

  // Alerte personnalisée
  final bool personalAlertEnabled; // Rappel quotidien astreinte
  final int personalAlertHour; // Heure quotidienne (0-23), défaut: 18

  // Notifications d'adhésion (admin uniquement)
  final bool membershipAlertEnabled; // Notifications pour les demandes d'adhésion

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
    this.positionIds = const [],
    this.keySkills = const [], // Par défaut : liste vide
    this.agentAvailabilityStatus = AgentAvailabilityStatus.active,
    this.suspensionStartDate,
    this.personalAlertEnabled = false,
    this.personalAlertHour = 18,
    this.membershipAlertEnabled = false,
  });

  /// Permet de dupliquer l'objet avec des champs modifiés.
  /// Utiliser [clearSuspensionStartDate] = true pour remettre [suspensionStartDate] à null.
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
    List<String>? positionIds,
    List<String>? keySkills,
    String? agentAvailabilityStatus,
    DateTime? suspensionStartDate,
    bool clearSuspensionStartDate = false,
    bool? personalAlertEnabled,
    int? personalAlertHour,
    bool? membershipAlertEnabled,
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
      positionIds: positionIds ?? this.positionIds,
      keySkills: keySkills ?? this.keySkills,
      agentAvailabilityStatus:
          agentAvailabilityStatus ?? this.agentAvailabilityStatus,
      suspensionStartDate: clearSuspensionStartDate
          ? null
          : (suspensionStartDate ?? this.suspensionStartDate),
      personalAlertEnabled: personalAlertEnabled ?? this.personalAlertEnabled,
      personalAlertHour: personalAlertHour ?? this.personalAlertHour,
      membershipAlertEnabled: membershipAlertEnabled ?? this.membershipAlertEnabled,
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
    if (positionIds.isNotEmpty) 'positionIds': positionIds,
    'keySkills': keySkills,
    'agentAvailabilityStatus': agentAvailabilityStatus,
    if (suspensionStartDate != null)
      'suspensionStartDate': suspensionStartDate!.toIso8601String(),
    'personalAlertEnabled': personalAlertEnabled,
    'personalAlertHour': personalAlertHour,
    'membershipAlertEnabled': membershipAlertEnabled,
  };

  /// Sérialisation pour Firestore : exclut les PII (firstName, lastName, email).
  /// Le chiffrement de ces champs est géré exclusivement par les Cloud Functions.
  /// [agentAvailabilityStatus] et [suspensionStartDate] sont des données opérationnelles (non PII).
  Map<String, dynamic> toFirestoreJson() => {
    'id': id,
    if (authUid != null) 'authUid': authUid,
    'station': station,
    'status': status,
    'admin': admin,
    'team': team,
    'skills': skills,
    if (positionIds.isNotEmpty) 'positionIds': positionIds,
    'keySkills': keySkills,
    'agentAvailabilityStatus': agentAvailabilityStatus,
    if (suspensionStartDate != null)
      'suspensionStartDate': suspensionStartDate!.toIso8601String(),
    'personalAlertEnabled': personalAlertEnabled,
    'personalAlertHour': personalAlertHour,
    'membershipAlertEnabled': membershipAlertEnabled,
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
    positionIds: json['positionIds'] != null
        ? List<String>.from(json['positionIds'])
        : (json['positionId'] != null ? [json['positionId'] as String] : []),
    keySkills: json['keySkills'] != null
        ? List<String>.from(json['keySkills'])
        : [],
    agentAvailabilityStatus:
        json['agentAvailabilityStatus'] as String? ?? AgentAvailabilityStatus.active,
    suspensionStartDate: json['suspensionStartDate'] != null
        ? DateTime.tryParse(json['suspensionStartDate'] as String)
        : null,
    personalAlertEnabled: json['personalAlertEnabled'] as bool? ?? false,
    personalAlertHour: json['personalAlertHour'] as int? ?? 18,
    membershipAlertEnabled: json['membershipAlertEnabled'] as bool? ?? false,
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

  /// Vrai si l'agent est en suspension d'engagement ou en arrêt maladie.
  bool get isSuspended =>
      agentAvailabilityStatus != AgentAvailabilityStatus.active;

  /// Vrai si l'agent peut participer aux remplacements (ni suspendu, ni en arrêt).
  bool get isActiveForReplacement =>
      agentAvailabilityStatus == AgentAvailabilityStatus.active;

  /// Retourne le nom de la station (à charger via StationNameCache)
  /// IMPORTANT: Ceci est l'ID - utilisez StationNameCache.getStationName() pour le nom
  String get stationId => station;
}
