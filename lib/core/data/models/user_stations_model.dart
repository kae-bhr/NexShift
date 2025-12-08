/// Modèle pour la collection racine user_stations
/// Cette collection permet de savoir à quelles stations appartient un utilisateur
/// et stocke les données personnelles uniques (non dupliquées par station)
class UserStations {
  final String userId;
  final List<String> stations;

  // Données personnelles uniques (partagées entre toutes les stations)
  final String firstName;
  final String lastName;
  final String? fcmToken;

  UserStations({
    required this.userId,
    required this.stations,
    required this.firstName,
    required this.lastName,
    this.fcmToken,
  });

  factory UserStations.fromJson(Map<String, dynamic> json) {
    return UserStations(
      userId: json['userId'] as String,
      stations: List<String>.from(json['stations'] as List),
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      fcmToken: json['fcmToken'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'stations': stations,
      'firstName': firstName,
      'lastName': lastName,
      if (fcmToken != null) 'fcmToken': fcmToken,
    };
  }

  /// Crée une copie avec les champs modifiés
  UserStations copyWith({
    String? userId,
    List<String>? stations,
    String? firstName,
    String? lastName,
    String? fcmToken,
  }) {
    return UserStations(
      userId: userId ?? this.userId,
      stations: stations ?? this.stations,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      fcmToken: fcmToken ?? this.fcmToken,
    );
  }
}
