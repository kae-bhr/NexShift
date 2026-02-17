import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/planning_agent_model.dart';
import 'package:nexshift_app/core/data/models/generated_shift_model.dart';
import 'package:nexshift_app/core/data/models/shift_exception_model.dart';
import 'package:nexshift_app/core/data/models/shift_rule_model.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:nexshift_app/core/repositories/shift_rule_repository.dart';
import 'package:nexshift_app/core/repositories/station_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/services/shift_generator.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Service qui génère les plannings à partir des règles d'astreinte
class PlanningGenerationService {
  final PlanningRepository _planningRepository;
  final ShiftRuleRepository _ruleRepository;
  final UserRepository _userRepository;
  final StationRepository _stationRepository;
  final ShiftGenerator _shiftGenerator;

  PlanningGenerationService({
    PlanningRepository? planningRepository,
    ShiftRuleRepository? ruleRepository,
    UserRepository? userRepository,
    StationRepository? stationRepository,
    ShiftGenerator? shiftGenerator,
  }) : _planningRepository = planningRepository ?? PlanningRepository(),
       _ruleRepository = ruleRepository ?? ShiftRuleRepository(),
       _userRepository = userRepository ?? UserRepository(),
       _stationRepository = stationRepository ?? StationRepository(),
       _shiftGenerator = shiftGenerator ?? ShiftGenerator();

  /// Génère les plannings à partir des règles actives
  /// Supprime tous les plannings dans la plage de dates et les remplace par les plannings générés
  /// [fromDate] : date de début de génération (par défaut : maintenant)
  /// [duration] : durée de génération (par défaut : 1 an)
  /// [station] : station pour laquelle générer les plannings (par défaut : station par défaut)
  Future<GenerationResult> generatePlannings({
    DateTime? fromDate,
    Duration duration = const Duration(days: 365),
    String? station,
    List<ShiftException>? exceptions,
  }) async {
    final startDate = fromDate ?? DateTime.now();
    final endDate = startDate.add(duration);
    final stationName = station ?? KConstants.station;

    // Compter les plannings qui vont être supprimés
    final oldPlannings = await _planningRepository.getByStationInRange(
      stationName,
      startDate,
      endDate.add(const Duration(days: 1)),
    );
    final deletedCount = oldPlannings.length;

    // Supprimer les plannings dans la plage de dates AVANT de générer les nouveaux
    await _planningRepository.deletePlanningsInRange(startDate, endDate, stationId: stationName);

    // Récupérer les règles actives
    final rules = await _ruleRepository.getActiveRules(stationId: stationName);

    if (rules.isEmpty) {
      // Même sans règles, on permet la suppression des plannings existants
      return GenerationResult(
        success: true,
        message: 'Plannings supprimés dans la période (aucune règle active)',
        planningsGenerated: 0,
        planningsDeleted: deletedCount,
        startDate: startDate,
        endDate: endDate,
      );
    }

    // Générer les shifts à partir des règles
    final generatedShifts = _shiftGenerator.generateShifts(
      rules: rules,
      exceptions: exceptions ?? [],
      startDate: startDate,
      endDate: endDate,
    );

    // Récupérer tous les utilisateurs pour l'assignation automatique
    final allUsers = await _userRepository.getByStation(stationName);

    // Convertir les GeneratedShift en Planning
    final newPlannings = await _convertShiftsToPlannings(
      generatedShifts,
      stationName,
      rules,
      exceptions ?? [],
      allUsers,
    );

    // Sauvegarder les nouveaux plannings (les anciens dans la plage ont déjà été supprimés)
    if (newPlannings.isNotEmpty) {
      final existingPlannings = await _planningRepository.getByStation(stationName);
      final allPlannings = [...existingPlannings, ...newPlannings];
      await _planningRepository.saveAll(allPlannings, stationId: stationName);
    }

    return GenerationResult(
      success: true,
      message: 'Plannings générés avec succès',
      planningsGenerated: newPlannings.length,
      planningsDeleted: deletedCount,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Convertit une liste de GeneratedShift en Planning
  Future<List<Planning>> _convertShiftsToPlannings(
    List<GeneratedShift> shifts,
    String station,
    List<ShiftRule> rules,
    List<ShiftException> exceptions,
    List<dynamic> allUsers,
  ) async {
    // Charger la configuration de la station pour récupérer maxAgentsPerShift
    final stationConfig = await _stationRepository.getById(station);
    final stationMaxAgents = stationConfig?.maxAgentsPerShift ?? 6;
    // Regrouper les shifts par date et équipe
    final Map<String, List<GeneratedShift>> shiftsByDateAndTeam = {};

    for (final shift in shifts) {
      // Ignorer les shifts non assignés (sans équipe)
      if (shift.teamId == null || shift.teamId!.isEmpty) {
        continue;
      }

      final date = shift.startDateTime;
      final key = '${date.year}-${date.month}-${date.day}_${shift.teamId}';
      shiftsByDateAndTeam.putIfAbsent(key, () => []);
      shiftsByDateAndTeam[key]!.add(shift);
    }

    // Créer un Planning pour chaque groupe
    final plannings = <Planning>[];

    for (final entry in shiftsByDateAndTeam.entries) {
      final shifts = entry.value;
      if (shifts.isEmpty) continue;

      final firstShift = shifts.first;
      final teamId = firstShift.teamId!;

      // Calculer les heures de début et fin
      // On prend la première heure de début et la dernière heure de fin
      DateTime startTime = firstShift.startDateTime;
      DateTime endTime = firstShift.endDateTime;

      // Ajuster pour tous les shifts du groupe
      for (final shift in shifts) {
        if (shift.startDateTime.isBefore(startTime)) {
          startTime = shift.startDateTime;
        }
        if (shift.endDateTime.isAfter(endTime)) {
          endTime = shift.endDateTime;
        }
      }

      // Déterminer le maxAgents : vérifier si ça vient d'une exception
      int maxAgents = stationMaxAgents; // Utiliser la config de la station

      if (firstShift.isException) {
        // Chercher l'exception correspondante
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
      } else {
        // Toujours utiliser la config de la station comme référence
        maxAgents = stationMaxAgents;
      }

      // Récupérer tous les agents de cette équipe
      final teamAgents = allUsers
          .where((user) => user.team == teamId)
          .map((user) => user.id as String)
          .toList();

      // Créer le planning avec les agents de l'équipe
      final planning = Planning(
        id: '${teamId}_${startTime.year}_${startTime.month}_${startTime.day}',
        startTime: startTime,
        endTime: endTime,
        station: station,
        team: teamId,
        agents: teamAgents.map((id) => PlanningAgent(
          agentId: id,
          start: startTime,
          end: endTime,
          levelId: '',
        )).toList(),
        maxAgents: maxAgents,
      );

      plannings.add(planning);
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
