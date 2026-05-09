import 'package:releve/core/data/models/trucks_model.dart';
import 'package:releve/core/utils/constants.dart';
import 'package:releve/core/utils/default_vehicle_rules.dart';

/// Script de debug pour vérifier la collection des compétences
void main() async {
  print('🔍 Testing skill collection for VSAV and FPT');

  // Simuler un VSAV et un FPT
  // Note: We don't actually use these trucks, just the rules

  // Récupérer les règles par défaut
  final vsavRules = KDefaultVehicleRules.getDefaultRuleSet(KTrucks.vsav);
  final fptRules = KDefaultVehicleRules.getDefaultRuleSet(KTrucks.fpt);

  print('\n📋 VSAV Rules:');
  if (vsavRules != null) {
    for (final mode in vsavRules.modes) {
      print('  Mode: ${mode.id} (${mode.label})');
      for (final position in mode.positions) {
        print('    Position ${position.id}: ${position.requiredSkills}');
      }
      if (mode.restrictedVariant != null) {
        print('  Restricted variant: ${mode.restrictedVariant!.id}');
        for (final position in mode.restrictedVariant!.positions) {
          print('    Position ${position.id}: ${position.requiredSkills}');
        }
      }
    }
  }

  print('\n📋 FPT Rules:');
  if (fptRules != null) {
    for (final mode in fptRules.modes) {
      print('  Mode: ${mode.id} (${mode.label})');
      for (final position in mode.positions) {
        print('    Position ${position.id}: ${position.requiredSkills}');
      }
      if (mode.restrictedVariant != null) {
        print('  Restricted variant: ${mode.restrictedVariant!.id}');
        for (final position in mode.restrictedVariant!.positions) {
          print('    Position ${position.id}: ${position.requiredSkills}');
        }
      }
    }
  }

  // Collecter manuellement les compétences requises
  final requiredSkills = <String>{};

  for (final ruleSet in [vsavRules, fptRules]) {
    if (ruleSet == null) continue;

    for (final mode in ruleSet.modes) {
      for (final position in mode.positions) {
        requiredSkills.addAll(position.requiredSkills);
        if (position.fallbackSkills != null) {
          requiredSkills.addAll(position.fallbackSkills!);
        }
      }

      for (final position in mode.optionalPositions) {
        requiredSkills.addAll(position.requiredSkills);
        if (position.fallbackSkills != null) {
          requiredSkills.addAll(position.fallbackSkills!);
        }
      }

      if (mode.restrictedVariant != null) {
        for (final position in mode.restrictedVariant!.positions) {
          requiredSkills.addAll(position.requiredSkills);
          if (position.fallbackSkills != null) {
            requiredSkills.addAll(position.fallbackSkills!);
          }
        }
      }
    }
  }

  print('\n✅ All required skills collected:');
  final sortedSkills = requiredSkills.toList()..sort();
  for (final skill in sortedSkills) {
    print('  - $skill');
  }

  print('\n🔍 Checking critical skills:');
  final criticalSkills = [
    KSkills.suapCA,
    KSkills.incCA,
    KSkills.vpsCA,
    KSkills.ppbeCA,
    KSkills.cod1,
  ];

  for (final skill in criticalSkills) {
    final isPresent = requiredSkills.contains(skill);
    print('  ${isPresent ? "✅" : "❌"} $skill: ${isPresent ? "PRESENT" : "MISSING"}');
  }
}
