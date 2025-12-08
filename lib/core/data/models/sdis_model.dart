/// Modèle pour un SDIS (Service Départemental d'Incendie et de Secours)
/// Chaque SDIS a un ID unique (code département) et un nom
class SDIS {
  final String id; // Code département (ex: "50", "30")
  final String name; // Nom du département (ex: "Manche", "Gard")
  final String fullName; // Nom complet (ex: "SDIS de la Manche")

  SDIS({
    required this.id,
    required this.name,
    required this.fullName,
  });

  factory SDIS.fromJson(Map<String, dynamic> json) {
    return SDIS(
      id: json['id'] as String,
      name: json['name'] as String,
      fullName: json['fullName'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'fullName': fullName,
    };
  }

  @override
  String toString() => '$fullName ($id)';
}
