/// Modèle pour les réservations de matricule (pré-affiliation)
class ReservedMatricule {
  final String matricule;
  final String reservedBy; // authUid de l'admin
  final DateTime reservedAt;

  ReservedMatricule({
    required this.matricule,
    required this.reservedBy,
    required this.reservedAt,
  });

  factory ReservedMatricule.fromJson(Map<String, dynamic> json) {
    return ReservedMatricule(
      matricule: json['matricule'] ?? '',
      reservedBy: json['reservedBy'] ?? '',
      reservedAt: json['reservedAt'] != null
          ? DateTime.parse(json['reservedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'matricule': matricule,
    'reservedBy': reservedBy,
    'reservedAt': reservedAt.toIso8601String(),
  };
}
