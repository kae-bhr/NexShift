import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/generation_options_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/planning_agent_model.dart';
import 'package:nexshift_app/core/data/models/generated_shift_model.dart';
import 'package:nexshift_app/core/data/models/shift_exception_model.dart';
import 'package:nexshift_app/core/data/models/shift_rule_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/repositories/shift_rule_repository.dart';
import 'package:nexshift_app/core/repositories/station_repository.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';
import 'package:nexshift_app/core/services/shift_generator.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Service qui génère les plannings à partir des règles d'astreinte
class PlanningGenerationService {
  final PlanningRepository _planningRepository;
  final ShiftRuleRepository _ruleRepository;
  final UserRepository _userRepository;
  final StationRepository _stationRepository;
  final ShiftGenerator _shiftGenerator;
  final SubshiftRepository _subshiftRepository;

  PlanningGenerationService({
    PlanningRepository? planningRepository,
    ShiftRuleRepository? ruleRepository,
    UserRepository? userRepository,
    StationRepository? stationRepository,
    ShiftGenerator? shiftGenerator,
    SubshiftRepository? subshiftRepository,
  }) : _planningRepository = planningRepository ?? PlanningRepository(),
       _ruleRepository = ruleRepository ?? ShiftRuleRepository(),
       _userRepository = userRepository ?? UserRepository(),
       _stationRepository = stationRepository ?? StationRepository(),
       _shiftGenerator = shiftGenerator ?? ShiftGenerator(),
       _subshiftRepository = subshiftRepository ?? SubshiftRepository();

  /// Simule la génération SANS écrire en Firestore.
  /// Retourne un [GenerationImpact] décrivant tous les changements qui seraient effectués.
  Future<GenerationImpact> simulateGeneration(
    GenerationOptions options, {
    String? station,
    List<ShiftException>? exceptions,
  }) async {
    final stationName = station ?? KConstants.station;

    final oldPlannings = await _planningRepository.getByStationInRange(
      stationName,
      options.startDate,
      options.endDate.add(const Duration(days: 1)),
    );

    // Générer les nouveaux plannings (sans écriture) et récupérer le scope
    final computed = await _computeNewPlannings(
      options: options,
      stationName: stationName,
      exceptions: exceptions ?? [],
    );
    final newPlannings = computed.plannings;

    // Restreindre les anciens plannings au scope : même équipe ET chevauchement temporel
    // avec au moins un nouveau planning. On n'utilise PAS les IDs pour filtrer car
    // un même ID peut correspondre à des timings complètement différents (ex: une
    // exception 04:00→17:00 et une règle 17:00→04:00+1 partagent le même ID
    // teamX_2026_4_6 mais sont disjoints → le planning de règle ne doit pas être touché).
    final newPlanningsByTeam = <String, List<Planning>>{};
    for (final p in newPlannings) {
      newPlanningsByTeam.putIfAbsent(p.team, () => []).add(p);
    }

    final filteredOldPlannings = oldPlannings.where((p) {
      if (options.teamFilter != null && !options.teamFilter!.contains(p.team)) return false;
      // Appartient au scope si un nouveau planning chevauche (strictement) cet ancien planning
      final candidates = newPlanningsByTeam[p.team] ?? [];
      return candidates.any(
        (newP) => newP.startTime.isBefore(p.endTime) && newP.endTime.isAfter(p.startTime),
      );
    }).toList();

    final allSubshifts = await _subshiftRepository.getAll(stationId: stationName);
    final oldPlanningIds = filteredOldPlannings.map((p) => p.id).toSet();
    final affectedSubshifts =
        allSubshifts.where((s) => oldPlanningIds.contains(s.planningId)).toList();

    // Comparaison par timing+équipe (pas par ID) pour le mode différentiel.
    // Un nouveau planning est "inchangé" s'il existe un ancien planning avec exactement
    // les mêmes horaires et la même équipe. Sinon il doit être créé.
    // Un ancien planning doit être supprimé s'il chevauche un nouveau planning
    // mais qu'aucun nouveau planning ne lui correspond exactement.
    final List<Planning> planningsToDelete;
    final List<Planning> planningsToAdd;

    if (options.mode == GenerationMode.differential) {
      // Index des anciens plannings par (équipe, start, end) pour comparaison exacte
      bool hasExactMatch(Planning newP) {
        return filteredOldPlannings.any((oldP) => _isSameTiming(oldP, newP));
      }
      bool isOldCoveredByNew(Planning oldP) {
        return newPlannings.any((newP) => _isSameTiming(oldP, newP));
      }

      planningsToAdd = newPlannings.where((newP) => !hasExactMatch(newP)).toList();
      planningsToDelete = filteredOldPlannings.where((oldP) => !isOldCoveredByNew(oldP)).toList();
    } else {
      planningsToDelete = filteredOldPlannings;
      planningsToAdd = newPlannings;
    }

    // Calculer l'impact sur les subshifts (uniquement sur les plannings réellement affectés)
    final affectedOldIds = planningsToDelete.map((p) => p.id).toSet();
    final affectedSubshiftsFiltered =
        affectedSubshifts.where((s) => affectedOldIds.contains(s.planningId)).toList();

    final subshiftImpacts = _computeSubshiftImpacts(
      subshifts: affectedSubshiftsFiltered,
      newPlannings: planningsToAdd,
      oldPlannings: planningsToDelete,
      preserveReplacements: options.preserveReplacements,
    );

    return GenerationImpact(
      planningsToDelete: planningsToDelete,
      planningsToAdd: planningsToAdd,
      subshiftImpacts: subshiftImpacts,
    );
  }

  /// Exécute la génération en Firestore à partir d'un impact pré-calculé.
  /// Si [precomputedImpact] est null, recalcule via [simulateGeneration].
  Future<GenerationResult> generatePlannings({
    required GenerationOptions options,
    String? station,
    List<ShiftException>? exceptions,
    GenerationImpact? precomputedImpact,
  }) async {
    final stationName = station ?? KConstants.station;

    final impact = precomputedImpact ??
        await simulateGeneration(options, station: station, exceptions: exceptions);

    // Supprimer uniquement les plannings identifiés dans l'impact.
    // En mode total sans filtre d'équipe on peut utiliser deletePlanningsInRange (plus rapide),
    // mais UNIQUEMENT si l'impact couvre réellement toute la plage (mode total).
    // En mode différentiel, on supprime toujours de façon ciblée pour ne toucher
    // que les plannings réellement modifiés.
    final useBulkDelete = options.mode == GenerationMode.total &&
        options.teamFilter == null;

    if (useBulkDelete) {
      await _planningRepository.deletePlanningsInRange(
        options.startDate,
        options.endDate,
        stationId: stationName,
      );
    } else {
      // Suppression ciblée : uniquement les plannings listés dans l'impact
      for (final p in impact.planningsToDelete) {
        await _planningRepository.delete(p.id);
      }
    }

    // Sauvegarder les nouveaux plannings
    if (impact.planningsToAdd.isNotEmpty) {
      if (useBulkDelete) {
        // Après suppression bulk : récupérer ce qui reste hors de la plage + ajouter les nouveaux
        final existingPlannings = await _planningRepository.getByStation(stationName);
        final allPlannings = [...existingPlannings, ...impact.planningsToAdd];
        await _planningRepository.saveAll(allPlannings, stationId: stationName);
      } else {
        // Suppression ciblée : récupérer l'existant, retirer les supprimés, ajouter les nouveaux
        final existingPlannings = await _planningRepository.getByStation(stationName);
        final deletedIds = impact.planningsToDelete.map((p) => p.id).toSet();
        final existingWithoutDeleted =
            existingPlannings.where((p) => !deletedIds.contains(p.id)).toList();
        final allPlannings = [...existingWithoutDeleted, ...impact.planningsToAdd];
        await _planningRepository.saveAll(allPlannings, stationId: stationName);
      }
    }

    // Appliquer les impacts sur les subshifts
    await _applySubshiftImpacts(
      impacts: impact.subshiftImpacts,
      stationName: stationName,
    );

    return GenerationResult(
      success: true,
      message: 'Plannings générés avec succès',
      planningsGenerated: impact.planningsToAdd.length,
      planningsDeleted: impact.planningsToDelete.length,
      startDate: options.startDate,
      endDate: options.endDate,
    );
  }

  // ---------------------------------------------------------------------------
  // Méthodes privées
  // ---------------------------------------------------------------------------

  /// Retourne true si deux plannings ont exactement les mêmes horaires (même équipe,
  /// même début, même fin à la minute près). Utilisé pour le mode différentiel.
  bool _isSameTiming(Planning a, Planning b) {
    return a.team == b.team &&
        a.startTime.year == b.startTime.year &&
        a.startTime.month == b.startTime.month &&
        a.startTime.day == b.startTime.day &&
        a.startTime.hour == b.startTime.hour &&
        a.startTime.minute == b.startTime.minute &&
        a.endTime.year == b.endTime.year &&
        a.endTime.month == b.endTime.month &&
        a.endTime.day == b.endTime.day &&
        a.endTime.hour == b.endTime.hour &&
        a.endTime.minute == b.endTime.minute;
  }

  /// Calcule les nouveaux plannings qui seraient générés selon les options.
  /// Retourne aussi l'ensemble des IDs de plannings "dans le scope" de la génération,
  /// c'est-à-dire les plannings existants qu'il faudra comparer/remplacer.
  Future<({List<Planning> plannings, Set<String> scopeIds})> _computeNewPlannings({
    required GenerationOptions options,
    required String stationName,
    required List<ShiftException> exceptions,
  }) async {
    if (!options.generateFromRules && !options.generateFromExceptions) {
      return (plannings: <Planning>[], scopeIds: <String>{});
    }

    final rules = await _ruleRepository.getActiveRules(stationId: stationName);
    if (rules.isEmpty) return (plannings: <Planning>[], scopeIds: <String>{});

    final allUsers = await _userRepository.getByStation(stationName);

    // Générer TOUJOURS avec règles + exceptions pour avoir les bons plannings complets.
    // On filtrera ensuite selon les options de contenu.
    final allGeneratedShifts = _shiftGenerator.generateShifts(
      rules: rules,
      exceptions: exceptions,
      startDate: options.startDate,
      endDate: options.endDate,
    );

    List<Planning> plannings;
    Set<String> scopeIds;

    if (!options.generateFromRules && options.generateFromExceptions) {
      // "Exceptions seulement" : scope = plannings dont au moins un shift source est une exception.
      // On identifie ces plannings via les shifts générés par exceptions.
      final exceptionOnlyShifts = _shiftGenerator.generateShifts(
        rules: rules,
        exceptions: exceptions,
        startDate: options.startDate,
        endDate: options.endDate,
      ).where((s) => s.isException).toList();

      // Construire les plannings directement depuis les shifts d'exception SEULEMENT.
      // Ne pas utiliser allPlannings ici : il est issu de règles+exceptions fusionnées,
      // ce qui produirait des plannings sur 24h (rule 19:00→06:00 + exception 06:00→19:00
      // sur le même jour = même clé de groupement → même Planning fusionné).
      plannings = await _convertShiftsToPlannings(
        exceptionOnlyShifts,
        stationName,
        rules,
        exceptions,
        allUsers,
      );
      scopeIds = plannings.map((p) => p.id).toSet();
    } else if (options.generateFromRules && !options.generateFromExceptions) {
      // "Règles seulement" : générer sans exceptions, scope = tous les plannings générés
      final ruleOnlyShifts = _shiftGenerator.generateShifts(
        rules: rules,
        exceptions: [],
        startDate: options.startDate,
        endDate: options.endDate,
      );
      plannings = await _convertShiftsToPlannings(
        ruleOnlyShifts,
        stationName,
        rules,
        [],
        allUsers,
      );
      scopeIds = plannings.map((p) => p.id).toSet();
    } else {
      // Les deux : convertir tous les shifts ensemble.
      // Le clustering par intervalles dans _convertShiftsToPlannings gère correctement
      // les cas contigus/chevauchants (fusionnés) et disjoints (plannings séparés).
      plannings = await _convertShiftsToPlannings(
        allGeneratedShifts, stationName, rules, exceptions, allUsers,
      );
      scopeIds = plannings.map((p) => p.id).toSet();
    }

    // Filtrer par équipe si demandé
    if (options.teamFilter != null) {
      plannings = plannings.where((p) => options.teamFilter!.contains(p.team)).toList();
      scopeIds = scopeIds.where((id) {
        return options.teamFilter!.any((team) => id.startsWith('${team}_'));
      }).toSet();
    }

    return (plannings: plannings, scopeIds: scopeIds);
  }

  /// Calcule l'impact de la génération sur les subshifts existants (3 cas).
  List<SubshiftImpact> _computeSubshiftImpacts({
    required List<Subshift> subshifts,
    required List<Planning> newPlannings,
    required List<Planning> oldPlannings,
    required bool preserveReplacements,
  }) {
    if (!preserveReplacements) {
      return subshifts
          .map((s) => SubshiftImpact(original: s, type: SubshiftImpactType.overwritten))
          .toList();
    }

    // Index des nouveaux plannings par équipe pour accès rapide
    final newPlanningsByTeam = <String, List<Planning>>{};
    for (final p in newPlannings) {
      newPlanningsByTeam.putIfAbsent(p.team, () => []).add(p);
    }

    // Index de l'équipe de chaque ancien planning
    final oldTeamById = {for (final p in oldPlannings) p.id: p.team};

    final impacts = <SubshiftImpact>[];

    for (final subshift in subshifts) {
      final teamId = oldTeamById[subshift.planningId];
      if (teamId == null) {
        // Ancien planning inconnu → orphelin
        impacts.add(SubshiftImpact(original: subshift, type: SubshiftImpactType.orphaned));
        continue;
      }

      final candidatePlannings = newPlanningsByTeam[teamId] ?? [];

      // Chercher un planning qui chevauche la période du subshift
      Planning? overlappingPlanning;
      for (final p in candidatePlannings) {
        if (p.startTime.isBefore(subshift.end) && p.endTime.isAfter(subshift.start)) {
          overlappingPlanning = p;
          break;
        }
      }

      if (overlappingPlanning == null) {
        // CAS 1 : aucun chevauchement → orphelin
        impacts.add(SubshiftImpact(original: subshift, type: SubshiftImpactType.orphaned));
      } else {
        final overlapStart = subshift.start.isAfter(overlappingPlanning.startTime)
            ? subshift.start
            : overlappingPlanning.startTime;
        final overlapEnd = subshift.end.isBefore(overlappingPlanning.endTime)
            ? subshift.end
            : overlappingPlanning.endTime;

        final isTotalOverlap =
            overlapStart == subshift.start && overlapEnd == subshift.end;

        if (isTotalOverlap) {
          // CAS 2 : chevauchement total → conservé intact
          impacts.add(SubshiftImpact(original: subshift, type: SubshiftImpactType.preserved));
        } else {
          // CAS 3 : chevauchement partiel → ajuster sur la période d'overlap
          final adjusted = subshift.copyWith(
            start: overlapStart,
            end: overlapEnd,
            planningId: overlappingPlanning.id,
          );
          impacts.add(SubshiftImpact(
            original: subshift,
            type: SubshiftImpactType.partiallyPreserved,
            adjusted: adjusted,
          ));
        }
      }
    }

    return impacts;
  }

  /// Applique les impacts calculés sur les subshifts en Firestore.
  Future<void> _applySubshiftImpacts({
    required List<SubshiftImpact> impacts,
    required String stationName,
  }) async {
    for (final impact in impacts) {
      switch (impact.type) {
        case SubshiftImpactType.preserved:
          // Réappliquer sur le nouveau planning (même période, même équipe)
          final teamId = _extractTeamFromPlanningId(impact.original.planningId);
          if (teamId == null) break;
          final d = impact.original.start;
          final newPlanningId = '${teamId}_${d.year}_${d.month}_${d.day}';
          await ReplacementNotificationService.updatePlanningAgentsForReplacement(
            planningId: newPlanningId,
            stationId: stationName,
            replacedId: impact.original.replacedId,
            replacerId: impact.original.replacerId,
            start: impact.original.start,
            end: impact.original.end,
          );

        case SubshiftImpactType.partiallyPreserved:
          final adjusted = impact.adjusted!;
          // Marquer l'original comme orphelin
          await _subshiftRepository.save(
            impact.original.copyWith(isOrphaned: true),
            stationId: stationName,
          );
          // Réappliquer le subshift ajusté sur le nouveau planning
          await ReplacementNotificationService.updatePlanningAgentsForReplacement(
            planningId: adjusted.planningId,
            stationId: stationName,
            replacedId: adjusted.replacedId,
            replacerId: adjusted.replacerId,
            start: adjusted.start,
            end: adjusted.end,
          );

        case SubshiftImpactType.orphaned:
          // Marquer comme orphelin sans réappliquer
          await _subshiftRepository.save(
            impact.original.copyWith(isOrphaned: true),
            stationId: stationName,
          );

        case SubshiftImpactType.overwritten:
          // L'utilisateur a choisi d'écraser → ne pas réappliquer, ne pas marquer
          debugPrint('Subshift ${impact.original.id} écrasé (choix utilisateur)');
      }
    }
  }

  /// Extrait le teamId depuis un planningId déterministe de format ${teamId}_${year}_${month}_${day}
  String? _extractTeamFromPlanningId(String planningId) {
    // Format : teamId_year_month_day — teamId peut contenir des underscores
    // On retire les 3 derniers segments (year, month, day)
    final parts = planningId.split('_');
    if (parts.length < 4) return null;
    return parts.sublist(0, parts.length - 3).join('_');
  }

  /// Convertit une liste de GeneratedShift en Planning
  Future<List<Planning>> _convertShiftsToPlannings(
    List<GeneratedShift> shifts,
    String station,
    List<ShiftRule> rules,
    List<ShiftException> exceptions,
    List<dynamic> allUsers,
  ) async {
    final stationConfig = await _stationRepository.getById(station);
    final stationMaxAgents = stationConfig?.maxAgentsPerShift ?? 6;

    // Grouper les shifts par équipe
    final Map<String, List<GeneratedShift>> shiftsByTeam = {};
    for (final shift in shifts) {
      if (shift.teamId == null || shift.teamId!.isEmpty) continue;
      shiftsByTeam.putIfAbsent(shift.teamId!, () => []).add(shift);
    }

    final plannings = <Planning>[];

    for (final entry in shiftsByTeam.entries) {
      final teamId = entry.key;
      // Trier les shifts par date de début
      final teamShifts = List<GeneratedShift>.from(entry.value)
        ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));

      // Clustering par intervalles contigus ou chevauchants :
      // deux shifts de la même équipe sont dans le même Planning si leurs intervalles
      // se touchent (adjacents) ou se chevauchent.
      // Ex: [01/01→02/01] + [02/01→03/01] → même cluster (contigus)
      //     [04:00→17:00] + [17:00→04:00+1] → même cluster (adjacents)
      //     [01/01→03/01] + [02/01→04/01] → même cluster (chevauchants)
      //
      // Critère : shift.start <= clusterEnd (contigu ou chevauchant)
      final List<List<GeneratedShift>> clusters = [];
      List<GeneratedShift>? currentCluster;
      DateTime? currentClusterEnd;

      for (final shift in teamShifts) {
        if (currentCluster == null || shift.startDateTime.isAfter(currentClusterEnd!)) {
          // Nouveau cluster
          currentCluster = [shift];
          currentClusterEnd = shift.endDateTime;
          clusters.add(currentCluster);
        } else {
          // Étendre le cluster existant
          currentCluster.add(shift);
          if (shift.endDateTime.isAfter(currentClusterEnd)) {
            currentClusterEnd = shift.endDateTime;
          }
        }
      }

      for (final cluster in clusters) {
        DateTime startTime = cluster.first.startDateTime;
        DateTime endTime = cluster.first.endDateTime;
        bool hasException = false;

        for (final shift in cluster) {
          if (shift.startDateTime.isBefore(startTime)) startTime = shift.startDateTime;
          if (shift.endDateTime.isAfter(endTime)) endTime = shift.endDateTime;
          if (shift.isException) hasException = true;
        }

        int maxAgents = stationMaxAgents;
        if (hasException) {
          final matchingException = exceptions.firstWhere(
            (ex) =>
                ex.teamId == teamId &&
                ex.startDateTime.isBefore(endTime) &&
                ex.endDateTime.isAfter(startTime),
            orElse: () => ShiftException(
              id: '',
              startDateTime: DateTime.now(),
              endDateTime: DateTime.now(),
              reason: '',
              maxAgents: stationMaxAgents,
            ),
          );
          maxAgents = matchingException.maxAgents;
        }

        final teamAgents = allUsers
            .where((user) => user.team == teamId)
            .map((user) => user.id as String)
            .toList();

        plannings.add(Planning(
          id: '${teamId}_${startTime.year}_${startTime.month}_${startTime.day}',
          startTime: startTime,
          endTime: endTime,
          station: station,
          team: teamId,
          agents: teamAgents
              .map((id) => PlanningAgent(
                    agentId: id,
                    start: startTime,
                    end: endTime,
                    levelId: '',
                  ))
              .toList(),
          maxAgents: maxAgents,
          isException: hasException,
        ));
      }
    }

    return plannings;
  }
}

/// Résultat de la génération de plannings
class GenerationResult {
  final bool success;
  final String message;
  final int planningsGenerated;
  final int planningsDeleted;
  final DateTime? startDate;
  final DateTime? endDate;

  GenerationResult({
    required this.success,
    required this.message,
    required this.planningsGenerated,
    required this.planningsDeleted,
    this.startDate,
    this.endDate,
  });
}
