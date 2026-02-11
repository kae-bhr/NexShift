/// Modèle pour les custom claims Firebase Auth
class UserClaims {
  final String sdisId;
  final UserRole role;
  final Map<String, StationRole> stations;

  UserClaims({
    required this.sdisId,
    required this.role,
    required this.stations,
  });

  /// L'utilisateur est-il admin d'au moins une station ?
  bool get isAdmin => role == UserRole.admin;

  /// L'utilisateur est-il chef ou supérieur ?
  bool get isChiefOrAbove =>
      role == UserRole.chief || role == UserRole.admin;

  /// L'utilisateur est-il leader ou supérieur ?
  bool get isLeaderOrAbove =>
      role == UserRole.leader ||
      role == UserRole.chief ||
      role == UserRole.admin;

  /// L'utilisateur a-t-il accès à au moins une station ?
  bool get hasStationAccess => stations.isNotEmpty;

  /// Liste des IDs de stations accessibles
  List<String> get stationIds => stations.keys.toList();

  /// Vérifie si l'utilisateur a accès à une station spécifique
  bool hasAccessToStation(String stationId) => stations.containsKey(stationId);

  /// Récupère le rôle de l'utilisateur dans une station spécifique
  StationRole? getRoleInStation(String stationId) => stations[stationId];

  /// Vérifie si l'utilisateur est admin d'une station spécifique
  bool isAdminOfStation(String stationId) =>
      stations[stationId] == StationRole.admin;

  /// Vérifie si l'utilisateur est leader ou supérieur dans une station
  bool isLeaderOrAboveInStation(String stationId) {
    final stationRole = stations[stationId];
    return stationRole == StationRole.leader ||
        stationRole == StationRole.chief ||
        stationRole == StationRole.admin;
  }

  factory UserClaims.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return UserClaims.empty();
    }

    final stationsMap = <String, StationRole>{};
    if (json['stations'] != null && json['stations'] is Map) {
      (json['stations'] as Map).forEach((key, value) {
        stationsMap[key.toString()] = StationRole.fromString(value.toString());
      });
    }

    return UserClaims(
      sdisId: json['sdisId']?.toString() ?? '',
      role: UserRole.fromString(json['role']?.toString() ?? 'agent'),
      stations: stationsMap,
    );
  }

  /// Crée une instance depuis les claims du token Firebase Auth
  factory UserClaims.fromIdTokenClaims(Map<String, dynamic> claims) {
    // Les claims Firebase peuvent avoir des clés différentes
    // selon la structure définie dans les Cloud Functions
    return UserClaims.fromJson(claims);
  }

  Map<String, dynamic> toJson() => {
    'sdisId': sdisId,
    'role': role.value,
    'stations': stations.map((key, value) => MapEntry(key, value.value)),
  };

  static UserClaims empty() => UserClaims(
    sdisId: '',
    role: UserRole.agent,
    stations: {},
  );

  @override
  String toString() =>
      'UserClaims(sdisId: $sdisId, role: $role, stations: $stations)';
}

/// Rôle global de l'utilisateur (le plus élevé parmi toutes ses stations)
enum UserRole {
  agent('agent'),
  leader('leader'),
  chief('chief'),
  admin('admin');

  final String value;
  const UserRole(this.value);

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (r) => r.value == value,
      orElse: () => UserRole.agent,
    );
  }
}

/// Rôle de l'utilisateur dans une station spécifique
enum StationRole {
  agent('agent'),
  leader('leader'),
  chief('chief'),
  admin('admin');

  final String value;
  const StationRole(this.value);

  static StationRole fromString(String value) {
    return StationRole.values.firstWhere(
      (r) => r.value == value,
      orElse: () => StationRole.agent,
    );
  }
}
