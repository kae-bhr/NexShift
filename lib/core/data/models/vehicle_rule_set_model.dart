import 'package:nexshift_app/core/data/models/crew_mode_model.dart';

/// Represents the complete rule set for a vehicle type
/// Defines all available crew modes and their configurations
class VehicleRuleSet {
  final String vehicleType; // e.g., 'VSAV', 'FPT', 'VTU'
  final List<CrewMode> modes; // All available modes for this vehicle
  final String? defaultModeId; // ID of the default mode
  final String? stationId; // If null, this is a global/default rule set

  const VehicleRuleSet({
    required this.vehicleType,
    required this.modes,
    this.defaultModeId,
    this.stationId,
  });

  /// Get the default mode for this vehicle
  CrewMode? get defaultMode {
    if (defaultModeId != null) {
      return modes.firstWhere(
        (mode) => mode.id == defaultModeId,
        orElse: () => modes.first,
      );
    }
    // If no default specified, use the first mode marked as default
    final defaultMarked = modes.where((m) => m.isDefault).toList();
    if (defaultMarked.isNotEmpty) {
      return defaultMarked.first;
    }
    // Fallback to first mode
    return modes.isNotEmpty ? modes.first : null;
  }

  /// Get a specific mode by ID
  CrewMode? getModeById(String modeId) {
    try {
      return modes.firstWhere((mode) => mode.id == modeId);
    } catch (e) {
      return null;
    }
  }

  /// Check if this is a station-specific rule set
  bool get isStationSpecific => stationId != null;

  /// Check if this is a global/default rule set
  bool get isGlobal => stationId == null;

  VehicleRuleSet copyWith({
    String? vehicleType,
    List<CrewMode>? modes,
    String? defaultModeId,
    String? stationId,
  }) {
    return VehicleRuleSet(
      vehicleType: vehicleType ?? this.vehicleType,
      modes: modes ?? this.modes,
      defaultModeId: defaultModeId ?? this.defaultModeId,
      stationId: stationId ?? this.stationId,
    );
  }

  /// Convert to JSON for Firestore
  Map<String, dynamic> toJson() {
    return {
      'vehicleType': vehicleType,
      'modes': modes.map((m) => m.toJson()).toList(),
      'defaultModeId': defaultModeId,
      'stationId': stationId,
    };
  }

  /// Create from JSON (Firestore)
  factory VehicleRuleSet.fromJson(Map<String, dynamic> json) {
    return VehicleRuleSet(
      vehicleType: json['vehicleType'] as String,
      modes:
          (json['modes'] as List<dynamic>?)
              ?.map((m) => CrewMode.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      defaultModeId: json['defaultModeId'] as String?,
      stationId: json['stationId'] as String?,
    );
  }
}
