class Truck {
  final int id; // ID unique global pour Firestore (clé primaire)
  final int displayNumber; // Numéro d'affichage par type (VSAV1, VSAV2, VTU1, etc.)
  final String type;
  final String station;
  final bool available; // Disponibilité du véhicule
  final String? modeId; // Mode actif du véhicule (e.g., 'complet', '4h', '6h')

  Truck({
    required this.id,
    required this.displayNumber,
    required this.type,
    required this.station,
    this.available = true, // Par défaut disponible
    this.modeId, // Si null, utilise le mode par défaut du véhicule
  });

  String get displayName => "$type$displayNumber";

  Truck copyWith({
    int? id,
    int? displayNumber,
    String? type,
    String? station,
    bool? available,
    String? modeId,
  }) {
    return Truck(
      id: id ?? this.id,
      displayNumber: displayNumber ?? this.displayNumber,
      type: type ?? this.type,
      station: station ?? this.station,
      available: available ?? this.available,
      modeId: modeId ?? this.modeId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayNumber': displayNumber,
      'type': type,
      'station': station,
      'available': available,
      'modeId': modeId,
    };
  }

  factory Truck.fromJson(Map<String, dynamic> json) {
    // Gérer le cas où l'id vient de Firestore (String) ou du JSON local (int)
    final id = json['id'];
    final parsedId = id is int ? id : int.parse(id.toString());

    // Gérer displayNumber (peut être null pour anciennes données)
    final displayNumber = json['displayNumber'];
    final parsedDisplayNumber = displayNumber != null
        ? (displayNumber is int ? displayNumber : int.parse(displayNumber.toString()))
        : parsedId; // Fallback vers id pour compatibilité avec anciennes données

    return Truck(
      id: parsedId,
      displayNumber: parsedDisplayNumber,
      type: json['type'] as String,
      station: json['station'] as String,
      available: json['available'] as bool? ?? true,
      modeId: json['modeId'] as String?,
    );
  }
}
