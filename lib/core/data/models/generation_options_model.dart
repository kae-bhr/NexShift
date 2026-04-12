import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';

/// Mode de génération des plannings
enum GenerationMode {
  /// Régénère uniquement les plannings dont les règles ont changé
  differential,

  /// Supprime tout et régénère intégralement
  total,
}

/// Options passées au service de génération
class GenerationOptions {
  final DateTime startDate;
  final DateTime endDate;
  final GenerationMode mode;

  /// Générer les plannings issus des règles actives
  final bool generateFromRules;

  /// Générer les plannings issus des exceptions
  final bool generateFromExceptions;

  /// null = toutes les équipes
  final List<String>? teamFilter;

  /// true = logique de chevauchement (3 cas), false = écraser sans conserver
  final bool preserveReplacements;

  const GenerationOptions({
    required this.startDate,
    required this.endDate,
    this.mode = GenerationMode.total,
    this.generateFromRules = true,
    this.generateFromExceptions = true,
    this.teamFilter,
    this.preserveReplacements = true,
  });
}

/// Type d'impact sur un remplacement lors d'une génération
enum SubshiftImpactType {
  /// Le nouveau planning couvre intégralement la période → remplacement conservé intact
  preserved,

  /// Chevauchement partiel → remplacement ajusté sur la période couverte
  partiallyPreserved,

  /// Aucun planning ne couvre la période (ou changement d'équipe) → orphelin
  orphaned,

  /// L'utilisateur a choisi d'écraser → remplacement supprimé
  overwritten,
}

/// Impact sur un seul subshift lors d'une simulation de génération
class SubshiftImpact {
  final Subshift original;
  final SubshiftImpactType type;

  /// Pour [SubshiftImpactType.partiallyPreserved] : le subshift recalculé sur la période d'overlap
  final Subshift? adjusted;

  const SubshiftImpact({
    required this.original,
    required this.type,
    this.adjusted,
  });
}

/// Résultat complet d'une simulation (sans écriture Firestore)
class GenerationImpact {
  final List<Planning> planningsToDelete;
  final List<Planning> planningsToAdd;
  final List<SubshiftImpact> subshiftImpacts;

  const GenerationImpact({
    required this.planningsToDelete,
    required this.planningsToAdd,
    required this.subshiftImpacts,
  });

  int get preservedCount =>
      subshiftImpacts.where((s) => s.type == SubshiftImpactType.preserved).length;

  int get partiallyPreservedCount =>
      subshiftImpacts.where((s) => s.type == SubshiftImpactType.partiallyPreserved).length;

  int get orphanedCount =>
      subshiftImpacts.where((s) => s.type == SubshiftImpactType.orphaned).length;

  int get overwrittenCount =>
      subshiftImpacts.where((s) => s.type == SubshiftImpactType.overwritten).length;

  bool get hasReplacementImpacts => subshiftImpacts.isNotEmpty;
}
