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
