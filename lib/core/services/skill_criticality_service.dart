import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/trucks_model.dart';
import 'package:nexshift_app/core/repositories/vehicle_rules_repository.dart';
import 'package:nexshift_app/features/replacement/services/crew_allocator.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Résultat du calcul de criticité pour une compétence
class SkillCriticalityScore {
  final String skill;
  final double level1Score; // Score basé sur criticité et rareté (0.0 à 1.0)
  final double level2Score; // Score basé sur simulation d'allocation (0.0 à 1.0)
  final double combinedScore; // Score combiné pondéré
  final bool isRequiredForVehicles; // Compétence requise pour au moins un véhicule
  final int agentsWithSkill; // Nombre d'agents ayant cette compétence

  SkillCriticalityScore({
    required this.skill,
    required this.level1Score,
    required this.level2Score,
    required this.combinedScore,
    required this.isRequiredForVehicles,
    required this.agentsWithSkill,
  });
}

/// Résultat de la simulation d'allocation
class AllocationSimulationResult {
  final int greenVehicles; // Nombre de véhicules en équipage complet
  final int orangeVehicles; // Nombre de véhicules en mode restreint
  final int redVehicles; // Nombre de véhicules incomplets
  final int greyVehicles; // Nombre de véhicules non gérés

  AllocationSimulationResult({
    required this.greenVehicles,
    required this.orangeVehicles,
    required this.redVehicles,
    required this.greyVehicles,
  });

  /// Score opérationnel total (green=3, orange=2, red=1, grey=0)
  int get operationalScore =>
      greenVehicles * 3 + orangeVehicles * 2 + redVehicles * 1;

  /// Nombre total de véhicules opérationnels (green + orange)
  int get operationalVehicles => greenVehicles + orangeVehicles;
}

/// Service pour calculer la criticité contextuelle des compétences
/// Implémente deux niveaux d'analyse :
/// - Niveau 1 : Scoring de criticité basé sur les véhicules et la rareté
/// - Niveau 2 : Simulation d'allocation pour mesurer l'impact opérationnel
class SkillCriticalityService {
  final VehicleRulesRepository _rulesRepo;

  /// Constructeur par défaut (production)
  SkillCriticalityService() : _rulesRepo = VehicleRulesRepository();

  /// Constructeur pour les tests
  SkillCriticalityService.forTest(VehicleRulesRepository rulesRepo)
      : _rulesRepo = rulesRepo;

  /// Calcule les scores de criticité pour toutes les compétences requises
  /// ou pour un agent spécifique selon le paramètre allSkills
  ///
  /// Si allSkills = true, calcule pour toutes les compétences requises par les véhicules
  /// Si allSkills = false, calcule uniquement pour les compétences du requester
  Future<Map<String, SkillCriticalityScore>> calculateSkillCriticality({
    required User requester,
    required List<User> teamMembers,
    required List<Truck> stationVehicles,
    String? stationId,
    bool allSkills = false,
  }) async {
    final scores = <String, SkillCriticalityScore>{};

    // Collecter toutes les compétences requises par les véhicules
    final requiredSkills = await _collectRequiredSkills(stationVehicles, stationId);

    // Compter combien d'agents ont chaque compétence
    final skillCounts = <String, int>{};
    for (final member in teamMembers) {
      for (final skill in member.skills) {
        skillCounts[skill] = (skillCounts[skill] ?? 0) + 1;
      }
    }

    // Déterminer les compétences à scorer
    final skillsToScore = allSkills ? requiredSkills : requester.skills.toSet();

    // Calculer le score pour chaque compétence
    for (final skill in skillsToScore) {
      // CONTRAINTE CRITIQUE : Si la compétence n'est requise pour aucun véhicule,
      // le score DOIT être 0 peu importe la rareté
      if (!requiredSkills.contains(skill)) {
        scores[skill] = SkillCriticalityScore(
          skill: skill,
          level1Score: 0.0,
          level2Score: 0.0,
          combinedScore: 0.0,
          isRequiredForVehicles: false,
          agentsWithSkill: skillCounts[skill] ?? 0,
        );
        continue;
      }

      // Niveau 1 : Calcul basé sur criticité et rareté
      final level1Score = _calculateLevel1Score(
        skill: skill,
        requiredSkills: requiredSkills,
        skillCounts: skillCounts,
        teamSize: teamMembers.length,
      );

      // Niveau 2 : Simulation d'allocation
      final level2Score = await _calculateLevel2Score(
        skill: skill,
        requester: requester,
        teamMembers: teamMembers,
        stationVehicles: stationVehicles,
        stationId: stationId,
      );

      // Score combiné (pondération 40% Level 1, 60% Level 2)
      final combinedScore = level1Score * 0.4 + level2Score * 0.6;

      scores[skill] = SkillCriticalityScore(
        skill: skill,
        level1Score: level1Score,
        level2Score: level2Score,
        combinedScore: combinedScore,
        isRequiredForVehicles: true,
        agentsWithSkill: skillCounts[skill] ?? 0,
      );
    }

    return scores;
  }

  /// Niveau 1 : Score basé sur la criticité et la rareté de la compétence
  /// Retourne un score entre 0.0 et 1.0
  double _calculateLevel1Score({
    required String skill,
    required Set<String> requiredSkills,
    required Map<String, int> skillCounts,
    required int teamSize,
  }) {
    // Si pas dans les compétences requises, score = 0
    if (!requiredSkills.contains(skill)) {
      return 0.0;
    }

    // Les compétences de niveau apprentice ont toujours un score bas
    final skillLevel = KSkills.skillColors[skill];
    if (skillLevel == SkillLevelColor.apprentice) {
      return 0.0;
    }

    final agentCount = skillCounts[skill] ?? 0;

    // Calcul de la rareté (inversement proportionnel au nombre d'agents)
    // Si 1 seul agent : très rare (score élevé)
    // Si beaucoup d'agents : commun (score bas)
    double rarityScore;
    if (agentCount <= 1) {
      rarityScore = 1.0; // Très rare : seul ou unique
    } else if (agentCount == 2) {
      rarityScore = 0.8; // Rare
    } else if (agentCount == 3) {
      rarityScore = 0.6; // Peu commun
    } else if (agentCount <= teamSize ~/ 2) {
      rarityScore = 0.4; // Moyennement commun
    } else {
      rarityScore = 0.2; // Très commun
    }

    return rarityScore;
  }

  /// Niveau 2 : Score basé sur simulation d'allocation
  /// Compare la capacité opérationnelle avec et sans le demandeur
  /// Retourne un score entre 0.0 et 1.0
  Future<double> _calculateLevel2Score({
    required String skill,
    required User requester,
    required List<User> teamMembers,
    required List<Truck> stationVehicles,
    String? stationId,
  }) async {
    // Simuler l'allocation AVEC le demandeur
    final withRequester = await _simulateAllocation(
      agents: teamMembers,
      vehicles: stationVehicles,
      stationId: stationId,
    );

    // Simuler l'allocation SANS le demandeur
    final withoutRequester = await _simulateAllocation(
      agents: teamMembers.where((u) => u.id != requester.id).toList(),
      vehicles: stationVehicles,
      stationId: stationId,
    );

    // Calculer l'impact de la perte du demandeur
    final scoreDiff = withRequester.operationalScore - withoutRequester.operationalScore;
    final maxPossibleScore = stationVehicles.length * 3; // Si tous green

    // Normaliser le score entre 0.0 et 1.0
    if (maxPossibleScore == 0) return 0.0;

    // Plus l'impact est grand, plus le score est élevé
    final normalizedScore = (scoreDiff / maxPossibleScore).clamp(0.0, 1.0);

    return normalizedScore;
  }

  /// Simule l'allocation des équipages et retourne le résultat
  Future<AllocationSimulationResult> _simulateAllocation({
    required List<User> agents,
    required List<Truck> vehicles,
    String? stationId,
  }) async {
    final results = await CrewAllocator.allocateAllVehicles(
      effectiveAgents: agents,
      trucks: vehicles,
      stationId: stationId,
    );

    int greenCount = 0;
    int orangeCount = 0;
    int redCount = 0;
    int greyCount = 0;

    for (final result in results.values) {
      switch (result.status) {
        case VehicleStatus.green:
          greenCount++;
          break;
        case VehicleStatus.orange:
          orangeCount++;
          break;
        case VehicleStatus.red:
          redCount++;
          break;
        case VehicleStatus.grey:
          greyCount++;
          break;
      }
    }

    return AllocationSimulationResult(
      greenVehicles: greenCount,
      orangeVehicles: orangeCount,
      redVehicles: redCount,
      greyVehicles: greyCount,
    );
  }

  /// Collecte toutes les compétences requises par les véhicules de la station
  Future<Set<String>> _collectRequiredSkills(
    List<Truck> vehicles,
    String? stationId,
  ) async {
    final requiredSkills = <String>{};

    for (final vehicle in vehicles) {
      final ruleSet = await _rulesRepo.getRules(
        vehicleType: vehicle.type,
        stationId: stationId,
      );

      if (ruleSet == null) continue;

      // Pour chaque mode du véhicule
      for (final mode in ruleSet.modes) {
        // Collecter les compétences requises et fallback
        for (final position in mode.positions) {
          requiredSkills.addAll(position.requiredSkills);
          if (position.fallbackSkills != null) {
            requiredSkills.addAll(position.fallbackSkills!);
          }
        }

        // Inclure aussi les positions optionnelles
        for (final position in mode.optionalPositions) {
          requiredSkills.addAll(position.requiredSkills);
          if (position.fallbackSkills != null) {
            requiredSkills.addAll(position.fallbackSkills!);
          }
        }

        // Inclure le mode restreint si disponible
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

    return requiredSkills;
  }

  /// Calcule les poids de rareté pour chaque compétence (version simplifiée pour compatibilité)
  /// DEPRECATED : Utiliser calculateSkillCriticality à la place
  /// Cette méthode est conservée pour compatibilité avec le code existant
  Map<String, int> calculateSkillRarityWeights({
    required List<User> teamMembers,
    required List<String> requesterSkills,
    Set<String>? requiredSkills,
  }) {
    final skillCounts = <String, int>{};

    // Compter combien d'agents ont chaque compétence
    for (final member in teamMembers) {
      for (final skill in member.skills) {
        skillCounts[skill] = (skillCounts[skill] ?? 0) + 1;
      }
    }

    // Calculer le poids de rareté pour chaque compétence du demandeur
    final weights = <String, int>{};
    for (final skill in requesterSkills) {
      // CONTRAINTE CRITIQUE : Si requiredSkills fourni et skill pas dedans, poids = 0
      if (requiredSkills != null && !requiredSkills.contains(skill)) {
        weights[skill] = 0;
        continue;
      }

      // Les compétences de niveau apprentice ont un poids de 0
      final skillLevel = KSkills.skillColors[skill];
      if (skillLevel == SkillLevelColor.apprentice) {
        weights[skill] = 0;
        continue;
      }

      final count = skillCounts[skill] ?? 0;

      // Plus la compétence est rare, plus le poids est élevé
      if (count <= 1) {
        weights[skill] = 10; // Très rare
      } else if (count == 2) {
        weights[skill] = 5; // Rare
      } else if (count == 3) {
        weights[skill] = 3; // Peu commun
      } else {
        weights[skill] = 1; // Commun
      }
    }

    return weights;
  }
}
