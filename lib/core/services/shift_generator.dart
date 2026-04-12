import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/generated_shift_model.dart';
import 'package:nexshift_app/core/data/models/shift_exception_model.dart';
import 'package:nexshift_app/core/data/models/shift_rule_model.dart';
import 'package:uuid/uuid.dart';

class ShiftGenerator {
  final _uuid = const Uuid();

  // Duration.zero ou Duration(hours: -2) selon si les DateTime sont générés en UTC ou en heure locale (Heure d'été française).
  static const _legacyUtcOffset = Duration.zero;

  /// Génère les astreintes pour une période donnée
  List<GeneratedShift> generateShifts({
    required List<ShiftRule> rules,
    required List<ShiftException> exceptions,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final shifts = <GeneratedShift>[];

    // Normaliser les dates (début de journée)
    final start = DateTime.utc(startDate.year, startDate.month, startDate.day);
    final end = DateTime.utc(endDate.year, endDate.month, endDate.day);

    // Trier les règles par priorité
    final sortedRules = List<ShiftRule>.from(rules)
      ..sort((a, b) => a.priority.compareTo(b.priority));

    // Pour chaque jour de la période
    DateTime currentDate = start;
    while (currentDate.isBefore(end) || currentDate.isAtSameMomentAs(end)) {
      // Pour chaque règle active
      for (final rule in sortedRules.where((r) => r.isActive)) {
        // Vérifier si la règle s'applique à ce jour
        if (_isRuleApplicable(rule, currentDate)) {
          // Générer l'astreinte pour ce jour
          final shift = _generateShiftForDay(rule: rule, date: currentDate);
          if (shift != null) {
            shifts.add(shift);
          }
        }
      }
      currentDate = currentDate.add(const Duration(days: 1));
    }

    // Fusionner les astreintes consécutives de la même équipe
    var mergedShifts = _mergeConsecutiveShifts(shifts);

    // Appliquer les exceptions (découpage temporel)
    mergedShifts = _applyExceptions(mergedShifts, exceptions);

    debugPrint('=== ShiftGenerator output (${mergedShifts.length} shifts) ===');
    for (final s in mergedShifts) {
      debugPrint(
        '  [${s.isException ? "EXC" : "RUL"}] ${s.teamId} ${s.startDateTime.toIso8601String()} → ${s.endDateTime.toIso8601String()}',
      );
    }

    // Fusionner à nouveau pour consolider les segments d'exception consécutifs
    mergedShifts = _mergeConsecutiveShifts(mergedShifts);

    return mergedShifts;
  }

  /// Fusionne les astreintes consécutives de la même équipe
  List<GeneratedShift> _mergeConsecutiveShifts(List<GeneratedShift> shifts) {
    if (shifts.isEmpty) return shifts;

    // Trier par date de début
    final sortedShifts = List<GeneratedShift>.from(shifts)
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));

    final mergedShifts = <GeneratedShift>[];
    GeneratedShift? currentShift;

    for (final shift in sortedShifts) {
      if (currentShift == null) {
        currentShift = shift;
        continue;
      }

      // Vérifier si les astreintes sont consécutives et de la même équipe
      final sameTeam =
          currentShift.teamId == shift.teamId && currentShift.teamId != null;
      final consecutive = currentShift.endDateTime.isAtSameMomentAs(
        shift.startDateTime,
      );

      if (sameTeam && consecutive) {
        // Fusionner : étendre la fin de l'astreinte courante
        // Combiner les noms de règles uniquement si différents
        String combinedName = currentShift.ruleName;
        if (currentShift.ruleName != shift.ruleName) {
          combinedName = '${currentShift.ruleName} + ${shift.ruleName}';
        }

        currentShift = GeneratedShift(
          id: currentShift.id, // Garder l'ID de la première
          startDateTime: currentShift.startDateTime,
          endDateTime: shift.endDateTime, // Nouvelle fin
          teamId: currentShift.teamId,
          ruleId: currentShift.ruleId,
          ruleName: combinedName,
          isException: currentShift.isException || shift.isException,
          exceptionReason:
              currentShift.exceptionReason ?? shift.exceptionReason,
        );
      } else {
        // Pas de fusion : ajouter l'astreinte actuelle et passer à la suivante
        mergedShifts.add(currentShift);
        currentShift = shift;
      }
    }

    // Ajouter la dernière astreinte
    if (currentShift != null) {
      mergedShifts.add(currentShift);
    }

    return mergedShifts;
  }

  /// Vérifie si une règle s'applique à une date donnée
  bool _isRuleApplicable(ShiftRule rule, DateTime date) {
    // Vérifier si la date est après le début de la règle
    final ruleStart = DateTime.utc(
      rule.startDate.year,
      rule.startDate.month,
      rule.startDate.day,
    );
    if (date.isBefore(ruleStart)) {
      return false;
    }

    // Vérifier si la date est avant la fin de la règle (si définie)
    if (rule.endDate != null) {
      final ruleEnd = DateTime.utc(
        rule.endDate!.year,
        rule.endDate!.month,
        rule.endDate!.day,
      );
      if (date.isAfter(ruleEnd)) {
        return false;
      }
    }

    // Vérifier si le jour de la semaine est applicable
    return rule.applicableDays.isDaySelected(date.weekday);
  }

  /// Génère une astreinte pour un jour donné
  GeneratedShift? _generateShiftForDay({
    required ShiftRule rule,
    required DateTime date,
  }) {
    // Créer les DateTime de début et fin
    // _legacyUtcOffset compense l'écart entre la version de prod (heure locale)
    // et la version dev (UTC wall-clock). Remettre à Duration.zero après migration.
    final startDateTime = DateTime.utc(
      date.year,
      date.month,
      date.day,
      rule.startTime.hour,
      rule.startTime.minute,
    ).add(_legacyUtcOffset);

    DateTime endDateTime;
    if (rule.spansNextDay) {
      endDateTime = DateTime.utc(
        date.year,
        date.month,
        date.day + 1,
        rule.endTime.hour,
        rule.endTime.minute,
      ).add(_legacyUtcOffset);
    } else {
      endDateTime = DateTime.utc(
        date.year,
        date.month,
        date.day,
        rule.endTime.hour,
        rule.endTime.minute,
      ).add(_legacyUtcOffset);
    }

    // Déterminer l'équipe selon la rotation
    String? teamId;
    if (rule.rotationType == ShiftRotationType.none) {
      // Plage non affectée
      teamId = null;
    } else {
      // Rotation normale
      teamId = _calculateTeamForDate(rule, date);
    }

    return GeneratedShift(
      id: _uuid.v4(),
      startDateTime: startDateTime,
      endDateTime: endDateTime,
      teamId: teamId,
      ruleId: rule.id,
      ruleName: rule.name,
      isException: false,
      exceptionReason: null,
    );
  }

  /// Applique les exceptions aux shifts générés
  /// Les exceptions remplacent complètement les shifts dans leur plage horaire
  List<GeneratedShift> _applyExceptions(
    List<GeneratedShift> shifts,
    List<ShiftException> exceptions,
  ) {
    if (exceptions.isEmpty) return shifts;

    debugPrint(
      '🔧 [ShiftGenerator] Applying ${exceptions.length} exceptions to ${shifts.length} shifts',
    );

    // Trier les shifts et exceptions par date de début
    final sortedShifts = List<GeneratedShift>.from(shifts)
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
    final sortedExceptions = List<ShiftException>.from(exceptions)
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));

    var result = <GeneratedShift>[];

    // Pour chaque exception, créer un segment d'exception continu
    for (final exception in sortedExceptions) {
      debugPrint(
        '  🔍 Processing exception: ${exception.reason} (${exception.startDateTime} - ${exception.endDateTime}), teamId: ${exception.teamId}',
      );

      // Trouver tous les shifts qui chevauchent cette exception
      final overlappingShifts = sortedShifts.where((shift) {
        return shift.startDateTime.isBefore(exception.endDateTime) &&
            shift.endDateTime.isAfter(exception.startDateTime);
      }).toList();

      debugPrint('    Found ${overlappingShifts.length} overlapping shifts');

      // Créer UN SEUL segment d'exception pour toute la plage
      // (seulement si teamId n'est pas null, sinon = annulation)
      if (exception.teamId != null) {
        // Si pas de shift chevauchant, on crée quand même l'exception avec des métadonnées par défaut
        if (overlappingShifts.isEmpty) {
          debugPrint(
            '    ⚠️ No overlapping shifts - creating exception with default metadata',
          );
          result.add(
            GeneratedShift(
              id: _uuid.v4(),
              startDateTime: exception.startDateTime,
              endDateTime: exception.endDateTime,
              teamId: exception.teamId,
              ruleId:
                  'exception', // ID par défaut pour les exceptions sans shift
              ruleName: 'Exception', // Nom par défaut
              isException: true,
              exceptionReason: exception.reason,
            ),
          );
        } else {
          // Utiliser le premier shift chevauchant pour les métadonnées
          final refShift = overlappingShifts.first;
          debugPrint(
            '    ✅ Creating exception shift for team ${exception.teamId}',
          );
          result.add(
            GeneratedShift(
              id: _uuid.v4(),
              startDateTime: exception.startDateTime,
              endDateTime: exception.endDateTime,
              teamId: exception.teamId,
              ruleId: refShift.ruleId,
              ruleName: refShift.ruleName,
              isException: true,
              exceptionReason: exception.reason,
            ),
          );
        }
      } else {
        debugPrint(
          '    ℹ️ Exception has null teamId - shift will be cancelled (removed)',
        );
      }
    }

    // Maintenant ajouter les shifts normaux, en excluant les parties couvertes par les exceptions
    for (var shift in sortedShifts) {
      // Trouver les exceptions qui chevauchent ce shift
      final overlappingExceptions = sortedExceptions.where((ex) {
        return ex.startDateTime.isBefore(shift.endDateTime) &&
            ex.endDateTime.isAfter(shift.startDateTime);
      }).toList()..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));

      if (overlappingExceptions.isEmpty) {
        // Pas d'exception, garder le shift tel quel
        result.add(shift);
      } else {
        // Créer des segments pour les parties NON couvertes par les exceptions
        var currentStart = shift.startDateTime;

        for (final exception in overlappingExceptions) {
          // Segment AVANT l'exception (si existant)
          if (currentStart.isBefore(exception.startDateTime)) {
            result.add(
              GeneratedShift(
                id: _uuid.v4(),
                startDateTime: currentStart,
                endDateTime: exception.startDateTime,
                teamId: shift.teamId,
                ruleId: shift.ruleId,
                ruleName: shift.ruleName,
                isException: false,
                exceptionReason: null,
              ),
            );
          }

          // Avancer le curseur au-delà de l'exception
          currentStart = exception.endDateTime;

          // Si l'exception se termine après le shift, plus besoin de continuer
          if (currentStart.isAfter(shift.endDateTime) ||
              currentStart.isAtSameMomentAs(shift.endDateTime)) {
            break;
          }
        }

        // Segment APRÈS toutes les exceptions (si existant)
        if (currentStart.isBefore(shift.endDateTime)) {
          result.add(
            GeneratedShift(
              id: _uuid.v4(),
              startDateTime: currentStart,
              endDateTime: shift.endDateTime,
              teamId: shift.teamId,
              ruleId: shift.ruleId,
              ruleName: shift.ruleName,
              isException: false,
              exceptionReason: null,
            ),
          );
        }
      }
    }

    debugPrint(
      '🔧 [ShiftGenerator] Final result: ${result.length} shifts (${result.where((s) => s.isException).length} exception shifts, ${result.where((s) => !s.isException).length} normal shifts)',
    );

    return result;
  }

  /// Calcule quelle équipe est de garde pour une date donnée
  String? _calculateTeamForDate(ShiftRule rule, DateTime date) {
    if (rule.teamIds.isEmpty) return null;

    final ruleStart = DateTime.utc(
      rule.startDate.year,
      rule.startDate.month,
      rule.startDate.day,
    );

    final currentDate = DateTime.utc(date.year, date.month, date.day);

    int teamIndex;
    switch (rule.rotationType) {
      case ShiftRotationType.daily:
        // Compter uniquement les jours applicables depuis le début
        teamIndex =
            _countApplicableDays(rule, ruleStart, currentDate) %
            rule.teamIds.length;
        break;

      case ShiftRotationType.weekly:
        // Compter uniquement les semaines où au moins un jour est applicable
        final weeksSinceStart = currentDate.difference(ruleStart).inDays ~/ 7;
        teamIndex = weeksSinceStart % rule.teamIds.length;
        break;

      case ShiftRotationType.monthly:
        // Compter les mois écoulés
        int monthsSinceStart =
            (currentDate.year - ruleStart.year) * 12 +
            (currentDate.month - ruleStart.month);
        teamIndex = monthsSinceStart % rule.teamIds.length;
        break;

      case ShiftRotationType.custom:
        // Compter uniquement les jours applicables avec intervalle personnalisé
        final applicableDaysPassed = _countApplicableDays(
          rule,
          ruleStart,
          currentDate,
        );
        final intervalsPassed =
            applicableDaysPassed ~/ rule.rotationIntervalDays;
        teamIndex = intervalsPassed % rule.teamIds.length;
        break;

      case ShiftRotationType.none:
        return null;
    }

    return rule.teamIds[teamIndex];
  }

  /// Compte le nombre de jours applicables entre deux dates (exclut la date de fin)
  int _countApplicableDays(
    ShiftRule rule,
    DateTime startDate,
    DateTime endDate,
  ) {
    int count = 0;
    DateTime current = startDate;

    while (current.isBefore(endDate)) {
      if (rule.applicableDays.isDaySelected(current.weekday)) {
        count++;
      }
      current = current.add(const Duration(days: 1));
    }

    return count;
  }

  /// Récupère les astreintes pour une date spécifique
  /// Inclut les astreintes qui commencent, se terminent ou traversent ce jour
  List<GeneratedShift> getShiftsForDate(
    List<GeneratedShift> allShifts,
    DateTime date,
  ) {
    final normalizedDate = DateTime.utc(date.year, date.month, date.day);
    final nextDay = DateTime.utc(date.year, date.month, date.day + 1);

    return allShifts.where((shift) {
      // Inclure si l'astreinte chevauche ce jour
      // L'astreinte chevauche le jour si elle commence avant la fin du jour
      // ET se termine après le début du jour
      return shift.startDateTime.isBefore(nextDay) &&
          shift.endDateTime.isAfter(normalizedDate);
    }).toList()..sort(
      (a, b) => a.startDateTime.compareTo(b.startDateTime),
    ); // Tri chronologique
  }

  /// Récupère les astreintes pour une équipe
  List<GeneratedShift> getShiftsForTeam(
    List<GeneratedShift> allShifts,
    String teamId,
  ) {
    return allShifts.where((shift) => shift.teamId == teamId).toList();
  }
}
