/// Modèle pour les demandes d'adhésion à une caserne
class MembershipRequest {
  final String authUid;
  final String matricule;
  final String firstName;
  final String lastName;
  final MembershipStatus status;
  final DateTime requestedAt;
  final DateTime? respondedAt;
  final String? respondedBy;

  MembershipRequest({
    required this.authUid,
    required this.matricule,
    required this.firstName,
    required this.lastName,
    required this.status,
    required this.requestedAt,
    this.respondedAt,
    this.respondedBy,
  });

  /// Nom complet du demandeur
  String get fullName => '$firstName $lastName'.trim();

  /// La demande est-elle en attente ?
  bool get isPending => status == MembershipStatus.pending;

  /// La demande a-t-elle été acceptée ?
  bool get isAccepted => status == MembershipStatus.accepted;

  /// La demande a-t-elle été refusée ?
  bool get isRejected => status == MembershipStatus.rejected;

  factory MembershipRequest.fromJson(Map<String, dynamic> json) {
    return MembershipRequest(
      authUid: json['authUid'] ?? '',
      matricule: json['matricule'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      status: MembershipStatus.fromString(json['status'] ?? 'pending'),
      requestedAt: json['requestedAt'] != null
          ? DateTime.parse(json['requestedAt'])
          : DateTime.now(),
      respondedAt: json['respondedAt'] != null
          ? DateTime.parse(json['respondedAt'])
          : null,
      respondedBy: json['respondedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'authUid': authUid,
    'matricule': matricule,
    'firstName': firstName,
    'lastName': lastName,
    'status': status.value,
    'requestedAt': requestedAt.toIso8601String(),
    if (respondedAt != null) 'respondedAt': respondedAt!.toIso8601String(),
    if (respondedBy != null) 'respondedBy': respondedBy,
  };

  MembershipRequest copyWith({
    String? authUid,
    String? matricule,
    String? firstName,
    String? lastName,
    MembershipStatus? status,
    DateTime? requestedAt,
    DateTime? respondedAt,
    String? respondedBy,
  }) {
    return MembershipRequest(
      authUid: authUid ?? this.authUid,
      matricule: matricule ?? this.matricule,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
      respondedAt: respondedAt ?? this.respondedAt,
      respondedBy: respondedBy ?? this.respondedBy,
    );
  }
}

/// Statut d'une demande d'adhésion
enum MembershipStatus {
  pending('pending'),
  accepted('accepted'),
  rejected('rejected');

  final String value;
  const MembershipStatus(this.value);

  static MembershipStatus fromString(String value) {
    return MembershipStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => MembershipStatus.pending,
    );
  }
}

/// Modèle pour les demandes d'adhésion de l'utilisateur courant
/// (vue simplifiée avec info station)
class MyMembershipRequest {
  final String stationId;
  final String stationName;
  final MembershipStatus status;
  final DateTime requestedAt;

  MyMembershipRequest({
    required this.stationId,
    required this.stationName,
    required this.status,
    required this.requestedAt,
  });

  factory MyMembershipRequest.fromJson(Map<String, dynamic> json) {
    return MyMembershipRequest(
      stationId: json['stationId'] ?? '',
      stationName: json['stationName'] ?? '',
      status: MembershipStatus.fromString(json['status'] ?? 'pending'),
      requestedAt: json['requestedAt'] != null
          ? DateTime.parse(json['requestedAt'])
          : DateTime.now(),
    );
  }
}
