import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/trucks_model.dart';
import 'package:nexshift_app/core/data/models/crew_position_model.dart';
import 'package:nexshift_app/core/data/models/crew_mode_model.dart';
import 'package:nexshift_app/core/repositories/vehicle_rules_repository.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Statut du véhicule selon le niveau d'équipage
/// green = mode complet, orange = mode restreint, red = incomplet, grey = non géré
enum VehicleStatus { green, orange, red, grey }

/// Assignment of an agent to a position
class PositionAssignment {
  final CrewPosition position;
  final User? assignedAgent;
  final bool
  isFallback; // true if agent is using fallback skills instead of required skills

  PositionAssignment({
    required this.position,
    this.assignedAgent,
    this.isFallback = false,
  });

  bool get isFilled => assignedAgent != null;
}

/// Résultat d'allocation d'un équipage
class CrewResult {
  final Truck truck;
  final List<User> crew;
  final List<PositionAssignment> positions;
  final List<CrewPosition>
  missingForFull; // Postes manquants pour équipage complet
  final VehicleStatus status;
  final String statusLabel;
  final CrewMode? mode; // Mode utilisé pour l'allocation
  final bool isRestrictedMode; // true si mode restreint (prompt secours)

  CrewResult({
    required this.truck,
    required this.crew,
    required this.positions,
    this.missingForFull = const [],
    required this.status,
    required this.statusLabel,
    this.mode,
    this.isRestrictedMode = false,
  });
}

/// Classe principale de gestion d'allocation
class CrewAllocator {
  final List<User> allAgents;
  final VehicleRulesRepository _rulesRepo = VehicleRulesRepository();

  CrewAllocator(this.allAgents);

  /// Wrapper statique utilisé par la page
  static Future<CrewResult> allocateVehicleCrew({
    required List<User> agents,
    required Truck truck,
    String? stationId,
  }) async {
    final allocator = CrewAllocator(agents);
    return allocator._allocateForTruck(truck, stationId: stationId);
  }

  /// Alloue un équipage pour un Truck donné
  Future<CrewResult> _allocateForTruck(Truck truck, {String? stationId}) async {
    // Get rules for this vehicle type
    final ruleSet = await _rulesRepo.getRules(
      vehicleType: truck.type,
      stationId: stationId,
    );

    if (ruleSet == null) {
      return CrewResult(
        truck: truck,
        crew: [],
        positions: [],
        status: VehicleStatus.grey,
        statusLabel: 'Type de véhicule non géré',
      );
    }

    // Get the mode to use (from truck.modeId or default)
    CrewMode? mode;
    if (truck.modeId != null) {
      mode = ruleSet.getModeById(truck.modeId!);
    }
    mode ??= ruleSet.defaultMode;

    if (mode == null) {
      return CrewResult(
        truck: truck,
        crew: [],
        positions: [],
        status: VehicleStatus.grey,
        statusLabel: 'Aucun mode défini',
      );
    }

    // Clone available agents
    final available = List<User>.from(allAgents);

    // Try to allocate full mode first (mandatory positions only)
    final fullModeResult = _tryAllocatePositions(
      truck: truck,
      positions: mode.mandatoryPositions,
      available: available,
      mode: mode,
    );

    if (fullModeResult.status == VehicleStatus.green) {
      return fullModeResult;
    }

    // If full mode failed, try restricted variant if available
    if (mode.hasRestrictedVariant) {
      final restrictedMode = mode.restrictedVariant!;
      final reducedAvailable = List<User>.from(allAgents);

      final restrictedResult = _tryAllocatePositions(
        truck: truck,
        positions: restrictedMode.mandatoryPositions,
        available: reducedAvailable,
        mode: restrictedMode,
        isRestricted: true,
      );

      if (restrictedResult.status == VehicleStatus.green) {
        // Calculate missing positions for full mode
        final missingPositions = _getMissingPositionsForFull(
          mode.mandatoryPositions,
          restrictedMode.mandatoryPositions,
        );

        return CrewResult(
          truck: restrictedResult.truck,
          crew: restrictedResult.crew,
          positions: restrictedResult.positions,
          missingForFull: missingPositions,
          status: VehicleStatus.orange,
          statusLabel: 'Prompt secours (${restrictedMode.label})',
          mode: restrictedMode,
          isRestrictedMode: true,
        );
      }
    }

    // If no restricted mode or it failed too, return partial result
    return CrewResult(
      truck: truck,
      crew: fullModeResult.crew,
      positions: fullModeResult.positions,
      status: VehicleStatus.red,
      statusLabel: 'Équipage incomplet',
      mode: mode,
    );
  }

  /// Try to allocate agents to all positions
  CrewResult _tryAllocatePositions({
    required Truck truck,
    required List<CrewPosition> positions,
    required List<User> available,
    required CrewMode mode,
    bool isRestricted = false,
  }) {
    final assignments = <PositionAssignment>[];
    final crew = <User>[];

    for (final position in positions) {
      final result = _findAndConsumeForPosition(available, position);
      assignments.add(result);
      if (result.assignedAgent != null) {
        crew.add(result.assignedAgent!);
      }
    }

    // Check if all mandatory positions are filled
    final allFilled = assignments.every((a) => a.isFilled);
    final status = allFilled ? VehicleStatus.green : VehicleStatus.red;
    final statusLabel = allFilled
        ? (isRestricted ? 'Prompt secours' : 'Équipage complet')
        : 'Équipage incomplet';

    return CrewResult(
      truck: truck,
      crew: crew,
      positions: assignments,
      status: status,
      statusLabel: statusLabel,
      mode: mode,
      isRestrictedMode: isRestricted,
    );
  }

  /// Find and consume an agent who can fill the position
  /// Optimized strategy: Among all candidates, choose the one with the LEAST total skills
  /// This preserves highly skilled agents for positions requiring rare skills
  PositionAssignment _findAndConsumeForPosition(
    List<User> available,
    CrewPosition position,
  ) {
    // Find ALL agents who can fill this position
    final candidates = <({User agent, bool isFallback})>[];

    for (final agent in available) {
      final result = position.canUserFillPosition(agent.skills);
      if (result.canFill) {
        candidates.add((agent: agent, isFallback: result.isFallback));
      }
    }

    if (candidates.isEmpty) {
      return PositionAssignment(position: position);
    }

    // Among candidates, choose the one with the LEAST skills
    // This optimizes allocation by saving highly skilled agents for demanding positions
    // Prioritize non-fallback candidates first, then sort by skill count
    candidates.sort((a, b) {
      // Non-fallback candidates have priority
      if (a.isFallback != b.isFallback) {
        return a.isFallback ? 1 : -1;
      }
      // Among same fallback status, prefer agent with fewer skills
      return a.agent.skills.length.compareTo(b.agent.skills.length);
    });

    final selected = candidates.first;
    available.remove(selected.agent);

    return PositionAssignment(
      position: position,
      assignedAgent: selected.agent,
      isFallback: selected.isFallback,
    );
  }

  /// Get positions that are in full crew but not in reduced crew
  List<CrewPosition> _getMissingPositionsForFull(
    List<CrewPosition> fullCrew,
    List<CrewPosition> reducedCrew,
  ) {
    final reducedIds = reducedCrew.map((p) => p.id).toSet();
    return fullCrew.where((p) => !reducedIds.contains(p.id)).toList();
  }

  /// Allocate all vehicles sequentially with shared pools per type
  /// Returns a map of vehicle results by vehicle key
  /// For vehicles with multiple modes (e.g., FPT), creates entries for each mode
  static Future<Map<String, CrewResult>> allocateAllVehicles({
    required List<User> effectiveAgents,
    required List<Truck> trucks,
    String? stationId,
  }) async {
    final results = <String, CrewResult>{};
    final rulesRepo = VehicleRulesRepository();

    // Build agent pools per vehicle type
    final Map<String, List<User>> poolsByType = {};
    for (final truckType in KTrucks.vehicleTypeOrder) {
      poolsByType[truckType] = List<User>.from(effectiveAgents);
    }

    // Group trucks by type
    final Map<String, List<Truck>> trucksByType = {};
    for (final truck in trucks) {
      trucksByType.putIfAbsent(truck.type, () => []).add(truck);
    }

    // Allocate each vehicle type sequentially
    for (final vehicleType in KTrucks.vehicleTypeOrder) {
      final typeTrucks = trucksByType[vehicleType] ?? [];
      if (typeTrucks.isEmpty) continue;

      final pool = poolsByType[vehicleType];
      if (pool == null) continue;

      // Get rules for this vehicle type
      final ruleSet = await rulesRepo.getRules(
        vehicleType: vehicleType,
        stationId: stationId,
      );
      if (ruleSet == null) continue;

      // Sort trucks by ID for consistent allocation order
      typeTrucks.sort((a, b) => a.id.compareTo(b.id));

      // For each truck of this type
      for (final truck in typeTrucks) {
        // Get all modes for this truck (from modeId or all available modes)
        final modes = <CrewMode>[];

        if (truck.modeId != null) {
          // Truck has a specific mode configured
          final mode = ruleSet.getModeById(truck.modeId!);
          if (mode != null) modes.add(mode);
        } else {
          // No specific mode: use all modes defined for this vehicle
          modes.addAll(ruleSet.modes);
        }

        // Allocate for each mode
        for (final mode in modes) {
          // Create pool snapshot for this truck+mode combination
          final thisModePool = List<User>.from(pool);

          final result = await CrewAllocator(
            thisModePool,
          )._allocateForTruckWithMode(truck: truck, mode: mode);

          // Build result key using displaySuffix
          final key = mode.displaySuffix.isNotEmpty
              ? '${truck.displayName}_${mode.displaySuffix}'
              : truck.displayName;

          results[key] = result;

          // For multi-mode trucks, agents are shared between modes of the SAME truck
          // So we DON'T remove from pool here (allows FPT1_4H and FPT1_6H to share agents)
        }

        // After all modes processed for this truck, remove agents used by ANY mode
        // This prevents other trucks from using these agents
        final allUsedIds = <String>{};
        for (final mode in modes) {
          final key = mode.displaySuffix.isNotEmpty
              ? '${truck.displayName}_${mode.displaySuffix}'
              : truck.displayName;
          final result = results[key];
          if (result != null) {
            for (final used in result.crew) {
              allUsedIds.add(used.id);
            }
          }
        }

        pool.removeWhere((a) => allUsedIds.contains(a.id));
      }
    }

    return results;
  }

  /// Internal method: allocate with a specific mode (no rule lookup)
  Future<CrewResult> _allocateForTruckWithMode({
    required Truck truck,
    required CrewMode mode,
  }) async {
    // Clone available agents
    final available = List<User>.from(allAgents);

    // Try to allocate full mode first
    final fullModeResult = _tryAllocatePositions(
      truck: truck,
      positions: mode.mandatoryPositions,
      available: available,
      mode: mode,
    );

    if (fullModeResult.status == VehicleStatus.green) {
      return fullModeResult;
    }

    // If full mode failed, try restricted variant if available
    if (mode.hasRestrictedVariant) {
      final restrictedMode = mode.restrictedVariant!;
      final reducedAvailable = List<User>.from(allAgents);

      final restrictedResult = _tryAllocatePositions(
        truck: truck,
        positions: restrictedMode.mandatoryPositions,
        available: reducedAvailable,
        mode: restrictedMode,
        isRestricted: true,
      );

      if (restrictedResult.status == VehicleStatus.green) {
        final missingPositions = _getMissingPositionsForFull(
          mode.mandatoryPositions,
          restrictedMode.mandatoryPositions,
        );

        return CrewResult(
          truck: restrictedResult.truck,
          crew: restrictedResult.crew,
          positions: restrictedResult.positions,
          missingForFull: missingPositions,
          status: VehicleStatus.orange,
          statusLabel: 'Prompt secours (${restrictedMode.label})',
          mode: restrictedMode,
          isRestrictedMode: true,
        );
      }
    }

    return CrewResult(
      truck: truck,
      crew: fullModeResult.crew,
      positions: fullModeResult.positions,
      status: VehicleStatus.red,
      statusLabel: 'Équipage incomplet',
      mode: mode,
    );
  }

  /// Sort vehicle icon specs by type priority and ID
  /// Follows order: VSAV1, VSAVx, VTU1, VTUx, FPT1_4H, FPT1_6H, FPTx_4H, FPTx_6H, VPS1, VPSx
  static List<Map<String, dynamic>> sortVehicleSpecs(
    List<Map<String, dynamic>> specs,
  ) {
    return specs.toList()..sort((a, b) {
      final typeA = a['type'] as String;
      final typeB = b['type'] as String;
      final idA = a['id'] as int;
      final idB = b['id'] as int;
      final periodA = a['period'] as String?;
      final periodB = b['period'] as String?;

      // Compare by type priority first
      final priorityA = KTrucks.vehicleTypePriority[typeA] ?? 999;
      final priorityB = KTrucks.vehicleTypePriority[typeB] ?? 999;
      if (priorityA != priorityB) return priorityA.compareTo(priorityB);

      // Same type: compare by ID
      if (idA != idB) return idA.compareTo(idB);

      // Same type and ID: for FPT, 4H before 6H
      if (periodA != null && periodB != null) {
        if (periodA == '4H' && periodB == '6H') return -1;
        if (periodA == '6H' && periodB == '4H') return 1;
      }

      return 0;
    });
  }
}
