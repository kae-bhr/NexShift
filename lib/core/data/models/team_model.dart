import 'dart:ui';

class Team {
  final String id; // e.g. 'A', 'B', 'C', 'D'
  final String name; // Display label, e.g. 'Équipe A'
  final String stationId; // Reference to Station.id
  final Color color; // Team color representation
  final int order; // Display order (lower = first)

  const Team({
    required this.id,
    required this.name,
    required this.stationId,
    required this.color,
    this.order = 0,
  });

  Team copyWith({
    String? id,
    String? name,
    String? stationId,
    Color? color,
    int? order,
  }) => Team(
    id: id ?? this.id,
    name: name ?? this.name,
    stationId: stationId ?? this.stationId,
    color: color ?? this.color,
    order: order ?? this.order,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'stationId': stationId,
    // Persist as ARGB int to ensure JSON-safe storage
    'color': color.toARGB32(),
    'order': order,
  };

  factory Team.fromJson(Map<String, dynamic> json) => Team(
    id: json['id'] as String,
    name: json['name'] as String,
    stationId: (json['stationId'] ?? '') as String,
    // Accept int (ARGB), hex string, or fallback to a default
    color: _parseColor(json['color'], json['id'] as String?),
    order: (json['order'] ?? 0) as int,
  );

  static Color _parseColor(dynamic raw, String? id) {
    if (raw is int) {
      return Color(raw);
    }
    if (raw is String) {
      // Try parse hex like '0xFFRRGGBB' or '#RRGGBB'
      final s = raw.trim();
      try {
        if (s.startsWith('0x')) {
          return Color(int.parse(s));
        } else if (s.startsWith('#')) {
          final hex = s.substring(1);
          // If only RRGGBB, prefix FF for alpha
          final val = hex.length == 6
              ? int.parse('0xFF$hex')
              : int.parse('0x$hex');
          return Color(val);
        } else {
          return Color(int.parse(s));
        }
      } catch (_) {
        // fallthrough to default
      }
    }
    // Default by team id for stability
    switch (id) {
      case 'A':
        return const Color(0xFFE53935); // red
      case 'B':
        return const Color(0xFF1E88E5); // blue
      case 'C':
        return const Color(0xFF43A047); // green
      case 'D':
        return const Color.fromARGB(255, 199, 202, 18); // yellow
      default:
        return const Color(0xFF757575); // grey
    }
  }
}
