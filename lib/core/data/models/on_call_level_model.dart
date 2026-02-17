import 'dart:ui';

/// Modèle représentant un niveau d'astreinte configurable par caserne.
/// Chaque niveau a un nom, une couleur et un ordre de priorité.
class OnCallLevel {
  final String id;
  final String name; // ex: "ASTR 1", "ASTR 2"
  final int colorValue; // Couleur stockée en ARGB int (comme Team.color)
  final int order; // Priorité (1 = plus haute, ordre décroissant)

  const OnCallLevel({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.order,
  });

  Color get color => Color(colorValue);

  OnCallLevel copyWith({
    String? id,
    String? name,
    int? colorValue,
    int? order,
  }) =>
      OnCallLevel(
        id: id ?? this.id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        order: order ?? this.order,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'order': order,
      };

  factory OnCallLevel.fromJson(Map<String, dynamic> json) => OnCallLevel(
        id: json['id'] as String,
        name: json['name'] as String,
        colorValue: json['colorValue'] as int,
        order: json['order'] as int? ?? 0,
      );
}
