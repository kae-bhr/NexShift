import 'package:nexshift_app/core/data/models/crew_position_model.dart';

/// Represents a crew mode for a vehicle (e.g., 'complet', '4h', '6h')
/// Each mode defines the crew positions required and may have a restricted variant
class CrewMode {
  final String id; // e.g., 'complet', 'reduit', '4h', '6h'
  final String label; // e.g., 'Équipage complet', 'Prompt secours', '4 hommes'
  final String
  displaySuffix; // Suffix for planning display (e.g., '', '4H', '6H'). Empty for single-mode vehicles
  final bool isDefault; // Whether this is the default mode for the vehicle
  final List<CrewPosition> positions; // Mandatory crew positions
  final List<CrewPosition>
  optionalPositions; // Optional positions (e.g., learners)
  final CrewMode?
  restrictedVariant; // Restricted version of this mode (Prompt Secours)

  const CrewMode({
    required this.id,
    required this.label,
    this.displaySuffix = '',
    this.isDefault = false,
    required this.positions,
    this.optionalPositions = const [],
    this.restrictedVariant,
  });

  /// Get all positions (mandatory + optional)
  List<CrewPosition> get allPositions => [...positions, ...optionalPositions];

  /// Get only mandatory positions (non-optional)
  List<CrewPosition> get mandatoryPositions =>
      positions.where((p) => !p.isOptional).toList();

  /// Check if this mode has a restricted variant
  bool get hasRestrictedVariant => restrictedVariant != null;

  /// Get the mode to use for crew allocation
  /// Returns the restricted variant if available, otherwise this mode
  CrewMode getEffectiveMode({bool preferRestricted = false}) {
    if (preferRestricted && hasRestrictedVariant) {
      return restrictedVariant!;
    }
    return this;
  }

  CrewMode copyWith({
    String? id,
    String? label,
    String? displaySuffix,
    bool? isDefault,
    List<CrewPosition>? positions,
    List<CrewPosition>? optionalPositions,
    CrewMode? restrictedVariant,
  }) {
    return CrewMode(
      id: id ?? this.id,
      label: label ?? this.label,
      displaySuffix: displaySuffix ?? this.displaySuffix,
      isDefault: isDefault ?? this.isDefault,
      positions: positions ?? this.positions,
      optionalPositions: optionalPositions ?? this.optionalPositions,
      restrictedVariant: restrictedVariant ?? this.restrictedVariant,
    );
  }

  /// Convert to JSON for Firestore
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'displaySuffix': displaySuffix,
      'isDefault': isDefault,
      'positions': positions.map((p) => _positionToJson(p)).toList(),
      'optionalPositions': optionalPositions
          .map((p) => _positionToJson(p))
          .toList(),
      'restrictedVariant': restrictedVariant?.toJson(),
    };
  }

  /// Convert CrewPosition to JSON
  static Map<String, dynamic> _positionToJson(CrewPosition position) {
    return {
      'id': position.id,
      'label': position.label,
      'requiredSkills': position.requiredSkills,
      'fallbackSkills': position.fallbackSkills,
      'requiresAll': position.requiresAll,
      'isOptional': position.isOptional,
    };
  }

  /// Create from JSON (Firestore)
  factory CrewMode.fromJson(Map<String, dynamic> json) {
    return CrewMode(
      id: json['id'] as String,
      label: json['label'] as String,
      displaySuffix: json['displaySuffix'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
      positions:
          (json['positions'] as List<dynamic>?)
              ?.map((p) => _positionFromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      optionalPositions:
          (json['optionalPositions'] as List<dynamic>?)
              ?.map((p) => _positionFromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      restrictedVariant: json['restrictedVariant'] != null
          ? CrewMode.fromJson(json['restrictedVariant'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Create CrewPosition from JSON
  static CrewPosition _positionFromJson(Map<String, dynamic> json) {
    return CrewPosition(
      id: json['id'] as String,
      label: json['label'] as String,
      requiredSkills:
          (json['requiredSkills'] as List<dynamic>?)
              ?.map((s) => s as String)
              .toList() ??
          [],
      fallbackSkills: (json['fallbackSkills'] as List<dynamic>?)
          ?.map((s) => s as String)
          .toList(),
      requiresAll: json['requiresAll'] as bool? ?? true,
      isOptional: json['isOptional'] as bool? ?? false,
    );
  }
}
