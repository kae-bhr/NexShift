import 'package:releve/core/data/models/user_model.dart';
import 'package:releve/core/data/models/trucks_model.dart';
import 'package:releve/core/services/skill_criticality_service.dart';
import 'package:releve/core/utils/constants.dart';

/// Sous-catégories pour les agents non-notifiés (vague 0)
enum NonNotifiedCategory {
  onDuty,               // En astreinte
  replacing,            // Remplaçant sur la période
  underQualified,       // Sous-qualifié (manque keySkills)
  sickLeave,            // En arrêt maladie
  suspendedFromDuty,    // En suspension d'engagement
}

/// Service pour calculer les vagues de notifications
/// en fonction des compétences et pondérations
class WaveCalculationService {
  final SkillCriticalityService _criticalityService = SkillCriticalityService();
  /// Calcule la vague d'un utilisateur pour une demande de remplacement
  ///
  /// Logique des vagues :
  /// - Vague 0 (jamais notifiés) : Agents en astreinte, agents remplaçants, agents sous-qualifiés
  /// - Vague 1 : Agents de la même équipe (hors astreinte)
  /// - Vague 2 : Agents avec exactement les mêmes compétences
  /// - Vague 3 : Agents avec compétences très proches (80%+)
  /// - Vague 4 : Agents avec compétences relativement proches (60%+)
  /// - Vague 5 : Tous les autres agents
  int calculateWave({
    required User requester,
    required User candidate,
    required String planningTeam,
    required List<String> agentsInPlanning,
    required Map<String, int> skillRarityWeights,
    Map<String, double>? stationSkillWeights, // Pondération configurable par station
  }) {
    // Vague 0 : Agents suspendus ou en arrêt maladie (jamais notifiés)
    if (!candidate.isActiveForReplacement) {
      return 0;
    }

    // Vague 0 : Agents en astreinte (jamais notifiés)
    if (agentsInPlanning.contains(candidate.id)) {
      return 0;
    }

    // Vague 0 : Agents ne possédant pas toutes les keySkills (jamais notifiés, anciennement vague 6)
    // Exception : les agents de la même équipe (vague 1) ne sont pas concernés
    if (candidate.team != planningTeam && requester.keySkills.isNotEmpty) {
      final hasAllKeySkills = requester.keySkills.every(
        (keySkill) => candidate.skills.contains(keySkill),
      );
      if (!hasAllKeySkills) {
        return 0; // Regroupé avec la vague 0 au lieu de 6
      }
    }

    // Vague 1 : Même équipe que l'astreinte (hors astreinte)
    if (candidate.team == planningTeam &&
        !agentsInPlanning.contains(candidate.id)) {
      return 1;
    }

    // Vague 2-5 : Basé sur les compétences
    return _calculateWaveBySkills(
      requester,
      candidate,
      skillRarityWeights,
      stationSkillWeights,
    );
  }

  /// Détermine la sous-catégorie d'un agent non-notifié (vague 0)
  ///
  /// Retourne null si l'agent n'est pas dans la vague 0
  NonNotifiedCategory? getNonNotifiedCategory({
    required User requester,
    required User candidate,
    required String planningTeam,
    required List<String> agentsInPlanning,
  }) {
    // Vérifier si l'agent est suspendu ou en arrêt maladie
    if (!candidate.isActiveForReplacement) {
      return candidate.agentAvailabilityStatus == AgentAvailabilityStatus.sickLeave
          ? NonNotifiedCategory.sickLeave
          : NonNotifiedCategory.suspendedFromDuty;
    }

    // Vérifier si l'agent est en astreinte
    if (agentsInPlanning.contains(candidate.id)) {
      return NonNotifiedCategory.onDuty;
    }

    // Vérifier si l'agent est sous-qualifié (manque keySkills)
    if (candidate.team != planningTeam && requester.keySkills.isNotEmpty) {
      final hasAllKeySkills = requester.keySkills.every(
        (keySkill) => candidate.skills.contains(keySkill),
      );
      if (!hasAllKeySkills) {
        return NonNotifiedCategory.underQualified;
      }
    }

    // L'agent n'est pas dans la vague 0
    return null;
  }

  /// Calcule la vague basée sur les compétences
  int _calculateWaveBySkills(
    User requester,
    User candidate,
    Map<String, int> skillRarityWeights,
    Map<String, double>? stationSkillWeights,
  ) {
    // Calculer le score de similarité pondéré
    final similarity = _calculateSkillSimilarity(
      requester,
      candidate,
      skillRarityWeights,
      stationSkillWeights,
    );

    // Définir les seuils pour chaque vague
    // similarity = 1.0 signifie équivalent (100% des points couverts, y compris si la seule
    // différence concerne des compétences pondérées à 0 qui n'impactent pas le score)
    // similarity = 0.0 signifie complètement différent
    int baseWave;
    if (similarity >= 1.0) {
      return 2; // Vague 2 : Compétences équivalentes (100% de similarité calculée)
    } else if (similarity >= 0.8) {
      baseWave = 3; // Vague 3 : Très similaire (80%+ de match)
    } else if (similarity >= 0.6) {
      baseWave = 4; // Vague 4 : Relativement similaire (60%+ de match)
    } else {
      baseWave = 5; // Vague 5 : Tous les autres
    }

    // Vérifier les compétences-clés : si une manque, descendre d'une vague (max vague 5)
    if (_missingKeySkills(requester, candidate) && baseWave < 5) {
      baseWave++;
    }

    return baseWave;
  }

  /// Vérifie si le candidat manque des compétences-clés du requester
  bool _missingKeySkills(User requester, User candidate) {
    if (requester.keySkills.isEmpty) return false;

    final candidateSkills = Set<String>.from(candidate.skills);
    for (final keySkill in requester.keySkills) {
      if (!candidateSkills.contains(keySkill)) {
        return true; // Au moins une keySkill manque
      }
    }
    return false;
  }

  /// Calcule la similarité entre deux agents via la formule couverture/précision.
  ///
  /// Formule : (couverture + précision) / 2
  ///   - couverture = pts communs / pts du référent  (à quel point le candidat couvre les besoins)
  ///   - précision  = pts communs / pts du candidat  (à quel point les compétences du candidat sont utiles)
  ///
  /// Les poids sont uniformes (1.0) multipliés par le stationMultiplier.
  /// Une compétence avec stationMultiplier = 0 a un poids 0 et n'influence pas le score.
  double _calculateSkillSimilarity(
    User requester,
    User candidate,
    Map<String, int> skillWeights,       // poids uniformes × stationMultiplier × 100
    Map<String, double>? stationSkillWeights,
  ) {
    final requesterSkills = Set<String>.from(requester.skills);
    final candidateSkills = Set<String>.from(candidate.skills);

    if (requesterSkills.isEmpty) return 0.0;

    double totalWeightRequester = 0.0;
    for (final skill in requesterSkills) {
      totalWeightRequester += (skillWeights[skill] ?? 0).toDouble();
    }

    if (totalWeightRequester == 0) {
      return candidateSkills.containsAll(requesterSkills) ? 1.0 : 0.0;
    }

    double totalWeightCandidate = 0.0;
    for (final skill in candidateSkills) {
      totalWeightCandidate += (skillWeights[skill] ?? 0).toDouble();
    }

    double matchedWeight = 0.0;
    for (final skill in requesterSkills) {
      if (candidateSkills.contains(skill)) {
        matchedWeight += (skillWeights[skill] ?? 0).toDouble();
      }
    }

    final coverage = matchedWeight / totalWeightRequester;
    final precision = totalWeightCandidate > 0 ? matchedWeight / totalWeightCandidate : 0.0;
    return ((coverage + precision) / 2).clamp(0.0, 1.0);
  }

  /// Construit les poids uniformes (1.0 × stationMultiplier) pour toutes les compétences
  /// de la station. C'est la référence utilisée pour le calcul de similarité.
  Map<String, int> buildUniformSkillWeights({
    required List<User> allUsers,
    required Map<String, double> stationSkillWeights,
  }) {
    final allSkills = <String>{};
    for (final user in allUsers) {
      allSkills.addAll(user.skills);
    }
    final weights = <String, int>{};
    for (final skill in allSkills) {
      final multiplier = stationSkillWeights[skill] ?? 1.0;
      weights[skill] = (multiplier * 100).round();
    }
    return weights;
  }

  /// Calcule les poids de rareté pour chaque compétence (version contextuelle)
  ///
  /// Cette version utilise le contexte opérationnel (véhicules et équipe) pour
  /// calculer des poids plus précis basés sur la criticité réelle des compétences.
  ///
  /// IMPORTANT: Les compétences non requises pour les véhicules ont un poids de 0
  Future<Map<String, int>> calculateSkillRarityWeightsWithContext({
    required User requester,
    required List<User> teamMembers,
    required List<Truck> stationVehicles,
    String? stationId,
  }) async {
    // Utiliser le nouveau service de criticité avec toutes les compétences
    // (pas seulement celles du requester, pour permettre l'affichage des points
    // de toutes les compétences dans l'UI)
    final criticalityScores = await _criticalityService.calculateSkillCriticality(
      requester: requester,
      teamMembers: teamMembers,
      stationVehicles: stationVehicles,
      stationId: stationId,
      allSkills: true,
    );

    // Convertir les scores en poids entiers (0-100) pour une meilleure granularité
    final weights = <String, int>{};
    for (final entry in criticalityScores.entries) {
      final score = entry.value;
      // Convertir le score combiné (0.0-1.0) en poids (0-100)
      // Les compétences non requises auront score 0.0 donc poids 0
      weights[entry.key] = (score.combinedScore * 100).round();
    }

    return weights;
  }

  /// Calcule les poids de rareté pour chaque compétence (version simple)
  ///
  /// DEPRECATED: Utiliser calculateSkillRarityWeightsWithContext pour de meilleurs résultats
  ///
  /// Cette version est conservée pour compatibilité avec le code existant
  /// qui ne peut pas fournir le contexte des véhicules.
  ///
  /// IMPORTANT: Les compétences de niveau apprentice ont toujours un poids de 0
  Map<String, int> calculateSkillRarityWeights({
    required List<User> teamMembers,
    required List<String> requesterSkills,
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
      // Les compétences de niveau apprentice ont un poids de 0
      final skillLevel = KSkills.skillColors[skill];
      if (skillLevel == SkillLevelColor.apprentice) {
        weights[skill] = 0;
        continue;
      }

      final count = skillCounts[skill] ?? 0;

      // Plus la compétence est rare, plus le poids est élevé
      // Si personne d'autre n'a la compétence : poids = 10
      // Si 1 personne l'a : poids = 5
      // Si 2+ personnes l'ont : poids = 1
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
