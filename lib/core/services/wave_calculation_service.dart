import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Service pour calculer les vagues de notifications
/// en fonction des compétences et pondérations
class WaveCalculationService {
  /// Calcule la vague d'un utilisateur pour une demande de remplacement
  ///
  /// Logique des vagues :
  /// - Vague 0 (jamais notifiés) : Agents présents sur l'astreinte
  /// - Vague 1 : Agents de la même équipe (hors astreinte)
  /// - Vague 2 : Agents avec exactement les mêmes compétences
  /// - Vague 3 : Agents avec compétences très proches
  /// - Vague 4 : Agents avec compétences relativement proches
  /// - Vague 5 : Tous les autres agents
  int calculateWave({
    required User requester,
    required User candidate,
    required String planningTeam,
    required List<String> agentsInPlanning,
    required Map<String, int> skillRarityWeights,
  }) {
    // Vague 0 : Agents en astreinte (jamais notifiés)
    if (agentsInPlanning.contains(candidate.id)) {
      return 0;
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
    );
  }

  /// Calcule la vague basée sur les compétences
  int _calculateWaveBySkills(
    User requester,
    User candidate,
    Map<String, int> skillRarityWeights,
  ) {
    // Vérifier si les compétences sont exactement les mêmes
    if (_hasExactSameSkills(requester, candidate)) {
      return 2; // Vague 2 : Compétences identiques
    }

    // Calculer le score de similarité pondéré
    final similarity = _calculateSkillSimilarity(
      requester,
      candidate,
      skillRarityWeights,
    );

    // Définir les seuils pour chaque vague
    // similarity = 1.0 signifie identique
    // similarity = 0.0 signifie complètement différent
    if (similarity >= 0.8) {
      return 3; // Vague 3 : Très similaire (80%+ de match)
    } else if (similarity >= 0.6) {
      return 4; // Vague 4 : Relativement similaire (60%+ de match)
    } else {
      return 5; // Vague 5 : Tous les autres
    }
  }

  /// Vérifie si deux utilisateurs ont exactement les mêmes compétences
  bool _hasExactSameSkills(User user1, User user2) {
    final skills1 = Set<String>.from(user1.skills);
    final skills2 = Set<String>.from(user2.skills);

    return skills1.length == skills2.length &&
        skills1.containsAll(skills2);
  }

  /// Calcule la similarité pondérée entre deux ensembles de compétences
  ///
  /// Retourne un score entre 0.0 et 1.0
  /// - 1.0 = compétences identiques
  /// - 0.0 = aucune compétence en commun
  double _calculateSkillSimilarity(
    User requester,
    User candidate,
    Map<String, int> skillRarityWeights,
  ) {
    final requesterSkills = Set<String>.from(requester.skills);
    final candidateSkills = Set<String>.from(candidate.skills);

    if (requesterSkills.isEmpty) return 0.0;

    // Calculer le poids total des compétences du demandeur
    double totalRequiredWeight = 0.0;
    for (final skill in requesterSkills) {
      totalRequiredWeight += (skillRarityWeights[skill] ?? 1).toDouble();
    }

    // Calculer le poids des compétences en commun
    double matchedWeight = 0.0;
    for (final skill in requesterSkills) {
      if (candidateSkills.contains(skill)) {
        matchedWeight += (skillRarityWeights[skill] ?? 1).toDouble();
      }
    }

    // Pénaliser si le candidat a beaucoup de compétences supplémentaires
    final extraSkills = candidateSkills.difference(requesterSkills).length;
    final penalty = extraSkills > 2 ? 0.1 * extraSkills : 0.0;

    final similarity = matchedWeight / totalRequiredWeight;
    return (similarity - penalty).clamp(0.0, 1.0);
  }

  /// Calcule les poids de rareté pour chaque compétence
  ///
  /// Plus une compétence est rare dans l'équipe, plus son poids est élevé
  /// Cela permet de prioriser les remplaçants qui ont les compétences rares
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
