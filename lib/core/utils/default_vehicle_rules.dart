import 'package:nexshift_app/core/data/models/crew_mode_model.dart';
import 'package:nexshift_app/core/data/models/crew_position_model.dart';
import 'package:nexshift_app/core/data/models/vehicle_rule_set_model.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Default vehicle crew rules for all vehicle types
/// These serve as the baseline and can be overridden per station
class KDefaultVehicleRules {
  // ==================== VSAV ====================
  static final vsavRuleSet = VehicleRuleSet(
    vehicleType: KTrucks.vsav,
    defaultModeId: 'complet',
    modes: [
      CrewMode(
        id: 'complet',
        label: 'Équipage complet',
        displaySuffix: '', // Single mode vehicle - no suffix
        isDefault: true,
        positions: const [
          CrewPosition(
            id: 'driver',
            label: 'Conducteur',
            requiredSkills: [KSkills.cod0, KSkills.suap],
          ),
          CrewPosition(
            id: 'team_leader',
            label: 'Chef d\'agrès',
            requiredSkills: [KSkills.suapCA],
          ),
          CrewPosition(
            id: 'crew_1',
            label: 'Équipier 1',
            requiredSkills: [KSkills.suap],
          ),
        ],
        optionalPositions: const [
          CrewPosition(
            id: 'learner',
            label: 'Apprenant',
            requiredSkills: [KSkills.suapA],
            isOptional: true,
          ),
        ],
        restrictedVariant: const CrewMode(
          id: 'prompt_secours',
          label: 'Prompt secours',
          displaySuffix: 'PS',
          positions: [
            CrewPosition(
              id: 'driver',
              label: 'Conducteur',
              requiredSkills: [KSkills.cod0, KSkills.suap],
            ),
            CrewPosition(
              id: 'crew_1',
              label: 'Équipier 1',
              requiredSkills: [KSkills.suap],
            ),
          ],
        ),
      ),
    ],
  );

  // ==================== VTU ====================
  static final vtuRuleSet = VehicleRuleSet(
    vehicleType: KTrucks.vtu,
    defaultModeId: 'complet',
    modes: [
      CrewMode(
        id: 'complet',
        label: 'Équipage complet',
        displaySuffix: '', // Single mode vehicle
        isDefault: true,
        positions: const [
          CrewPosition(
            id: 'team_leader',
            label: 'Chef d\'agrès',
            requiredSkills: [KSkills.ppbeCA, KSkills.cod0],
          ),
          CrewPosition(
            id: 'crew_1',
            label: 'Équipier 1',
            requiredSkills: [KSkills.ppbe],
          ),
        ],
        optionalPositions: const [
          CrewPosition(
            id: 'learner',
            label: 'Apprenant',
            requiredSkills: [KSkills.ppbeA],
            isOptional: true,
          ),
        ],
        restrictedVariant: const CrewMode(
          id: 'prompt_secours',
          label: 'Prompt secours',
          displaySuffix: 'PS',
          positions: [
            CrewPosition(
              id: 'driver',
              label: 'Conducteur',
              requiredSkills: [KSkills.cod0, KSkills.ppbe],
            ),
            CrewPosition(
              id: 'crew_1',
              label: 'Équipier 1',
              requiredSkills: [KSkills.ppbe],
            ),
          ],
        ),
      ),
    ],
  );

  // ==================== FPT ====================
  static final fptRuleSet = VehicleRuleSet(
    vehicleType: KTrucks.fpt,
    defaultModeId: '4h',
    modes: [
      // Mode 4H avec mode restreint
      CrewMode(
        id: '4h',
        label: '4 Hommes',
        displaySuffix: '4H', // Multi-mode vehicle
        isDefault: true,
        positions: const [
          CrewPosition(
            id: 'driver',
            label: 'Conducteur PL',
            requiredSkills: [KSkills.cod1, KSkills.inc],
          ),
          CrewPosition(
            id: 'team_leader',
            label: 'Chef d\'agrès',
            requiredSkills: [KSkills.incCA],
          ),
          CrewPosition(
            id: 'squad_leader_1',
            label: 'Chef d\'équipe 1',
            requiredSkills: [KSkills.incCE],
            fallbackSkills: [KSkills.inc],
          ),
          CrewPosition(
            id: 'crew_1',
            label: 'Équipier 1',
            requiredSkills: [KSkills.inc],
          ),
        ],
        optionalPositions: const [
          CrewPosition(
            id: 'learner',
            label: 'Apprenant',
            requiredSkills: [KSkills.incA],
            isOptional: true,
          ),
        ],
        restrictedVariant: const CrewMode(
          id: '4h_prompt_secours',
          label: 'Prompt secours (3H)',
          displaySuffix: '4H_PS',
          positions: [
            CrewPosition(
              id: 'driver',
              label: 'Conducteur PL',
              requiredSkills: [KSkills.cod1, KSkills.inc],
            ),
            CrewPosition(
              id: 'squad_leader_1',
              label: 'Chef d\'équipe 1',
              requiredSkills: [KSkills.incCE],
              fallbackSkills: [KSkills.inc],
            ),
            CrewPosition(
              id: 'crew_1',
              label: 'Équipier 1',
              requiredSkills: [KSkills.inc],
            ),
          ],
        ),
      ),
      // Mode 6H sans mode restreint
      const CrewMode(
        id: '6h',
        label: '6 Hommes',
        displaySuffix: '6H', // Multi-mode vehicle
        positions: [
          CrewPosition(
            id: 'driver',
            label: 'Conducteur PL',
            requiredSkills: [KSkills.cod1, KSkills.inc],
          ),
          CrewPosition(
            id: 'team_leader',
            label: 'Chef d\'agrès',
            requiredSkills: [KSkills.incCA],
          ),
          CrewPosition(
            id: 'squad_leader_1',
            label: 'Chef d\'équipe 1',
            requiredSkills: [KSkills.incCE],
            fallbackSkills: [KSkills.inc],
          ),
          CrewPosition(
            id: 'crew_1',
            label: 'Équipier 1',
            requiredSkills: [KSkills.inc],
          ),
          CrewPosition(
            id: 'squad_leader_2',
            label: 'Chef d\'équipe 2',
            requiredSkills: [KSkills.incCE],
            fallbackSkills: [KSkills.inc],
          ),
          CrewPosition(
            id: 'crew_2',
            label: 'Équipier 2',
            requiredSkills: [KSkills.inc],
          ),
        ],
        optionalPositions: [
          CrewPosition(
            id: 'learner',
            label: 'Apprenant',
            requiredSkills: [KSkills.inc],
            isOptional: true,
          ),
        ],
      ),
    ],
  );

  // ==================== VPS ====================
  static final vpsRuleSet = VehicleRuleSet(
    vehicleType: KTrucks.vps,
    defaultModeId: 'complet',
    modes: const [
      CrewMode(
        id: 'complet',
        label: 'Équipage complet',
        displaySuffix: '', // Single mode
        isDefault: true,
        positions: [
          CrewPosition(
            id: 'driver',
            label: 'Conducteur',
            requiredSkills: [KSkills.cod0, KSkills.vps],
          ),
          CrewPosition(
            id: 'team_leader',
            label: 'Chef d\'agrès',
            requiredSkills: [KSkills.vpsCA],
          ),
        ],
      ),
    ],
  );

  // ==================== EPA ====================
  static final epaRuleSet = VehicleRuleSet(
    vehicleType: KTrucks.epa,
    defaultModeId: 'complet',
    modes: const [
      CrewMode(
        id: 'complet',
        label: 'Équipage complet',
        displaySuffix: '', // Single mode
        isDefault: true,
        positions: [
          CrewPosition(
            id: 'driver',
            label: 'Conducteur PL',
            requiredSkills: [KSkills.cod1, KSkills.inc],
          ),
          CrewPosition(
            id: 'team_leader',
            label: 'Chef d\'agrès',
            requiredSkills: [KSkills.incCE],
            fallbackSkills: [KSkills.inc],
          ),
          CrewPosition(
            id: 'crew_1',
            label: 'Équipier 1',
            requiredSkills: [KSkills.inc],
          ),
        ],
      ),
    ],
  );

  // ==================== VSR ====================
  static final vsrRuleSet = VehicleRuleSet(
    vehicleType: KTrucks.vsr,
    defaultModeId: 'complet',
    modes: const [
      CrewMode(
        id: 'complet',
        label: 'Équipage complet',
        displaySuffix: '', // Single mode
        isDefault: true,
        positions: [
          CrewPosition(
            id: 'driver',
            label: 'Conducteur PL',
            requiredSkills: [KSkills.cod1, KSkills.inc],
          ),
          CrewPosition(
            id: 'team_leader',
            label: 'Chef d\'agrès',
            requiredSkills: [KSkills.incCE],
            fallbackSkills: [KSkills.inc],
          ),
          CrewPosition(
            id: 'crew_1',
            label: 'Équipier 1',
            requiredSkills: [KSkills.inc],
          ),
        ],
      ),
    ],
  );

  // ==================== CCF ====================
  static final ccfRuleSet = VehicleRuleSet(
    vehicleType: KTrucks.ccf,
    defaultModeId: 'complet',
    modes: const [
      CrewMode(
        id: 'complet',
        label: 'Équipage complet',
        displaySuffix: '', // Single mode
        isDefault: true,
        positions: [
          CrewPosition(
            id: 'driver',
            label: 'Conducteur PL',
            requiredSkills: [KSkills.cod1, KSkills.inc],
          ),
          CrewPosition(
            id: 'team_leader',
            label: 'Chef d\'agrès',
            requiredSkills: [KSkills.incCE],
            fallbackSkills: [KSkills.inc],
          ),
          CrewPosition(
            id: 'crew_1',
            label: 'Équipier 1',
            requiredSkills: [KSkills.inc],
          ),
          CrewPosition(
            id: 'crew_2',
            label: 'Équipier 2',
            requiredSkills: [KSkills.inc],
          ),
          CrewPosition(
            id: 'crew_3',
            label: 'Équipier 3',
            requiredSkills: [KSkills.inc],
          ),
        ],
      ),
    ],
  );

  // ==================== VSS ====================
  static final vssRuleSet = VehicleRuleSet(
    vehicleType: KTrucks.vss,
    defaultModeId: 'complet',
    modes: const [
      CrewMode(
        id: 'complet',
        label: 'Équipage complet',
        displaySuffix: '', // Single mode
        isDefault: true,
        positions: [
          CrewPosition(
            id: 'driver',
            label: 'Conducteur PL',
            requiredSkills: [KSkills.cod1, KSkills.inc],
          ),
          CrewPosition(
            id: 'team_leader',
            label: 'Chef d\'agrès',
            requiredSkills: [KSkills.incCE],
            fallbackSkills: [KSkills.inc],
          ),
          CrewPosition(
            id: 'crew_1',
            label: 'Équipier 1',
            requiredSkills: [KSkills.inc],
          ),
        ],
      ),
    ],
  );

  // ==================== VPC ====================
  static final vpcRuleSet = VehicleRuleSet(
    vehicleType: KTrucks.vpc,
    defaultModeId: 'complet',
    modes: const [
      CrewMode(
        id: 'complet',
        label: 'Équipage complet',
        displaySuffix: '', // Single mode
        isDefault: true,
        positions: [
          CrewPosition(
            id: 'commander',
            label: 'Commandant',
            requiredSkills: [KSkills.cod2],
          ),
        ],
      ),
    ],
  );

  /// Map of all default vehicle rule sets by vehicle type
  static final Map<String, VehicleRuleSet> defaultRuleSets = {
    KTrucks.vsav: vsavRuleSet,
    KTrucks.vtu: vtuRuleSet,
    KTrucks.fpt: fptRuleSet,
    KTrucks.vps: vpsRuleSet,
    KTrucks.epa: epaRuleSet,
    KTrucks.vsr: vsrRuleSet,
    KTrucks.ccf: ccfRuleSet,
    KTrucks.vss: vssRuleSet,
    KTrucks.vpc: vpcRuleSet,
  };

  /// Get default rule set for a vehicle type
  static VehicleRuleSet? getDefaultRuleSet(String vehicleType) {
    return defaultRuleSets[vehicleType];
  }
}
